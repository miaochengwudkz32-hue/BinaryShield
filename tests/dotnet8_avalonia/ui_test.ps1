# UI test for ListDemo (Avalonia .NET 8: 10,000-item ListBox, data binding, button click).
# Starts the app, clicks the button and scrolls the list with real mouse input,
# takes screenshots, and checks the app's own test log.
#
# Two modes:
#   Windows (default): starts ExePath directly.
#   Linux (-LinuxExe):  starts the same binary inside Ubuntu (WSL2) with wsl.exe. The app's
#                       window is shown through WSLg as a normal Windows window, so the same
#                       mouse input and screenshots apply. ExePath must be the Windows path
#                       of that same file, because the app writes its log next to it.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File ui_test.ps1 -ExePath <path\ListDemo.exe> -OutDir <dir> -Label <name>
#   powershell -ExecutionPolicy Bypass -File ui_test.ps1 -ExePath <path\ListDemo> -LinuxExe /mnt/c/.../ListDemo -OutDir <dir> -Label <name>
# Exit codes: 0 = all checks PASS | 1 = at least one check FAIL | 2 = window never appeared
#
# Button position (ButtonX/ButtonY) is relative to the window's top-left corner in physical
# pixels. The defaults were measured at 125% display scaling; adjust them on other setups.

param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$LinuxExe = "",
    # Environment variables for the Linux process. The default turns on .NET invariant globalization,
    # because Ubuntu here has no ICU library (libicu). A real Linux deployment needs libicu installed
    # or this setting. Pass -LinuxEnv "" to test with ICU instead.
    [string]$LinuxEnv = "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1",
    [string]$Label = "run",
    [int]$ButtonX = 75,
    [int]$ButtonY = 60,
    [int]$Clicks = 3,
    [int]$WheelNotches = 5,
    # Pause between wheel notches. WSLg may merge notches sent too fast, so Linux runs use a longer pause.
    [int]$WheelDelayMs = 120,
    [int]$ExpectedItems = 10000
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, int dwData, IntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
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

# Launch
$proc = $null
if ($linuxMode) {
    # --cd and env avoid shell quoting, so the paths and variables reach the process intact.
    $linuxDir = $LinuxExe.Substring(0, $LinuxExe.LastIndexOf("/"))
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-d Ubuntu --cd $linuxDir -- env $LinuxEnv ./ListDemo"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
} else {
    $proc = Start-Process -FilePath $ExePath -WorkingDirectory $exeDir -PassThru
}

function Stop-App {
    if ($linuxMode) { & wsl.exe -d Ubuntu -- pkill -x ListDemo | Out-Null }
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill() } catch { } }
}

# Wait for the main window
$hwnd = [IntPtr]::Zero
for ($i = 0; $i -lt 60 -and $hwnd -eq [IntPtr]::Zero; $i++) {
    Start-Sleep -Milliseconds 500
    if ($linuxMode) {
        # WSLg adds the distro name to the window title ("ListDemo (Ubuntu)"), so match by prefix.
        $w = Get-Process | Where-Object { $_.MainWindowTitle -like "ListDemo*" } | Select-Object -First 1
        if ($w) { $hwnd = $w.MainWindowHandle }
    } else {
        $proc.Refresh()
        if ($proc.HasExited) { break }
        $hwnd = $proc.MainWindowHandle
    }
}
if ($hwnd -eq [IntPtr]::Zero) {
    Check "window appears" $false "no window titled ListDemo"
    Stop-App
    "SUMMARY: FAIL ($Label) - window never appeared"
    exit 2
}
if ($linuxMode) { $titleInfo = "title: ListDemo (WSLg)" } else { $titleInfo = "title: $($proc.MainWindowTitle)" }
Check "window appears" $true $titleInfo

