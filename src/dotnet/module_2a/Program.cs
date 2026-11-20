// BinaryShield — Module 2A: Obfuscar 3.0 配置生成器
//
// 作用：读入 Module 1A 的 JSON 清单（目标必须是 .NET 8），生成 Obfuscar 3.0 的 XML 配置 obf.xml。
//       对 Avalonia 与 CompiledAvaloniaXaml 命名空间用 SkipNamespace rx 正则排除；
//       输出目录为配置文件所在目录下的 protected 子目录。
//       只生成配置文件：不运行 Obfuscar，不修改清单或目标程序，不实现任何混淆算法。
//
// 用法: module_2a <清单.json> <obf.xml>
//
// 退出码: 0 成功 | 64 用法错误，或配置输出路径与清单 / 目标程序相同 | 65 清单无效 / 非 .NET 8 / skip 命名空间未被规则覆盖 |
//         66 清单或目标程序不存在 | 70 内部错误 | 73 写入失败
//
// 兼容性：用 .NET Framework 自带 csc(C# 5) 编译，不用字符串插值、?. 等新语法。

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;
using System.Xml;
using System.Xml.Linq;

namespace BinaryShield.Module2A
{
    // 带退出码的错误：Main 捕获后打印消息并以该退出码结束。
    internal sealed class Fail : Exception
    {
        public readonly int Code;
        public Fail(int code, string message) : base(message) { Code = code; }
    }

    internal static class Program
    {
        // Avalonia 规则的正则形式（CLAUDE.md）。Obfuscar 的 rx 属性使用同一个模式。
        // 只匹配精确的 Avalonia / CompiledAvaloniaXaml，或以 "名字." 开头的子命名空间；
        // 不匹配 AvaloniaApp 之类只是以同样字样开头的应用命名空间。
        internal const string SkipRegex = "^(Avalonia|CompiledAvaloniaXaml)(\\..*)?$";

        private const string RequiredFramework = ".NETCoreApp,Version=v8.";
        private const long MaxManifestBytes = 256L * 1024 * 1024;

        private static int Main(string[] args)
        {
            try
            {
                return Run(args);
            }
            catch (Fail f)
            {
                Console.Error.WriteLine("错误: " + f.Message);
                return f.Code;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("内部错误: " + ex.GetType().Name + ": " + ex.Message);
                return 70;
            }
        }

