# Module 1C — CLI 包装 · 规格文档

> 状态:**STEP 1 已确认**（D1–D6 按推荐方案确认，其中 D4 的实现方式见第 9 节）。STEP 2 测试脚本已写，待确认后进入 STEP 4。
> 背景：2026-11-01 运行验证中止；静态验证作为当前阶段依据。

## 1. 目标

用一条命令串起完整的 .NET 保护流水线：

```
module_1c protect <输入.dll|exe> --out <输出目录> --confuser <Confuser.CLI.exe 路径>
```

依次执行：Module 1A 分析 → Module 1B 生成配置 → ConfuserEx2 执行 → 静态复核 → 写报告。

本模块**不实现任何保护算法**，也**不运行**保护后的程序。

## 2. 输入

| 项 | 说明 |
|---|---|
| 目标程序 | 托管 .NET 程序（.dll 或 .exe）。非托管文件拒绝（退出码 65）。 |
| `--out` | 输出目录。已存在且非空时拒绝（退出码 64，见 D3）。 |
| `--confuser` | ConfuserEx2 CLI（`Confuser.CLI.exe`）的路径。**必须由用户指定**，本模块不下载、不内置。 |
| `--keep-work` | 可选。保留中间文件（清单与配置），默认保留。 |

## 3. 输出

```
<out>/
  protected/        ← ConfuserEx2 产出的保护后程序，以及输入目录下的依赖 DLL（D2）
  work/
    <目标程序>.dll  ← 目标程序的副本（原文件不动），与同目录依赖 DLL 一起放在 work\ 根目录
    manifest.json   ← Module 1A 输出
    config.crproj   ← Module 1B 输出
  report.json       ← 本次运行的摘要（见第 5 节）
```

## 4. 流程

1. **检查输入**：文件存在；经 Module 1A 判断为托管程序，否则退出 65。
2. **Module 1A**：分析输入，写 `work/manifest.json`。非零退出则中止（退出码 70）。
3. **Module 1B**：读取清单，写 `work/config.crproj`（`outputDir="protected"`，`baseDir="."`）。非零退出则中止（退出码 70）。
4. **ConfuserEx2**：把输入及同目录依赖复制到 `work/`，在 `work/` 下执行 `Confuser.CLI.exe -n config.crproj`。返回非零则中止（退出码 70）。
   - 副本放在 `work/` 根目录，而不是子目录。原因：1B 生成的 `baseDir` 是 `.`，ConfuserEx2 会把模块相对于 `baseDir` 的目录结构写进输出路径。放在子目录时，产物会落在 `protected\input\...`。
5. **静态复核**（只读，见第 6 节）。
6. **写 `report.json`**，按复核结果决定退出码。

## 5. report.json 结构

```json
{
  "tool": "BinaryShield",
  "module": "1c",
  "schemaVersion": "0.1",
  "input": {
    "path": "...",
    "sha256_before": "...",
    "sha256_after": "...",
    "unchanged": true
  },
  "steps": {
    "module_1a": { "exit": 0, "stderr": "..." },
    "module_1b": { "exit": 0, "stderr": "..." },
    "confuser":  { "exit": 0, "stderr": "..." }
  },
  "checks": [
    { "id": "a", "name": "...", "status": "PASS", "detail": "..." }
  ],
  "summary": { "pass": 0, "fail": 0, "warn": 0 },
  "exitCode": 0
}
```

- `checks` 的 `id` 为第 6 节的 a–f；`status` 为 `PASS`、`FAIL` 或 `WARN`。
- 应用中继承自 Avalonia 类型的类的详细列表，放在检查 `e` 的 `detail` 里。

## 6. 静态复核项

所有复核都只读取元数据与资源流，**不执行**保护后的代码。

| 编号 | 检查 | 结果 |
|---|---|---|
| a | 排除范围（`Avalonia.*` 与 `CompiledAvaloniaXaml`，与 1B 的排除规则一致）中，每个方法的字符串字面量集合在保护前后相同 | FAIL 则计入失败 |
| b | 排除范围中，类型名、成员签名集合相同 | FAIL 则计入失败 |
| c | 排除范围中，每个方法的 IL 长度相同 | FAIL 则计入失败 |
| d | 嵌入资源（`.axaml` 等）的名字与字节逐个相同 | FAIL 则计入失败 |
| e | 应用中继承自 Avalonia 类型的类：名字与 IL 是否保持 | WARN，不计入失败（D6） |
| f | 输入 SHA256 运行前后相同 | FAIL 则计入失败 |

读取元数据使用已锁定的 **dnlib 4.5.0**（`src/dotnet/module_1a/dnlib.dll`）。

## 7. 退出码

