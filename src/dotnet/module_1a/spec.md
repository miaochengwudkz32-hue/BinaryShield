# Module 1A 规格文档 — .NET IL 解析器与命名空间分类器

> 状态：**待人工确认**（按 README 工作流，第①步写完规格后需等待确认，再进入第②步写测试）
> 对应版本：v0.1 · 日期：2026-11-01

---

## 1. 目标（一句话）

读取一个 .NET 4.7 的 `.exe` / `.dll`，把里面所有程序集、类型、方法、字符串字面量（含 IL 偏移）解析成结构化 JSON，并把所有 `Avalonia.` 命名空间标记为 `"skip": true`。

本模块只**读取和分类**，不做任何转换、编码或写回（那是 module_1b / module_1c 的事）。

---

## 2. 输入（Input）

| 项 | 说明 |
|----|------|
| 文件类型 | 单个 .NET 4.7 托管 PE：`.exe` 或 `.dll`（IL 字节码） |
| 传入方式 | 命令行参数：`module_1a <输入文件路径> [输出json路径]` |
| 前置假设 | 文件存在、可读、是合法托管 PE |

**需要稳妥处理的非理想输入：**
- 文件不存在 / 无读取权限
- 不是托管 PE（纯原生 C/C++/Rust 二进制，没有 .NET 元数据）
- 文件损坏或被加壳/加密，dnlib 抛异常
- 多模块程序集（一个 assembly 含多个 module）

---

## 3. 输出（Output）

UTF-8 编码的合法 JSON。建议结构如下（字段名可在确认阶段调整）：

```json
{
  "tool": "BinaryShield",
  "module": "1a",
  "schemaVersion": "0.1",
  "input": {
    "path": "C:/.../MyApp.dll",
    "fileName": "MyApp.dll",
    "sha256": "……",
    "isManaged": true,
    "targetFramework": ".NETFramework,Version=v4.7"
  },
  "assemblies": [
    {
      "fullName": "MyApp, Version=1.0.0.0, Culture=neutral, PublicKeyToken=null",
      "modules": [
        {
          "name": "MyApp.dll",
          "types": [
            {
              "namespace": "MyApp.Utils",
              "name": "Helper",
              "fullName": "MyApp.Utils.Helper",
              "isNested": false,
              "skip": false,
              "methods": [
                {
                  "name": "Encode",
                  "signature": "System.String Encode(System.String)",
                  "hasBody": true,
                  "stringLiterals": [
                    { "value": "secret-prefix", "ilOffset": 12, "opcode": "ldstr" }
                  ]
                }
              ]
            }
          ]
        }
      ]
    }
  ],
  "summary": {
    "typeCount": 0,
    "methodCount": 0,
    "stringLiteralCount": 0,
    "skippedTypeCount": 0
  }
}
```

**字段要点：**
- `skip`：由命名空间规则决定（见第 5 节）。被跳过的类型仍然列在 JSON 里，只是打上标记，后续模块据此绝不对它做转换。
- `ilOffset`：该 `ldstr` 指令在方法体内的 IL 偏移（`Instruction.Offset`）。
- `stringLiterals`：逐条列出，**同一字符串出现多次就记多条**，各带各自偏移。
- `sha256`：记录输入文件哈希，便于后续"运行时完整性校验"模块对账。

---

## 4. 方法（Approach）

锁定库：**dnlib**（唯一的 .NET IL 读写库，README 已锁定）。

1. `ModuleDefMD.Load(path)` 载入模块。
2. 读 `TargetFrameworkAttribute` / 元数据，填 `input` 段。
3. 遍历 `module.GetTypes()`（含嵌套类型）。
4. 每个类型：按第 5 节规则算出 `skip`。
5. 每个方法：
   - 无方法体（abstract / extern / P/Invoke）→ `hasBody: false`，无字符串。
   - 有方法体：遍历 `method.Body.Instructions`，筛 `OpCode == OpCodes.Ldstr`，取操作数（字符串）与 `Instruction.Offset`。
