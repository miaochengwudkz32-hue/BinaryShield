# BinaryShield 使用说明

本文件说明如何构建、运行和理解 BinaryShield。快速概览见 [README.md](README.md)。

BinaryShield 只调用 ConfuserEx2，适用于 .NET Framework 4.x 程序。.NET 8 程序使用 Obfuscar，需要手动运行，说明见第 13 节。

## 1. 前提条件

| 项目 | 要求 |
|---|---|
| 操作系统 | Windows（已在 Windows 11 上测试） |
| .NET 运行时 | .NET Framework 4.x（系统自带即可，已在 4.8.1 上测试） |
| 编译工具 | `csc.exe`（.NET Framework 4.x 自带），或 Visual Studio 2022 的 MSBuild |
| ConfuserEx2 | 1.6.0 的命令行工具 `Confuser.CLI.exe`（见第 2 节） |

BinaryShield 只能处理**托管的 .NET 程序集**（.dll 或 .exe）。原生程序会被拒绝（退出码 65）。

## 2. 获取 ConfuserEx2 1.6.0

BinaryShield 不会自动下载 ConfuserEx2，需要你自己获取：

1. 打开 https://github.com/mkaring/ConfuserEx/releases/tag/v1.6.0 ，下载 `ConfuserEx-CLI.zip`。
2. 核对压缩包的 SHA256（PowerShell）：

   ```bash
   Get-FileHash .\ConfuserEx-CLI.zip -Algorithm SHA256
   ```

   应为 `A00DE7CDDC740F7EDB1BAAB4C6C9073553DCC88F7E873D15B7FD34DDD33753D7`。

3. 解压到任意目录，例如 `C:\tools\ConfuserEx\`。
4. 核对解压后的两个文件（BinaryShield 启动时也会自行校验，不一致会以退出码 2 拒绝运行）：

   | 文件 | SHA256 |
   |---|---|
   | `Confuser.Core.dll` | `12193041A68CBBABB4A9EA7A7C14621407739F613516FEA5CC19D1BD1257C8ED` |
   | `Confuser.CLI.exe` | `0790671F930BD1375FA06ECE29A776404CEE44695E083CACE46C905433644130` |

## 3. 构建

仓库里的源码需要分别编译。下面的命令假设在仓库根目录执行，并使用 `csc.exe`。

```bash
set CSC=C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe

%CSC% /nologo /target:exe /platform:anycpu /out:src\dotnet\module_1a\module_1a.exe src\dotnet\module_1a\Program.cs /reference:src\dotnet\module_1a\dnlib.dll

%CSC% /nologo /target:exe /platform:anycpu /out:src\dotnet\module_1b\module_1b.exe src\dotnet\module_1b\Program.cs

