# Module 1B — ConfuserEx2 .crproj 配置生成器 · 规格文档

> 状态:**STEP 1、STEP 2 已完成;决定点 A–F 全部确认;进入 STEP 4（功能代码）。**
> 测试脚本已同步;功能代码见 `Program.cs`。

## 1. 目标

读取 Module 1A 输出的 JSON 清单,生成一份 ConfuserEx2 项目文件(`.crproj`)。
文件里对 Avalonia 命名空间排除保护,让 ConfuserEx2 不改动这些类型。

本模块**只生成配置文件**:
- 不调用 ConfuserEx2(那是 v0.2 CLI 包装层的事)
- 不修改任何目标程序或输入 JSON
- 不实现任何混淆或加密算法

## 2. 输入

| 项 | 来源 | 说明 |
|---|---|---|
| Module 1A 的 JSON | 命令行参数 | 由 `module_1a.exe` 产生 |
| 目标程序路径 | JSON 的 `input.path` | 写入 `.crproj` 的 `<module path=...>` |
| 输出路径 | 命令行参数 | 生成的 `.crproj` 写到这里 |

## 3. 输出

一份 XML 格式的 `.crproj`,结构如下(排除规则为第 6 节实测通过的形式):

```xml
<project outputDir="protected" baseDir="." xmlns="http://confuser.codeplex.com">
  <module path="目标程序路径">
    <!-- 排除的 Avalonia 命名空间: Avalonia, Avalonia.Controls.Internal, ... -->
    <rule pattern="true" preset="normal" inherit="false">
      <protection id="resources" action="remove" />
      <protection id="ref proxy" action="remove" />
    </rule>
    <rule pattern="namespace('Avalonia(\..*)?') or namespace('CompiledAvaloniaXaml(\..*)?')" inherit="false">
      <protection id="anti debug" action="remove" />
      <protection id="anti dump" action="remove" />
      <protection id="anti ildasm" action="remove" />
      <protection id="anti tamper" action="remove" />
      <protection id="constants" action="remove" />
      <protection id="ctrl flow" action="remove" />
      <protection id="harden" action="remove" />
      <protection id="invalid metadata" action="remove" />
      <protection id="ref proxy" action="remove" />
      <protection id="resources" action="remove" />
      <protection id="typescramble" action="remove" />
      <protection id="rename" action="remove" />
    </rule>
  </module>
</project>
```

- 第一条是基础规则:对非 Avalonia 代码施加 `normal` 预设保护,并去掉 `resources` 与 `ref proxy`(决定点 E,见第 6 节)。
- 第二条是排除规则:对 Avalonia 命名空间移除全部 12 项保护。
- 注释列表由 JSON 中 `skip:true` 的命名空间生成(决定点 B)。

## 4. 处理步骤

1. 读取 JSON,校验 `schemaVersion == "0.1"`,并确认 `input.isManaged == true`。
2. 遍历 `assemblies → modules → types`,收集 `skip == true` 的类型及其命名空间。
3. 用 `System.Xml.Linq` 生成 XML。**不用字符串拼接**,路径里的 `&`、引号、中文等字符由 XML 库自动转义。
4. 有 skip 类型时,写入基础规则、排除规则与注释;没有时按决定点 C 处理。
5. 以 UTF-8(无 BOM)写入输出文件。

## 5. 决定点

**A. 规则粒度与规则文本 — 已确认一条固定排除规则,但规则文本需要你重新确认。**
- 你确认的文本 `namespace('Avalonia') or startswith(namespace, 'Avalonia.')` **实测无效**:
  - `startswith(...)` 报错:`Unknown token 'startswith'`。
  - 即使换成合法的写法,**只写排除规则而不移除保护,也不起排除作用**(第 6 节)。
- 改为已验证的形式:`namespace('Avalonia(\..*)?')` + 移除全部 12 项保护。
- **2026-11-01 修订（A'）**:排除范围增加 `CompiledAvaloniaXaml`（Avalonia 编译 XAML 时生成的代码，运行时按名字反射访问）。写法为 `namespace('Avalonia(\..*)?') or namespace('CompiledAvaloniaXaml(\..*)?')`，同样移除全部 12 项保护。组合写法已在 ConfuserEx2 1.6.0 上验证可解析。
- 因为 `Avalonia(\..*)?` 已能一次覆盖精确与子命名空间,原先的备选("每个命名空间各一条精确规则")不再需要。
- **请确认这个改动。**

