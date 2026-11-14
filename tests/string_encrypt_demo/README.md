# tests/string_encrypt_demo — 编译期字符串加密的可行性演示

**要证明什么**：用编译期字符串加密库写的程序，编译后的可执行文件里找不到明文字符串，但程序运行时能正确输出这些字符串。

> **重要**：这是"减少明文暴露"，不是"字符串已受保护"。解密代码和密钥都在程序里，运行时明文会出现在内存中。下面的结果只说明静态搜索找不到字符串，不说明程序已经受到保护。

- C++：[ADVobfuscator](https://github.com/andrivet/ADVobfuscator)（BSD-3-Clause-Clear，C++20 头文件库）
- Rust：[obfstr](https://github.com/CasualX/obfstr)（MIT，Rust 宏）

## 结果（2026-11-14）

| 检查 | 结果 |
|---|---|
| C++ 普通构建（固定密钥 XOR 参数）：15 次构建 | 15/15 通过：文件里找不到明文，程序正常输出四个秘密字符串 |
| C++ 对照构建（普通字面量） | 通过：文件里能找到四个秘密字符串 |
| Rust 普通构建（obfstr）：1 次构建 | 通过：文件里找不到明文，程序正常输出 |
| Rust 对照构建（普通字面量） | 通过：文件里能找到四个秘密字符串 |
| C++ 默认 `_obf` 写法（参数由编译时间决定）：第一次运行 | **失败**：URL 明文出现在文件里（见下） |
| C++ 默认 `_obf` 写法：之后的测量 | 实验中共约 48 次构建，其中 2 次有明文泄漏；本次 15 次构建中 0 次泄漏 |

**失败如实记录**：第一次运行 `run_demo.ps1` 时，用默认 `_obf` 写法的 C++ 普通构建里，`https://demo-secret.example.invalid/api/v1/token` 以明文出现在文件中（偏移约 0x37C0），其余三个秘密字符串没有出现。检查脚本正确地判定了失败。

**我做了什么**：
- 默认 `_obf` 写法的参数由 `__TIME__` 决定（精确到秒）。我用不同时间编译了同样的代码多次，每 48 次里有 2 次泄漏。
- 在泄漏的那次构建中，没有找到明确的原因：不是优化级别（`-O0`、`-O1`、`-O2` 都测过），不是常量折叠（`static constexpr` 与直接输出的写法都测过），也不是参数选中了恒等变换（实验中导出的参数没有出现这种情况）。泄漏只出现在 URL 上，其他三个字符串没有泄漏。**原因未确定。**
- 改为固定参数（`key=0x5A`，`key_algo=IDENTITY`，`data_algo=XOR`），这是 ADVobfuscator 文档中的显式参数写法。固定参数消除了编译时间带来的随机性。15 次构建中没有泄漏。
- 这个改动是缓解，不是根本修复：我没有找到泄漏的根本原因，所以不能保证固定参数一定不泄漏。
- 固定参数用的是**单字节 XOR**，密钥是固定常量。它很容易被识别和还原，只是让静态搜索找不到字符串，安全性很弱。

## 怎么验证（对照组设计）

每个语言各做两个构建：

| 构建 | 字符串写法 | 期望 |
|---|---|---|
| 普通构建（protected） | 加密字符串 | 文件里**找不到**任何秘密字符串（ASCII 和 UTF-16LE 都查）；程序**输出**全部秘密字符串 |
| 对照构建（control） | 普通字符串字面量 | 文件里**能找到**全部秘密字符串 |

对照构建是为了证明检查本身有效：如果对照构建里都找不到，说明检查方法有问题，普通构建的"找不到"就不可信。

秘密字符串在 `secrets.txt` 里，四条，都带有不会在其他地方出现的标记。

## 怎么运行

```bash
powershell -ExecutionPolicy Bypass -File tests\string_encrypt_demo\run_demo.ps1
powershell -ExecutionPolicy Bypass -File tests\string_encrypt_demo\run_demo.ps1 -Repeat 15 -RandomParamsRepeat 15
```

- `-Repeat N`：C++ 普通构建重复 N 次，每次都检查（默认 1）。
- `-RandomParamsRepeat N`：测量默认 `_obf` 写法 N 次构建中有多少次泄漏。只报告数字，不影响退出码。

退出码：0 = 全部通过；1 = 有检查失败；2 = 缺少工具链或第三方库；3 = 编译失败。

## 前置条件

- **C++**：`g++`（支持 C++20，已用 MinGW-w64 GCC 16.2.0 WinLibs 验证），在 PATH 上。
- **Rust**：rustup 的 `stable-x86_64-pc-windows-gnu` 工具链（已用 rustc 1.100.0 验证）。默认的 MSVC 工具链需要 Visual Studio 的 `link.exe`，本机没有，所以用 GNU 工具链，它借用 MinGW 的 GCC 做链接。obfstr 使用 edition 2024，需要 rustc 1.85 或更新版本。
- **第三方库**：从 GitHub 克隆到 `third_party/`（这个目录已加入 `.gitignore`，不提交）：

```bash
git clone --depth 1 https://github.com/andrivet/ADVobfuscator.git tests/string_encrypt_demo/third_party/ADVobfuscator
git clone --depth 1 https://github.com/CasualX/obfstr.git tests/string_encrypt_demo/third_party/obfstr
```

Rust 的 `Cargo.toml` 直接从 GitHub 按 commit 拉取 obfstr，不依赖 `third_party/obfstr`。`third_party/obfstr` 只用于阅读源码。

用到的版本（2026-11-14 克隆）：
- ADVobfuscator `9058623d0caf1fdf784d16e7f9233d29a5993acb`（2026-10-27）
- obfstr `9e56c1938dfd3bd65fe305fbafcb57394c701356`（2026-07-17）

## 文件

- `cpp/main.cpp`：C++ 示例。默认是固定参数 XOR 写法；`-DRANDOM_PARAMS` 是默认 `_obf` 写法，用来测量泄漏；`-DPLAIN_STRINGS` 是对照构建。
- `rust/`：Rust 示例，用 `obfstr::obfstr!`。`--no-default-features --features plain` 得到对照构建。
- `secrets.txt`：秘密字符串，每行一条。
- `verify.ps1`：检查文件中是否有明文，检查程序输出；`-Control` 切换为对照模式。
- `run_demo.ps1`：构建、验证，并可选地做重复测量。

## 限制（这个演示证明了什么，没有证明什么）

- 只证明**静态搜索**找不到字符串。解密代码和密钥都在程序里，程序运行时明文会出现在内存中。有经验的逆向工程师可以拿到它们。
- C++ 普通构建使用固定密钥的单字节 XOR，很容易还原。它只能挡住 `strings` 之类的静态搜索。
- 默认 `_obf` 写法在实验中偶尔泄漏（约 4%，原因未确定）。我没有找到它不泄漏的保证，所以不建议在没有逐次检查的情况下依赖它。
- obfstr 只做了 1 次普通构建的检查，没有做重复测量。它的种子来自源码中的字符串和宏位置，我在源码中没有发现使用构建时间（这是读源码的结论，没有在构建中验证）。
- 只覆盖源码中用字面量写出的字符串。运行时拼接、从文件或网络读取的字符串不在覆盖范围内。
- 只对**有源码**的程序有效。对已经编译好的二进制，这个方案不适用（见 `docs/research/native_string_protection.md`）。
- 编译器优化和库版本都会影响结果。这里只在上面记录的版本上验证过。
- 检查只查了两种编码（ASCII 和 UTF-16LE）。其他编码或拆分存放的字符串不在检查范围内。
