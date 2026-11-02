// BinaryShield — Module 1C: CLI 包装（一条命令跑完整条 .NET 保护流水线）
//
// 用法: module_1c protect <输入.dll|exe> --out <输出目录> --confuser <Confuser.CLI.exe 路径> [--keep-work]
//
// 流程: 1A 分析 → 1B 生成 .crproj → ConfuserEx2 执行 → 静态复核（只读元数据，不执行目标代码）→ report.json
// 退出码: 0 全部通过 | 1 参数错误 | 2 ConfuserEx2 路径无效或版本不符 | 3 复核有 FAIL
//         | 64 输出目录非空，或与输入重叠 | 65 输入不是托管程序 | 66 输入不存在
//         | 70 子步骤失败 | 73 无法写入输出
//
// 兼容性: .NET Framework 4.x 自带 csc(C# 5)，故不用字符串插值、?. 等新语法。
// 1A、1B 以子进程调用（决定点 D1）。dnlib 与 Module 1A 共用同一个 dll，运行时从 ../module_1a/ 加载。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;
using dnlib.DotNet;
using dnlib.DotNet.Emit;
using dnlib.DotNet.Resources;
using dnlib.IO;

namespace BinaryShield.Module1C
{
    internal static class Program
    {
        // ConfuserEx2 1.6.0 的 Confuser.Core.dll SHA256（D4）。来源：mkaring/ConfuserEx release v1.6.0 的 ConfuserEx-CLI.zip。
        private const string ExpectedCoreSha256 = "12193041A68CBBABB4A9EA7A7C14621407739F613516FEA5CC19D1BD1257C8ED";

        // 同一发布包中 Confuser.CLI.exe 的 SHA256（与 Core.dll 一起校验，防止只替换 CLI 本身）
        private const string ExpectedCliSha256 = "0790671F930BD1375FA06ECE29A776404CEE44695E083CACE46C905433644130";

        // 单个子进程的超时。ConfuserEx2 处理大程序可能较慢，所以给 10 分钟。
        private const int StepTimeoutMs = 10 * 60 * 1000;

        // 进程结束后，等待异步输出读完的上限。孙进程占住管道时，不能无限等。
        private const int DrainTimeoutMs = 5000;

        private const string Usage = "用法: module_1c protect <输入.dll|exe> --out <输出目录> --confuser <Confuser.CLI.exe 路径> [--keep-work]";