**B. 审阅注释 — 已确认:加。**

**C. 没有任何 skip 类型时 — 已确认:方案 1。** 照常生成(输出结构与有 skip 时相同),并输出以 `WARNING:` 开头的警告,退出码为 0。

**D. JSON 解析 — 已确认:`System.Web.Extensions`。** .NET Framework 自带,本机已确认可用,已登记 `dependencies.md`。

**E. 非 Avalonia 代码的基础保护预设 — 已确认:`normal`，并去掉 `resources` 与 `ref proxy`（2026-11-01 修订，见第 6 节）。** 目前用 `normal`(第 6 节实测可用)。如需更强保护,可换其他预设,但需要另行测试。

**F. 输出目录 — 已确认:`.crproj` 所在目录下的 `protected` 子目录**（`outputDir="protected"`，`baseDir="."`）。

## 6. 实测结论（ConfuserEx2 1.6.0,在 临时目录 中完成,未修改任何项目文件）

| 测试 | 结果 |
|---|---|
| `startswith(...)` | CLI 报错 `Unknown token 'startswith'`,不生成输出 |
| `namespace-prefix(...)` | CLI 报错 `Unknown token 'namespace-prefix'`,不生成输出 |
| 排除规则无保护移除（有或无 `preset="none"`） | Avalonia 字符串仍被保护,**不起排除作用** |
| `namespace(...)` 的匹配方式 | **完整匹配**:`'Avalonia'` 只匹配精确命名空间;`'Avalonia(\..*)?'` 同时覆盖精确与子命名空间 |
| 排除规则 + 移除 `constants` | Avalonia 字符串可见 ✅ |
| **完整方案（移除全部 12 项）** | Avalonia 字符串可见 ✅;Avalonia 方法 IL 长度 11→11（未变）✅;DemoApp 方法 IL 长度 11→57（被保护，作为对照）✅;Avalonia 类型名不变 ✅ |
| 基础规则去掉 `resources`（2026-11-01 修订） | `resources` 已在 Avalonia 的 12 项里，但真实应用的 XAML 仍被加密，说明它不由 Avalonia 规则决定；必须在基础规则里去掉。去掉后嵌入资源字节与原始逐字节一致（1C 复核 d 通过）。 |
| 基础规则去掉 `ref proxy`（2026-11-01 修订） | ConfuserEx2 1.6.0 的引用代理无法解析 Avalonia 11 编译 XAML 产生的成员引用，报 `MemberRefResolveException` 而失败。去掉后保护可以完成。 |
| 排除范围增加 `CompiledAvaloniaXaml`（2026-11-01 修订） | Avalonia 编译 XAML 时生成的代码（`!XamlIlPopulate` 等）运行时按名字反射访问。rename 会改掉其中被访问的字段，运行时报 `MissingFieldException`，界面无法加载。把它纳入排除后，保护后的界面可以正常加载（截图验证）。 |
| `Ki.Compressor.Protection` | 不能作为项目里的保护 ID 移除（CLI 报 `Cannot find protection`），因此不在列表中 |

保护 ID 列表（12 个，由 `Confuser.Protections.dll` 与 `Confuser.Renamer.dll` 反射读取）：

```
anti debug, anti dump, anti ildasm, anti tamper, constants, ctrl flow,
harden, invalid metadata, ref proxy, resources, typescramble, rename
```

## 7. 待核实的风险与局限

- 验证只用了一个自制小样本(两个 Avalonia 类型、一个普通类型),**未在真实 Avalonia 程序上验证**。
- 改名保护对**非 public** 类型的影响未测(样本中的类型都是 public)。
- ConfuserEx 1.6.0 发布于 2022-01-17,仓库是否仍在维护未知,这是长期依赖风险。
- 保护是否真正不影响 Avalonia UI 运行,属于 v0.2 的端到端测试。
- 本模块自身不验证保护效果。

