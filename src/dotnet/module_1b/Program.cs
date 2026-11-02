// BinaryShield — Module 1B: ConfuserEx2 .crproj 配置生成器
//
// 作用：读取 Module 1A 输出的 JSON 清单，生成一份 ConfuserEx2 项目文件(.crproj)。
//       第一条规则对全部代码施加 normal 预设保护；第二条规则对 Avalonia 命名空间
//       移除全部保护项（规则语法与保护 ID 均已在 ConfuserEx2 1.6.0 上实测，见 spec.md 第 6 节）。
//       只生成配置文件：不调用 ConfuserEx2，不修改目标程序或输入 JSON。
//
// 用法: module_1b <输入.json> <输出.crproj>
//
// 退出码: 0 成功 | 64 用法错误(含输入与输出为同一文件) | 65 清单内容不合法
//         | 66 找不到或无法读取输入 | 73 无法写入输出
//
// 兼容性: .NET Framework 4.x 自带 csc(C# 5)，故不用字符串插值、?. 等新语法。
// JSON 解析使用框架自带的 System.Web.Extensions（决定点 D）。

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Web.Script.Serialization;
using System.Xml;
using System.Xml.Linq;

namespace BinaryShield.Module1B
{
    internal static class Program
    {
        // 排除规则的命名空间范围（2026-11-01 修订）：
        //   Avalonia 及其子命名空间（决定点 A）；
        //   CompiledAvaloniaXaml：Avalonia 编译 XAML 时生成的代码，运行时按名字反射访问，
        //   被 rename 保护后会因找不到字段而崩溃（见 module_1b/spec.md 第 6 节）。
        private const string ExclusionPattern = @"namespace('Avalonia(\..*)?') or namespace('CompiledAvaloniaXaml(\..*)?')";

        // 决定点 E：非 Avalonia 代码使用的基础预设
        private const string BasePreset = "normal";

        // 决定点 F：保护产物输出到 .crproj 所在目录下的子目录
        private const string OutputDir = "protected";

        // 排除规则移除的全部保护项（ConfuserEx2 1.6.0 实测 ID，见 spec.md 第 6 节）
        private static readonly string[] ProtectionIds = new string[]
        {
            "anti debug", "anti dump", "anti ildasm", "anti tamper", "constants", "ctrl flow",
            "harden", "invalid metadata", "ref proxy", "resources", "typescramble", "rename"
        };

        // ConfuserEx2 的项目文件命名空间（Confuser.Core.dll 内置字符串，已核实）
        private static readonly XNamespace Ns = "http://confuser.codeplex.com";

        // 输入清单的大小上限，防止异常大的文件耗尽内存
        private const long MaxInputBytes = 256L * 1024 * 1024;

