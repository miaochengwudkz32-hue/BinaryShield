# tests/dotnet8_avalonia — .NET 8 Avalonia 列表测试

**验证内容**：Avalonia 11.0.10 + .NET 8 程序，包含 10,000 项的 ListBox、数据绑定、按钮点击和滚轮滚动。经 Obfuscar 3.0.0-beta.22 保护后（`SkipNamespace Avalonia*`、`SkipNamespace CompiledAvaloniaXaml*`），行为应与原始版一致。

## 运行

前置条件：
- Windows 桌面会话。UI 测试发送真实鼠标输入，运行期间不要动鼠标和键盘。
- Visual Studio 2022（含 MSBuild）。
- .NET 8 运行时。
- Obfuscar.GlobalTool 3.0.0-beta.22 的 `GlobalTools.dll`。下载方法和 SHA256 见 `dependencies.md`，解压后使用 `tools/net8.0/any/GlobalTools.dll`。

```bash
powershell -ExecutionPolicy Bypass -File tests\dotnet8_avalonia\run_test.ps1 -ObfuscarDll <路径>\tools\net8.0\any\GlobalTools.dll
```

退出码：0 = 全部通过；1 = 有检查失败；2 = 前置缺失；3 = 编译或保护失败。

## 文件

- `ListDemo/`：测试程序源码（csproj 手写，用 MSBuild 编译）。
- `run_test.ps1`：编译 → 测试原始版 → Obfuscar 保护 → 组装保护版目录 → 测试保护版。
- `ui_test.ps1`：启动程序，点击按钮 3 次，滚轮 5 次，检查应用日志和截图，每项输出 PASS 或 FAIL。
- `run_linux_test.ps1`：Linux 版端到端测试。发布 linux-x64（自包含）→ Obfuscar 保护 → 补 X11 库 → 在 WSL2 Ubuntu 中通过 WSLg 运行并测试。
- `setup_linux_libs.sh`：在 Ubuntu 中用 `apt-get download` 下载 X11 库并解压，不需要 sudo，不改动系统。
- `out/`、`ListDemo/bin/`、`ListDemo/obj/`：生成物，已加入 `.gitignore`。

## 注意

- 按钮坐标（`-ButtonX 75 -ButtonY 60`）是在 125% 显示缩放下测得的。换显示设置后可能需要调整。
- Windows 测试：原始版和保护版都通过（9/9）。
- Linux 测试：**未通过**。保护版最终一次 9/9，但滚轮计数（5 次）在两个版本中都出现过只记录到 3 次的情况，根因未确认。
- 测试只说明这个小程序的表现，不代表目标程序通过。
