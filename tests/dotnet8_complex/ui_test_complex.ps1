# UI test for ComplexDemo (Avalonia .NET 8: three tabs, DataGrid, MVVM bindings, modal dialog).
# Starts the app, drives it with real mouse input, and checks the app's own log and screenshots.
#
# Click targets come from the app, not from hand-measured coordinates. At startup and after each
# tab change the app writes the centre of every named control:
#     pos <window> <name> <x> <y>    (device-independent pixels, relative to that window's client area)
#     size <window> <w> <h>          (client size in the same units)
# This script maps them to screen pixels with the window's live client origin and the ratio between
# the real and the logged client size. Nothing is calibrated per machine.
#
# Wheel scrolling is not part of this test. The WSLg wheel input was unreliable.
#
# Two modes:
#   Windows (default): starts ExePath directly.
#   Linux (-LinuxExe): starts the same binary in WSL2 Ubuntu through wsl.exe. WSLg shows the window
#                      as a normal Windows window. ExePath must be the Windows path of the same file,
#                      because the app writes its log next to it.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ui_test_complex.ps1 -ExePath <path>\ComplexDemo.exe -OutDir <dir> -Label <name>
#   powershell -ExecutionPolicy Bypass -File ui_test_complex.ps1 -ExePath <path>\ComplexDemo -LinuxExe /mnt/c/.../ComplexDemo -OutDir <dir> -Label <name>
#
# Exit codes: 0 = all checks PASS | 1 = at least one check FAIL | 2 = main window never appeared

param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$LinuxExe = "",
    # Turns on .NET invariant globalization, because the test Ubuntu has no libicu. See README.md.
    [string]$LinuxEnv = "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1",
    [string]$Label = "run"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Native {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr h);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int cmd);
    [DllImport("user32.dll")] static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool attach);
    [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();

    // Makes hwnd the foreground window, and returns true only if it really is. Clicks must not be sent
    // unless this is true, or they land on whatever other window is in front.
    public static bool IsForeground(IntPtr hwnd) { return GetForegroundWindow() == hwnd; }

    public static bool BringToFront(IntPtr hwnd) {
        if (GetForegroundWindow() == hwnd) return true;
        uint dummy;
        uint target = GetWindowThreadProcessId(hwnd, out dummy);
        uint fg = GetWindowThreadProcessId(GetForegroundWindow(), out dummy);
        uint me = GetCurrentThreadId();
        AttachThreadInput(me, fg, true);
        AttachThreadInput(me, target, true);
        ShowWindow(hwnd, 9); // SW_RESTORE, in case the window is minimized
        SetForegroundWindow(hwnd);
        AttachThreadInput(me, target, false);
        AttachThreadInput(me, fg, false);
        return GetForegroundWindow() == hwnd;
    }

    // Visible top-level window whose title starts with prefix, with the largest client area.
    // Several windows can share the prefix (the app also has small helper windows), so the
    // largest one is the real window. ownerPid 0 = any process; WSLg windows belong to
    // msrdc.exe, not to the app, so Linux runs pass 0.
    public static IntPtr FindWindow(string prefix, uint ownerPid) {
        IntPtr best = IntPtr.Zero;
        long bestArea = 0;
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            var sb = new StringBuilder(512);
            GetWindowText(h, sb, 512);
            if (!sb.ToString().StartsWith(prefix, StringComparison.Ordinal)) return true;
            uint pid;
            GetWindowThreadProcessId(h, out pid);
            if (ownerPid != 0 && pid != ownerPid) return true;
            RECT r;
            GetClientRect(h, out r);
            long area = (long)(r.Right - r.Left) * (r.Bottom - r.Top);
            if (area > bestArea) { bestArea = area; best = h; }
            return true;
        }, IntPtr.Zero);
        return best;
    }
}
"@

[void][Native]::SetProcessDPIAware()

$linuxMode = [bool]$LinuxExe
$exeDir  = Split-Path -Parent $ExePath
$logPath = Join-Path $exeDir "app_test.log"
$shotDir = Join-Path $OutDir "shots_$Label"
New-Item -ItemType Directory -Force -Path $shotDir | Out-Null
if (Test-Path $logPath) { Remove-Item $logPath -Force }