        private static int Main(string[] args)
        {
            try
            {
                Console.OutputEncoding = Encoding.UTF8;
            }
            catch (Exception)
            {
                // 没有控制台（服务、计划任务等）时忽略，不影响主流程
            }

            if (args.Length != 2)
            {
                Console.Error.WriteLine("用法: module_1b <输入.json> <输出.crproj>");
                return 64;
            }

            string inputPath = args[0];
            string outputPath = args[1];

            if (IsSameFile(inputPath, outputPath))
            {
                Console.Error.WriteLine("错误: 输出文件不能与输入清单相同，否则会覆盖清单。");
                return 64;
            }

            if (!File.Exists(inputPath))
            {
                Console.Error.WriteLine("错误: 找不到输入文件: " + inputPath);
                return 66;
            }

            if (new FileInfo(inputPath).Length > MaxInputBytes)
            {
                Console.Error.WriteLine("错误: 输入清单超过大小上限（256 MB），拒绝处理。");
                return 65;
            }

            string text;
            try
            {
                text = File.ReadAllText(inputPath, Encoding.UTF8);
            }
            catch (IOException ex)
            {
                Console.Error.WriteLine("错误: 无法读取输入文件: " + ex.Message);
                return 66;
            }
            catch (UnauthorizedAccessException ex)
            {
                Console.Error.WriteLine("错误: 无权读取输入文件: " + ex.Message);
                return 66;
            }

            Dictionary<string, object> root;
            try
            {
                root = ParseJson(text);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("错误: JSON 无法解析: " + ex.Message);
                return 65;
            }
            if (root == null)
            {
                Console.Error.WriteLine("错误: 输入不是 JSON 对象。");
                return 65;
            }

            // 校验 Module 1A 的输出（spec 第 4 节第 1 步）
            if (GetString(root, "schemaVersion") != "0.1")
            {
                Console.Error.WriteLine("错误: schemaVersion 不是 0.1，无法识别该清单格式。");
                return 65;
            }

            Dictionary<string, object> input = GetDict(root, "input");
            if (input == null || !GetBool(input, "isManaged"))
            {
                Console.Error.WriteLine("错误: 目标不是托管 .NET 程序（isManaged 不为 true），ConfuserEx2 不适用，拒绝生成。");
                return 65;
            }

            string targetPath = GetString(input, "path");
            if (string.IsNullOrEmpty(targetPath) || !Path.IsPathRooted(targetPath))
            {
                Console.Error.WriteLine("错误: input.path 缺失或不是绝对路径。");
                return 65;
            }

            List<string> skipNamespaces = CollectSkipNamespaces(root);
            if (skipNamespaces == null)
            {
                Console.Error.WriteLine("错误: 清单结构不符合 Module 1A 输出格式（assemblies/modules/types 必须是数组，skip 必须是布尔值）。");
                return 65;
            }

            XDocument doc;
            try
            {
                doc = BuildCrproj(targetPath, skipNamespaces);
            }
            catch (ArgumentException ex)
            {
                Console.Error.WriteLine("错误: 清单中的路径或命名空间含有 XML 不允许的字符: " + ex.Message);
                return 65;
            }

            string fullPath;
            try
            {
                fullPath = WriteXml(doc, outputPath);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("错误: 无法写入输出文件: " + ex.Message);
                return 73;
            }

            if (skipNamespaces.Count == 0)
            {
                // 决定点 C：照常生成，只给出警告
                Console.Error.WriteLine("WARNING: 清单中没有 skip:true 的类型，已按固定规则照常生成配置。");
            }
            Console.WriteLine("已生成: " + fullPath);
            return 0;
        }

        // 输入与输出是否指向同一文件（路径无法解析时视为不同，由后续步骤报告具体错误）
        private static bool IsSameFile(string a, string b)
        {
            try
            {
                return string.Equals(Path.GetFullPath(a), Path.GetFullPath(b), StringComparison.OrdinalIgnoreCase);
            }
            catch (Exception)
            {
                return false;
            }
        }

        // 遍历 assemblies → modules → types，收集 skip:true 的命名空间（去重、排序以保证输出稳定）。
        // 结构不符合 Module 1A 输出格式时返回 null，而不是静默跳过。
        private static List<string> CollectSkipNamespaces(Dictionary<string, object> root)
        {
            List<string> result = new List<string>();

            List<object> assemblies = GetArray(root, "assemblies");
            if (assemblies == null) return null;
            foreach (object a in assemblies)
            {
                List<object> modules = GetArray(AsDict(a), "modules");
                if (modules == null) return null;
                foreach (object m in modules)
                {
                    List<object> types = GetArray(AsDict(m), "types");
                    if (types == null) return null;
                    foreach (object t in types)
                    {
                        Dictionary<string, object> type = AsDict(t);
                        if (type == null) return null;
                        if (!(GetValue(type, "skip") is bool)) return null;
                        if (!GetBool(type, "skip")) continue;

                        string ns = GetString(type, "namespace") ?? "";
                        if (ns.Length == 0) continue;
                        if (!result.Contains(ns)) result.Add(ns);
                    }
                }
            }

            result.Sort(StringComparer.Ordinal);
            return result;
        }

