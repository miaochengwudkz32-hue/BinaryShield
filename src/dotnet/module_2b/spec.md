# Module 2B — 统一 CLI（bs.exe）· 规格文档

> 状态：**已实现，基准全部通过**（2026-11-20）。`tests/benchmarks/test_module_2b.ps1`：R 17/17、E 10/10、F 8/8（F2、F3 用真实 ConfuserEx2 1.6.0 运行）。`deploy.ps1` 组装扁平的 `dist\`（第 15 节）。
> 已确认的决定（来自用户）：
> - 入口 `bs.exe`，子命令 `analyze` 与 `protect`（决定 1）。
> - 不支持的框架直接以 65 拒绝（决定 2）。
> - `--bin-dir` 默认为 exe 所在目录，启动时检查依赖，缺失以 66 退出（决定 3）。
> - 增加退出码 75，表示外部工具（ConfuserEx2 或 Obfuscar）失败。
>
> N1–N5 已于 2026-11-20 按推荐确认（第 9 节）。确认时另加了两处修正（第 13 节）：运行所需的 runtimeconfig/deps 文件要复制；`bs-report.json` 的字段与写入条件。

---

## 1. 目标

把现有流水线收成一个入口：`bs protect <输入>` 完成 分析 → 按框架路由 → 保护 → 复核 → 输出。

- **.NET Framework 4.x**：交给 `module_1c`（1A + 1B + ConfuserEx2 + 复核）。1C 的逻辑不改、不重写。
- **.NET 8**：2B 自己编排 1A → 2A → Obfuscar → 复核。这一段目前要人工运行 Obfuscar，是 2B 要补上的缺口。

2B 只调用 1A、1C、2A 和外部工具，不改输入文件，不实现任何保护算法。

## 2. 输入

| 项 | 来源 | 说明 |
|---|---|---|
| 输入程序 | 命令行 | `.exe` 或 `.dll`，必须存在 |
| 工具目录 | `--bin-dir`（默认 exe 所在目录） | 必须含 `module_1a.exe`、`module_1b.exe`、`module_1c.exe`、`module_2a.exe`、`dnlib.dll` |
| ConfuserEx2 | `--confuser`（.NET Framework 路由需要） | `Confuser.CLI.exe` 路径；SHA256 校验由 1C 负责 |
| Obfuscar | `--obfuscar`（.NET 8 路由需要） | `GlobalTools.dll` 路径；通过 `dotnet <dll> <obf.xml>` 调用 |

## 3. 输出

`--out` 指定的目录（不存在或为空）：

```
out\
├── protected\            ← 唯一交付位置（两条路由相同）
│   ├── <程序>.dll/.exe   保护后的主程序
│   └── 依赖、原生库子目录、.config（规则同 1C 的 CopyDependencies）
├── bs-report.json        ← 2B 汇总（字段见下）
└── work\                 ← 中间产物，始终保留（与 1C 现状一致）
    ├── in\               原输入的工作副本（仅 .NET 8 路由）
    ├── manifest.json     1A 清单（仅 .NET 8 路由）
    ├── obf.xml           2A 配置（仅 .NET 8 路由）
    ├── obfuscar.log      Obfuscar 输出（仅 .NET 8 路由）
    ├── protected\        Obfuscar 原始输出（仅 .NET 8 路由，复制到 out\protected 后保留）
    └── manifest-protected.json   保护后再次分析的清单（仅 .NET 8 路由）
