# 原生二进制（PE）字符串保护：GitHub 调研报告

- 日期：2026-11-14
- 范围：只做文档和 GitHub 研究。没有下载、克隆、编译或运行任何工具，也没有写代码。
- 数据来源：`gh search repos`、`gh repo view`、`gh api repos/<repo>/readme`、`gh issue list`（均为只读）。星数、最后推送时间和许可证是 2026-11-14 查询时 GitHub 返回的值。

## 结论

**没有找到适合我们流水线的现成开源工具。**

- 能做字符串加密的成熟开源工具，几乎都在**编译期**工作。它们需要源码，并且要改构建过程，不能直接处理已经编译好的 PE 文件。
- 能直接处理已编译 PE 的开源工具，要么没有字符串加密功能，要么许可证不明、维护停止，要么 README 的定位是研究用途或规避检测。
- 因此：如果目标方的原生模块有源码，可以在目标方的构建里加入编译期库（C/C++ 推荐 ADVobfuscator，Rust 推荐 obfstr 或 litcrypt）。如果只有二进制，目前没有可以直接集成的现成方案。
- 自己实现 PE 级字符串加密与 `CLAUDE.md` 的项目范围冲突，需要你决定（见第 5 节）。

## 1. 有没有支持 PE 字符串加密的开源工具？

**编译期（需要源码，不能处理已编译的 PE）**

| 工具 | 语言 | 字符串加密 | 说明 |
|---|---|---|---|
| ADVobfuscator (andrivet) | C++20 | 是（README 明确写明） | 头文件库，运行时解码 |
| xorstr (JustasMasiulis) | C++17 | 是（仅看了简介） | 编译期 XOR 字符串加密 |
| obfstr (CasualX) | Rust | 是（README 明确写明） | 编译期字符串混淆宏 |
| litcrypt.rs (anvie) | Rust | 是 | 编译期字符串加密（过程宏） |
| Hikari | LLVM | 是（README 配图） | 已归档并声明弃用，不建议使用 |
| YANSOllvm | LLVM 21 插件 | 未明确列出 | README 提到对只读数组编码 |
| DeClang (DeNA) | LLVM 分支 | README 中未见字符串加密 | 面向 iOS、Android、Unity |
| OLLVM、Pluto | LLVM | 未见（OLLVM 不含字符串加密是我已有的知识，未在本次 README 中核实） | |

**后处理（直接处理已编译的 PE）**

| 工具 | 功能 | 是否逐个字符串加密 |
|---|---|---|
| Ryujin (keowu) | PE x64 bin2bin：代码段加密、虚拟化、反调试 | 否，功能列表里没有字符串加密 |
| Alcatraz (weak1337) | PE x64：立即数混淆、控制流平坦化、导入混淆 | 否，功能列表里没有字符串加密 |
| pe-packer (notcpuid) | 增加一个运行时解密的节 | 否。`-senc` 是对选定的节做 XOR 加密，运行时整节还原 |
| Windows-PE-Packer (czs108) | 加密节、清除节名、重建导入表 | 否，节级加密 |

后处理工具里，没有一个同时满足"逐个字符串加密""许可证清楚""维护活跃"。

## 2. 有没有命令行接口？

| 工具 | 命令行 | 集成难度 |
|---|---|---|
| ADVobfuscator | 无（头文件库） | 低，但需要源码和 C++20 编译器 |
| obfstr / litcrypt.rs | 无（Rust 宏，由 cargo 构建） | 低，但需要源码 |
| xorstr | 无（头文件） | 低，但需要源码 |
| YANSOllvm | 通过 `opt -load-pass-plugin` 调用 | 高：需要先从源码编译 LLVM 21.1.8 |
| DeClang | 编译器 fork，替换编译器 | 高：需要自行编译整个工具链 |
| Ryujin | 有 CLI，也有 GUI（GUI 依赖 wxWidgets） | 中：部分变换需要 PDB |
| Alcatraz | README 只描述了 GUI 操作（打开文件、点 compile），未见 CLI | 未核实 |
| pe-packer | 有 CLI：`pe-packer.exe <in> <out> <level> [flags]` | 低 |
| Windows-PE-Packer | 前半部分 README 未见 CLI 说明 | 未核实 |

## 3. 维护状态

