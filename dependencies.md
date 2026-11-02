# 依赖与版本登记（dependencies.md）

> 本文件登记项目实际使用的库和版本。README 的"锁定技术栈"若有调整，必须在此记录原因。
> 最近更新：2026-11-01

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

## 待办 / 开放问题

- [ ] 构建阶段实际下载 dnlib.dll 并核对内部 `lib/` 目标目录名
- [ ] 需要一个测试用 .dll（含字符串字面量 + 一个 `Avalonia.*` 命名空间），计划用 csc 现场编译生成