%CSC% /nologo /target:exe /platform:anycpu /out:src\dotnet\module_1c\module_1c.exe src\dotnet\module_1c\Program.cs /reference:src\dotnet\module_1a\dnlib.dll
```

编译后，`module_1c.exe` 会在同级的 `..\module_1a\` 与 `..\module_1b\` 目录中查找 `module_1a.exe` 和 `module_1b.exe`，所以保持仓库的目录结构不变。

也可以用 Visual Studio 2022 的 MSBuild 编译同样的源码（需要 .NET Framework 4.7 目标包时要确认已安装）。

## 4. 快速上手：一条命令完成保护

```bash
module_1c.exe protect "C:\path\to\YourApp.exe" --out "C:\path\to\output" --confuser "C:\tools\ConfuserEx\Confuser.CLI.exe"
```

参数说明：

| 参数 | 含义 |
|---|---|
| `protect` | 子命令（目前只有这一个） |
| `<输入>` | 要保护的 .dll 或 .exe（绝对或相对路径） |
| `--out <目录>` | 输出目录。**必须不存在或为空**，否则拒绝运行（退出码 64）。 |
| `--confuser <路径>` | `Confuser.CLI.exe` 的路径。它所在目录下必须有 `Confuser.Core.dll`。 |
| `--keep-work` | 接受但无实际作用：`work\` 目录始终保留。 |

输入文件**不会被修改**。运行前后会计算输入的 SHA256 并在报告中比较。

## 5. 输出结构

```
<输出目录>\
├── protected\                    ← 最终产物
│   ├── YourApp.exe               ← 保护后的程序
│   ├── YourApp.exe.config        ← 输入旁边的 .config（如果存在），含绑定重定向
│   ├── Avalonia.*.dll 等         ← 输入目录中的依赖（原样复制，未保护）
│   └── x64\, x86\, ...           ← 依赖的子目录（例如 SkiaSharp 的原生库）
├── work\                         ← 中间文件（始终保留，便于排查）
│   ├── YourApp.exe               ← 输入的副本（原文件不动）
│   ├── manifest.json             ← 模块 1A 的分析结果
│   ├── config.crproj             ← 模块 1B 生成的 ConfuserEx2 配置
│   ├── protected\YourApp.exe     ← ConfuserEx2 的原始输出
│   └── ...                       ← 依赖的副本
└── report.json                   ← 运行报告
```

## 6. 退出码

| 退出码 | 含义 | 该怎么办 |
|---|---|---|
| 0 | 全部完成，复核全部通过（WARN 不算失败） | — |
| 1 | 参数错误 | 检查命令行 |
| 2 | ConfuserEx2 路径无效，或 `Confuser.Core.dll` / `Confuser.CLI.exe` 的 SHA256 不符 | 按第 2 节获取 1.6.0 |
| 3 | 保护已生成，但有复核项 FAIL | 看 `report.json` 的 `checks`，产物保留可供排查 |
| 64 | 输出目录非空，或与输入目录相同或互相包含 | 换一个空的输出目录 |
| 65 | 输入不是托管 .NET 程序集 | 确认输入是 .dll 或 .exe |
| 66 | 输入文件不存在 | 检查路径 |
| 70 | 模块 1A、1B 或 ConfuserEx2 执行失败，或某一步超过 10 分钟被终止 | 看 `report.json` 的 `steps`，每一步的完整输出都保留在那里 |
| 73 | 无法写入输出 | 检查磁盘空间和权限 |

## 7. report.json

`report.json` 的结构如下（示例已省略部分内容）：

```json
{
  "tool": "BinaryShield",
  "module": "1c",
  "schemaVersion": "0.1",
  "input": {
    "path": "C:/path/to/YourApp.exe",
    "sha256_before": "…",
    "sha256_after": "…",
    "unchanged": true
  },
  "steps": {
    "module_1a": { "exit": 0, "stderr": "…" },
    "module_1b": { "exit": 0, "stderr": "…" },
    "confuser":  { "exit": 0, "stderr": "…" }
  },
  "checks": [
    { "id": "a", "name": "…", "status": "PASS", "detail": "…" }
  ],
  "summary": { "pass": 6, "fail": 0, "warn": 0 },
  "exitCode": 0
}
```

- `steps.*.stderr` 保留子进程的完整输出（超过 60 KB 时保留前 40 KB 和后 20 KB）。ConfuserEx2 失败时，首个错误通常在前面。
- `checks` 的每一项含义见第 8 节。

## 8. 复核项

复核只读取元数据和资源流，**不运行**保护后的程序。

| 编号 | 检查 | 失败意味着什么 |
|---|---|---|
| a | 排除范围内每个方法的字符串字面量，保护前后相同 | Avalonia 相关代码的字符串被加密了 |
| b | 排除范围内的类型名与成员签名，保护前后相同 | Avalonia 相关类型被改名了 |
| c | 排除范围内每个方法的指令序列（归一化后）相同 | Avalonia 相关代码被改写了 |
| d | 嵌入资源（包括 `.axaml`）的名字与字节逐个相同 | 界面资源被加密或改写 |
| e | 应用自身的界面类（继承 Avalonia 类型）的指令序列 | WARN：这些类仍受保护，指令被改动时会列出 |
| f | 输入文件的 SHA256 运行前后相同 | 输入被修改了（理论上不应发生） |

"排除范围" 指 `Avalonia` 与 `Avalonia.*` 以及 `CompiledAvaloniaXaml` 与 `CompiledAvaloniaXaml.*` 命名空间。

## 9. 保护规则

BinaryShield 生成的 `config.crproj` 包含两条规则：

**基础规则**：对所有代码使用 ConfuserEx2 的 `normal` 预设，但去掉两项保护：

- `resources`：嵌入的界面资源（`.axaml`）如果被加密，Avalonia 无法加载界面。
- `ref proxy`：ConfuserEx2 1.6.0 无法解析 Avalonia 11 编译 XAML 产生的成员引用，去掉它保护才能完成。

**排除规则**：对排除范围内的命名空间，移除以下全部 12 项保护：

```
anti debug, anti dump, anti ildasm, anti tamper, constants, ctrl flow,
harden, invalid metadata, ref proxy, resources, typescramble, rename
```

`CompiledAvaloniaXaml` 必须排除：Avalonia 编译 XAML 时生成的代码在运行时按名字反射访问，如果被 `rename` 改名，界面会因找不到字段而崩溃。

完整的规则与理由见 `src/dotnet/module_1b/spec.md`。

## 10. 单独使用各个模块

每个模块也可以单独运行。

**模块 1A：分析程序集，输出 JSON 清单**

```bash
module_1a.exe "C:\path\to\YourApp.exe" "C:\path\to\manifest.json"
```

清单列出所有类型、方法和字符串字面量（含 IL 偏移），并把 `Avalonia`、`Avalonia.*` 标为 `skip: true`。

**模块 1B：根据清单生成 ConfuserEx2 配置**

```bash
module_1b.exe "C:\path\to\manifest.json" "C:\path\to\config.crproj"
```

清单中没有 `skip: true` 的类型时，仍会生成配置，并输出 `WARNING`。

## 11. 排错

| 现象 | 可能原因 | 处理 |
|---|---|---|
| 退出码 2 | ConfuserEx2 不是 1.6.0，或文件被替换 | 按第 2 节重新获取并核对 SHA256 |
| 退出码 64 | 输出目录已存在且非空 | 换一个新目录 |
| 退出码 70，`report.json` 的 `confuser.stderr` 中有 `[ERROR]` | ConfuserEx2 在某个保护阶段失败 | 看 stderr 中第一个 `[ERROR]` 及其前后内容；常见原因是某个保护与 Avalonia 的反射访问冲突 |
| 运行时报 `FileLoadException`，提到 `System.Numerics.Vectors` | 应用的 `.config`（绑定重定向）缺失 | 1C 会自动复制 `<程序名>.config`；确认输入旁边确实有这个文件 |
| 运行时报 `Unable to load library 'libSkiaSharp'` | 原生库在子目录（`x64\` 等）中未复制 | 1C 已递归复制依赖；确认输入目录结构完整 |
| 运行时报 `MissingFieldException` 或 `MissingMethodException`，且指向 Avalonia 生成的代码 | 某个被 Avalonia 反射访问的成员被改名 | 确认排除范围包含该命名空间；这类问题应在 `report.json` 的 `checks` 中体现为 b 或 c 的 FAIL |
| 复核 e 为 WARN | 应用自身的界面类被保护，指令有改动 | 正常情况；如果运行异常，需要检查这些类 |
| 某一步超过 10 分钟被终止（退出码 70） | 输入非常大，或 ConfuserEx2 卡住 | 检查输入大小；超时阈值在 `module_1c/Program.cs` 中定义（`StepTimeoutMs`） |

## 12. 已知限制

- 只支持 .NET 程序集。原生程序（PE/ELF 的 C/C++/Rust）暂不支持。
- 依赖 ConfuserEx2 1.6.0。其他版本的规则语法和保护项 ID 未经验证。
- 排除范围内的代码不受保护，基础规则也去掉了 `ref proxy` 与 `resources`。保护强度因此低于全部开启。
- 输入目录中的所有依赖都会原样复制到 `protected\`，不做保护。
- `work\` 目录始终保留，会占用与输入相当的磁盘空间。
- 只在一个 Avalonia 11 示例程序（.NET Framework 4.7，VS 2022 编译）上做过端到端验证。界面能加载并显示；滚动、点击等交互，以及目标程序的真实代码，尚未验证。
- 进程树终止与超时分支没有自动化测试。
- 只在 Windows 上测试。

## 13. Obfuscar（.NET 8 程序）

BinaryShield 目前只调用 ConfuserEx2，不能处理 .NET 8 程序。2026-11-02 的实测中，ConfuserEx2 1.6.0 连 `preset="none"`（不做任何保护）都失败，报 `TypeResolveException`（找不到 `System.Runtime 8.0.0.0`），原因是推断的，未找到变通方法。

.NET 8 程序目前用 **Obfuscar 3.0.0-beta.22** 手动保护。它还没有集成进 `module_1c`（计划中的 Module 2A）。

### 13.1 与 ConfuserEx2 的区别

| 项目 | ConfuserEx2 1.6.0 | Obfuscar 3.0.0-beta.22 |
|---|---|---|
| 支持的运行时 | .NET Framework 4.x | .NET 8（全局工具运行在 .NET 8 上） |
| 保护项 | 多：控制流、反调试、反篡改、字符串加密、改名等（BinaryShield 的规则见第 9 节） | 较少：主要是改名和字符串隐藏（我们在测试中观察到的范围） |
| 配置方式 | 由 BinaryShield 生成 `.crproj` | 手写 XML（`Obfuscator` 根元素，`Module`、`SkipNamespace` 等） |
| 命令行 | `Confuser.CLI.exe` | `dotnet GlobalTools.dll <config.xml>` |
| 版本状态 | 1.6.0 发布于 2022-01，之后的维护状态未知 | 3.0 仍是 beta。稳定线是 2.2.x（面向 .NET Framework，net462） |
| 许可证 | 见上游仓库 | MIT |
| 在本项目中的验证 | 对 .NET Framework 4.7 的测试程序做过端到端验证（第 12 节） | 对 .NET 8 的测试程序做过验证（见 13.5） |

### 13.2 什么时候用哪个

- 目标是 **.NET Framework 4.x**：用 ConfuserEx2，通过 BinaryShield 运行。保护项更多。
- 目标是 **.NET 8**：ConfuserEx2 1.6.0 无法处理，只能用 Obfuscar 3.0 beta。它的保护项较少，不要把它当作强保护。
- 两者都要排除 Avalonia 命名空间（`Avalonia*` 与 `CompiledAvaloniaXaml*`）。Avalonia 的界面代码按名字反射访问，被改名或加密后界面会崩溃。

### 13.3 .NET 8 程序怎么用

1. **获取 Obfuscar**：NuGet 包 `Obfuscar.GlobalTool` 3.0.0-beta.22。核对 `.nupkg` 的 SHA256（见 `dependencies.md`），解压后使用 `tools/net8.0/any/GlobalTools.dll`。
2. **编译程序**：`dotnet build -c Release`，生成 `bin\Release\net8.0\`。
3. **写配置文件**（见下面的示例）。路径必须是绝对路径。
4. **运行**：

   ```bash
   dotnet C:\tools\obfuscar\GlobalTools.dll C:\build\obf.xml
   ```

   成功时输出 `Done.` 并以退出码 0 结束。
5. **组装运行目录**：复制 `bin\Release\net8.0\` 的全部文件，用输出目录中的同名 DLL 替换原来的 DLL，删除不再匹配的 `.pdb`。
6. **运行并验证**：至少在目标平台上启动程序，检查界面、绑定和点击。

配置示例：

```xml
<?xml version='1.0'?>
<Obfuscator>
  <!-- 使用绝对路径。Obfuscar 3.0 beta 不支持 $(...) 变量替换。 -->
  <Var name="InPath" value="C:\build\bin\Release\net8.0" />
  <Var name="OutPath" value="C:\build\obf_out" />
  <Module file="C:\build\bin\Release\net8.0\YourApp.dll">
    <SkipNamespace name="Avalonia*" />
    <SkipNamespace name="CompiledAvaloniaXaml*" />
  </Module>