6. 汇总 `summary`，序列化为 JSON 写出。

> **为什么只取 `ldstr`：** IL 层面的字符串字面量就是 `ldstr` 指令的操作数；这是后续"字符串编码"模块真正要替换的目标。资源(resources)/字段初始值里的字符串不在 v0.1 范围，避免误伤。

---

## 5. Avalonia 规则（硬约束）

- 命名空间以 `Avalonia.` 开头 → `skip: true`。
- 命名空间正好等于 `Avalonia`（无点）→ 同样 `skip: true`（建议一并覆盖，见第 7 节待确认项）。
- 被跳过的类型：其方法与字符串**照常列出**，但 `skip: true`；后续任何模块在任何情况下都不得对其做转换。
- 大小写：命名空间按**精确大小写**匹配 `Avalonia`（.NET 命名空间区分大小写）。

---

## 6. 边界情况（Edge cases）

| 情况 | 处理 |
|------|------|
| 文件不存在 / 不可读 | 报错并以非 0 退出码退出，不产出 JSON |
| 非托管 PE（原生二进制） | 检测后输出 `isManaged: false` 并友好退出（本模块不处理原生，交给 module_3a/3b） |
| 加壳/加密致 dnlib 抛异常 | 捕获，报告失败原因，非 0 退出 |
| 无方法体的方法 | `hasBody: false`，空字符串列表 |
| 全局命名空间（空命名空间） | `namespace: ""`，`skip: false` |
| 嵌套类型 | `fullName` 含外层类型名，`isNested: true` |
| `<Module>` 全局类型 | 照常列出 |
| 泛型类型 / 方法 | 列出，`signature` 带泛型信息 |
| 多模块程序集 | 遍历全部 module |
| 重复字符串字面量 | 每次出现各记一条（各自偏移） |
| Unicode / 含特殊字符的字符串 | JSON 正确转义，UTF-8 输出 |
| 超大程序集 | v0.1 允许整体载入内存；若后续有内存压力再优化 |

---

## 7. 需要你确认的技术决策（关键）

1. **实现语言冲突。** README 的"锁定技术栈"写 `Tool language: C` / 编译器 GCC/MinGW，但 **dnlib 是 .NET(C#) 库，无法从 C 直接调用**。仓库目录也把 `src/dotnet/`（托管模块）和 `src/native/`（原生模块）分开了。
   - **我的建议：** `src/dotnet/` 下的模块（含本 1A）用 **C# + .NET 4.7 控制台程序 + dnlib** 实现；`src/native/` 下的 C/C++/Rust 处理模块仍用 C。即"C 是原生侧的语言，托管侧用 C#"。
   - 若确认，需要在 `dependencies.md` 里登记：dnlib 版本、.NET 4.7 SDK、JSON 序列化方式（建议 System.Text.Json 或手写，避免引入未锁定的第三方库）。
   - **这条按 README 的"锁定技术栈不得擅改"要求，必须你拍板。**

2. **输出去向：** 写到 `[输出json路径]` 文件，同时可选打到 stdout？还是只写文件？（建议：默认写文件，加 `--stdout` 可选打印。）

3. **Avalonia 精确匹配：** 命名空间正好是 `Avalonia`（无后续点）是否也算 skip？（我的建议：算，见第 5 节。）

---

## 8. 验收标准（来自 README，全部必须 PASS）

- [ ] 能解析一个测试 `.dll` 而不崩溃
- [ ] 输出至少包含一条字符串字面量
- [ ] 所有 `Avalonia.*` 命名空间的条目 `skip: true`
- [ ] 输出是合法、可解析的 JSON

---

## 9. 不在本模块范围（Out of scope）

- 任何转换 / 编码 / 混淆（module_1b / 1c）
- 任何写回修改二进制
- 原生二进制（module_3a/3b/3c）
- 运行时完整性校验、节区编码（后续版本）