# Wait until the window content stops changing (three identical screenshots in a row, 500 ms apart).
# A fixed sleep was not enough on a cold start: the 10,000-item list was still being laid out.
function Wait-ScreenStable([IntPtr]$hwnd) {
    $prev = ""; $same = 0; $tmp = Join-Path $env:TEMP "bs_stable_probe.png"
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
$settleTicks = Wait-ScreenStable $hwnd
Check "UI rendered and stable before input" ($settleTicks -gt 0) "stable after $settleTicks x 500 ms"

[void][Native]::SetForegroundWindow($hwnd)
Start-Sleep -Milliseconds 300
$r = New-Object Native+RECT
[void][Native]::GetWindowRect($hwnd, [ref]$r)
$shotStart = Join-Path $shotDir "01_start.png"
Save-WindowShot $hwnd $shotStart

# Button clicks with real mouse input
[void][Native]::SetCursorPos($r.Left + $ButtonX, $r.Top + $ButtonY)
Start-Sleep -Milliseconds 200
for ($c = 0; $c -lt $Clicks; $c++) {
    [Native]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    [Native]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 300
}
Start-Sleep -Milliseconds 500
$shotClicks = Join-Path $shotDir "02_after_clicks.png"
Save-WindowShot $hwnd $shotClicks

# Wheel scroll over the middle of the window (the list fills the lower part)
$lx = $r.Left + [int](($r.Right - $r.Left) / 2)
$ly = $r.Top + [int](($r.Bottom - $r.Top) * 0.6)
[void][Native]::SetCursorPos($lx, $ly)
Start-Sleep -Milliseconds 200
# Settle: a small move inside the list, then wait, so the window has the pointer before the first notch
[void][Native]::SetCursorPos($lx + 2, $ly + 2)
Start-Sleep -Milliseconds 500
for ($n = 0; $n -lt $WheelNotches; $n++) {
    [Native]::mouse_event(0x0800, 0, 0, -120, [IntPtr]::Zero)
    Start-Sleep -Milliseconds $WheelDelayMs
}
Start-Sleep -Milliseconds 800
$shotScroll = Join-Path $shotDir "03_after_scroll.png"
Save-WindowShot $hwnd $shotScroll

if ($linuxMode) {
    Check "app still running after input" ([Native]::IsWindow($hwnd)) "window still open"
} else {
    $proc.Refresh()
    Check "app still running after input" (-not $proc.HasExited)
}
Stop-App

# Checks against the app's own log
$log = @()
if (Test-Path $logPath) { $log = @(Get-Content $logPath -Encoding UTF8) }

$openedLine = @($log | Where-Object { $_ -match "window opened; items=(\d+)" })
$items = -1
if ($openedLine.Count -gt 0) { $items = [int]([regex]::Match($openedLine[-1], "items=(\d+)").Groups[1].Value) }
Check "list bound to $ExpectedItems items" ($items -eq $ExpectedItems) "items=$items"

$clickLines = @($log | Where-Object { $_ -match "button click #\d+" })
Check "button click handled $Clicks times" ($clickLines.Count -eq $Clicks) "logged clicks=$($clickLines.Count)"

$wheelLines = @($log | Where-Object { $_ -match "wheel delta" })
Check "wheel input reached the list $WheelNotches times" ($wheelLines.Count -eq $WheelNotches) "logged wheel events=$($wheelLines.Count)"

$offsets = @($log | Where-Object { $_ -match "scroll offset.y=" } | ForEach-Object {
    [double]([regex]::Match($_, "offset.y=([-\d\.,]+)").Groups[1].Value -replace ",", ".")
})
$lastOffset = 0.0
if ($offsets.Count -gt 0) { $lastOffset = $offsets[-1] }
Check "list scrolled (offset increased)" ($lastOffset -gt 0) "last offset.y=$lastOffset"

# Screenshot checks: the window content must change after clicks and after scrolling
$h1 = Get-RegionHash $shotStart
$h2 = Get-RegionHash $shotClicks
$h3 = Get-RegionHash $shotScroll
Check "screen changed after clicks" ($h1 -ne $h2) "shots: $shotDir"
Check "screen changed after scroll" ($h2 -ne $h3) "shots: $shotDir"

$fail = @($results | Where-Object { -not $_.Pass }).Count
$pass = $results.Count - $fail
if ($fail -eq 0) { $verdict = "PASS" } else { $verdict = "FAIL" }
"SUMMARY: $verdict ($Label) - $pass passed, $fail failed"
if ($fail -eq 0) { exit 0 } else { exit 1 }