</Obfuscator>
```

要点：

- `InPath` 必须指向包含全部依赖 DLL 的目录。没有它，Obfuscar 只在配置文件所在目录查找依赖，报 `Unable to resolve dependency`。
- `SkipNamespace` 的范围与 BinaryShield 的排除范围相同。
- `KeepPublicApi` 默认为 true：公开类型和成员的名字保留，所以基于反射的 XAML 数据绑定仍然有效。
- `HidePrivateApi` 默认为 true：私有方法会被改名。我们的测试中，私有事件处理方法（如 `OnButtonClick`）在保护后的 DLL 中找不到原名。
- 运行时会输出 `.NET Core/.NET ... referenced assembly directory does not exist` 形式的警告（例如 `Microsoft.NETCore.App.Ref\6.0.0`）。它们不影响结果。

### 13.4 Linux 部署

- Obfuscar 只改写 IL，同一组托管 DLL 可以在 Linux 上运行，前提是运行时版本一致。
- 原生库（例如 `libSkiaSharp.dll`）不能在 Linux 上用，需要换成 Linux 版本。
- 测试 Ubuntu 没有 ICU（libicu）。测试中使用 `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1`。真实部署要么安装 libicu，要么保留这个设置。

### 13.5 已验证的范围与限制

- 验证对象是我们自己写的测试程序（Avalonia 11.0.10，.NET 8）。包括 10,000 项的列表、数据绑定、按钮点击；另一个测试程序还包含 DataGrid、多标签页、MVVM 绑定和模态对话框。它们**不是**任何真实程序。
- Windows：两个测试程序的保护版和原始版都通过了全部检查（个别运行中有一次因其他窗口抢走焦点而失败，记录在 `tests/dotnet8_complex/README.md`）。
- Linux（WSL2 + WSLg）：多标签页测试程序的保护版和原始版都通过了 23 项检查。列表测试程序在 Linux 上未完全通过，原因见 `tests/dotnet8_avalonia/README.md`。
- Obfuscar 3.0 仍是 beta，版本之间可能有变化。
- 保护项很少，程序仍然可以被反编译。
- 没有像 BinaryShield 那样的复核项。保护后需要自己运行、验证。
- 目前是手动运行，还没有集成进 BinaryShield。

## 14. 相关文件

- `src/dotnet/module_1a/spec.md`、`src/dotnet/module_1b/spec.md`、`src/dotnet/module_1c/spec.md`：各模块的规格与决定点。
- `the progress log`：开发记录与实测发现。
- `dependencies.md`：依赖清单与校验值。
- `tests/benchmarks/`：各模块的验收脚本（`powershell -ExecutionPolicy Bypass -File <脚本> -Confuser <路径>`）。