| 工具 | 许可证 | 星数 | 最后推送 | 备注 |
|---|---|---|---|---|
| ADVobfuscator | BSD-3-Clause-Clear | 1788 | 2026-10-27 | 无未关闭的 issue |
| xorstr | Apache-2.0 | 1456 | 2026-11-08 | 仅看了元数据 |
| obfstr | MIT | 627 | 2026-07-17 | |
| litcrypt.rs | Apache-2.0（LICENSE 正文；GitHub 页面显示 other） | 265 | 2026-04-22 | |
| YANSOllvm | GPL-3.0 | 409 | 2026-07-22 | 固定 LLVM 21.1.8 |
| DeClang | Other（LLVM 的 Apache-2.0 with LLVM Exceptions；DeNA 增加的部分未核实） | 504 | 2026-10-16 | |
| pe-packer | Apache-2.0 | 141 | 2026-08-21 | README 声明仅供研究和教育用途 |
| Ryujin | GPL-2.0 | 353 | 2025-11-20 | 无未关闭的 issue |
| Windows-PE-Packer | MIT | 369 | 2024-10-22 | |
| Pluto | 无 | 916 | 2024-11-21 | |
| OLLVM（obfuscator-llvm） | 无（API 显示 null） | 4397 | 2023-10-20 | |
| Alcatraz | 无 | 2003 | 2023-07-14 | |
| Hikari | 无（API 显示 null，许可证在 wiki 中） | 2103 | 2023-01-29 | 已归档；README 写明"不应再使用" |

按照项目规则，没有许可证的仓库只能阅读后借鉴思路，不能复制代码。

## 4. 已知兼容问题

只查了 open issue 的标题和状态，没有逐条核实是否真的影响运行。

- **ADVobfuscator**：需要 C++20 编译器；嵌入式环境的标准库可能不完整。README 提醒 debug 构建不做优化，编译期计算的效果在 debug 下会不同。
- **litcrypt.rs**：open issue #12（转义字符，2025-12 仍有更新）；#7 询问原始字符串的用法。
- **Alcatraz**：open issue #27 "corrupts 'Hello, world!' .exe msvc"（2024-03 起未关闭，2025-04 最后更新）；#23、#24 报告崩溃（2023）。
- **Windows-PE-Packer**：open issue #9 "Packed hello.exe doesn't work"（2025-01）；#5 x64 支持的功能请求未关闭。
- **YANSOllvm**：只支持 LLVM 21.1.8；issue #2 报告 PIE 对象错误（2021）。
- **DeClang**：issue #27 说明 OLLVM 的部分功能已被移除。多数 issue 与 iOS、Android、Swift 构建有关。
- **Ryujin**：README 写明 "TrollReversers" 功能可能在逆向时导致蓝屏。这对交付给目标方的程序是不可接受的风险。部分变换还需要 PDB。
- **pe-packer**：`-senc` 只是 XOR 节加密；README 注明仅供研究和教育用途。
- **Hikari**：已归档，README 明确声明已弃用。

## 5. 与项目范围的冲突（需要你决定）

`CLAUDE.md` 的"项目范围 · 不做"部分写明：本项目不实现字符串编码或任何保护算法，只配置和调用现成工具。

自己写 PE 级字符串加密（定位字符串引用、加密、插入解密桩）就是在实现保护算法，与这条冲突。LIEF 可以改写 PE 文件，但"技术上能做"不等于"在项目范围内"。

可选路径：

- **A. 只做源码级方案。** 如果目标方有 C/C++ 或 Rust 源码，把编译期库加入目标方的构建：C/C++ 用 ADVobfuscator，Rust 用 obfstr 或 litcrypt。这不是我们流水线中的一步，我们只能提供集成说明。
- **B. 原生字符串保护暂不纳入 v0.3。** 如实告诉目标方：没有源码的原生二进制，目前无法覆盖字符串保护。
- **C. 修改项目范围，允许我们实现 PE 级字符串加密。** 需要你明确决定，并补充安全评审。

**推荐：A + B。** A 的许可证清楚、维护活跃，也不改变项目范围。B 诚实地说明覆盖范围。

## 6. 未核实的内容

- 没有下载、编译或运行任何工具。兼容性结论只来自 README 和 issue 的标题与状态。
- xorstr 只看了元数据和简介，没有读 README。
- OLLVM、Pluto、YANSOllvm、DeClang 是否含字符串加密，需要读源码或文档确认。
- DeClang 中 DeNA 增加部分的许可证未核实。
- 中文搜索（"字符串加密 混淆 可执行文件"）的结果都是 Java、Android 或 Nim 相关，没有找到中文的 PE 工具。
- 商业工具（如 Themida、VMProtect）不在本次范围内，因为需求是开源工具。
- 没有纳入的项目：SaadAhla/PE-Obfuscator（无许可证，描述以"规避检测"为目标）；PEzor、amber 等偏向免杀加载器的项目（只看了描述，未读 README）。