| 码 | 含义 |
|---|---|
| 0 | 全部完成，复核全部通过（e 可为 WARN） |
| 1 | 参数错误 |
| 2 | `--confuser` 路径无效，或版本检查不通过（见 D4） |
| 3 | 保护已生成，但复核有 FAIL；产物保留，report.json 标明失败项（D5） |
| 64 | 输出目录已存在且非空（D3），或输入与输出重叠 |
| 65 | 输入不是托管 .NET 程序 |
| 66 | 输入文件不存在 |
| 70 | Module 1A、1B 或 ConfuserEx2 执行失败，或单个子进程超过 10 分钟被终止（report.json 记录哪一步） |
| 73 | 无法写入输出 |

## 8. 边界与异常

- 原始输入文件**不被修改**（复核 f 检查）。
- 不下载任何文件；ConfuserEx2 只能通过 `--confuser` 指定。
- 本模块只写入 `--out` 目录，不写仓库内任何文件。
- 输出目录与输入目录相同或互相包含：拒绝（退出码 64）。
- 已知限制：当前 1B 排除规则只覆盖 `Avalonia.*` 命名空间。应用自身的界面类是否被改名，由复核项 e 报告，**不能保证**。

## 9. 决定点（已确认）

**D1. Module 1A、1B 的调用方式 — 已确认：子进程调用。**
`module_1a.exe`、`module_1b.exe` 各自已通过测试，边界清晰。

**D2. 依赖 DLL 的处理 — 已确认：复制到 `protected/`。**
把输入目录下的其他 DLL（如 Avalonia 的依赖）**连同子目录**复制到 `protected/`，使产物可以直接运行。
- 子目录必须包含：SkiaSharp 等库的原生部分位于 `x64\`、`x86\`、`arm64\` 等子目录中，漏掉会导致 `libSkiaSharp` 加载失败。
- 输入旁边的 `<目标>.config`（如 `AvaloniaApp47.exe.config`）必须复制为 `protected/<目标>.config`，它含绑定重定向（例如 `System.Numerics.Vectors`），缺少时运行会因版本不匹配而失败。
- 2026-11-01 修订：修复了之前只复制顶层 DLL、不复制 `.config` 的缺口（真实应用运行时暴露）。

**D3. 输出目录已存在时 — 已确认：拒绝（退出码 64）。**

**D4. ConfuserEx2 版本检查 — 已确认：校验 `Confuser.Core.dll` 的 SHA256。**
- 期望值：`12193041A68CBBABB4A9EA7A7C14621407739F613516FEA5CC19D1BD1257C8ED`，取自 mkaring/ConfuserEx release v1.6.0 的 `ConfuserEx-CLI.zip`（zip 本身 SHA256 `A00DE7CD…33753D7`，已核对）。
- `Confuser.CLI.exe` 的期望 SHA256 为 `0790671F930BD1375FA06ECE29A776404CEE44695E083CACE46C905433644130`，同样必须一致。
- 任一不一致则退出码 2。
- 版本串 `1.6.0+447341964f` 与运行日志一致，仅作参考，不作为判定依据。

**D5. 复核出现 FAIL 时 — 已确认：退出码 3，保留产物与报告。**

**D6. 复核项 e 的严重程度 — 已确认：WARN，不计入失败，在报告中醒目列出。**

## 10. 验收标准（由 `tests/benchmarks/test_module_1c.ps1` 实现）

1. 一条命令成功运行后，`protected/` 中有保护后的程序，`report.json` 存在且为合法 JSON。
2. 运行前后输入文件的 SHA256 相同，且 `report.json` 中 `input.unchanged` 为 true。
3. 三步（1A、1B、ConfuserEx2）的退出码均记录为 0。
4. 复核 a、b、c、d、f 全部 PASS；e 为 PASS 或 WARN。
5. 保留 `work\manifest.json` 与 `work\config.crproj`。
6. 输入不是托管程序时退出 65，且不生成 `protected/`。
7. 输出目录已存在且非空时退出 64。
8. 输入与输出目录重叠时退出 64。
9. `--confuser` 指向不存在的文件时退出 2。
10. `--confuser` 指向的目录不是 1.6.0 版本时退出 2（D4）。
11. 仓库内没有任何文件被改动（只写 `--out` 目录）。
12. `Confuser.CLI.exe` 被替换而 `Confuser.Core.dll` 正确时退出 2（D4）。
13. 输入旁边有 `<目标>.config` 时，`protected/<目标>.config` 存在。
14. 依赖子目录（如 `x64\libnative.dll`）被复制到 `protected/` 下对应子目录。

## 11. 不做的事

- 不运行保护后的程序（运行验证已中止）。
- 不做原生程序（3A、3B）。
- 不下载 ConfuserEx2。
- 不修复应用界面类排除的问题。这是另案：1A 输出基类信息，1B 按类型生成排除规则。

## 12. 依赖

- `module_1a.exe`、`module_1b.exe`（本仓库，子进程调用，见 D1）。
- dnlib 4.5.0（锁定，只读元数据）。
- ConfuserEx2 1.6.0 CLI（外部，由用户提供路径，见 D4）。
- 运行测试需要传入 `Confuser.CLI.exe` 的路径（`-Confuser` 参数或环境变量 `BS_CONFUSER_CLI`）。
