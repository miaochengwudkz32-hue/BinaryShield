# tests/dotnet8_complex — complex .NET 8 Avalonia test app

**What it covers**: a more complex Avalonia 11.0.10 + .NET 8 program than `tests/dotnet8_avalonia/`:

- three tabs (Customers, Filter, Counter) with two-way binding of the selected tab;
- an `Avalonia.Controls.DataGrid` with 500 customers, bound to a filtered collection, with row selection;
- MVVM: a view model with public properties, `ICommand` commands, and change notification;
- a modal dialog (`DetailsWindow`) opened from a command and bound to the selected customer, closed by its button.

The app is protected with Obfuscar 3.0.0-beta.22 (`SkipNamespace Avalonia*`, `SkipNamespace CompiledAvaloniaXaml*`), as in `tests/dotnet8_avalonia/`.

## Run

Prerequisites: same as `tests/dotnet8_avalonia/README.md` (Windows desktop session, Visual Studio 2022 MSBuild, .NET 8 runtime, Obfuscar `GlobalTools.dll`). Do not touch the mouse or keyboard while a UI test runs.

```bash
powershell -ExecutionPolicy Bypass -File tests\dotnet8_complex\run_test.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
powershell -ExecutionPolicy Bypass -File tests\dotnet8_complex\run_linux_test.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
```

Exit codes: 0 = all PASS; 1 = a check FAIL; 2 = prerequisite missing; 3 = build, protect or setup failed.

## How the test finds what to click

The app writes its own layout to `app_test.log` next to the exe: `screen <window> <name> <x> <y>` (centre of each named control in physical screen pixels, from Avalonia's `PointToScreen`). `ui_test_complex.ps1` clicks those points directly. No per-machine coordinates are needed. On WSLg the window's target area includes decorations, so a formula based on the target program rectangle put clicks in the wrong place; `PointToScreen` avoids that.

**Focus guard**: a click is sent only when the app window is the foreground window, checked before the move and again before the press. If focus is lost, later clicks are skipped and the run fails ("app stayed in front for every click"). This prevents clicks reaching another window (for example, a browser).

## Status (2026-11-13)

| Run | Result |
|---|---|
| Windows protected | 23/23 PASS |
| Windows plain | first run 22/23 (North click did not register). Rerun 23/23 PASS. Cause: during this run the Edge window took focus from the app (the screenshot showed Edge in front). This is a test-environment problem, not a problem with the app or the protection. Not fully proven; see below. |
| Linux plain | 23/23 PASS |
| Linux protected | 23/23 PASS |

Windows plain has failed once in two runs of the final code, so it is not yet proven stable. The cause is not confirmed: the screenshot shows Edge in front after the failed click, but that does not rule out other causes. Keep other windows, especially any that update themselves (for example a chat in Edge), out of the way during a run.

## Files

- `ComplexDemo/`: app source (csproj written by hand; built with MSBuild).
- `ui_test_complex.ps1`: launches the app, clicks through it, checks the app log and screenshots. Each check prints PASS or FAIL.
- `run_test.ps1`: Windows: build → UI test (plain) → Obfuscar → UI test (protected).
- `run_linux_test.ps1`: Linux: publish linux-x64 self-contained → Obfuscar → X11 libraries (`../dotnet8_avalonia/setup_linux_libs.sh`) → UI test (plain and protected) through WSLg.
- `out/`, `ComplexDemo/bin/`, `ComplexDemo/obj/`: generated (screenshots in `out/shots_*`, app logs next to each exe); in `.gitignore`.

## Checks

See the list in `ui_test_complex.ps1` (section comments 1–8). In short: window and stable rendering; ItemsSource bound to 500 rows; row click sets the view model (two-way); Details opens the dialog with the selected name; dialog Close works; tab click sets the view model (two-way); North filter gives 125 rows in both the view model and the grid; Add button ×3 updates the bound counter text; no unhandled exceptions.

## Not tested (and why)

- **Wheel scrolling**: removed from this test. WSLg wheel delivery was unreliable, so a wheel check would fail for reasons unrelated to the app.
- **Rendered row count**: Avalonia 11.0.10's `DataGrid` has no public item count. "rows=" is the count of the collection bound to `ItemsSource`, plus a check that it is the view model's collection. The rendered rows are only visible in the screenshots.
- Frame rate, DataGrid virtualization internals, complex XAML, the target program's real code.
- The test shows how this test app behaves; it does not show that the target program passes.
