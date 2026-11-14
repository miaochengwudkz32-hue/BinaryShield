# industrial — 模拟工业软件的字符串加密验证

这是 `tests/string_encrypt_demo` 的第二个演示。它比 Hello World 更接近真实工业软件：有数据库连接字符串、API 密钥、授权密钥、错误信息和业务函数名。它**不是**任何真实项目的程序，也不连接任何网络或硬件，只是一个用来测试的替身。

> 这是"减少明文暴露"，不是"字符串已受保护"。解密代码和密钥都在程序里，运行时明文会出现在内存中。

## 要验证什么

| 检查 | 含义 |
|---|---|
| 对照版（普通字面量）能找到所有敏感字符串 | 证明检查方法能看到这些字符串 |
| 加密版找不到任何敏感字符串（ASCII 和 UTF-16LE） | 证明静态搜索看不到明文 |
| 两个版本的标准输出完全一致 | 证明加密不改变程序行为 |
| 两个版本都以退出码 0 结束 | 证明程序正常运行 |

## 敏感字符串（`secrets.txt`，10 条）

- 数据库连接字符串（含用户名和密码）
- API 密钥
- 两个授权密钥（企业版、试用版）
- 三条错误信息（授权不足、标定超限、历史库超时）
- 三个业务函数名（写在日志里）

不属于敏感字符串、保持明文的标签：`[config]`、`[api]`、`[license]`、`tier=`、`enterprise`、`other`、`steps=`、`ok=`、`max_drift=`、`rc=`、`fingerprint` 等。这些不包含秘密。"任何明文"指的是 `secrets.txt` 里列出的字符串。

## 两种语言

- **C++**（`cpp/industrial.cpp`）：ADVobfuscator，**固定参数 XOR**（`key=0x5A`，`IDENTITY`，`XOR`）。对照版用 `-DPLAIN_STRINGS`。
- **Rust**（`rust/src/main.rs`）：obfstr（`obfstr::obfstr!`）。对照版用 `--no-default-features --features plain`。

两个版本都用 `std::hint::black_box` 包住每个敏感字符串（见下文"过程中发现的问题"）。

## 结果（2026-11-14）

| 检查 | 结果 |
|---|---|
| C++ 普通版，10 次独立构建，每次对照版比较 | 10/10 通过，每次 23 项检查全部 PASS |
| Rust 普通版 vs 对照版（1 次构建） | 通过，23 项检查全部 PASS |
| 两个版本的标准输出（C++ 与 Rust 各自） | 与对照版逐字节一致（9 行） |

C++ 的 10 次构建结果一致。这是预期的：参数是固定的，不依赖编译时间。Rust 只做了 1 次构建，没有重复测量。

## 过程中发现的问题

1. **Rust 对照版一开始检查失败**：连接字符串、API 密钥、两个授权密钥都没有出现在对照版里。原因是编译器做了常量折叠：`count_fields` 和 `fnv1a` 的输入是常量，结果被算成常数，字符串本身从二进制里消失了。这说明对照版不可靠，检查会误判。修复方法是两个版本都用 `std::hint::black_box` 包住敏感字符串。修复后，对照版找到了全部 10 条。
2. **obfstr 的值是临时对象**：`obfstr::obfstr!` 返回的 `&str` 只在创建它的那条语句中有效（obfstr 的文档也这样说）。第一次把它存到 `let` 变量里时，编译报错。修复方法是把字符串直接传给调用，不先存进变量。
3. C++ 的第一次构建就通过了所有检查。

## 限制

- **固定参数 XOR 很弱**：它是单字节 XOR，密钥是固定常量。它只挡住静态搜索，不挡住任何有经验的逆向工程师。
- **只检查了 `secrets.txt` 里的 10 条**：列表之外的敏感内容不在检查范围内。
- **Rust 只做了 1 次构建**。obfstr 的种子来自源码中的字符串和宏位置，我在源码中没有发现使用构建时间（这是读源码的结论，没有在构建中验证）。
- **运行时会输出错误信息**：错误信息在程序运行时以明文打印，这是有意的，它们是程序的正常输出。
- **不覆盖**：运行时拼接的字符串、从文件或网络读取的字符串、符号表和调试信息（我没有检查 PDB 和符号名）。
- 只对**有源码**的程序有效。对已经编译好的二进制，这个方案不适用（见 `docs/research/native_string_protection.md`）。

## 文件

- `cpp/industrial.cpp`：C++ 版本。
- `rust/`：Rust 版本（`Cargo.toml`、`Cargo.lock`、`src/main.rs`）。
- `secrets.txt`：敏感字符串清单，每行一条。
- `verify_pair.ps1`：比较普通版和对照版：退出码、标准输出、每条秘密在对照版中存在、在普通版中不存在。
- `run_industrial.ps1`：构建并验证。

## 运行

```bash
powershell -ExecutionPolicy Bypass -File tests\string_encrypt_demo\industrial\run_industrial.ps1
powershell -ExecutionPolicy Bypass -File tests\string_encrypt_demo\industrial\run_industrial.ps1 -Repeat 10
```

`-Repeat N` 重复构建 C++ 普通版 N 次并逐次验证。前置条件与 `tests/string_encrypt_demo/README.md` 相同（g++、Rust GNU 工具链、`third_party/ADVobfuscator`）。

退出码：0 = 全部通过；1 = 有检查失败；2 = 缺少工具链或第三方库；3 = 编译失败。