## 8. 边界与异常

| 情况 | 行为 |
|---|---|
| JSON 文件不存在或不是合法 JSON | 报错,非零退出码 |
| `isManaged == false` | 拒绝生成（目标不是 .NET 程序，ConfuserEx2 不适用），非零退出码，且不生成 `.crproj` |
| 路径含空格、中文、`&`、引号 | XML 库自动转义，生成的 XML 仍合法，路径原样还原 |
| 同一输入多次运行 | 输出字节完全相同（幂等） |
| 输出路径已存在 | 覆盖，但不改动输入 JSON 或目标程序（先写临时文件再替换，失败时原文件保持不变） |
| 输入与输出是同一文件 | 拒绝，退出码 64，不改动清单 |
| `input.path` 不是绝对路径 | 拒绝，退出码 65 |
| `assemblies` / `modules` / `types` 不是数组，或 `skip` 不是布尔值 | 拒绝，退出码 65，不静默跳过 |
| 输入文件超过 256 MB | 拒绝，退出码 65 |
| 命名空间或路径含 XML 不允许的字符 | 拒绝，退出码 65 |

## 9. 验收标准（由 `tests/benchmarks/test_module_1b.ps1` 实现）

1. 生成的 `.crproj` 是合法 XML。
2. 共 2 条 rule：基础规则（`pattern="true"`、`preset="normal"`）+ 排除规则。
3. 排除规则 `pattern` 为 `namespace('Avalonia(\..*)?') or namespace('CompiledAvaloniaXaml(\..*)?')`，`inherit="false"`，移除全部 12 项保护。
4. 含 skip 类型时，`.crproj` 含注释，列出被排除的 Avalonia 命名空间。
5. 无 skip 类型时：退出码 0，仍生成合法 XML，输出 `WARNING:`。
6. `isManaged == false`：非零退出，且未生成 `.crproj`。
7. 输入 JSON 不存在：非零退出。
8. 路径含 `&`、空格、中文：仍是合法 XML，路径原样还原。
9. 同一输入运行两次，输出文件逐字节相同。
10. 输出目录为 `protected`，`baseDir` 为 `.`（决定点 F）。
11. 根命名空间为 `http://confuser.codeplex.com`（ConfuserEx2 项目格式，已从 Confuser.Core.dll 核实）。
12. 输入与输出为同一文件时拒绝（退出码 64），且清单内容不变。
13. `input.path` 不是绝对路径时拒绝（退出码 65）。
14. `assemblies` 不是数组时拒绝（退出码 65）。
15. 命名空间含连续连字符时，注释仍为合法 XML 且不含 `--`。
16. 基础规则移除 `resources` 与 `ref proxy` 两项保护（测试 2g、2h）。
16. 基础规则（`pattern="true"`）移除 `resources` 保护，使嵌入的 XAML 保持可读。

## 10. 依赖

- XML 输出：`System.Xml.Linq`（.NET Framework 自带）。
- JSON 解析：`System.Web.Extensions`（决定点 D，已确认）。
- 外部工具：ConfuserEx2 1.6.0 CLI（`mkaring/ConfuserEx` release v1.6.0，`ConfuserEx-CLI.zip`，SHA256 `A00DE7CDDC740F7EDB1BAAB4C6C9073553DCC88F7E873D15B7FD34DDD33753D7`）。**本模块不调用它**；上面的实测只在 临时目录 中运行，用于验证规则语法。
- 构建仍用 `csc.exe`，与 Module 1A 一致。

---

**待你确认:**
1. 第 5 节 A：排除规则文本改为 `namespace('Avalonia(\..*)?')` + 移除 12 项保护（替代你给的 `startswith` 写法）。
2. 决定点 E：已确认（`normal` 预设，去掉 `resources`）。
3. 决定点 F：输出目录放在哪里。
4. 测试脚本 `tests/benchmarks/test_module_1b.ps1` 已同步新规则，确认后即进入 STEP 3–5（写功能代码、跑测试）。