        private static int Main(string[] args)
        {
            AppDomain.CurrentDomain.AssemblyResolve += ResolveDnlib;
            try
            {
                Console.OutputEncoding = Encoding.UTF8;
            }
            catch (Exception)
            {
                // 没有控制台（服务、计划任务等）时忽略
            }

            Options opt = new Options();
            string argError = ParseArgs(args, opt);
            if (argError != null)
            {
                Console.Error.WriteLine("错误: " + argError);
                Console.Error.WriteLine(Usage);
                return 1;
            }

            string inputPath = Path.GetFullPath(opt.Input);
            if (!File.Exists(inputPath))
            {
                Console.Error.WriteLine("错误: 找不到输入文件: " + inputPath);
                return 66;
            }

            string outPath = Path.GetFullPath(opt.Out);
            string inputDir = Path.GetDirectoryName(inputPath);
            if (PathsOverlap(outPath, inputDir))
            {
                Console.Error.WriteLine("错误: 输出目录与输入目录相同或互相包含。");
                return 64;
            }
            if (Directory.Exists(outPath) && Directory.GetFileSystemEntries(outPath).Length > 0)
            {
                Console.Error.WriteLine("错误: 输出目录已存在且非空，拒绝覆盖: " + outPath);
                return 64;
            }

            string confuserPath = Path.GetFullPath(opt.Confuser);
            string confuserError = VerifyConfuser(confuserPath);
            if (confuserError != null)
            {
                Console.Error.WriteLine("错误: " + confuserError);
                return 2;
            }

            string targetName = Path.GetFileName(inputPath);
            string workDir = Path.Combine(outPath, "work");
            // 工作副本放在 work\ 根目录：1B 的 baseDir 是 .，子目录会被写进 ConfuserEx 的输出路径
            string workTarget = Path.Combine(workDir, targetName);
            string workProtected = Path.Combine(workDir, "protected");
            string protectedDir = Path.Combine(outPath, "protected");
            string protectedTarget = Path.Combine(protectedDir, targetName);
            string manifestPath = Path.Combine(workDir, "manifest.json");
            string configPath = Path.Combine(workDir, "config.crproj");
            string reportPath = Path.Combine(outPath, "report.json");

            string sha0 = Sha256File(inputPath);
            try
            {
                // 输入与同目录的其他 DLL 复制到 work\，原文件不动
                Directory.CreateDirectory(workDir);
                File.Copy(inputPath, workTarget, true);
                foreach (string dep in Directory.GetFiles(inputDir, "*.dll"))
                {
                    string depName = Path.GetFileName(dep);
                    if (string.Equals(depName, targetName, StringComparison.OrdinalIgnoreCase)) continue;
                    File.Copy(dep, Path.Combine(workDir, depName), true);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("错误: 无法准备工作目录: " + ex.Message);
                return 73;
            }

            Dictionary<string, StepResult> steps = new Dictionary<string, StepResult>(StringComparer.Ordinal);
            List<Dictionary<string, object>> checks = new List<Dictionary<string, object>>();
            int code = 0;

            // 1A：分析工作副本，写 manifest.json
            string tool1a = ResolveTool("module_1a");
            StepResult s1a = tool1a == null
                ? StepResult.Failed("找不到 module_1a.exe")
                : RunStep(tool1a, Quote(workTarget) + " " + Quote(manifestPath), workDir);
            steps["module_1a"] = s1a;
            if (s1a.Exit != 0)
            {
                code = 70;
            }
            else
            {
                int managed = ReadManagedFlag(manifestPath);
                if (managed < 0) code = 70;        // 清单无法读取
                else if (managed == 0) code = 65;  // 输入不是托管程序
            }

            // 1B：读取清单，写 config.crproj
            if (code == 0)
            {
                string tool1b = ResolveTool("module_1b");
                StepResult s1b = tool1b == null
                    ? StepResult.Failed("找不到 module_1b.exe")
                    : RunStep(tool1b, Quote(manifestPath) + " " + Quote(configPath), workDir);
                steps["module_1b"] = s1b;
                if (s1b.Exit != 0) code = 70;
            }
            else
            {
                steps["module_1b"] = StepResult.NotRun();
            }

            // ConfuserEx2：在 work\ 下执行生成的配置
            if (code == 0)
            {
                StepResult sc = RunStep(confuserPath, "-n " + Quote(configPath), workDir);
                if (sc.Exit == 0 && !File.Exists(Path.Combine(workProtected, targetName)))
                {
                    sc.Exit = 70;
                    sc.Stderr = sc.Stderr + "\n未生成 protected\\" + targetName;
                }
                steps["confuser"] = sc;
                if (sc.Exit != 0) code = 70;
            }
            else
            {
                steps["confuser"] = StepResult.NotRun();
            }

            // 产物与依赖 DLL 放入 protected\，再做静态复核
            if (code == 0)
            {
                try
                {
                    Directory.CreateDirectory(protectedDir);
                    foreach (string f in Directory.GetFiles(workProtected))
                    {
                        File.Copy(f, Path.Combine(protectedDir, Path.GetFileName(f)), true);
                    }
                    // 依赖连同子目录一起复制：SkiaSharp 等库的原生部分放在 x64\、x86\、arm64\ 等子目录中
                    CopyDependencies(inputDir, protectedDir, targetName);

                    // 应用配置（如 AvaloniaApp47.exe.config）含绑定重定向，必须随产物一起放入 protected\
                    string configSrc = inputPath + ".config";
                    if (File.Exists(configSrc))
                    {
                        File.Copy(configSrc, Path.Combine(protectedDir, targetName + ".config"), true);
                    }
                }
                catch (Exception ex)
                {
                    Console.Error.WriteLine("错误: 无法写入输出文件: " + ex.Message);
                    return 73;
                }

                try
                {
                    checks.AddRange(RunStaticChecks(workTarget, protectedTarget));
                }
                catch (Exception ex)
                {
                    checks.Clear();
                    foreach (string id in new string[] { "a", "b", "c", "d", "e" })
                    {
                        checks.Add(MakeCheck(id, "复核异常", "FAIL", ex.Message));
                    }
                }
            }

            // f：输入 SHA256 运行前后相同
            string sha1 = Sha256File(inputPath);
            bool unchanged = string.Equals(sha0, sha1, StringComparison.Ordinal);
            checks.Add(MakeCheck("f", "输入 SHA256 运行前后相同", unchanged ? "PASS" : "FAIL",
                "before=" + sha0 + " after=" + sha1));

            int pass = 0, fail = 0, warn = 0;
            foreach (Dictionary<string, object> c in checks)
            {
                string st = (string)c["status"];
                if (st == "PASS") pass++;
                else if (st == "FAIL") fail++;
                else warn++;
            }
            if (code == 0 && fail > 0) code = 3;

            // report.json
            Dictionary<string, object> report = new Dictionary<string, object>(StringComparer.Ordinal);
            report["tool"] = "BinaryShield";
            report["module"] = "1c";
            report["schemaVersion"] = "0.1";

            Dictionary<string, object> inputInfo = new Dictionary<string, object>(StringComparer.Ordinal);
            inputInfo["path"] = inputPath.Replace('\\', '/');
            inputInfo["sha256_before"] = sha0;
            inputInfo["sha256_after"] = sha1;
            inputInfo["unchanged"] = unchanged;
            report["input"] = inputInfo;

            Dictionary<string, object> stepInfo = new Dictionary<string, object>(StringComparer.Ordinal);
            foreach (string name in new string[] { "module_1a", "module_1b", "confuser" })
            {
                StepResult s = steps.ContainsKey(name) ? steps[name] : StepResult.NotRun();
                Dictionary<string, object> d = new Dictionary<string, object>(StringComparer.Ordinal);
                d["exit"] = s.Exit;
                d["stderr"] = s.Stderr;
                stepInfo[name] = d;
            }
            report["steps"] = stepInfo;
            report["checks"] = checks;

            Dictionary<string, object> summary = new Dictionary<string, object>(StringComparer.Ordinal);
            summary["pass"] = pass;
            summary["fail"] = fail;
            summary["warn"] = warn;
            report["summary"] = summary;
            report["exitCode"] = code;

            try
            {
                WriteJson(reportPath, report);
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("错误: 无法写入 report.json: " + ex.Message);
                return 73;
            }

            if (code == 0)
            {
                Console.WriteLine("完成。保护产物: " + protectedTarget);
            }
            else
            {
                Console.Error.WriteLine("退出码 " + code + "，详见 " + reportPath);
            }
            return code;
        }

        // --- 参数解析 ---

        private static string ParseArgs(string[] args, Options opt)
        {
            if (args.Length == 0 || args[0] != "protect") return "第一个参数必须是 protect";

            for (int i = 1; i < args.Length; i++)
            {
                string a = args[i];
                if (a == "--out")
                {
                    if (++i >= args.Length) return "--out 缺少值";
                    opt.Out = args[i];
                }
                else if (a == "--confuser")
                {
                    if (++i >= args.Length) return "--confuser 缺少值";
                    opt.Confuser = args[i];
                }
                else if (a == "--keep-work")
                {
                    opt.KeepWork = true;
                }
                else if (a.StartsWith("--", StringComparison.Ordinal))
                {
                    return "未知参数: " + a;
                }
                else if (opt.Input == null)
                {
                    opt.Input = a;
                }
                else
                {
                    return "多余的参数: " + a;
                }
            }

            if (opt.Input == null || opt.Out == null || opt.Confuser == null)
            {
                return "缺少必需参数：<输入> --out <目录> --confuser <路径>";
            }
            return null;
        }

        // --- 路径与工具 ---

        // 两个路径是否相同，或一个位于另一个之内
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

        // 同目录或仓库布局下的 ../<name>/<name>.exe
        private static string ResolveTool(string name)
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates =
            {
                Path.Combine(baseDir, "..", name, name + ".exe"),
                Path.Combine(baseDir, name + ".exe")
            };
            foreach (string c in candidates)
            {
                string full = Path.GetFullPath(c);
                if (File.Exists(full)) return full;
            }
            return null;
        }