        private static XDocument BuildCrproj(string targetPath, List<string> skipNamespaces)
        {
            XElement module = new XElement(Ns + "module", new XAttribute("path", targetPath));

            string comment = skipNamespaces.Count > 0
                ? " 排除的 Avalonia 命名空间: " + string.Join(", ", skipNamespaces) + " "
                : " 清单中未发现 Avalonia 命名空间 ";
            // XML 注释中不允许出现 "--"；连续多个连字符需要反复替换直到清空
            while (comment.IndexOf("--", StringComparison.Ordinal) >= 0)
            {
                comment = comment.Replace("--", "- -");
            }
            module.Add(new XComment(comment));

            // 基础规则：非 Avalonia 代码使用 normal 预设，但去掉两项保护：
            //   resources：嵌入的 .axaml 是模块级资源，不受命名空间规则覆盖，保留则 XAML 被加密；
            //   ref proxy：ConfuserEx2 1.6.0 无法解析 Avalonia 11 编译 XAML 产生的成员引用（编译失败）。
            module.Add(new XElement(Ns + "rule",
                new XAttribute("pattern", "true"),
                new XAttribute("preset", BasePreset),
                new XAttribute("inherit", "false"),
                new XElement(Ns + "protection",
                    new XAttribute("id", "resources"),
                    new XAttribute("action", "remove")),
                new XElement(Ns + "protection",
                    new XAttribute("id", "ref proxy"),
                    new XAttribute("action", "remove"))));

            // 排除规则：对 Avalonia 命名空间移除全部保护项
            XElement exclusion = new XElement(Ns + "rule",
                new XAttribute("pattern", ExclusionPattern),
                new XAttribute("inherit", "false"));
            foreach (string id in ProtectionIds)
            {
                exclusion.Add(new XElement(Ns + "protection",
                    new XAttribute("id", id),
                    new XAttribute("action", "remove")));
            }
            module.Add(exclusion);

            XElement project = new XElement(Ns + "project",
                new XAttribute("outputDir", OutputDir),
                new XAttribute("baseDir", "."),
                module);
            return new XDocument(new XDeclaration("1.0", "utf-8", null), project);
        }

        // 先写到同目录的临时文件，成功后再替换目标，失败时目标文件保持原样
        private static string WriteXml(XDocument doc, string outputPath)
        {
            string fullPath = Path.GetFullPath(outputPath);
            string dir = Path.GetDirectoryName(fullPath);
            if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
            {
                Directory.CreateDirectory(dir);
            }

            string temp = fullPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            XmlWriterSettings settings = new XmlWriterSettings();
            settings.Encoding = new UTF8Encoding(false);
            settings.Indent = true;
            settings.IndentChars = "  ";
            try
            {
                using (XmlWriter writer = XmlWriter.Create(temp, settings))
                {
                    doc.Save(writer);
                }

                if (File.Exists(fullPath))
                {
                    File.Replace(temp, fullPath, null);
                }
                else
                {
                    File.Move(temp, fullPath);
                }
            }
            finally
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
            return fullPath;
        }

        private static Dictionary<string, object> ParseJson(string text)
        {
            JavaScriptSerializer serializer = new JavaScriptSerializer();
            serializer.MaxJsonLength = int.MaxValue;
            return serializer.Deserialize<Dictionary<string, object>>(text);
        }

        // --- 取值辅助：缺字段或类型不对时返回 null / 默认值，由调用方决定是否报错 ---

        private static object GetValue(Dictionary<string, object> d, string key)
        {
            if (d == null) return null;
            object v;
            return d.TryGetValue(key, out v) ? v : null;
        }

        private static string GetString(Dictionary<string, object> d, string key)
        {
            return GetValue(d, key) as string;
        }

        private static bool GetBool(Dictionary<string, object> d, string key)
        {
            object v = GetValue(d, key);
            return v is bool && (bool)v;
        }

        private static Dictionary<string, object> GetDict(Dictionary<string, object> d, string key)
        {
            return AsDict(GetValue(d, key));
        }

        // JavaScriptSerializer 对 JSON 数组的具体 .NET 类型不固定（实测不是 object[]），
        // 所以这里接受任何非字符串、非字典的可枚举值；不是数组则返回 null
        private static List<object> GetArray(Dictionary<string, object> d, string key)
        {
            object v = GetValue(d, key);
            if (v == null || v is string || v is IDictionary) return null;
            IEnumerable items = v as IEnumerable;
            if (items == null) return null;

            List<object> list = new List<object>();
            foreach (object item in items) list.Add(item);
            return list;
        }

        private static Dictionary<string, object> AsDict(object o)
        {
            return o as Dictionary<string, object>;
        }
    }
}