$results = @()
function Check([string]$name, [bool]$ok, [string]$detail = "") {
    $script:results += [pscustomobject]@{ Test = $name; Pass = $ok; Detail = $detail }
    if ($ok) { $tag = "PASS" } else { $tag = "FAIL" }
    "{0}  {1}  {2}" -f $tag, $name, $detail
}

function Save-WindowShot([IntPtr]$hwnd, [string]$file) {
    $r = New-Object Native+RECT
    [void][Native]::GetWindowRect($hwnd, [ref]$r)
    $w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($r.Left, $r.Top, 0, 0, (New-Object System.Drawing.Size $w, $h))
    $bmp.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
}

# Hash of the window body only (inner 80% of the capture, sampled every 6 px).
# The capture rectangle also contains whatever is behind the window, so whole-file hashes would
# change when a background window changes; this region is what the app itself draws.
function Get-RegionHash([string]$file) {
    $img = [System.Drawing.Bitmap]::FromFile($file)
    try {
        $x0 = [int]($img.Width * 0.10); $x1 = [int]($img.Width * 0.90)
        $y0 = [int]($img.Height * 0.10); $y1 = [int]($img.Height * 0.90)
        $sb = New-Object System.Text.StringBuilder
        for ($y = $y0; $y -lt $y1; $y += 6) {
            for ($x = $x0; $x -lt $x1; $x += 6) { [void]$sb.Append($img.GetPixel($x, $y).ToArgb()).Append(",") }
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($sb.ToString())))).Replace("-", "")
    } finally { $img.Dispose() }
}

# Wait until the window content stops changing (three identical captures 500 ms apart).
function Wait-ScreenStable([IntPtr]$hwnd) {
    $prev = ""; $same = 0; $tmp = Join-Path $env:TEMP "bs_complex_stable_probe.png"
    for ($t = 1; $t -le 40; $t++) {
        Start-Sleep -Milliseconds 500
        Save-WindowShot $hwnd $tmp
        $h = Get-RegionHash $tmp
        if ($h -eq $prev) { $same++ } else { $same = 0 }
        $prev = $h
        if ($same -ge 3) { return $t }
    }
    return -1
}

# Top-level window by title prefix (see Native.FindWindow). Returns IntPtr.Zero after the timeout.
function Wait-Window([string]$prefix, [int]$seconds, [uint32]$owner) {
    for ($i = 0; $i -lt ($seconds * 2); $i++) {
        $h = [Native]::FindWindow($prefix, $owner)
        if ($h.ToInt64() -ne 0) { return $h }
        Start-Sleep -Milliseconds 500
    }
    return [IntPtr]::Zero
}

function Read-Log { if (Test-Path $logPath) { return @(Get-Content $logPath -Encoding UTF8) } return @() }

# Last log line matching the regex, or $null after the timeout.
function Wait-Log([string]$pattern, [int]$timeoutMs = 8000) {
    $deadline = (Get-Date).AddMilliseconds($timeoutMs)
    while ($true) {
        $hits = @(Read-Log | Where-Object { $_ -match $pattern })
        if ($hits.Count -gt 0) { return $hits[-1] }
        if ((Get-Date) -ge $deadline) { return $null }
        Start-Sleep -Milliseconds 200
    }
}

# Centre of a named control in screen pixels, as logged by the app: screen <label> <name> <x> <y>
function Get-Screen([string]$label, [string]$name) {
    $line = Wait-Log ('screen ' + $label + ' ' + [regex]::Escape($name) + ' -?\d+ -?\d+$')
    if (-not $line) { return $null }
    $m = [regex]::Match($line, '(-?\d+) (-?\d+)$')
    return [pscustomobject]@{ X = [int]$m.Groups[1].Value; Y = [int]$m.Groups[2].Value }
}

# Set when the app window stops being the foreground window. After that no more clicks are sent,
# because a click would reach whatever other window is in front (for example, another app).
$script:focusLost = $false

