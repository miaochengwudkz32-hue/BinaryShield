// Module 1A 测试样本源码 —— 由 csc 编译成 sample.dll。
// 目的：提供一个可控的 .NET 程序，既有普通命名空间（应被正常解析），
// 也有 Avalonia 命名空间（必须被标记为 skip、永不转换）。
//
// 覆盖的验收点：
//   - 普通命名空间里有多条字符串字面量（满足"至少一条字符串"）
//   - 命名空间正好等于 "Avalonia"（决策③：也要 skip）
//   - 命名空间以 "Avalonia." 开头（标准 Avalonia 规则）

using System;

namespace DemoApp.Core
{
    public class Greeter
    {
        public string Hello()    { return "hello-from-demo"; }
        public string Farewell() { return "goodbye-demo-app"; }
    }
}

namespace DemoApp.Utils
{
    public static class Formatter
    {
        public static string Tag(string name) { return "tag:" + name + ":end"; }
    }
}

// ---- Avalonia 命名空间：必须 skip:true，后续任何模块都不得转换 ----

namespace Avalonia
{
    public class Root
    {
        public string Marker() { return "avalonia-root-marker"; }
    }
}

namespace Avalonia.Controls.Internal
{
    public class VirtualList
    {
        public string Render() { return "avalonia-virtualization-string"; }
    }
}
