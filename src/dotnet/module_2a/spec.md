# Module 2A — Obfuscar 3.0 配置生成器 · 规格文档

> 状态：**已实现，基准全部通过（2026-11-20）**：P 15/15、A 26/26、B 8/8（`tests/benchmarks/test_module_2a.ps1`）。STEP 8：DeepSeek 第一轮已完成并修改（第 13 节）；Opus 审查待做。
> 对应：Obfuscar 3.0.0-beta.22（`Obfuscar.GlobalTool`，见 `dependencies.md`）。
>
> 决定点 A 已确认为正则写法 `rx="^(Avalonia|CompiledAvaloniaXaml)(\..*)?$"`。基准 P 组已实测通过（Obfuscar 接受该写法，跳过效果正确；不带 `^` `$` 的对照版会误伤 AvaloniaApp47）。其余决定点 B–I 按推荐方案确认。

## 1. 目标

读取 Module 1A 输出的 JSON 清单，生成一份 Obfuscar 3.0 的 XML 配置文件（`obf.xml`）。
配置里对 `Avalonia` 与 `CompiledAvaloniaXaml` 两个命名空间使用 `SkipNamespace` 排除，输出目录为 `protected\` 子目录。
目标是 .NET 8 程序，与 Module 1B（ConfuserEx2 的 `.crproj`，面向 .NET Framework 4.x）对应。

本模块**只生成配置文件**：
- 不运行 Obfuscar（运行与集成是后续模块的事）；
- 不修改输入的 JSON 或目标程序；
- 不实现任何混淆或加密算法。

## 2. 输入

| 项 | 来源 | 说明 |
|---|---|---|
| Module 1A 的 JSON | 命令行第 1 个参数 | 由 `module_1a.exe` 产生，`schemaVersion` 必须为 `"0.1"` |
| 目标程序路径 | JSON 的 `input.path` | 必须是绝对路径，且文件存在 |
| 目标框架 | JSON 的 `input.targetFramework` | 必须是 .NET 8（见决定点 F） |
| 配置输出路径 | 命令行第 2 个参数 | 绝对或相对路径；相对路径按当前目录转换为绝对路径（决定点 I） |

## 3. 输出

一份 UTF-8（无 BOM）的 XML 文件，结构如下（路径为示例）：

```xml
<?xml version="1.0" encoding="utf-8"?>
<Obfuscator>
  <!-- 排除的命名空间（来自 1A 清单中 skip:true 的类型）: Avalonia.Controls, ... -->
  <Var name="InPath" value="C:\build\bin\Release\net8.0" />
  <Var name="OutPath" value="C:\build\protected" />
  <Var name="KeepPublicApi" value="true" />
  <Var name="HidePrivateApi" value="true" />
  <Module file="C:\build\bin\Release\net8.0\YourApp.dll">
    <SkipNamespace name="Avalonia" />
    <SkipNamespace name="Avalonia.*" />
    <SkipNamespace name="CompiledAvaloniaXaml" />
    <SkipNamespace name="CompiledAvaloniaXaml.*" />
  </Module>