# Left-click the centre of a logged control. Returns "" on success, or the reason it could not click.
function Do-Click($hwnd, [string]$label, [string]$name) {
    if ($script:focusLost) { return "skipped: focus was lost earlier in this run" }
    $p = Get-Screen $label $name
    if ($null -eq $p) { return "no screen position logged for $label/$name" }
    $x = $p.X; $y = $p.Y
    # Never click unless the target window is in front; otherwise the click reaches another window.
    if (-not [Native]::BringToFront($hwnd)) { $script:focusLost = $true; return "target window is not in front; click skipped" }
    Start-Sleep -Milliseconds 150
    [void][Native]::SetCursorPos($x, $y)
    Start-Sleep -Milliseconds 150
    # Check again right before pressing: focus can move between the first check and the press.
    if (-not [Native]::IsForeground($hwnd)) { $script:focusLost = $true; return "focus moved to another window before the press; click skipped" }
    [Native]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Native]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    return ""
}

# Launch
$proc = $null
if ($linuxMode) {
    # --cd and env avoid shell quoting, so the paths and variables reach the process intact.
    $linuxDir = $LinuxExe.Substring(0, $LinuxExe.LastIndexOf("/"))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d Ubuntu --cd $linuxDir -- env $LinuxEnv ./ComplexDemo"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    [uint32]$ownerPid = 0
} else {
    $proc = Start-Process -FilePath $ExePath -WorkingDirectory $exeDir -PassThru
    [uint32]$ownerPid = $proc.Id
}

function Stop-App {
    if ($linuxMode) { & wsl.exe -d Ubuntu -- pkill -x ComplexDemo | Out-Null }
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
}

# 0. Main window
$mainHwnd = Wait-Window "ComplexDemo" 30 $ownerPid
if ($mainHwnd.ToInt64() -eq 0) {
    Check "window appears" $false "no window titled ComplexDemo"
    Stop-App
    "SUMMARY: FAIL ($Label) - window never appeared"
    exit 2
}
Check "window appears" $true ("title starts with ComplexDemo")
$mainRect = New-Object Native+RECT
[void][Native]::GetClientRect($mainHwnd, [ref]$mainRect)
$mainW = $mainRect.Right - $mainRect.Left; $mainH = $mainRect.Bottom - $mainRect.Top
Check "chosen window is the app window (client area at least 400x300)" ($mainW -ge 400 -and $mainH -ge 300) "client ${mainW}x${mainH}"

$settle = Wait-ScreenStable $mainHwnd
Check "UI rendered and stable before input" ($settle -gt 0) "stable after $settle x 500 ms"
$front = [Native]::BringToFront($mainHwnd)
Check "app window is in front before input" $front
Start-Sleep -Milliseconds 300
$shotStart = Join-Path $shotDir "01_start.png"
Save-WindowShot $mainHwnd $shotStart

# 1. Startup: the view model and the DataGrid are bound to 500 customers
$opened = Wait-Log 'window opened; customers=\d+'
Check "view model bound to 500 customers" ([bool]($opened -match "customers=500")) "$opened"
$rows = Wait-Log 'view grid rows='
Check "DataGrid ItemsSource is the filtered view-model collection, 500 rows" ([bool]($rows -match "rows=500 bound=True")) "$rows"

# 2. Row click: view -> view model (two-way SelectedItem)
$err = Do-Click $mainHwnd "main" "RowFirst"
$sel = Wait-Log 'selected=Customer 001'
Check "row click sets view model SelectedCustomer (two-way binding)" ([bool]$sel) "$sel $err"
$shotRow = Join-Path $shotDir "02_row_selected.png"
Save-WindowShot $mainHwnd $shotRow
Check "screen changed after row click" ((Get-RegionHash $shotStart) -ne (Get-RegionHash $shotRow))

# 3. Details button: command -> code-behind -> modal dialog bound to the selected customer
$err = Do-Click $mainHwnd "main" "BtnDetails"
$det = Wait-Log 'details opened name=Customer 001'
Check "Details button opens a dialog for the selected customer" ([bool]$det) "$det $err"
$dlg = Wait-Window "Customer details" 10 $ownerPid
Check "dialog window appears" ($dlg.ToInt64() -ne 0)
$dlgView = Wait-Log 'details view name=Customer 001'
Check "dialog shows the customer through its DataContext" ([bool]$dlgView) "$dlgView"
Start-Sleep -Milliseconds 500
$shotDlg = Join-Path $shotDir "03_dialog_open.png"
Save-WindowShot $mainHwnd $shotDlg
Check "screen changed while dialog is open" ((Get-RegionHash $shotRow) -ne (Get-RegionHash $shotDlg))