        private static int Run(string[] args)
        {
            if (args.Length != 2)
                throw new Fail(64, "用法: module_2a <清单.json> <obf.xml>");

            // 配置里的路径一律使用绝对路径（Obfuscar 3 对相对路径直接报错）。
            string manifestFull = Path.GetFullPath(args[0]);
            string configFull = Path.GetFullPath(args[1]);
            if (Path.GetDirectoryName(configFull) == null)
                throw new Fail(73, "配置路径没有目录部分，无法写入: " + configFull);
            if (string.Equals(manifestFull, configFull, StringComparison.OrdinalIgnoreCase))
                throw new Fail(64, "配置输出路径与清单相同，拒绝覆盖清单: " + manifestFull);

            if (!File.Exists(manifestFull))
                throw new Fail(66, "找不到清单文件: " + manifestFull);
            if (new FileInfo(manifestFull).Length > MaxManifestBytes)
                throw new Fail(65, "清单超过 256 MB，拒绝处理");

            string text = File.ReadAllText(manifestFull, Encoding.UTF8);
            object parsed;
            try
            {
                JavaScriptSerializer js = new JavaScriptSerializer();
                js.MaxJsonLength = int.MaxValue;
                parsed = js.DeserializeObject(text);
            }
            catch (Exception ex)
            {
                throw new Fail(65, "清单不是合法 JSON: " + ex.Message);
            }

            IDictionary root = AsDict(parsed);
            if (root == null) throw new Fail(65, "清单顶层不是 JSON 对象");
            if (GetString(root, "schemaVersion") != "0.1")
                throw new Fail(65, "schemaVersion 必须为 \"0.1\"");

            IDictionary input = AsDict(Get(root, "input"));
            if (input == null) throw new Fail(65, "缺少 input 对象");

            object isManaged = Get(input, "isManaged");
            if (!(isManaged is bool) || !(bool)isManaged)
                throw new Fail(65, "input.isManaged 不是 true：目标不是 .NET 程序");

            string tfm = GetString(input, "targetFramework");
            if (tfm == null) throw new Fail(65, "清单缺少 input.targetFramework");
            if (!tfm.StartsWith(RequiredFramework, StringComparison.Ordinal))
                throw new Fail(65, "目标框架不是 .NET 8：" + tfm);

            string inputPathRaw = GetString(input, "path");
            if (inputPathRaw == null) throw new Fail(65, "缺少 input.path");
            if (!IsAbsolutePath(inputPathRaw))
                throw new Fail(65, "input.path 不是绝对路径：" + inputPathRaw);
            string inputFull = Path.GetFullPath(inputPathRaw);
            // 配置输出路径不能是目标程序本身，否则会覆盖输入文件（与清单相同的检查同理）。
            if (string.Equals(inputFull, configFull, StringComparison.OrdinalIgnoreCase))
                throw new Fail(64, "配置输出路径与目标程序相同，拒绝覆盖输入文件: " + inputFull);
            if (!File.Exists(inputFull))
                throw new Fail(66, "找不到目标程序: " + inputFull);

            SortedSet<string> skipNs = CollectSkipNamespaces(root);

            // 一致性检查（决定点 D）：1A 标为 skip 的命名空间，必须被 SkipNamespace 规则覆盖。
            List<string> uncovered = new List<string>();
            foreach (string ns in skipNs)
            {
                if (!Regex.IsMatch(ns, SkipRegex)) uncovered.Add(ns);
            }
            if (uncovered.Count > 0)
                throw new Fail(65, "以下 skip:true 命名空间未被 SkipNamespace 规则覆盖（1A 与 2A 的定义不一致）: "
                    + string.Join(", ", uncovered));

            string inputDir = Path.GetDirectoryName(inputFull);
            string configDir = Path.GetDirectoryName(configFull);
            string protectedDir = Path.Combine(configDir, "protected");

            XDocument doc = BuildConfig(inputDir, protectedDir, inputFull, skipNs);
            WriteAtomically(doc, configFull);

            Console.WriteLine("已写入: " + configFull);
            Console.WriteLine("  InPath : " + inputDir);
            Console.WriteLine("  OutPath: " + protectedDir);
            if (skipNs.Count == 0)
                Console.Error.WriteLine("WARNING: 清单中没有 skip:true 的类型，已按固定规则照常生成配置。");
            return 0;
        }

        // 收集所有 skip:true 的命名空间（去重、排序）。字段类型不对时拒绝，不静默跳过。
        private static SortedSet<string> CollectSkipNamespaces(IDictionary root)
        {
            SortedSet<string> set = new SortedSet<string>(StringComparer.Ordinal);
            List<object> asms = AsList(Get(root, "assemblies"));
            if (asms == null) throw new Fail(65, "assemblies 不是数组");

            foreach (object a in asms)
            {
                IDictionary asm = AsDict(a);
                if (asm == null) throw new Fail(65, "assemblies 中的条目不是对象");
                List<object> mods = AsList(Get(asm, "modules"));
                if (mods == null) throw new Fail(65, "modules 不是数组");

                foreach (object m in mods)
                {
                    IDictionary mod = AsDict(m);
                    if (mod == null) throw new Fail(65, "modules 中的条目不是对象");
                    List<object> types = AsList(Get(mod, "types"));
                    if (types == null) throw new Fail(65, "types 不是数组");

                    foreach (object t in types)
                    {
                        IDictionary type = AsDict(t);
                        if (type == null) throw new Fail(65, "types 中的条目不是对象");

                        object skipObj = Get(type, "skip");
                        if (!(skipObj is bool)) throw new Fail(65, "types 中的 skip 不是布尔值");
                        if (!(bool)skipObj) continue;

                        string ns = GetString(type, "namespace");
                        if (string.IsNullOrEmpty(ns)) throw new Fail(65, "skip:true 的类型缺少命名空间");
                        if (!IsValidXmlText(ns)) throw new Fail(65, "命名空间含 XML 不允许的字符: " + ns);
                        set.Add(ns);
                    }
                }
            }
            return set;
        }

