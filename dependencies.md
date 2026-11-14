# 依赖与版本登记（dependencies.md）

> 本文件登记项目实际使用的库和版本。README 的"锁定技术栈"若有调整，必须在此记录原因。
> 最近更新：2026-11-02

## 已确认的技术决策（Module 1A，经人工确认）

1. **托管侧实现语言 = C#**
   - 原因：锁定库 dnlib 是 .NET(C#) 库，无法从 C 直接调用；`src/dotnet/` 模块用 C# + .NET Framework 4.7，`src/native/` 模块仍用 C。README 原本就把两类分在不同目录，此处只是把说明补明确，未更换任何锁定库。
2. **JSON 输出 = .NET Framework 内置方式，不引入未锁定的第三方库**（手写轻量序列化，完全控制结构与 IL 偏移字段）。
3. **Avalonia 匹配**：命名空间以 `Avalonia.` 开头 **或** 正好等于 `Avalonia` → `skip: true`。
4. 输出：默认写入 JSON 文件；可选参数打印到屏幕（stdout）。

## 库清单

| 用途 | 库 / 工具 | 版本 | 来源 | 状态 |
|------|-----------|------|------|------|
| .NET IL 读/写 | dnlib | v4.5.0（GitHub 最新 release） | NuGet 包 `dnlib.4.5.0.nupkg`（GitHub release 无预编译 dll） | 待构建时下载 |
| C# 编译器 | csc.exe (.NET Framework) | v4.0.30319 | `C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe`（系统自带） | ✅ 本机已有 |
| 目标运行时 | .NET Framework | 4.7 | 系统自带 | ✅ |
| 版本控制 | git | 2.55 | 系统自带 | ✅ |
| GitHub 访问 | gh (GitHub CLI) | 2.98 | 系统自带 | ✅ |
| JSON 解析 | System.Web.Extensions（JavaScriptSerializer） | .NET Framework 4.x 自带 | 框架程序集，本机 GAC 已确认可用 | ✅ 已确认（Module 1B 决定点 D） |
| 保护引擎（外部工具，仅调用，不改写） | ConfuserEx2 | 1.6.0（mkaring/ConfuserEx，release v1.6.0，2022-01-17） | `ConfuserEx-CLI.zip`，GitHub 未提供摘要，本地算得 SHA256 `A00DE7CDDC740F7EDB1BAAB4C6C9073553DCC88F7E873D15B7FD34DDD33753D7` | ✅ 已下载、已实测 |
| .NET 8 保护引擎（外部工具，仅调用，不改写） | Obfuscar.GlobalTool | 3.0.0-beta.22（obfuscar/obfuscar，MIT，LeXtudio 维护） | NuGet 包 `obfuscar.globaltool.3.0.0-beta.22.nupkg`，5,596,857 字节，SHA256 `36EA43A84D83642ADEE9ECEE3D370F36687602B24FEDCF98FCDB572A5A873709`，SHA512（base64，与 NuGet v2 API 的 PackageHash 一致）`XEKW1r1xb5FCUbo2LYhRZjIOM817U8KkLZBd3nAAhzEWfOvJh4JyF3fCkOaeULTZFF9/hcn35FrxqzF9KkgwJw==`。下载：`https://api.nuget.org/v3-flatcontainer/obfuscar.globaltool/3.0.0-beta.22/obfuscar.globaltool.3.0.0-beta.22.nupkg` | ✅ 已下载、已实测（.NET 8 Hello World；.NET 8 Avalonia 11 最小程序） |
| 测试程序 DataGrid（仅 `tests/dotnet8_complex`，不进入 BinaryShield 工具本身） | Avalonia.Controls.DataGrid | 11.0.10（与 Avalonia 同版本） | NuGet 包，`PackageReference` 写在 `ComplexDemo.csproj` 中，随 `/restore` 下载 | ✅ 已编译、已在 Windows 和 Linux 运行（2026-11-13） |
| 演示：C++ 编译期字符串加密（仅 `tests/string_encrypt_demo`，不进入 BinaryShield 工具本身） | ADVobfuscator | commit `9058623d0caf1fdf784d16e7f9233d29a5993acb`（2026-10-27），BSD-3-Clause-Clear | `git clone` 到 `tests/string_encrypt_demo/third_party/`（已加入 `.gitignore`，不提交） | ✅ 已编译、已验证（2026-11-14） |
| 演示：Rust 编译期字符串加密（仅 `tests/string_encrypt_demo`） | obfstr | 0.4.6，commit `9e56c1938dfd3bd65fe305fbafcb57394c701356`（2026-07-17），MIT | `rust/Cargo.toml` 从 GitHub 按 rev 拉取 | ✅ 已编译、已验证（2026-11-14） |
| 演示工具链：C++ 编译器 | MinGW-w64 GCC（WinLibs POSIX UCRT） | 16.2.0（r3） | winget `BrechtSanders.WinLibs.POSIX.UCRT`（2026-11-14 经用户授权安装） | ✅ 已安装 |
| 演示工具链：Rust | rustup 1.29.3，rustc 1.100.0，`stable-x86_64-pc-windows-gnu` | 1.100.0 | winget `Rustlang.Rustup`（2026-11-14 经用户授权安装）；GNU 工具链用 `rustup toolchain install` 安装 | ✅ 已安装（默认 MSVC 工具链不可用，缺 `link.exe`） |

## dnlib 获取方式（无 nuget/dotnet 时）

本机没有 nuget / dotnet SDK / msbuild。dnlib 的 NuGet 包本质是 zip，取法：
- 下载：`https://api.nuget.org/v3-flatcontainer/dnlib/4.5.0/dnlib.4.5.0.nupkg`
- 解压后取 .NET Framework 目标（`lib/net45/dnlib.dll`，兼容 4.7）
- 编译时 `csc /reference:dnlib.dll ...` 引用即可

## ConfuserEx2 实测结论（Module 1B 研究）

详细过程与证据见 `src/dotnet/module_1b/spec.md` 第 6 节。要点：
- `startswith(...)`、`namespace-prefix(...)` 不是 ConfuserEx2 1.6.0 的合法函数，CLI 会直接报错。
- `namespace(...)` 按**完整匹配**：`Avalonia(\..*)?` 同时覆盖精确命名空间与子命名空间。
- 只写排除规则（不移除保护）**不起排除作用**；必须对每个保护项写 `<protection id="..." action="remove"/>`。
- 保护 ID 共 12 个，`Ki.Compressor.Protection` 不能作为项目里的保护 ID 移除。

## Obfuscar 3.0 beta 实测结论（2026-11-02）

- 包内的运行入口是 `tools/net8.0/any/GlobalTools.dll`，用 `dotnet GlobalTools.dll <配置.xml>` 运行（命令名 `obfuscar.console`）。本机 .NET 8 运行时 8.0.33 可以运行。
- 配置必须使用绝对路径和明确的值。`$(...)` 变量替换会报错（`Variable substitution via $(...) is not supported`）。
- 引用解析：`System.Runtime` 从 `Microsoft.NETCore.App.Ref\8.0.33` 找到，ConfuserEx 那次的引用解析错误没有出现。
- `SkipNamespace Avalonia*` 与 `SkipNamespace CompiledAvaloniaXaml*` 在 mapping 中确实生效（相关类型被跳过）；但不加这两条规则的对照组同样能启动，所以它们的必要性未证明。
- 测试范围（2026-11-02）：只验证了 .NET 8 Hello World 和最小 Avalonia 11 程序的启动与界面显示。
- 配置需要 `<Var name="InPath" value="...">` 指向包含依赖 DLL 的目录（2026-11-12）。没有它时，Obfuscar 只搜索配置文件所在目录，报 `Unable to resolve dependency: Avalonia.Controls`。
- 2026-11-12：ListBox 10,000 项、数据绑定、按钮点击、滚轮滚动，保护前后在 Windows 上通过（`tests/dotnet8_avalonia`，单次运行，模拟鼠标输入）。未测 Linux、DataGrid、复杂 XAML 和大型程序。
- 运行时会输出 net6.0 参考目录不存在的警告（如 `Microsoft.NETCore.App.Ref\6.0.0`），不影响结果。
- Linux 运行（2026-11-12）：测试程序用 `dotnet publish -r linux-x64 --self-contained`，运行时随程序一起发布，Ubuntu 上不需要安装 .NET。Ubuntu 没有 ICU（libicu），测试用 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`。X11 运行库（libice6、libsm6、libxi6、libxext6、libxrender1）用 `apt-get download` + `dpkg-deb -x` 解压到 `tests/dotnet8_avalonia/out/linux/syslibs`，不用 sudo。真实 Linux 部署要装 libicu 或保留不变模式，需要写进部署说明。

## 待办 / 开放问题

- [ ] 构建阶段实际下载 dnlib.dll 并核对内部 `lib/` 目标目录名
- [ ] 需要一个测试用 .dll（含字符串字面量 + 一个 `Avalonia.*` 命名空间），计划用 csc 现场编译生成