        private static Assembly ResolveDnlib(object sender, ResolveEventArgs args)
        {
            AssemblyName name = new AssemblyName(args.Name);
            if (!string.Equals(name.Name, "dnlib", StringComparison.OrdinalIgnoreCase)) return null;

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string[] candidates =
            {
                Path.Combine(baseDir, "..", "module_1a", "dnlib.dll"),
                Path.Combine(baseDir, "dnlib.dll")
            };
            foreach (string c in candidates)
            {
                string full = Path.GetFullPath(c);
                if (File.Exists(full)) return Assembly.LoadFrom(full);
            }
            return null;
        }

        // ConfuserEx2 版本检查（D4）：Confuser.Core.dll 的 SHA256 必须与 1.6.0 一致
        private static string VerifyConfuser(string cliPath)
        {
            if (!File.Exists(cliPath)) return "找不到 ConfuserEx2 CLI: " + cliPath;

            string core = Path.Combine(Path.GetDirectoryName(cliPath), "Confuser.Core.dll");
            if (!File.Exists(core)) return "ConfuserEx2 目录中缺少 Confuser.Core.dll";

            string sha = Sha256File(core);
            if (!string.Equals(sha, ExpectedCoreSha256, StringComparison.OrdinalIgnoreCase))
            {
                return "Confuser.Core.dll 的 SHA256 与 ConfuserEx2 1.6.0 不符（实际 " + sha + "）";
            }

            string cliSha = Sha256File(cliPath);
            if (!string.Equals(cliSha, ExpectedCliSha256, StringComparison.OrdinalIgnoreCase))
            {
                return "Confuser.CLI.exe 的 SHA256 与 ConfuserEx2 1.6.0 不符（实际 " + cliSha + "）";
            }
            return null;
        }

