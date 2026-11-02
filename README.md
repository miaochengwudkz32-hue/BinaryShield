# BinaryShield

BinaryShield 是一个 .NET 程序的保护流水线：它调用开源工具 ConfuserEx2 完成保护，并为 Avalonia 界面程序补上关键的兼容规则。

BinaryShield 本身不实现任何混淆或加密算法。它做三件事：读取程序集、生成 ConfuserEx2 的配置、把结果交给 ConfuserEx2 执行，最后用只读方式复核保护前后的关键内容。

## 解决什么问题

使用 Avalonia 开发的桌面程序，在直接用 ConfuserEx2 全局保护后，界面往往无法加载或变慢。原因是两点：

- Avalonia 在运行时依赖类型名、成员名和资源的原始形式（例如界面代码是按名字反射访问的），被重命名或加密后界面就会失效。
- 编译后的界面资源（XAML）如果被加密，界面同样无法加载。

BinaryShield 会自动识别 Avalonia 相关的命名空间，对它们移除保护，并对嵌入的界面资源保持不加密，其余代码仍然按 ConfuserEx2 的 `normal` 预设保护。

## 快速上手

前提：Windows，.NET Framework 4.x，以及 ConfuserEx2 1.6.0 的命令行工具（`Confuser.CLI.exe`）。具体构建与准备步骤见 [USAGE.md](USAGE.md)。

```bash
module_1c.exe protect "C:\path\to\YourApp.exe" --out "C:\path\to\output" --confuser "C:\tools\ConfuserEx\Confuser.CLI.exe"
```

完成后：

- `output\protected\` 中是保护后的程序，以及需要它一起运行的依赖文件。
- `output\report.json` 是本次运行的复核报告，列出每一步的结果和每一项检查的 PASS / FAIL / WARN。

## 输出说明

```
output\
├── protected\        ← 保护后的程序与依赖，可直接运行
├── work\             ← 中间文件：副本、清单、配置、ConfuserEx2 原始输出
└── report.json       ← 本次运行的摘要与复核结果
```

退出码含义、`report.json` 字段和复核项的说明见 [USAGE.md](USAGE.md)。

## 已知限制

- **只支持 .NET 程序集**（.dll 与 .exe）。原生程序（PE/ELF 的 C/C++/Rust 程序）暂不支持。
- **依赖 ConfuserEx2 1.6.0**。该版本发布于 2022 年，其规则语法和保护项 ID 是针对 1.6.0 验证的，其他版本可能不兼容。
- **保护强度有所降低**：Avalonia 相关代码不受保护；基础规则去掉了 `ref proxy` 和 `resources` 两项保护。
- **应用自身的界面类仍然受保护**，但复核会检查它们的指令是否被改动，并在报告中列出。
- **已在一个 Avalonia 11 示例程序上验证**（.NET Framework 4.7，VS 2022 编译）。界面能够加载并显示；滚动、点击等交互，以及真实应用程序，还需要单独验证。
- 只在 Windows 上测试。

## 文档

- [USAGE.md](USAGE.md)：构建、参数、输出、退出码、保护规则与排错。
