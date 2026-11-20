// BinaryShield — Module 2B: 统一命令行入口 bs.exe（规格见 spec.md）
//
// 用法:
//   bs analyze <输入.dll|exe> [输出.json]
//   bs protect <输入.dll|exe> --out <输出目录> [--confuser <Confuser.CLI.exe>] [--obfuscar <GlobalTools.dll>] [--bin-dir <目录>]
//
// 路由: 先用 1A 读取 targetFramework。
//   .NETFramework,Version=v4.*  -> 1C（ConfuserEx2）原样调用
//   .NETCoreApp,Version=v8.*    -> 1A -> 2A -> Obfuscar 3 -> 复核（本模块编排）
//   其他                        -> 拒绝（65）
// 退出码: 0 成功 | 2 ConfuserEx2 版本不符（1C 透传）| 3 复核有 FAIL
//         | 64 用法错误 / 输出目录非空或与输入重叠 / 缺少路由所需参数
//         | 65 非托管或框架不受支持 | 66 文件缺失 | 70 内部步骤失败 | 73 无法写入
//         | 75 外部工具失败（ConfuserEx2 或 Obfuscar 无法运行、超时、或返回非 0）
//
// 兼容性: 用 .NET Framework 自带 csc（C# 5）编译，不用字符串插值、?. 等新语法。

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace BinaryShield.Module2B
{
    // 带退出码的错误：Main 捕获后打印消息并以该退出码结束。
    internal sealed class Fail : Exception
    {
        public readonly int Code;
        public Fail(int code, string message) : base(message) { Code = code; }
    }

    internal static class Program
    {
        private const string Usage =
            "用法:\n" +
            "  bs analyze <输入.dll|exe> [输出.json]\n" +
            "  bs protect <输入.dll|exe> --out <输出目录> [--confuser <Confuser.CLI.exe>] [--obfuscar <GlobalTools.dll>] [--bin-dir <目录>]";

        private const int ToolTimeoutMs = 10 * 60 * 1000;   // 与 1C 的单步超时相同
        private const int DrainTimeoutMs = 5000;            // 进程结束后等待异步输出的上限
        private const int TailChars = 4000;

        private const string NetFxPrefix = ".NETFramework,Version=v4.";
        private const string Net8Prefix = ".NETCoreApp,Version=v8.";

        // 保护流程需要的工具（与 1C、2A 同目录）。dnlib.dll 供 1A 与 1C 加载。
        private static readonly string[] RequiredTools =
        {
            "module_1a.exe", "module_1b.exe", "module_1c.exe", "module_2a.exe", "dnlib.dll"
        };

        private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);

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
            if (args.Length == 0) throw new Fail(64, Usage);
            if (args[0] == "analyze") return Analyze(args);
            if (args[0] == "protect") return Protect(args);
            throw new Fail(64, Usage);
        }

        // --- analyze：原样转发给 module_1a.exe ---

        private static int Analyze(string[] args)
        {
            if (args.Length < 2 || args.Length > 3) throw new Fail(64, Usage);
            if (args[1].StartsWith("--", StringComparison.Ordinal)) throw new Fail(64, Usage);
            if (args.Length == 3 && args[2].StartsWith("--", StringComparison.Ordinal)) throw new Fail(64, Usage);

            string binDir = ExeDir();
            CheckFiles(binDir, new string[] { "module_1a.exe", "dnlib.dll" });

            string arguments = Quote(Path.GetFullPath(args[1]));
            if (args.Length == 3) arguments += " " + Quote(Path.GetFullPath(args[2]));

            string output;
            int code = RunTool(Path.Combine(binDir, "module_1a.exe"), arguments, binDir, false, out output);
            if (code < 0) throw new Fail(70, output);
            return code;
        }

        // --- protect ---

        private static int Protect(string[] args)
        {
            if (args.Length < 2 || args[1].StartsWith("--", StringComparison.Ordinal)) throw new Fail(64, Usage);
            string inputPath = Path.GetFullPath(args[1]);

            string outArg = null, confuserArg = null, obfArg = null, binArg = null;
            for (int i = 2; i < args.Length; i++)
            {
                string a = args[i];
                if (a == "--out") outArg = NextValue(args, ref i, a);
                else if (a == "--confuser") confuserArg = NextValue(args, ref i, a);
                else if (a == "--obfuscar") obfArg = NextValue(args, ref i, a);
                else if (a == "--bin-dir") binArg = NextValue(args, ref i, a);
                else throw new Fail(64, "未知参数: " + a + "\n" + Usage);
            }
            if (outArg == null) throw new Fail(64, "缺少 --out\n" + Usage);

            if (!File.Exists(inputPath)) throw new Fail(66, "找不到输入文件: " + inputPath);

            string outPath = Path.GetFullPath(outArg);
            string binDir = binArg != null ? Path.GetFullPath(binArg) : ExeDir();
            string inputDir = Path.GetDirectoryName(inputPath);

            if (PathsOverlap(outPath, inputDir)) throw new Fail(64, "输出目录与输入目录相同或互相包含，拒绝执行。");
            if (File.Exists(outPath) || (Directory.Exists(outPath) && Directory.GetFileSystemEntries(outPath).Length > 0))
                throw new Fail(64, "输出目录已存在且非空，拒绝覆盖: " + outPath);

            CheckFiles(binDir, RequiredTools);

            // 路由分析只读输入，结果写到临时目录，不写 --out（1C 要求输出目录为空）。
            string tmp = Path.Combine(Path.GetTempPath(), "bs_" + Guid.NewGuid().ToString("N").Substring(0, 8));
            Directory.CreateDirectory(tmp);
            try
            {
                string routeJson = Path.Combine(tmp, "route.json");
                string output;
                int c1a = RunTool(Path.Combine(binDir, "module_1a.exe"),
                    Quote(inputPath) + " " + Quote(routeJson), tmp, true, out output);
                if (c1a != 0) throw new Fail(70, "1A 分析输入失败（退出码 " + c1a + "）:\n" + Tail(output));

                IDictionary root = ReadJsonDict(routeJson);
                IDictionary inObj = AsDict(Get(root, "input"));
                if (inObj == null) throw new Fail(70, "1A 清单缺少 input 对象");

                object managed = Get(inObj, "isManaged");
                if (!IsTrue(managed)) throw new Fail(65, "输入不是托管 .NET 程序，无法保护。");

                string tfm = GetString(inObj, "targetFramework");
                if (tfm == null) throw new Fail(65, "1A 清单缺少 targetFramework，无法判断框架。");

                if (tfm.StartsWith(NetFxPrefix, StringComparison.Ordinal))
                    return RouteNetFx(inputPath, outPath, binDir, confuserArg);
                if (tfm.StartsWith(Net8Prefix, StringComparison.Ordinal))
                    return RouteNet8(inputPath, outPath, binDir, obfArg);

                throw new Fail(65, "目标框架不受支持: " + tfm + "（仅支持 .NET Framework 4.x 与 .NET 8）");
            }
            finally
            {
                try { Directory.Delete(tmp, true); } catch (Exception) { }
            }
        }

        // --- .NET Framework 路由：原样调用 1C ---

        private static int RouteNetFx(string inputPath, string outPath, string binDir, string confuserArg)
        {
            if (confuserArg == null) throw new Fail(64, ".NET Framework 路由需要 --confuser。");
            string confuser = Path.GetFullPath(confuserArg);
            if (!File.Exists(confuser)) throw new Fail(66, "找不到 ConfuserEx2 CLI: " + confuser);

            // 1C 直接输出到终端（进度可见），本模块只读取它的 report.json。
            string output;
            int c1c = RunTool(Path.Combine(binDir, "module_1c.exe"),
                "protect " + Quote(inputPath) + " --out " + Quote(outPath) + " --confuser " + Quote(confuser),
                binDir, false, out output);

            string rep1cPath = Path.Combine(outPath, "report.json");
            IDictionary rep1c = TryReadJsonDict(rep1cPath);
            int code = MapNetFxExit(c1c, rep1c);

            if (Directory.Exists(outPath))
            {
                Dictionary<string, object> steps = new Dictionary<string, object>(StringComparer.Ordinal);
                steps["module_1c"] = c1c;
                List<object> checks = new List<object>();
                if (rep1c != null)
                {
                    List<object> cs = AsList(Get(rep1c, "checks"));
                    if (cs != null) checks = cs;
                }
                WriteReport(outPath, "netfx", steps, checks, code);
            }

            if (code == 0) return 0;
            if (code == 3) throw new Fail(3, "复核有 FAIL，详见 " + Path.Combine(outPath, "bs-report.json"));
            if (code == 75) throw new Fail(75, "ConfuserEx2 步骤失败，详见 " + rep1cPath);
            throw new Fail(code, "1C 返回退出码 " + c1c + "（上面是 1C 的输出）。");
        }

        // 1C 的退出码直接映射。1C 的 70 有两种来源：1A/1B 失败（仍是我们的问题，70），
        // 或 ConfuserEx2 步骤失败（外部工具，75）。只有 1A、1B 都成功、ConfuserEx2 非 0 时才映射为 75。
        private static int MapNetFxExit(int c, IDictionary rep1c)
        {
            if (c == 0 || c == 2 || c == 3 || c == 64 || c == 65 || c == 66 || c == 73) return c;
            if (c == 70 && rep1c != null)
            {
                IDictionary steps = AsDict(Get(rep1c, "steps"));
                if (steps != null)
                {
                    IDictionary s1a = AsDict(Get(steps, "module_1a"));
                    IDictionary s1b = AsDict(Get(steps, "module_1b"));
                    IDictionary conf = AsDict(Get(steps, "confuser"));
                    if (ExitOf(s1a) == 0 && ExitOf(s1b) == 0 && conf != null && ExitOf(conf) != 0) return 75;
                }
            }
            return 70;
        }

        // --- .NET 8 路由：2B 编排 1A -> 2A -> Obfuscar -> 复核 ---

        private static int RouteNet8(string inputPath, string outPath, string binDir, string obfArg)
        {
            if (obfArg == null) throw new Fail(64, ".NET 8 路由需要 --obfuscar。");
            string obf = Path.GetFullPath(obfArg);
            if (!File.Exists(obf)) throw new Fail(66, "找不到 Obfuscar: " + obf);

            Dictionary<string, object> steps = new Dictionary<string, object>(StringComparer.Ordinal);
            List<object> checks = new List<object>();
            int code;
            try
            {
                code = Net8Steps(inputPath, outPath, binDir, obf, steps, checks);
            }
            catch (Fail f)
            {
                if (Directory.Exists(outPath)) WriteReport(outPath, "net8", steps, checks, f.Code);
                throw;
            }

            WriteReport(outPath, "net8", steps, checks, code);
            if (code == 3) throw new Fail(3, "复核有 FAIL，详见 " + Path.Combine(outPath, "bs-report.json"));
            return 0;
        }

        private static int Net8Steps(string inputPath, string outPath, string binDir, string obf,
            Dictionary<string, object> steps, List<object> checks)
        {
            string targetName = Path.GetFileName(inputPath);
            string inputDir = Path.GetDirectoryName(inputPath);
            string workDir = Path.Combine(outPath, "work");
            string inDir = Path.Combine(workDir, "in");
            string manifest = Path.Combine(workDir, "manifest.json");
            string cfg = Path.Combine(workDir, "obf.xml");
            string obfLog = Path.Combine(workDir, "obfuscar.log");
            string workProt = Path.Combine(workDir, "protected");
            string manifestProt = Path.Combine(workDir, "manifest-protected.json");
            string protDir = Path.Combine(outPath, "protected");
            string protTarget = Path.Combine(protDir, targetName);
            string sha0 = Sha256File(inputPath);
            string output;

            // 原输入不动：只在 work\in\ 的副本上运行 1A、2A、Obfuscar（N1）。
            try
            {
                Directory.CreateDirectory(inDir);   // 同时创建 outPath 与 work
                File.Copy(inputPath, Path.Combine(inDir, targetName), true);
                foreach (string f in Directory.GetFiles(inputDir))
                {
                    string name = Path.GetFileName(f);
                    if (string.Equals(name, targetName, StringComparison.OrdinalIgnoreCase)) continue;
                    if (IsRuntimeInput(name)) File.Copy(f, Path.Combine(inDir, name), true);
                }
            }
            catch (IOException ex) { throw new Fail(73, "无法准备工作副本: " + ex.Message); }
            catch (UnauthorizedAccessException ex) { throw new Fail(73, "无法准备工作副本: " + ex.Message); }

            int c1a = RunTool(Path.Combine(binDir, "module_1a.exe"),
                Quote(Path.Combine(inDir, targetName)) + " " + Quote(manifest), workDir, true, out output);
            steps["module_1a"] = c1a;
            if (c1a != 0) throw new Fail(70, "1A 分析工作副本失败（退出码 " + c1a + "）:\n" + Tail(output));

            int c2a = RunTool(Path.Combine(binDir, "module_2a.exe"),
                Quote(manifest) + " " + Quote(cfg), workDir, true, out output);
            steps["module_2a"] = c2a;
            if (c2a != 0)
            {
                // 2A 的输入类错误原样传出；其余视为内部步骤失败。
                if (c2a == 64 || c2a == 65 || c2a == 66 || c2a == 73) throw new Fail(c2a, "2A 失败:\n" + Tail(output));
                throw new Fail(70, "2A 失败（退出码 " + c2a + "）:\n" + Tail(output));
            }

            int cOb = RunTool("dotnet", Quote(obf) + " " + Quote(cfg), workDir, true, out output);
            steps["obfuscar"] = cOb;
            WriteText(obfLog, output);
            if (cOb != 0) throw new Fail(75, "Obfuscar 失败（退出码 " + cOb + "），日志: " + obfLog);
            if (!File.Exists(Path.Combine(workProt, targetName)))
                throw new Fail(75, "Obfuscar 返回 0，但没有生成 protected\\" + targetName);

            // 产物 + 依赖放入 out\protected（依赖规则同 1C；运行所需的 deps/runtimeconfig 也在内，N2）。
            try
            {
                Directory.CreateDirectory(protDir);
                foreach (string f in Directory.GetFiles(workProt))
                    File.Copy(f, Path.Combine(protDir, Path.GetFileName(f)), true);
                CopyDependencies(inputDir, protDir, targetName);
            }
            catch (IOException ex) { throw new Fail(73, "无法写入输出: " + ex.Message); }
            catch (UnauthorizedAccessException ex) { throw new Fail(73, "无法写入输出: " + ex.Message); }

            // 复核（第 8 节 n1–n6）：再次用 1A 读取保护后的程序。
            int c1aProt = RunTool(Path.Combine(binDir, "module_1a.exe"),
                Quote(protTarget) + " " + Quote(manifestProt), workDir, true, out output);
            IDictionary inM = ReadJsonDict(manifest);
            IDictionary outM = c1aProt == 0 ? TryReadJsonDict(manifestProt) : null;

            IDictionary inInput = AsDict(Get(inM, "input"));
            string tfmIn = inInput == null ? null : GetString(inInput, "targetFramework");
            IDictionary outInput = outM == null ? null : AsDict(Get(outM, "input"));

            bool protExists = File.Exists(protTarget);
            bool outManaged = outInput != null && IsTrue(Get(outInput, "isManaged"));
            string sha1 = Sha256File(inputPath);
            string shaOut = protExists ? Sha256File(protTarget) : "";

            // n1：保护后的程序存在，且为托管程序
            bool n1 = protExists && outManaged;
            AddCheck(checks, "n1", n1 ? "PASS" : "FAIL",
                n1 ? "保护后的程序存在，且为托管程序"
                   : (protExists ? "保护后的程序无法作为托管程序分析" : "保护后的程序不存在"));

            // n2：Avalonia 相关类型（skip == true）的全名集合与输入一致
            List<IDictionary> inTypes = CollectTypes(inM);
            List<string> inSkip = SkipNames(inTypes, true);
            if (outM == null)
            {
                AddCheck(checks, "n2", "FAIL", "无法分析保护后的程序集");
            }
            else
            {
                List<string> outSkip = SkipNames(CollectTypes(outM), true);
                bool same = string.Join("\n", inSkip) == string.Join("\n", outSkip);
                AddCheck(checks, "n2", same ? "PASS" : "FAIL",
                    "Avalonia 相关类型：输入 " + inSkip.Count + " 个，输出 " + outSkip.Count + " 个" + (same ? "，名称一致" : "，名称不一致"));
            }

            // n3：至少一个非 Avalonia 类型被改名。只作信息，不判失败（N5）。
            List<string> inPlain = SkipNames(inTypes, false);
            if (outM == null)
            {
                AddCheck(checks, "n3", "WARN", "无法分析保护后的程序集");
            }
            else if (inPlain.Count == 0)
            {
                AddCheck(checks, "n3", "WARN", "输入中没有 Avalonia 以外的类型可检查");
            }
            else
            {
                HashSet<string> outAll = new HashSet<string>(AllNames(CollectTypes(outM)), StringComparer.Ordinal);
                int renamed = 0;
                foreach (string name in inPlain) if (!outAll.Contains(name)) renamed++;
                if (renamed > 0)
                    AddCheck(checks, "n3", "PASS", "改名 " + renamed + " / " + inPlain.Count + " 个非 Avalonia 类型");
                else
                    AddCheck(checks, "n3", "WARN", "没有类型被改名（KeepPublicApi=true 时公开类型保持名字）");
            }

            // n4：输入文件运行前后未改变
            bool n4 = sha0 == sha1;
            AddCheck(checks, "n4", n4 ? "PASS" : "FAIL", "输入 SHA256 运行前后" + (n4 ? "相同" : "不同"));

            // n5：保护后的程序与输入不同
            bool n5 = protExists && shaOut != sha0;
            AddCheck(checks, "n5", n5 ? "PASS" : "FAIL", n5 ? "保护后的程序与输入不同" : "保护后的程序与输入相同或不存在");

            // n6：目标框架未改变
            bool n6 = outInput != null && tfmIn != null && string.Equals(GetString(outInput, "targetFramework"), tfmIn, StringComparison.Ordinal);
            AddCheck(checks, "n6", n6 ? "PASS" : "FAIL", "目标框架 " + (n6 ? "保持不变" : "与输入不一致或无法读取"));

            int fails = 0;
            foreach (object c in checks)
            {
                if (GetString((IDictionary)c, "status") == "FAIL") fails++;
            }
            return fails > 0 ? 3 : 0;
        }

        // --- 报告与检查项 ---

        private static void AddCheck(List<object> checks, string id, string status, string detail)
        {
            Dictionary<string, object> c = new Dictionary<string, object>(StringComparer.Ordinal);
            c["id"] = id;
            c["status"] = status;
            c["detail"] = detail;
            checks.Add(c);
        }

        private static void WriteReport(string outPath, string route, Dictionary<string, object> steps, List<object> checks, int exitCode)
        {
            Dictionary<string, object> r = new Dictionary<string, object>(StringComparer.Ordinal);
            r["tool"] = "BinaryShield";
            r["module"] = "2b";
            r["schemaVersion"] = "0.1";
            r["route"] = route;
            r["steps"] = steps;
            r["checks"] = checks;
            r["exitCode"] = exitCode;

            JavaScriptSerializer js = new JavaScriptSerializer();
            js.MaxJsonLength = int.MaxValue;
            File.WriteAllText(Path.Combine(outPath, "bs-report.json"), js.Serialize(r), Utf8NoBom);
        }

        private static List<IDictionary> CollectTypes(IDictionary manifest)
        {
            List<IDictionary> list = new List<IDictionary>();
            List<object> asms = AsList(Get(manifest, "assemblies"));
            if (asms == null) return list;
            foreach (object a in asms)
            {
                IDictionary asm = AsDict(a);
                if (asm == null) continue;
                List<object> mods = AsList(Get(asm, "modules"));
                if (mods == null) continue;
                foreach (object m in mods)
                {
                    IDictionary mod = AsDict(m);
                    if (mod == null) continue;
                    List<object> types = AsList(Get(mod, "types"));
                    if (types == null) continue;
                    foreach (object t in types)
                    {
                        IDictionary td = AsDict(t);
                        if (td != null) list.Add(td);
                    }
                }
            }
            return list;
        }

        // 按 skip 值筛选类型全名，并排序（用于逐项比较）。
        private static List<string> SkipNames(List<IDictionary> types, bool wantSkip)
        {
            List<string> names = new List<string>();
            foreach (IDictionary t in types)
            {
                if (IsTrue(Get(t, "skip")) != wantSkip) continue;
                string n = GetString(t, "fullName");
                if (n != null) names.Add(n);
            }
            names.Sort(StringComparer.Ordinal);
            return names;
        }

        private static List<string> AllNames(List<IDictionary> types)
        {
            List<string> names = new List<string>();
            foreach (IDictionary t in types)
            {
                string n = GetString(t, "fullName");
                if (n != null) names.Add(n);
            }
            return names;
        }

        // --- 进程 ---

        // 返回子进程退出码；超时返回 -2；无法启动返回 -1（原因写入 output）。
        // capture = true 时收集子进程输出（写日志用）；false 时输出直接显示在终端。
        private static int RunTool(string exe, string arguments, string workDir, bool capture, out string output)
        {
            output = "";
            StringBuilder log = new StringBuilder();
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe, arguments);
                psi.WorkingDirectory = workDir;
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.RedirectStandardInput = true;   // 子进程不会因等待输入而挂住
                if (capture)
                {
                    psi.RedirectStandardOutput = true;
                    psi.RedirectStandardError = true;
                }

                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    if (capture)
                    {
                        p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                        {
                            if (e.Data != null) lock (log) log.AppendLine(e.Data);
                        };
                        p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
                        {
                            if (e.Data != null) lock (log) log.AppendLine(e.Data);
                        };
                    }
                    p.Start();
                    p.StandardInput.Close();
                    if (capture)
                    {
                        p.BeginOutputReadLine();
                        p.BeginErrorReadLine();
                    }

                    if (!p.WaitForExit(ToolTimeoutMs))
                    {
                        KillTree(p);
                        DrainAsyncOutput(p);
                        lock (log) output = log.ToString();
                        return -2;
                    }

                    if (capture) DrainAsyncOutput(p);
                    lock (log) output = log.ToString();
                    return p.ExitCode;
                }
            }
            catch (Exception ex)
            {
                output = "无法启动 " + Path.GetFileName(exe) + ": " + ex.Message;
                return -1;
            }
        }

        // 异步输出的回调只有无参 WaitForExit() 才能保证全部处理完。放到后台线程并设上限，
        // 孙进程占住管道时不能无限等。
        private static void DrainAsyncOutput(Process p)
        {
            Thread t = new Thread(delegate()
            {
                try { p.WaitForExit(); }
                catch (Exception) { }
            });
            t.IsBackground = true;
            t.Start();
            t.Join(DrainTimeoutMs);
        }

        // 先用 taskkill 结束整棵进程树；失败时退回到只结束本进程。
        private static void KillTree(Process p)
        {
            try
            {
                ProcessStartInfo k = new ProcessStartInfo("taskkill", "/T /F /PID " + p.Id);
                k.UseShellExecute = false;
                k.CreateNoWindow = true;
                k.RedirectStandardOutput = true;
                k.RedirectStandardError = true;
                using (Process tk = Process.Start(k))
                {
                    tk.StandardOutput.ReadToEnd();
                    tk.StandardError.ReadToEnd();
                    tk.WaitForExit(DrainTimeoutMs);
                }
            }
            catch (Exception) { }

            try
            {
                if (!p.HasExited) p.Kill();
            }
            catch (Exception) { }
        }

        // --- 文件与路径 ---

        // 递归复制依赖目录（规则同 1C）。顶层跳过目标程序本身，已存在的文件不覆盖。
        private static void CopyDependencies(string srcDir, string dstDir, string skipTopLevelName)
        {
            Directory.CreateDirectory(dstDir);
            foreach (string f in Directory.GetFiles(srcDir))
            {
                string name = Path.GetFileName(f);
                if (skipTopLevelName != null && string.Equals(name, skipTopLevelName, StringComparison.OrdinalIgnoreCase)) continue;
                string dst = Path.Combine(dstDir, name);
                if (!File.Exists(dst)) File.Copy(f, dst, true);
            }
            foreach (string d in Directory.GetDirectories(srcDir))
            {
                CopyDependencies(d, Path.Combine(dstDir, Path.GetFileName(d)), null);
            }
        }

        // 工作副本需要的运行时文件：*.dll、*.deps.json、*.runtimeconfig.json（N1）。
        private static bool IsRuntimeInput(string name)
        {
            return name.EndsWith(".dll", StringComparison.OrdinalIgnoreCase)
                || name.EndsWith(".deps.json", StringComparison.OrdinalIgnoreCase)
                || name.EndsWith(".runtimeconfig.json", StringComparison.OrdinalIgnoreCase);
        }

        private static void CheckFiles(string dir, string[] names)
        {
            if (!Directory.Exists(dir)) throw new Fail(66, "工具目录不存在: " + dir);
            List<string> missing = new List<string>();
            foreach (string n in names)
            {
                if (!File.Exists(Path.Combine(dir, n))) missing.Add(n);
            }
            if (missing.Count > 0) throw new Fail(66, "工具目录 " + dir + " 缺少: " + string.Join(", ", missing));
        }

        private static string ExeDir()
        {
            return Path.GetFullPath(AppDomain.CurrentDomain.BaseDirectory);
        }

        // 两个路径是否相同，或一个位于另一个之内（与 1C 的判断相同）。
        private static bool PathsOverlap(string a, string b)
        {
            string na = EnsureTrailingSeparator(Path.GetFullPath(a));
            string nb = EnsureTrailingSeparator(Path.GetFullPath(b));
            return na.StartsWith(nb, StringComparison.OrdinalIgnoreCase)
                || nb.StartsWith(na, StringComparison.OrdinalIgnoreCase);
        }

        private static string EnsureTrailingSeparator(string p)
        {
            return p.EndsWith("\\", StringComparison.Ordinal) ? p : p + "\\";
        }

        private static string Sha256File(string path)
        {
            using (FileStream fs = File.OpenRead(path))
            using (SHA256 sha = SHA256.Create())
            {
                return BitConverter.ToString(sha.ComputeHash(fs)).Replace("-", "");
            }
        }

        private static void WriteText(string path, string text)
        {
            try
            {
                File.WriteAllText(path, text, Utf8NoBom);
            }
            catch (IOException ex) { throw new Fail(73, "无法写入 " + path + ": " + ex.Message); }
            catch (UnauthorizedAccessException ex) { throw new Fail(73, "无法写入 " + path + ": " + ex.Message); }
        }

        private static string NextValue(string[] args, ref int i, string name)
        {
            if (i + 1 >= args.Length) throw new Fail(64, name + " 缺少值");
            i++;
            return args[i];
        }

        private static string Quote(string p)
        {
            return "\"" + p + "\"";
        }

        // 超长输出只保留末尾（错误通常在最后）。
        private static string Tail(string s)
        {
            if (s == null) return "";
            if (s.Length <= TailChars) return s;
            return s.Substring(s.Length - TailChars);
        }

        // --- JSON（System.Web.Extensions，与 1A、1B、1C、2A 相同）---

        private static IDictionary ReadJsonDict(string path)
        {
            IDictionary d = TryReadJsonDict(path);
            if (d == null) throw new Fail(70, "无法读取 JSON 清单: " + path);
            return d;
        }

        private static IDictionary TryReadJsonDict(string path)
        {
            if (!File.Exists(path)) return null;
            try
            {
                JavaScriptSerializer js = new JavaScriptSerializer();
                js.MaxJsonLength = int.MaxValue;
                return js.DeserializeObject(File.ReadAllText(path, Encoding.UTF8)) as IDictionary;
            }
            catch (Exception)
            {
                return null;
            }
        }

        // JavaScriptSerializer 返回的数组类型不是固定的 object[]，按"可枚举、非字符串、非字典"判断。
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
            if (d == null) return null;
            return d.Contains(key) ? d[key] : null;
        }

        private static string GetString(IDictionary d, string key)
        {
            return Get(d, key) as string;
        }

        private static bool IsTrue(object o)
        {
            return o is bool && (bool)o;
        }

        private static int ExitOf(IDictionary d)
        {
            if (d == null) return 0;
            object e = Get(d, "exit");
            return e is int ? (int)e : 0;
        }
    }
}