        // 返回 1 = 托管，0 = 非托管，-1 = 清单无法读取
        private static int ReadManagedFlag(string manifestPath)
        {
            try
            {
                JavaScriptSerializer ser = new JavaScriptSerializer();
                ser.MaxJsonLength = int.MaxValue;
                Dictionary<string, object> root = ser.Deserialize<Dictionary<string, object>>(File.ReadAllText(manifestPath, Encoding.UTF8));
                object inputObj;
                if (!root.TryGetValue("input", out inputObj)) return -1;
                Dictionary<string, object> input = inputObj as Dictionary<string, object>;
                if (input == null) return -1;
                object managed;
                if (!input.TryGetValue("isManaged", out managed) || !(managed is bool)) return -1;
                return (bool)managed ? 1 : 0;
            }
            catch (Exception)
            {
                return -1;
            }
        }

        // --- 子进程 ---

        private static string Quote(string p)
        {
            return "\"" + p + "\"";
        }

        private static StepResult RunStep(string exe, string arguments, string workDir)
        {
            StringBuilder log = new StringBuilder();
            try
            {
                ProcessStartInfo psi = new ProcessStartInfo(exe, arguments);
                psi.WorkingDirectory = workDir;
                psi.UseShellExecute = false;
                psi.RedirectStandardOutput = true;
                psi.RedirectStandardError = true;
                psi.RedirectStandardInput = true; // 子进程不会因等待输入而挂住
                psi.CreateNoWindow = true;

                using (Process p = new Process())
                {
                    p.StartInfo = psi;
                    p.OutputDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (e.Data != null) lock (log) log.AppendLine(e.Data);
                    };
                    p.ErrorDataReceived += delegate(object s, DataReceivedEventArgs e)
                    {
                        if (e.Data != null) lock (log) log.AppendLine(e.Data);
                    };
                    p.Start();
                    p.StandardInput.Close();
                    p.BeginOutputReadLine();
                    p.BeginErrorReadLine();
                    if (!p.WaitForExit(StepTimeoutMs))
                    {
                        KillTree(p);
                        DrainAsyncOutput(p);
                        string partial;
                        lock (log) partial = log.ToString();
                        return new StepResult(-2, "超时（超过 " + (StepTimeoutMs / 1000) + " 秒），已终止。\n" + Tail(partial));
                    }
                    DrainAsyncOutput(p); // 进程已退出：等异步输出读完（有上限）

                    string text;
                    lock (log) text = log.ToString();
                    return new StepResult(p.ExitCode, Tail(text));
                }
            }
            catch (Exception ex)
            {
                return StepResult.Failed("无法启动 " + Path.GetFileName(exe) + ": " + ex.Message);
            }
        }

