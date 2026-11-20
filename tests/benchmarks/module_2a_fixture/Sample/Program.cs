using System;

// Benchmark fixture for Module 2A.
// Types live in the namespaces the Avalonia rule must cover (Avalonia, Avalonia.*, CompiledAvaloniaXaml, CompiledAvaloniaXaml.*),
// plus one trap namespace (AvaloniaApp47) that must NOT be skipped, and the application namespace (MyApp).
// Each probe class is internal, so KeepPublicApi does not keep its name. Only SkipNamespace can.
// Each probe returns a literal marker: skipped namespaces keep the literal, renamed ones hide it.

namespace MyApp
{
    internal static class Program
    {
        private static void Main()
        {
            Console.WriteLine(Avalonia.Controls.SkipProbeFoo.Run());
            Console.WriteLine(Avalonia.SkipProbeRoot.Run());
            Console.WriteLine(CompiledAvaloniaXaml.Sub.SkipProbeQux.Run());
            Console.WriteLine(AvaloniaApp47.RenameProbeBar.Run());
            Console.WriteLine("probe done");
        }
    }
}

namespace Avalonia.Controls
{
    internal static class SkipProbeFoo
    {
        public static string Run() { return "PROBE-SKIP-CONTROLS-7731"; }
    }
}

namespace Avalonia
{
    internal static class SkipProbeRoot
    {
        public static string Run() { return "PROBE-SKIP-ROOT-7732"; }
    }
}

namespace CompiledAvaloniaXaml.Sub
{
    internal static class SkipProbeQux
    {
        public static string Run() { return "PROBE-SKIP-XAML-7733"; }
    }
}

namespace AvaloniaApp47
{
    internal static class RenameProbeBar
    {
        public static string Run() { return "PROBE-RENAME-APP-7734"; }
    }
}