</Obfuscator>
```

- `InPath`：目标程序所在目录（`input.path` 的父目录）。Obfuscar 用它解析依赖 DLL。
- `OutPath`：配置文件所在目录下的 `protected` 子目录（决定点 E）。
- `Module file`：目标程序的绝对路径。
- 四条 `SkipNamespace` 是 Avalonia 规则（第 5 节）。
- 两个 `Var`（`KeepPublicApi`、`HidePrivateApi`）的值与 Obfuscar 默认值相同，显式写出是为了让配置自描述（决定点 B）。

## 4. 处理步骤

1. 读取 JSON（`System.Web.Extensions`，与 1A、1B 一致）。
2. 校验：`schemaVersion == "0.1"`；`input.isManaged == true`；`input.targetFramework` 为 .NET 8；`input.path` 为绝对路径且文件存在。任何一项不满足，不生成文件。
3. 遍历 `assemblies → modules → types`，收集 `skip == true` 的命名空间。
4. 一致性检查：每个 `skip:true` 的命名空间都必须被第 5 节的四条规则覆盖（决定点 D）。
5. 用 `System.Xml.Linq` 生成 XML。不用字符串拼接，路径中的 `&`、引号、空格、中文由 XML 库转义。
6. 先写临时文件，再替换目标文件（与 1B 一致）。
7. 没有任何 `skip:true` 类型时，照常生成，并输出以 `WARNING:` 开头的提示，退出码为 0（决定点 C）。

## 5. Avalonia 规则在 Obfuscar 中的实现

**Obfuscar 的 `SkipNamespace name` 不是正则**，而是通配符：`*` 匹配任意长度字符，`?` 匹配单个字符，并且必须整个字符串匹配。只有以 `^` 开头的值才当作正则（`rx` 属性）。
这一点来自上游源码：`Helper.MatchWithWildCards` 与 `NamespaceTester`（`obfuscar/obfuscar` 仓库，`src/Obfuscar/Helper.cs`、`src/Obfuscar/NamespaceTester.cs`）。

由此得到的语义：
- `Avalonia*` 会匹配 `AvaloniaApp47`。应用自己的命名空间如果以 `Avalonia` 开头，就会被误排除。这与 2026-11-02 的记录一致。
- `Avalonia.*` 只匹配以 `Avalonia.` 开头的命名空间，**不匹配** `Avalonia` 本身，所以还需要单独一条精确规则。

因此采用四条规则：`Avalonia`、`Avalonia.*`、`CompiledAvaloniaXaml`、`CompiledAvaloniaXaml.*`，与 Avalonia 规则（`CLAUDE.md`）一致。
等价的单条正则写法是 `rx="^(Avalonia|CompiledAvaloniaXaml)(\..*)?$"`（决定点 A）。

**`SkipNamespace` 的效果**：上游源码中，类型的改名判断（`ShouldSkip(TypeKey, …)`）和字符串隐藏判断（`ShouldSkip(method.TypeKey, TypeAffectFlags.AffectString, …)`）都先检查命名空间。因此排除后，该命名空间的类型既不改名，其方法里的字符串也不被隐藏，效果与 1B 的"移除全部保护项"对应。

## 6. 决定点（请逐条确认）

**A. 规则写法：四条通配符，还是一条正则？**
- 推荐：四条通配符。它与上游文档的写法一致，也容易读。
- 备选：`rx="^(Avalonia|CompiledAvaloniaXaml)(\..*)?$"`。一条即可，但读的人需要懂正则。

**B. 是否显式写出 `KeepPublicApi` 与 `HidePrivateApi`？**
- 推荐：显式写出，值为 `true`（与默认值相同）。
- 理由：配置文件本身说明了保护的边界。基准会验证 Obfuscar 能接受这两个变量名。

**C. 没有 Avalonia 类型时怎么办？**
- 推荐：与 1B 一致。照常生成，输出 `WARNING:`，退出码 0。
- 理由：缺少 Avalonia 类型不代表配置错误。

**D. `skip:true` 的命名空间不被规则覆盖时？**
- 推荐：失败，退出码 65，不生成文件。
- 理由：1A 的分类与 2A 的规则不一致，说明其中一方的假设有问题，不应该静默通过。

**E. 输出目录**
- 推荐：配置文件所在目录下的 `protected` 子目录（与 1B 的决定点 F 一致）。2A 不创建该目录，只把它写进 `OutPath`。
- 待基准验证：Obfuscar 是否会自己创建 `OutPath`。

**F. 目标框架**
- 推荐：只接受 .NET 8，即 `input.targetFramework` 为 `.NETCoreApp,Version=v8.0`（或同一主版本）。其他框架退出码 65，并说明原因。
- 理由：本模块的目标是 .NET 8；.NET Framework 4.x 由 1B 处理。
- 待验证：真实 .NET 8 程序的 1A 输出中 `targetFramework` 的确切字符串。

**G. 命令行参数形式**
- 推荐：与 1B 一致，`module_2a.exe <manifest.json> <obf.xml>`。
- 不设 `--out`：输出目录由配置文件位置决定（决定点 E）。

**H. 语言与依赖**
- 推荐：C#，`csc.exe`（.NET Framework 4.7），`System.Web.Extensions` 解析 JSON，`System.Xml.Linq` 生成 XML。与 1A、1B 相同，不新增依赖。

**I. 相对路径**
- 推荐：配置文件里的路径一律写成绝对路径。命令行给出相对路径时，转换为绝对路径后写入，并在输出中打印转换结果。
- 理由：Obfuscar 3.0 beta 源码中，`InPath`/`OutPath` 不是绝对路径时会直接报错（`must be an absolute path`）。上游文档也说明相对路径已弃用。

## 7. 边界与异常

| 情况 | 行为 | 退出码 |
|---|---|---|
| 参数数量不对 | 打印用法 | 64 |
| JSON 文件不存在 | 报错 | 66 |
| JSON 不是合法 JSON，或结构不对（数组、布尔值类型错误） | 报错，不生成文件 | 65 |
| `schemaVersion` 不是 `"0.1"` | 报错 | 65 |
| `isManaged == false` | 拒绝（目标不是 .NET 程序） | 65 |
| `targetFramework` 缺失或不是 .NET 8 | 拒绝，说明实际值 | 65 |
| `input.path` 不是绝对路径，或文件不存在 | 拒绝 | 65 / 66 |
| 配置输出路径与 JSON 路径相同 | 拒绝，清单不改动 | 64 |
| 配置输出路径与目标程序相同 | 拒绝，目标程序不改动 | 64 |
| 一致性检查失败（决定点 D） | 拒绝，列出未覆盖的命名空间 | 65 |
| 路径含空格、中文、`&`、引号 | XML 库转义，路径原样还原 | — |
| 同一输入运行两次 | 输出字节完全相同（幂等） | — |
| 配置输出路径已存在 | 覆盖，先写临时文件再替换 | — |
| 写文件失败 | 报错，原文件保持不变 | 73 |

## 8. 验收标准（候选，待确认后写入基准脚本）

1. 生成的配置是合法 XML，根元素为 `Obfuscator`。
2. `InPath`、`OutPath`、`Module file` 都是绝对路径。
3. `OutPath` 等于配置文件所在目录下的 `protected`。
4. 恰好四条 `SkipNamespace`，名字与第 5 节一致。
5. `KeepPublicApi` 与 `HidePrivateApi` 显式存在且值为 `true`（决定点 B）。
6. 含 Avalonia 类型的清单：生成成功，退出码 0。
7. 没有 Avalonia 类型的清单：退出码 0，输出 `WARNING:`（决定点 C）。
8. `skip:true` 的命名空间没有被规则覆盖：退出码 65，不生成文件（决定点 D）。
9. `targetFramework` 为 .NET Framework 4.7：退出码 65（决定点 F）。
10. `isManaged == false`：退出码 65，不生成文件。
11. 输入 JSON 不存在：退出码 66。
12. 路径含空格、中文、`&`：仍是合法 XML，路径原样还原。
13. 同一输入运行两次，输出文件逐字节相同。
14. 配置输出路径与清单相同，或与目标程序相同：退出码 64，相应文件不被修改（基准 A21、A26）。
15. **端到端（可选，需要 Obfuscar 与 .NET 8 SDK）**：用生成的配置对一个 .NET 8 测试程序运行 Obfuscar，退出码 0；输出 DLL 可运行。

## 9. 依赖

- `csc.exe`（.NET Framework 4.7）、`System.Web.Extensions`、`System.Xml.Linq`：与 1A、1B 相同。
- 没有新增依赖。Obfuscar 本身不由本模块调用；端到端验证（第 8 节第 15 条）需要 Obfuscar 3.0.0-beta.22，已在 `dependencies.md` 登记。

## 10. GitHub 初步检查（STEP 3 的初步结果，最终结论在基准确认后补充）

搜索 `obfuscar config` 与 `SkipNamespace`，找到的现成配置生成器：
- `SirLpc/GenerateObfuscarConfigForUnity`：面向 Unity，9 星，2023 年最后推送，无许可证。
- `kiraventom/ObfuscarConfigGenerator`：0 星，2025-12 最后推送，无许可证。
- `hsu-net/obfuscar`：MSBuild 集成，3 星，2026-01 最后推送。

结论：都没有许可证，或规模太小，不适合复用代码。Obfuscar 的配置格式很简单，我们自己写，结构与 Module 1B 一致。
匹配语义直接读上游源码确认（第 5 节）。

## 11. 不在本模块范围

- 运行 Obfuscar，或把它集成进流水线（后续模块）。
- 任何混淆、加密、改名算法。
- 原生二进制（C/C++/Rust）。
- Linux 上运行配置生成器（方案 A：工具只在 Windows 上运行）。
- Obfuscar 的 `SkipType`、`SkipMethod` 等更细的规则（当前只按命名空间排除，与 1B 的粒度一致）。

## 12. 已知风险

- Obfuscar 3.0 仍是 beta，版本之间可能有变化。配置语法以 `3.0.0-beta.22` 为准。
- 2A 只检查 1A 的清单，不检查目标程序本身。清单不准确时，配置也不准确。
- 通配符规则的语义已读源码确认，但只在本版本上验证过。
- Obfuscar 的安全说明提醒：它依赖底层的 PE 读取 API，不适合处理不可信的输入。目标程序必须是我们信任的程序。
- 路径相同的检查只比较字符串（忽略大小写）。符号链接、硬链接、8.3 短文件名指向同一文件时，检查不到。
- 用法错误的退出码是 64，而 1C 的参数错误仍是 1。两者不一致，1C 本次未改（不在本次范围）。

---

## 请确认的决定点

1. **A** 规则写法：四条通配符（推荐）还是一条正则？
2. **B** 是否显式写出 `KeepPublicApi` / `HidePrivateApi`（推荐：是）？
3. **C** 没有 Avalonia 类型时：WARNING 并退出 0（推荐）？
4. **D** 一致性检查失败时：退出码 65（推荐）？
5. **E** 输出目录：配置文件同级的 `protected`（推荐）？
6. **F** 目标框架只接受 .NET 8（推荐）？
7. **G** 命令行：`module_2a.exe <manifest.json> <obf.xml>`（推荐）？
8. **I** 相对路径：转换为绝对路径后写入（推荐）？

确认后进入 STEP 2：先写基准脚本 `tests/benchmarks/test_module_2a.ps1`，再停下来等确认。

## 13. 实现结果（2026-11-20）

- 代码：`src/dotnet/module_2a/Program.cs`（C#，`csc` / .NET Framework 4.7，`System.Web.Extensions` 解析 JSON，`System.Xml.Linq` 生成 XML）。
- 基准：`tests/benchmarks/test_module_2a.ps1`。P 组（Obfuscar 直接测）15/15；A 组（module_2a.exe 合成清单）25/25；B 组（端到端，保护后的程序输出与未保护版一致）8/8。
- 基准过程中的两处说明：
  - A23 最初传入两个空字符串，这不是"参数太少"，测试写错了。在运行前改为只传一个参数。
  - A24（无盘符的 `\` 开头路径）、A25（配置路径是盘符根）是自检后补的两个用例，对应代码里新增的两处检查。
- B3 确认：Obfuscar 3.0.0-beta.22 会在 OutPath 不存在时自动创建它（决定点 E 的待验证项已确认）。2A 本身不创建该目录。
- 与 1A 的关系：1A 的 `skip` 规则已在同一批修改中加入 `CompiledAvaloniaXaml`（见 `module_1a/spec.md` 第 5 节），两者现在一致。
- 2026-11-20 DeepSeek 交叉审查后的修改（本次只收到以下四条的结论，其他意见未收到，未记录）：
  - 新增检查：配置输出路径与目标程序相同时拒绝，退出码 64（基准 A26）。
  - 用法错误（参数数量不对）的退出码由 1 改为 64，与 1A、1B 一致（基准 A23）。
  - 核实（无需改代码）：`BuildConfig` 的 `SkipNamespace` 只写固定的 `SkipRegex` 常量；`skip:true` 的命名空间只出现在 XML 注释里，注释经过 `SafeComment` 处理。
  - 核实（无需改代码）：`AsList` 对非数组输入（字符串、对象、数字、布尔值、null）返回 null，不返回空列表。