        // 异步输出的回调只有无参 WaitForExit() 才能保证全部处理完。
        // 放到后台线程里并设上限：孙进程占住管道时，不能无限等。
        private static void DrainAsyncOutput(Process p)
        {
            Thread t = new Thread(delegate()
            {
                try
                {
                    p.WaitForExit();
                }
                catch (Exception)
                {
                    // 进程对象已被释放等情况：忽略，只影响日志完整性
                }
            });
            t.IsBackground = true;
            t.Start();
            t.Join(DrainTimeoutMs);
        }

        // 先用 taskkill 结束整棵进程树（含孙进程）；失败时退回到只结束本进程
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
            catch (Exception)
            {
                // taskkill 不可用时，退回到下面的 Kill
            }

            try
            {
                if (!p.HasExited) p.Kill();
            }
            catch (Exception)
            {
                // 进程在检查与 Kill 之间已经退出：忽略，不影响超时的结论
            }
        }

        // 递归复制依赖目录。顶层跳过目标程序本身（它已由 ConfuserEx2 生成），已存在的文件不覆盖。
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

        // 完整保留子进程输出。超长时保留前 40000 字符（根因通常在前面）和后 20000 字符。
        private static string Tail(string s)
        {
            const int Max = 60000;
            const int Head = 40000;
            const int TailLen = 20000;
            if (s.Length <= Max) return s;
            return s.Substring(0, Head)
                + "\n...（中间省略 " + (s.Length - Head - TailLen) + " 字符）...\n"
                + s.Substring(s.Length - TailLen);
        }

        // --- 静态复核（只读，见 spec 第 6 节）---

        private static List<Dictionary<string, object>> RunStaticChecks(string originalPath, string protectedPath)
        {
            List<Dictionary<string, object>> checks = new List<Dictionary<string, object>>();

            using (ModuleDefMD orig = ModuleDefMD.Load(originalPath))
            using (ModuleDefMD prot = ModuleDefMD.Load(protectedPath))
            {
                Dictionary<string, TypeDef> origTypes = IndexTypes(orig);
                Dictionary<string, TypeDef> protTypes = IndexTypes(prot);

                List<string> literalFail = new List<string>();
                List<string> signatureFail = new List<string>();
                List<string> ilFail = new List<string>();
                int avaloniaTypes = 0;
                int avaloniaMethods = 0;

                foreach (TypeDef t in origTypes.Values)
                {
                    if (!IsExcludedNamespace(t.Namespace)) continue;
                    avaloniaTypes++;

                    TypeDef pt;
                    if (!protTypes.TryGetValue(t.FullName, out pt))
                    {
                        signatureFail.Add("类型缺失: " + t.FullName);
                        continue;
                    }

                    if (!SameSet(MethodNames(t), MethodNames(pt))) signatureFail.Add("方法签名不同: " + t.FullName);
                    if (!SameSet(FieldNames(t), FieldNames(pt))) signatureFail.Add("字段不同: " + t.FullName);

                    foreach (MethodDef m in t.Methods)
                    {
                        if (!m.HasBody) continue;
                        MethodDef pm = FindMethod(pt, m.FullName);
                        if (pm == null) continue; // 已在签名比较中报告
                        avaloniaMethods++;

                        if (!SameList(Literals(m), Literals(pm))) literalFail.Add(m.FullName);
                        if (!SameList(NormalizedIL(m), NormalizedIL(pm))) ilFail.Add(m.FullName);
                    }
                }

                checks.Add(MakeCheck("a", "Avalonia 方法的字符串字面量保持明文",
                    literalFail.Count == 0 ? "PASS" : "FAIL",
                    avaloniaMethods == 0 ? "无 Avalonia 命名空间方法可比较"
                        : "方法 " + avaloniaMethods + " 个；不同: " + Join(literalFail)));

                checks.Add(MakeCheck("b", "Avalonia 类型名与成员签名不变",
                    signatureFail.Count == 0 ? "PASS" : "FAIL",
                    avaloniaTypes == 0 ? "无 Avalonia 命名空间类型"
                        : "类型 " + avaloniaTypes + " 个；不同: " + Join(signatureFail)));

                checks.Add(MakeCheck("c", "Avalonia 方法的 IL 长度不变",
                    ilFail.Count == 0 ? "PASS" : "FAIL",
                    avaloniaMethods == 0 ? "无 Avalonia 命名空间方法可比较"
                        : "方法 " + avaloniaMethods + " 个；不同: " + Join(ilFail)));

                Dictionary<string, string> origRes = ResourceHashes(orig);
                Dictionary<string, string> protRes = ResourceHashes(prot);
                List<string> resourceFail = new List<string>();
                foreach (KeyValuePair<string, string> kv in origRes)
                {
                    string pv;
                    if (!protRes.TryGetValue(kv.Key, out pv)) resourceFail.Add("缺失 " + kv.Key);
                    else if (pv != kv.Value) resourceFail.Add("字节不同 " + kv.Key);
                }
                foreach (string k in protRes.Keys)
                {
                    if (!origRes.ContainsKey(k)) resourceFail.Add("新增 " + k);
                }
                checks.Add(MakeCheck("d", "嵌入资源的名字与字节逐个相同",
                    resourceFail.Count == 0 ? "PASS" : "FAIL",
                    origRes.Count == 0 ? "无嵌入资源"
                        : "资源 " + origRes.Count + " 个；不同: " + Join(resourceFail)));

                // e：直接继承 Avalonia 类型的应用类（D6：只作为警告）
                List<string> inheritors = new List<string>();
                List<string> problems = new List<string>();
                foreach (TypeDef t in origTypes.Values)
                {
                    if (IsAvalonia(t.Namespace)) continue;
                    if (t.BaseType == null || !IsAvalonia(t.BaseType.Namespace)) continue;
                    inheritors.Add(t.FullName);

                    TypeDef pt;
                    if (!protTypes.TryGetValue(t.FullName, out pt))
                    {
                        problems.Add("名字改变或消失: " + t.FullName);
                        continue;
                    }
                    foreach (MethodDef m in t.Methods)
                    {
                        if (!m.HasBody) continue;
                        MethodDef pm = FindMethod(pt, m.FullName);
                        if (pm == null)
                        {
                            problems.Add("方法签名改变: " + m.FullName);
                            continue;
                        }
                        if (!SameList(NormalizedIL(m), NormalizedIL(pm))) problems.Add("指令序列改变: " + m.FullName);
                    }
                }
                if (inheritors.Count == 0)
                {
                    checks.Add(MakeCheck("e", "应用界面类（继承 Avalonia 类型）", "PASS", "未发现直接继承 Avalonia 类型的应用类"));
                }
                else if (problems.Count == 0)
                {
                    checks.Add(MakeCheck("e", "应用界面类（继承 Avalonia 类型）", "PASS",
                        "类 " + inheritors.Count + " 个，名字与 IL 保持: " + Join(inheritors)));
                }
                else
                {
                    checks.Add(MakeCheck("e", "应用界面类（继承 Avalonia 类型）", "WARN",
                        "类 " + inheritors.Count + " 个；变化: " + Join(problems)));
                }
            }

            return checks;
        }

        private static Dictionary<string, TypeDef> IndexTypes(ModuleDef mod)
        {
            Dictionary<string, TypeDef> d = new Dictionary<string, TypeDef>(StringComparer.Ordinal);
            foreach (TypeDef t in mod.GetTypes())
            {
                if (!d.ContainsKey(t.FullName)) d.Add(t.FullName, t);
            }
            return d;
        }

        private static MethodDef FindMethod(TypeDef t, string fullName)
        {
            foreach (MethodDef m in t.Methods)
            {
                if (m.FullName == fullName) return m;
            }
            return null;
        }

        private static HashSet<string> MethodNames(TypeDef t)
        {
            HashSet<string> set = new HashSet<string>(StringComparer.Ordinal);
            foreach (MethodDef m in t.Methods) set.Add(m.FullName);
            return set;
        }

        private static HashSet<string> FieldNames(TypeDef t)
        {
            HashSet<string> set = new HashSet<string>(StringComparer.Ordinal);
            foreach (FieldDef f in t.Fields) set.Add(f.Name.ToString());
            return set;
        }

        private static List<string> Literals(MethodDef m)
        {
            List<string> list = new List<string>();
            if (m.HasBody && m.Body != null)
            {
                foreach (Instruction i in m.Body.Instructions)
                {
                    if (i.OpCode.Code == Code.Ldstr)
                    {
                        string s = i.Operand as string;
                        list.Add(s ?? "");
                    }
                }
            }
            list.Sort(StringComparer.Ordinal);
            return list;
        }

        // 归一化指令序列：短/长形式视为相同；分支目标按指令序号比较；成员引用按全名比较。
        // 原始字节长度会因 dnlib 重新编码（如 ldc.i4 5 → ldc.i4.5）而变化，不能直接用来判断是否被改动。
        private static List<string> NormalizedIL(MethodDef m)
        {
            List<string> list = new List<string>();
            if (!m.HasBody || m.Body == null) return list;

            IList<Instruction> ins = m.Body.Instructions;
            Dictionary<Instruction, int> index = new Dictionary<Instruction, int>();
            for (int i = 0; i < ins.Count; i++) index[ins[i]] = i;

            foreach (Instruction i in ins)
            {
                string extra;
                string op = NormalizeOpName(i.OpCode.Name, out extra);
                string operand = null;

                Instruction target = i.Operand as Instruction;
                IList<Instruction> targets = i.Operand as IList<Instruction>;
                IFullName named = i.Operand as IFullName;
                if (target != null)
                {
                    int t;
                    operand = index.TryGetValue(target, out t) ? "->" + t : "->?";
                }
                else if (targets != null)
                {
                    List<string> parts = new List<string>();
                    foreach (Instruction x in targets)
                    {
                        int t;
                        parts.Add(index.TryGetValue(x, out t) ? t.ToString() : "?");
                    }
                    operand = "switch:" + string.Join(",", parts);
                }
                else if (named != null)
                {
                    operand = "ref:" + named.FullName;
                }
                else if (i.Operand is Parameter)
                {
                    operand = "p" + ((Parameter)i.Operand).Index;
                }
                else if (i.Operand is Local)
                {
                    operand = "l" + ((Local)i.Operand).Index;
                }
                else if (i.Operand != null)
                {
                    operand = Convert.ToString(i.Operand, System.Globalization.CultureInfo.InvariantCulture);
                }

                // 短形式的数字（如 ldc.i4.5、ldarg.0）已经折叠进 extra，优先使用它，保证与长形式一致
                list.Add(extra != null ? op + " " + extra : op + (operand == null ? "" : " " + operand));
            }
            return list;
        }

        // 把短形式指令名折叠为基本名。返回基本名；数字后缀（ldc.i4.5 → 5）放进 extra。
        private static string NormalizeOpName(string name, out string extra)
        {
            extra = null;
            if (name == "ldc.i4.m1")
            {
                extra = "-1";
                return "ldc.i4";
            }
            if (name.StartsWith("ldc.i4.", StringComparison.Ordinal)
                || name.StartsWith("ldarg.", StringComparison.Ordinal)
                || name.StartsWith("ldloc.", StringComparison.Ordinal)
                || name.StartsWith("stloc.", StringComparison.Ordinal))
            {
                char last = name[name.Length - 1];
                if (char.IsDigit(last))
                {
                    extra = last.ToString();
                    return name.Substring(0, name.Length - 2);
                }
            }
            if (name.EndsWith(".s", StringComparison.Ordinal))
            {
                return name.Substring(0, name.Length - 2);
            }
            return name;
        }

        private static int ILSize(MethodDef m)
        {
            int size = 0;
            if (m.HasBody && m.Body != null)
            {
                foreach (Instruction i in m.Body.Instructions) size += i.GetSize();
            }
            return size;
        }

        private static Dictionary<string, string> ResourceHashes(ModuleDef mod)
        {
            Dictionary<string, string> d = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (Resource r in mod.Resources)
            {
                EmbeddedResource er = r as EmbeddedResource;
                if (er == null) continue;

                DataReader reader = er.CreateReader();
                byte[] data = reader.ReadBytes((int)reader.Length);
                using (SHA256 sha = SHA256.Create())
                {
                    d[er.Name.ToString()] = ToHex(sha.ComputeHash(data));
                }
            }
            return d;
        }

        private static bool IsAvalonia(string ns)
        {
            if (string.IsNullOrEmpty(ns)) return false;
            return ns == "Avalonia" || ns.StartsWith("Avalonia.", StringComparison.Ordinal);
        }

        // 排除范围与 Module 1B 的排除规则一致：Avalonia.* 与 CompiledAvaloniaXaml（Avalonia 编译 XAML 生成的代码）
        private static bool IsExcludedNamespace(string ns)
        {
            if (IsAvalonia(ns)) return true;
            if (string.IsNullOrEmpty(ns)) return false;
            return ns == "CompiledAvaloniaXaml" || ns.StartsWith("CompiledAvaloniaXaml.", StringComparison.Ordinal);
        }

        private static bool SameSet(HashSet<string> a, HashSet<string> b)
        {
            return a.SetEquals(b);
        }

        private static bool SameList(List<string> a, List<string> b)
        {
            if (a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++)
            {
                if (a[i] != b[i]) return false;
            }
            return true;
        }

        private static string Join(List<string> items)
        {
            if (items.Count == 0) return "无";
            return string.Join("; ", items);
        }

        private static Dictionary<string, object> MakeCheck(string id, string name, string status, string detail)
        {
            Dictionary<string, object> c = new Dictionary<string, object>(StringComparer.Ordinal);
            c["id"] = id;
            c["name"] = name;
            c["status"] = status;
            c["detail"] = detail;
            return c;
        }

        // --- 杂项 ---

        private static string Sha256File(string path)
        {
            using (SHA256 sha = SHA256.Create())
            using (FileStream fs = File.OpenRead(path))
            {
                return ToHex(sha.ComputeHash(fs));
            }
        }

        private static string ToHex(byte[] bytes)
        {
            StringBuilder sb = new StringBuilder(bytes.Length * 2);
            foreach (byte b in bytes) sb.Append(b.ToString("X2"));
            return sb.ToString();
        }

        private static void WriteJson(string path, Dictionary<string, object> report)
        {
            JavaScriptSerializer ser = new JavaScriptSerializer();
            ser.MaxJsonLength = int.MaxValue;
            string json = ser.Serialize(report); // 先完成序列化，序列化失败时不碰原文件

            // 先写临时文件，再替换目标：写入中途失败时，原 report.json 保持不变
            string temp = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            try
            {
                using (FileStream fs = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                {
                    byte[] bytes = new UTF8Encoding(false).GetBytes(json);
                    fs.Write(bytes, 0, bytes.Length);
                    fs.Flush(true); // 落盘：避免断电后 report.json 为空或被截断
                }
                if (File.Exists(path))
                {
                    File.Replace(temp, path, null);
                }
                else
                {
                    File.Move(temp, path);
                }
            }
            finally
            {
                if (File.Exists(temp)) File.Delete(temp);
            }
        }
    }

    internal sealed class Options
    {
        public string Input;
        public string Out;
        public string Confuser;
        public bool KeepWork;
    }

    internal sealed class StepResult
    {
        public int Exit;
        public string Stderr;

        public StepResult(int exit, string stderr)
        {
            Exit = exit;
            Stderr = stderr;
        }

        public static StepResult NotRun()
        {
            return new StepResult(-1, "未执行");
        }

        public static StepResult Failed(string message)
        {
            return new StepResult(-1, message);
        }
    }
}