# 4. Dialog Close button closes the dialog
if ($dlg.ToInt64() -ne 0) {
    $err = Do-Click $dlg "details" "BtnDetailsClose"
} else { $err = "dialog not found" }
$closed = Wait-Log 'details closed'
Start-Sleep -Milliseconds 800
$stillOpen = $false
if ($dlg.ToInt64() -ne 0) { $stillOpen = [Native]::IsWindow($dlg) }
Check "dialog Close button closes the dialog" ([bool]$closed -and -not $stillOpen) "$closed $err"

# 5. Tab click: view -> view model (two-way SelectedIndex)
$err = Do-Click $mainHwnd "main" "TabFilter"
$tab1 = Wait-Log 'vm SelectedTabIndex=1'
Check "tab click sets view model SelectedTabIndex (two-way binding)" ([bool]$tab1) "$tab1 $err"
$shotFilterBefore = Join-Path $shotDir "04_filter_tab.png"
Save-WindowShot $mainHwnd $shotFilterBefore

# 6. North filter: command -> view model -> DataGrid ItemsSource (125 of 500 customers)
$err = Do-Click $mainHwnd "main" "BtnNorth"
$filt = Wait-Log 'filter=North vm='
Check "North filter: view model and DataGrid agree on 125 rows" ([bool]($filt -match "vm=125 view=125")) "$filt $err"
$shotFilterAfter = Join-Path $shotDir "05_filter_north.png"
Save-WindowShot $mainHwnd $shotFilterAfter
Check "screen changed after North filter" ((Get-RegionHash $shotFilterBefore) -ne (Get-RegionHash $shotFilterAfter))

# 7. Counter tab: three clicks on Add; the view must show the bound count
$err = Do-Click $mainHwnd "main" "TabCounter"
$tab2 = Wait-Log 'vm SelectedTabIndex=2'
Check "tab click sets view model SelectedTabIndex to Counter" ([bool]$tab2) "$tab2 $err"
$shotCountBefore = Join-Path $shotDir "06_counter_before.png"
Save-WindowShot $mainHwnd $shotCountBefore
$addErr = @()
for ($c = 0; $c -lt 3; $c++) { $e = Do-Click $mainHwnd "main" "BtnAdd"; if ($e) { $addErr += $e } }
$counted = @(Read-Log | Where-Object { $_ -match 'counter click #' }).Count
Check "Add button handled 3 times (view model command)" ($counted -eq 3) "logged=$counted $($addErr -join '; ')"
$txt = Wait-Log 'view CountText=Count: 3'
Check "counter text bound in the view shows Count: 3" ([bool]$txt) "$txt"
$shotCountAfter = Join-Path $shotDir "07_counter_after.png"
Save-WindowShot $mainHwnd $shotCountAfter
Check "screen changed after counter clicks" ((Get-RegionHash $shotCountBefore) -ne (Get-RegionHash $shotCountAfter))

# 8. Still alive, then the app's own log
$proc.Refresh()
if ($linuxMode) { $alive = [Native]::IsWindow($mainHwnd) } else { $alive = -not $proc.HasExited }
Check "app still running after input" $alive
$frontDetail = ""; if ($script:focusLost) { $frontDetail = "focus lost: later clicks were skipped" }
Check "app stayed in front for every click" (-not $script:focusLost) $frontDetail
Stop-App
Start-Sleep -Milliseconds 300

$log = Read-Log
$unhandled = @($log | Where-Object { $_ -match 'unhandled exception' })
Check "no unhandled exceptions in the app log" ($unhandled.Count -eq 0) "lines=$($unhandled.Count)"

$fail = @($results | Where-Object { -not $_.Pass }).Count
$pass = $results.Count - $fail
if ($fail -eq 0) { $verdict = "PASS" } else { $verdict = "FAIL" }
"SUMMARY: $verdict ($Label) - $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