```

- .NET Framework 路由下，1C 会在 `out\` 直接写 `report.json` 和 `work\`。2B 的汇总名为 `bs-report.json`，两者不冲突。
- 2A 的 `OutPath` 由 `obf.xml` 所在目录决定，即 `out\work\protected`。Obfuscar 成功后，2B 把它复制到 `out\protected`。
- **`bs-report.json` 字段**（新增，基准需要）：
  - `route`：`"net8"` 或 `"netfx"`（拒绝的情况不写报告，见下）。
  - `steps`：各子步骤的退出码，键为 `module_1a`、`module_2a`、`obfuscar`（仅 .NET 8）或 `module_1c`（仅 .NET Framework）。
  - `checks`：数组，每项为 `{ "id", "status", "detail" }`（FX 路由沿用 1C 的条目，还带 `name`），`status` 为 `PASS`、`WARN` 或 `FAIL`。
  - `exitCode`：最终退出码，与进程退出码相同。
- **何时写 `bs-report.json`**：只在 `out` 已经由本次运行创建时才写。例如 1C 因 ConfuserEx2 版本不符而在创建 `out` 之前返回 2，此时 `out` 不存在，2B 不写报告，只返回 2。

## 4. 命令行

```
bs analyze <输入.dll|exe> [输出.json]
bs protect <输入.dll|exe> --out <输出目录> [--confuser <Confuser.CLI.exe>] [--obfuscar <GlobalTools.dll>] [--bin-dir <目录>]
```

**`analyze`**：原样转发给 `module_1a.exe`，退出码照传（0、64、66）。

**`protect`**：
- `--out` 必填。目录不存在或为空。非空，或与输入目录相同或互相包含，以 64 拒绝（与 1C 的规则相同）。
- `--confuser`：仅 .NET Framework 路由需要。路由确定后缺少，以 64 拒绝。
- `--obfuscar`：仅 .NET 8 路由需要。路由确定后缺少，以 64 拒绝。
- `--bin-dir`：默认为 `bs.exe` 所在目录（决定 3）。

**无参数或参数错误**：打印用法，退出码 64。与 1A、1B、2A 一致。1C 仍是 1（见第 12 节）。

**不提供 `--keep-work`（N4）**：1C 解析了该选项，但代码中从未使用（已核实：`KeepWork` 只被赋值，没有被读取）；`work\` 实际上从不删除。2B 不复制这个空操作，`work\` 始终保留。修正 1C 的选项属于另一项任务。

## 5. 路由规则

路由依据是 1A 清单中的两个字段。1A 只读输入，2B 直接在原输入上运行它（写到临时目录，不写 `--out`）。

| 条件 | 路由 | 失败处理 |
|---|---|---|
| `input.isManaged == false` | 拒绝 | 65 |
| `input.targetFramework` 以 `.NETFramework,Version=v4.` 开头 | .NET Framework → 1C | — |
| `input.targetFramework` 以 `.NETCoreApp,Version=v8.` 开头 | .NET 8 → 2B 编排 | — |
| 其他（.NET 6/7/9、`.NETStandard`、字段缺失） | 拒绝 | 65，并打印实际值 |

注意：1A 对非托管 PE 返回退出码 0，并写 `isManaged: false`。2B 必须自己检查该字段，不能只看退出码。

## 6. 处理步骤

### 公共步骤

1. 解析命令行。检查 `--out`（64）：非空，或与输入重叠。
2. 检查 `--bin-dir` 中的必需文件（66）。检查输入存在（66）。
3. 在 `%TEMP%\bs_<随机>` 运行 `module_1a.exe <输入> <temp>\route.json`。非 0 → 70。
4. 读取 `route.json`，按第 5 节路由。路由失败 → 65。
5. 检查路由需要的参数（缺少 → 64）和文件（`--confuser` 或 `--obfuscar` 指向的文件不存在 → 66）。

### .NET Framework 路由（沿用 1C）

6. 运行 `module_1c.exe protect <原输入> --out <out> --confuser <path>`。此时 `out` 必须不存在或为空，所以 2B 在这一步之前不得写 `out` 中的任何文件。
7. 读取 1C 生成的 `out\report.json`，映射退出码（见第 7 节）。
8. 写 `out\bs-report.json`。

### .NET 8 路由（2B 编排）

6. 创建 `out\work\in\`，把原输入及同目录的 `*.dll`、`*.deps.json`、`*.runtimeconfig.json` 复制进去。原文件不动（N1）。`*.runtimeconfig.json` 缺失时 `dotnet <程序>.dll` 无法启动，所以必须复制（这是编写基准时发现的遗漏）。
7. 在副本上运行 `module_1a.exe out\work\in\<name> out\work\manifest.json`。非 0 → 70。
8. 运行 `module_2a.exe out\work\manifest.json out\work\obf.xml`。退出码 64、65、66、73 照传；其他非 0 → 70。
9. 运行 `dotnet <GlobalTools.dll> out\work\obf.xml`，日志写到 `out\work\obfuscar.log`，超时 10 分钟。非 0、超时、或无法启动 `dotnet` → 75。
10. 把 `out\work\protected\*` 复制到 `out\protected\`。再从原输入目录按 `CopyDependencies` 的规则复制依赖（子目录、原生库、`.config`、`*.deps.json`、`*.runtimeconfig.json`），跳过主程序名，与 1C 相同（N2）。
11. 在 `out\protected\<name>` 上运行 `module_1a.exe`，输出 `out\work\manifest-protected.json`，用于第 8 节的复核。
12. 执行第 8 节的复核，写 `out\bs-report.json`。

## 7. 退出码

| 码 | 含义 | 来源 |
|---|---|---|
| 0 | 成功，全部复核通过 | — |
| 2 | ConfuserEx2 版本不符（`Confuser.Core.dll` 的 SHA256 与 1.6.0 不符） | 1C 的 2，原样传出 |
| 3 | 复核有 FAIL | 1C 的 3，或 2B 的第 8 节检查 |
| 64 | 用法错误；`--out` 非空或与输入重叠；缺少路由所需的参数 | 2B；1C 的 64 原样传出 |
| 65 | 输入不是托管程序；目标框架不受支持 | 2B；1C 的 65 原样传出；2A 的 65 原样传出 |
| 66 | 输入不存在；`--bin-dir` 缺少必需文件；`--confuser` 或 `--obfuscar` 文件不存在 | 2B；1C 的 66 原样传出 |
| 70 | 内部步骤失败（1A、2A 的非工具错误；清单无法读取） | 2B；1C 的 70 且其 `steps` 中 `module_1a`/`module_1b` 失败 |
| 73 | 无法写入输出 | 2B；1C 的 73 原样传出；2A 的 73 原样传出 |
| 75 | **外部工具失败**：ConfuserEx2 或 Obfuscar 无法运行、超时、或返回非 0 | 2B；1C 的 70 且 `steps.confuser.exit` 非 0 时映射为 75 |

退出码 2 与 75 的区别：2 是路径或版本问题（我们可以判断），75 是工具运行失败（需要查看日志）。

## 8. 复核

### .NET Framework 路由

沿用 1C 的复核 a–f，不改。2B 把 1C 的 `report.json` 摘要写入 `bs-report.json`。

### .NET 8 路由

| 编号 | 检查 | 失败时 |
|---|---|---|
| n1 | `out\protected\<name>` 存在，且再次分析的 `isManaged == true` | FAIL |
| n2 | `skip == true` 的类型（Avalonia、CompiledAvaloniaXaml 及其子命名空间）的 `fullName` 集合，与输入清单中的完全一致 | FAIL |
| n3 | 至少一个 `skip == false` 的类型名称被改变（输出中不存在于输入的 `fullName`）。**只作信息**，不判失败（N5） | WARN |
| n4 | 输入文件 SHA256 运行前后相同 | FAIL |
| n5 | 保护后的主程序 SHA256 与输入不同 | FAIL |
| n6 | 保护后的 `targetFramework` 与输入相同（`.NETCoreApp,Version=v8.`） | FAIL |

存在 FAIL 时退出码为 3。

## 9. 待确认的新决定（N1–N5）

- **N1**：.NET 8 路由是否在工作副本 `out\work\in\` 上运行 1A、2A 和 Obfuscar，原输入不动。
  - 推荐：是。路由阶段只在原输入上做只读分析；`out` 直到路由确定后才创建，因此 1C 的"输出目录必须为空"规则不受影响。
- **N2**：.NET 8 路由的依赖复制是否沿用 1C 的 `CopyDependencies` 规则。
  - 推荐：是。Obfuscar 是否会把未处理的 DLL 复制到 `OutPath`，未核实，在基准 B 组中核实。若它不复制，2B 的复制步骤是必需的。
- **N3**：2B 是否复制 1C 的 `RunStep`（子进程、超时、结束进程树）与 `CopyDependencies` 代码，不做共享库。
  - 推荐：是。2B 自包含，不改动 1C。代价是两份代码，需要在 1C 修正时同步。
- **N4**：不提供 `--keep-work`。
  - 推荐：是。1C 的该选项是空操作，2B 不复制这一行为。
- **N5**：n3 只作信息，不判失败。
  - 推荐：是。`KeepPublicApi=true` 时公开类型保持名字，若程序的非 Avalonia 类型都是公开的，n3 会误判。

## 10. 验收标准（候选，待确认后写入基准脚本）

1. `analyze` 的退出码与直接运行 `module_1a.exe` 相同（0、64、66）。
2. 用法错误（参数数量不对）→ 64。`--out` 非空 → 64。`--out` 与输入重叠 → 64。
3. 非托管输入 → 65，且不创建 `--out`。
4. `targetFramework` 为 `.NETCoreApp,Version=v6.0` 或 `v9.0`、`.NETStandard2.0` → 65，打印实际值，且不创建 `--out`。
5. `--bin-dir` 缺少 `module_2a.exe` → 66，且不创建 `--out`。
6. 输入不存在 → 66。
7. .NET 8 路由（Avalonia 测试样本）：退出码 0；`out\protected` 中的主程序运行输出与未保护版一致（沿用 2A 的 B 组方法）。
8. 复核 n2：Avalonia 类型名称不变。
9. 用一个不是有效程序集的 `stub.dll` 作为 `--obfuscar` → 75。
10. 退出码映射：1C 的 70 且 `steps.confuser` 失败 → 2B 的 75。**本机无法验证**（见第 12 节）。
11. `bs-report.json` 是合法 JSON，包含路由、子步骤退出码、复核结果和最终退出码。

## 11. 依赖

- 无新依赖。C#（`csc`，.NET Framework 4.7，C# 5 语法），`System.Web.Extensions`（解析 1A、2A、1C 的 JSON），`System.Diagnostics`（子进程）。
- 运行 .NET 8 路由需要 `dotnet` 命令。Obfuscar 3.0.0-beta.22 已登记 `dependencies.md`。
- GitHub 检索（STEP 3）尚未做，按全局规则在写代码前进行。

## 12. 已知风险与局限

- **FX 路由无法在本机端到端验证。** ConfuserEx2 1.6.0 CLI 不在本机（1C 的基准也因此未重跑）。本机能测的只有：路由判断、66 与 65 的拒绝、2 的透传（用错误的 `--confuser`）。
- **.NET 8 路由只在 Avalonia 测试程序上验证。** 目标方的 .NET 8 程序尚未收到。
- **1C 的 `--keep-work` 是空操作**（已核实）。修正属于另一项任务。
- **1C 的参数错误退出码是 1**，与 1A、1B、2A 的 64 不一致。2B 用 64；1C 未改。
- **`--bin-dir` 应指向专用的扁平目录。** 1C 的 `ResolveTool` 先查找 `..\module_1a\`，再查找同目录。若 `bin-dir` 的上级目录恰好有另一份 `module_1a`，1C 会使用它。2B 启动时只检查 `bin-dir` 内的文件。
- **Obfuscar 3.0 仍是 beta**。2B 只调用它，不解释它的内部行为。
- **只支持 Windows**（方案 A）。2B 不做 Linux 打包：原生库替换、运行时准备属于 Linux 部署计划的后续步骤。
- **退出码 75 依赖 1C 的 `report.json` 结构。** 若 1C 的报告格式变化，映射会出错，需要同步。
- **1A 对没有 `TargetFrameworkAttribute` 的程序集，`targetFramework` 回退为运行时版本**（如 `v4.0.30319`）。2B 把它当作不受支持的框架，以 65 拒绝（基准 R17）。VS 构建的 .NET Framework 程序都带该属性，不受影响。`tests/test_files/sample.dll` 由 csc 编译、没有该属性，所以 FX 基准样本改为生成带 `.NETFramework,Version=v4.7` 属性的程序集。
- **F2、F3 已在本机用真实 ConfuserEx2 1.6.0 验证。** F3 的输入是一个 .NET Framework 程序集，它引用的 DLL 没有放进输入目录，ConfuserEx2 因此报 `Could not resolve assembly`；1C 返回 70，2B 映射为 75。映射规则：先看 1A、1B 是否成功（`NotRun()` 的退出码是 -1），再看 ConfuserEx2 步骤的退出码。
- **FX 路由的 `checks` 沿用 1C 报告的条目。** 字段为 `id`、`name`、`status`、`detail`，已在 F2 中核对。
- **超时与进程树结束（`KillTree`）没有自动化测试**，与 1A–1C 相同。
- **`analyze` 不带输出文件时，JSON 直接打印到终端**，这条路径未测试（基准只测了写文件）。

## 13. 确认时的修正（2026-11-20）

- N1–N5 按推荐确认。
- 运行所需文件：`*.deps.json` 与 `*.runtimeconfig.json` 也要复制，并放进 `out\protected`。只复制 `*.dll` 时，保护后的程序无法用 `dotnet` 启动。这是编写基准时发现的，原 spec 没有覆盖。
- `bs-report.json` 的字段与写入条件已在第 3 节写明。

## 14. 不在本模块范围

- 原生程序（3A/3B/3C）。
- Linux 打包与运行。
- 目标程序的测试。
- Obfuscar 的 `SkipType`、`SkipMethod` 等细粒度规则。
- 图形界面。
- 修正 1C 的 `--keep-work` 与退出码 1。

## 15. 部署（`deploy.ps1`，2026-11-20）

- 在仓库根目录运行。编译 1A、1B、1C、2A、2B（输出写回 `src\dotnet\<模块>\`），再把 `bs.exe` 与子模块放进扁平的 `dist\`（`bs.exe` 默认在自己所在目录找子模块）。
- 复制 ConfuserEx2（`tools\ConfuserEx-1.6.0\`）到 `dist\ConfuserEx-1.6.0\`，复制前核对 `Confuser.CLI.exe`、`Confuser.Core.dll` 的 SHA256（与 1C 中的常量一致）。
- 给出 `-ObfuscarNupkg` 时，核对 nupkg 的 SHA256（与 dependencies.md 一致），解压 `tools/net8.0/any/` 到 `dist\obfuscar\`。
- 冒烟测试：`bs.exe` 无参数退出码 64，`analyze` 对 `module_2a.exe` 退出码 0。
- 写 `dist\deploy-manifest.txt`（每个文件的 SHA256）。
- 不联网，不下载。
