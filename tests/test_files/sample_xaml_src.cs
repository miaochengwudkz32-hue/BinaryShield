// Module 1A test sample (second sample) -- compiled by csc into sample_xaml.dll.
// Covers the CompiledAvaloniaXaml part of the Avalonia rule (CLAUDE.md, "Avalonia rule"):
//   - namespace exactly "CompiledAvaloniaXaml"        -> skip:true
//   - namespace starting with "CompiledAvaloniaXaml."  -> skip:true
// Trap namespaces (must stay skip:false, they belong to the application):
//   - "AvaloniaApp"                 (starts with Avalonia but not "Avalonia." / exact)
//   - "CompiledAvaloniaXamlHelper"  (starts with CompiledAvaloniaXaml but not "CompiledAvaloniaXaml.")
//   - "MyApp.Avalonia"              (contains Avalonia but does not start with it)

using System;

namespace CompiledAvaloniaXaml
{
    public class XamlRoot
    {
        public string Marker() { return "xaml-root-marker"; }
    }
}

namespace CompiledAvaloniaXaml.Sub
{
    public class XamlPopulate
    {
        public string Marker() { return "xaml-populate-marker"; }
    }
}

namespace AvaloniaApp
{
    public class AppShell
    {
        public string Marker() { return "app-shell-marker"; }
    }
}

namespace CompiledAvaloniaXamlHelper
{
    public class HelperShell
    {
        public string Marker() { return "helper-shell-marker"; }
    }
}

namespace MyApp.Avalonia
{
    public class Nested
    {
        public string Marker() { return "nested-marker"; }
    }
}