        private static XDocument BuildConfig(string inputDir, string protectedDir, string inputFull, SortedSet<string> skipNs)
        {
            XElement obf = new XElement("Obfuscator");

            if (skipNs.Count > 0)
            {
                string list = SafeComment(string.Join(", ", skipNs));
                obf.Add(new XComment(" 排除的命名空间（来自 1A 清单中 skip:true 的类型）: " + list + " "));
            }

            obf.Add(new XElement("Var", new XAttribute("name", "InPath"), new XAttribute("value", inputDir)));
            obf.Add(new XElement("Var", new XAttribute("name", "OutPath"), new XAttribute("value", protectedDir)));
            obf.Add(new XElement("Var", new XAttribute("name", "KeepPublicApi"), new XAttribute("value", "true")));
            obf.Add(new XElement("Var", new XAttribute("name", "HidePrivateApi"), new XAttribute("value", "true")));

            XElement module = new XElement("Module", new XAttribute("file", inputFull));
            module.Add(new XElement("SkipNamespace", new XAttribute("rx", SkipRegex)));
            obf.Add(module);

            return new XDocument(new XDeclaration("1.0", "utf-8", null), obf);
        }

        // 先写临时文件，再替换目标文件。配置目录不存在时直接报写入失败（不替用户创建目录）。
        private static void WriteAtomically(XDocument doc, string configFull)
        {
            string dir = Path.GetDirectoryName(configFull);
            if (!Directory.Exists(dir)) throw new Fail(73, "配置输出目录不存在: " + dir);

            string tmp = configFull + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                XmlWriterSettings settings = new XmlWriterSettings();
                settings.Encoding = new UTF8Encoding(false);
                settings.Indent = true;
                settings.IndentChars = "  ";
                using (XmlWriter w = XmlWriter.Create(tmp, settings))
                {
                    doc.Save(w);
                }
                if (File.Exists(configFull)) File.Replace(tmp, configFull, null);
                else File.Move(tmp, configFull);
            }
            catch (IOException ex)
            {
                CleanTmp(tmp);
                throw new Fail(73, "写入失败: " + ex.Message);
            }
            catch (UnauthorizedAccessException ex)
            {
                CleanTmp(tmp);
                throw new Fail(73, "没有写入权限: " + ex.Message);
            }
        }

        private static void CleanTmp(string tmp)
        {
            try { if (File.Exists(tmp)) File.Delete(tmp); } catch { }
        }

        // 绝对路径：带盘符（C:\ 或 C:/），或 UNC（\\server\share）。
        // 只以单个 \ 或 / 开头的路径没有盘符，会被解析到当前盘，不是绝对路径，拒绝。
        private static bool IsAbsolutePath(string p)
        {
            if (p.Length >= 3 && char.IsLetter(p[0]) && p[1] == ':' && (p[2] == '\\' || p[2] == '/')) return true;
            if (p.Length >= 2 && (p[0] == '\\' || p[0] == '/') && (p[1] == '\\' || p[1] == '/')) return true;
            return false;
        }

        // XML 注释里不能出现 "--"，也不能以 "-" 结尾。
        private static string SafeComment(string s)
        {
            while (s.IndexOf("--", StringComparison.Ordinal) >= 0) s = s.Replace("--", "- -");
            if (s.EndsWith("-", StringComparison.Ordinal)) s += " ";
            return s;
        }

        // XML 1.0 允许的字符（代理项成对出现时有效）。
        private static bool IsValidXmlText(string s)
        {
            foreach (char c in s)
            {
                bool ok = c == 0x9 || c == 0xA || c == 0xD
                    || (c >= 0x20 && c <= 0xD7FF)
                    || (c >= 0xD800 && c <= 0xDFFF)
                    || (c >= 0xE000 && c <= 0xFFFD);
                if (!ok) return false;
            }
            return true;
        }

        // JavaScriptSerializer 返回的数组类型不是固定的 object[]，所以按"可枚举、非字符串、非字典"判断。
        private static List<object> AsList(object o)
        {
            if (o == null || o is string || o is IDictionary) return null;
            IEnumerable e = o as IEnumerable;
            if (e == null) return null;
            List<object> list = new List<object>();
            foreach (object x in e) list.Add(x);
            return list;
        }

        private static IDictionary AsDict(object o)
        {
            return o as IDictionary;
        }

        // 缺少键时返回 null（IDictionary 的索引器对缺失的键会抛异常）。
        private static object Get(IDictionary d, string key)
        {
            return d.Contains(key) ? d[key] : null;
        }

        private static string GetString(IDictionary d, string key)
        {
            return Get(d, key) as string;
        }
    }
}
