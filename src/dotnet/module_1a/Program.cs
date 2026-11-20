// BinaryShield — Module 1A: .NET 程序集只读分析器
//
// 作用：读入一个 .NET 程序(.exe/.dll)，输出一份 JSON 清单——
//       列出其中的 程序集 / 模块 / 类型 / 方法 / 字符串字面量(含 IL 偏移)，
//       并把 Avalonia 与 CompiledAvaloniaXaml 命名空间标上 skip=true
//       (正好是 "Avalonia" / "CompiledAvaloniaXaml"，或以 "Avalonia." / "CompiledAvaloniaXaml." 开头)。
//       只读取与分类，不修改任何内容(性质同 ILSpy / dnSpy 查看器)。使用锁定库 dnlib。
//
// 用法: module_1a <输入.dll/.exe> [输出.json] [--stdout]
//       不给输出文件时直接打印到屏幕。
//
// 兼容性：用 .NET Framework 自带旧版 csc(C# 5)编译，故不用 ?. / 字符串插值 等新语法。

using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using dnlib.DotNet;
using dnlib.DotNet.Emit;

namespace BinaryShield.Module1A
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            if (args.Length < 1)
            {
                Console.Error.WriteLine("用法: module_1a <输入.dll/.exe> [输出.json] [--stdout]");
                return 64;
            }

            string input = args[0];
            string output = null;
            bool toStdout = false;
            for (int i = 1; i < args.Length; i++)
            {
                if (args[i] == "--stdout") toStdout = true;
                else if (output == null) output = args[i];
            }
            if (output == null) toStdout = true;

            if (!File.Exists(input))
            {
                Console.Error.WriteLine("错误: 找不到输入文件: " + input);
                return 66;
            }

            string sha256 = ComputeSha256(input);

            ModuleDefMD mod = null;
            try
            {
                mod = ModuleDefMD.Load(input);
            }
            catch (Exception ex)
            {
                // 不是托管 .NET 程序(原生 PE)或文件损坏：友好输出 isManaged=false
                JObj na = new JObj();
                na.Add("tool", "BinaryShield");
                na.Add("module", "1a");
                na.Add("schemaVersion", "0.1");
                JObj inNa = new JObj();
                inNa.Add("path", FullPath(input));
                inNa.Add("fileName", Path.GetFileName(input));
                inNa.Add("sha256", sha256);
                inNa.Add("isManaged", false);
                inNa.Add("error", ex.GetType().Name + ": " + ex.Message);
                na.Add("input", inNa);
                na.Add("assemblies", new JArr());
                Emit(na, output, toStdout);
                Console.Error.WriteLine("提示: 该文件不是托管 .NET 程序，本模块只处理托管 PE。");
                return 0;
            }

            try
            {
                JObj root = BuildReport(mod, input, sha256);
                Emit(root, output, toStdout);
                return 0;
            }
            finally
            {
                mod.Dispose();
            }
        }

        private static JObj BuildReport(ModuleDefMD mod, string input, string sha256)
        {
            JObj root = new JObj();
            root.Add("tool", "BinaryShield");
            root.Add("module", "1a");
            root.Add("schemaVersion", "0.1");

            JObj inObj = new JObj();
            inObj.Add("path", FullPath(input));
            inObj.Add("fileName", Path.GetFileName(input));
            inObj.Add("sha256", sha256);
            inObj.Add("isManaged", true);
            inObj.Add("targetFramework", GetTargetFramework(mod));
            root.Add("input", inObj);

            long typeCount = 0, methodCount = 0, strCount = 0, skippedTypeCount = 0;

            JArr typesArr = new JArr();
            foreach (TypeDef type in mod.GetTypes())
            {
                typeCount++;
                string ns = S(type.Namespace);
                bool skip = IsExcluded(ns);
                if (skip) skippedTypeCount++;

                JObj tObj = new JObj();
                tObj.Add("namespace", ns);
                tObj.Add("name", S(type.Name));
                tObj.Add("fullName", type.FullName);
                tObj.Add("isNested", type.IsNested);
                tObj.Add("skip", skip);

                JArr methodsArr = new JArr();
                foreach (MethodDef m in type.Methods)
                {
                    methodCount++;
                    JObj mObj = new JObj();
                    mObj.Add("name", S(m.Name));
                    mObj.Add("signature", m.FullName);
                    bool hasBody = m.HasBody;
                    mObj.Add("hasBody", hasBody);

                    JArr litArr = new JArr();
                    if (hasBody && m.Body != null)
                    {
                        foreach (Instruction instr in m.Body.Instructions)
                        {
                            if (instr.OpCode.Code == Code.Ldstr)
                            {
                                JObj lit = new JObj();
                                lit.Add("value", instr.Operand as string);
                                lit.Add("ilOffset", (long)instr.Offset);
                                lit.Add("opcode", "ldstr");
                                litArr.Add(lit);
                                strCount++;
                            }
                        }
                    }
                    mObj.Add("stringLiterals", litArr);
                    methodsArr.Add(mObj);
                }
                tObj.Add("methods", methodsArr);
                typesArr.Add(tObj);
            }

            JObj modObj = new JObj();
            modObj.Add("name", S(mod.Name));
            modObj.Add("types", typesArr);
            JArr modArr = new JArr();
            modArr.Add(modObj);

            JObj asmObj = new JObj();
            asmObj.Add("fullName", mod.Assembly != null ? mod.Assembly.FullName : S(mod.Name));
            asmObj.Add("modules", modArr);
            JArr asmArr = new JArr();
            asmArr.Add(asmObj);
            root.Add("assemblies", asmArr);

            JObj summary = new JObj();
            summary.Add("typeCount", typeCount);
            summary.Add("methodCount", methodCount);
            summary.Add("stringLiteralCount", strCount);
            summary.Add("skippedTypeCount", skippedTypeCount);
            root.Add("summary", summary);

            return root;
        }

        // Avalonia rule (CLAUDE.md): exactly "Avalonia" or "Avalonia.*", and exactly "CompiledAvaloniaXaml"
        // or "CompiledAvaloniaXaml.*". Matching is case-sensitive, as .NET namespaces are.
        // Names that merely start with these words (e.g. "AvaloniaApp") are NOT excluded.
        private static bool IsExcluded(string ns)
        {
            if (string.IsNullOrEmpty(ns)) return false;
            return ns == "Avalonia"
                || ns.StartsWith("Avalonia.", StringComparison.Ordinal)
                || ns == "CompiledAvaloniaXaml"
                || ns.StartsWith("CompiledAvaloniaXaml.", StringComparison.Ordinal);
        }

        private static string GetTargetFramework(ModuleDefMD mod)
        {
            try
            {
                if (mod.Assembly != null)
                {
                    foreach (CustomAttribute ca in mod.Assembly.CustomAttributes)
                    {
                        if (ca.TypeFullName == "System.Runtime.Versioning.TargetFrameworkAttribute"
                            && ca.ConstructorArguments.Count > 0)
                        {
                            object v = ca.ConstructorArguments[0].Value;
                            if (v != null) return v.ToString();
                        }
                    }
                }
            }
            catch { }
            return mod.RuntimeVersion;
        }

        private static string ComputeSha256(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(path))
            {
                byte[] hash = sha.ComputeHash(fs);
                StringBuilder sb = new StringBuilder(hash.Length * 2);
                foreach (byte b in hash) sb.Append(b.ToString("x2"));
                return sb.ToString();
            }
        }

        private static string FullPath(string p)
        {
            try { return Path.GetFullPath(p).Replace('\\', '/'); }
            catch { return p; }
        }

        private static string S(UTF8String u)
        {
            return ReferenceEquals(u, null) ? "" : u.ToString();
        }

        private static void Emit(JObj root, string outputPath, bool toStdout)
        {
            StringBuilder sb = new StringBuilder();
            JsonWriter.Write(root, sb, 0);
            string json = sb.ToString();
            if (!string.IsNullOrEmpty(outputPath))
            {
                File.WriteAllText(outputPath, json, new UTF8Encoding(false));
            }
            if (toStdout)
            {
                Console.OutputEncoding = Encoding.UTF8;
                Console.WriteLine(json);
            }
        }
    }

    // --- 极简 JSON 数据模型 + 序列化(不引入第三方库) ---

    internal sealed class JObj
    {
        public readonly List<KeyValuePair<string, object>> Items = new List<KeyValuePair<string, object>>();
        public void Add(string key, object value) { Items.Add(new KeyValuePair<string, object>(key, value)); }
    }

    internal sealed class JArr
    {
        public readonly List<object> Items = new List<object>();
        public void Add(object value) { Items.Add(value); }
    }

    internal static class JsonWriter
    {
        public static void Write(object v, StringBuilder sb, int indent)
        {
            if (v == null) { sb.Append("null"); return; }
            if (v is string) { WriteString((string)v, sb); return; }
            if (v is bool) { sb.Append(((bool)v) ? "true" : "false"); return; }
            if (v is int) { sb.Append(((int)v).ToString(CultureInfo.InvariantCulture)); return; }
            if (v is long) { sb.Append(((long)v).ToString(CultureInfo.InvariantCulture)); return; }
            if (v is JObj) { WriteObj((JObj)v, sb, indent); return; }
            if (v is JArr) { WriteArr((JArr)v, sb, indent); return; }
            WriteString(v.ToString(), sb);
        }

        private static void WriteObj(JObj o, StringBuilder sb, int indent)
        {
            if (o.Items.Count == 0) { sb.Append("{}"); return; }
            sb.Append("{\n");
            string pad = new string(' ', (indent + 1) * 2);
            for (int i = 0; i < o.Items.Count; i++)
            {
                sb.Append(pad);
                WriteString(o.Items[i].Key, sb);
                sb.Append(": ");
                Write(o.Items[i].Value, sb, indent + 1);
                if (i < o.Items.Count - 1) sb.Append(',');
                sb.Append('\n');
            }
            sb.Append(new string(' ', indent * 2));
            sb.Append('}');
        }

        private static void WriteArr(JArr a, StringBuilder sb, int indent)
        {
            if (a.Items.Count == 0) { sb.Append("[]"); return; }
            sb.Append("[\n");
            string pad = new string(' ', (indent + 1) * 2);
            for (int i = 0; i < a.Items.Count; i++)
            {
                sb.Append(pad);
                Write(a.Items[i], sb, indent + 1);
                if (i < a.Items.Count - 1) sb.Append(',');
                sb.Append('\n');
            }
            sb.Append(new string(' ', indent * 2));
            sb.Append(']');
        }

        private static void WriteString(string s, StringBuilder sb)
        {
            if (s == null) { sb.Append("null"); return; }
            sb.Append('"');
            foreach (char c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\b': sb.Append("\\b"); break;
                    case '\f': sb.Append("\\f"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': sb.Append("\\r"); break;
                    case '\t': sb.Append("\\t"); break;
                    default:
                        if (c < 0x20) sb.Append("\\u").Append(((int)c).ToString("x4"));
                        else sb.Append(c);
                        break;
                }
            }
            sb.Append('"');
        }
    }
}
