# End-to-end Linux test for the .NET 8 Avalonia test app.
# Run from Windows; the app runs in WSL2 Ubuntu and its window is shown through WSLg.
#   1. publish linux-x64, self-contained (the .NET runtime is inside the output; nothing to install in Ubuntu)
#   2. protect the published ListDemo.dll with Obfuscar 3.0.0-beta.22 (SkipNamespace Avalonia*, CompiledAvaloniaXaml*)
#   3. fetch X11 runtime libraries into out\linux\syslibs (no root; see setup_linux_libs.sh)
#   4. UI test of the plain and the protected build through WSLg
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run_linux_test.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
#   (or set BS_OBFUSCAR_DLL)
#
# Requirements: Windows 11 with WSL2 and WSLg, an Ubuntu distro whose first-run setup is finished,
# Visual Studio 2022 (MSBuild), the Obfuscar package (see ../../dependencies.md), a desktop session.
# The Linux runtime uses invariant globalization (no libicu on the test machine); see README.md.
#
# Exit codes: 0 = all PASS | 1 = a UI test FAIL | 2 = prerequisite missing | 3 = build, protect or setup failed

param([string]$ObfuscarDll = $env:BS_OBFUSCAR_DLL)

$ErrorActionPreference = "Stop"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj    = Join-Path $here "ListDemo\ListDemo.csproj"
$out     = Join-Path $here "out\linux"
$build   = Join-Path $out "build"
$obfOut  = Join-Path $out "obf_out"
$prot    = Join-Path $out "protected"
$syslibs = Join-Path $out "syslibs"
$cfg     = Join-Path $out "obf.xml"
$uiTest  = Join-Path $here "ui_test.ps1"
$setupSh = Join-Path $here "setup_linux_libs.sh"

if (-not $ObfuscarDll -or -not (Test-Path -LiteralPath $ObfuscarDll)) {
    Write-Host "[missing] Obfuscar GlobalTools.dll: pass -ObfuscarDll or set BS_OBFUSCAR_DLL" -ForegroundColor Red
    exit 2
}
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    Write-Host "[missing] wsl.exe (WSL2 is not installed)" -ForegroundColor Red
    exit 2
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = $null
if (Test-Path $vswhere) {
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
}
if (-not $msbuild) {
    Write-Host "[missing] MSBuild.exe: install Visual Studio 2022 with MSBuild" -ForegroundColor Red
    exit 2
}

# Windows path -> WSL path, e.g. C:\a\b -> /mnt/c/a/b
function To-WslPath([string]$winPath) {
    $full = [IO.Path]::GetFullPath($winPath)
    $drive = $full.Substring(0, 1).ToLower()
    $rest = $full.Substring(2) -replace "\\", "/"
    return "/mnt/$drive$rest"
}

# Clean previous Linux outputs
Remove-Item $build, $obfOut, $prot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1. Publish linux-x64, self-contained
"=== 1. Publish linux-x64 (self-contained) ==="
& $msbuild $proj /restore /t:Publish /p:Configuration=Release /p:RuntimeIdentifier=linux-x64 /p:SelfContained=true "/p:PublishDir=$build\" /v:minimal /nologo
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $build "ListDemo.dll"))) { Write-Host "[publish failed]" -ForegroundColor Red; exit 3 }

# 2. Protect with Obfuscar
"=== 2. Obfuscar 3.0.0-beta.22 ==="
New-Item -ItemType Directory -Force -Path $obfOut | Out-Null
$cfgText = @"
<?xml version='1.0'?>
<Obfuscator>
  <Var name="InPath" value="$build" />
  <Var name="OutPath" value="$obfOut" />
  <Module file="$(Join-Path $build 'ListDemo.dll')">
    <SkipNamespace name="Avalonia*" />
    <SkipNamespace name="CompiledAvaloniaXaml*" />
  </Module>
</Obfuscator>
"@
[IO.File]::WriteAllText($cfg, $cfgText, (New-Object Text.UTF8Encoding $false))
& dotnet $ObfuscarDll $cfg
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $obfOut "ListDemo.dll"))) { Write-Host "[obfuscar failed]" -ForegroundColor Red; exit 3 }

# Protected folder = full publish output with the protected ListDemo.dll on top (no PDB: it no longer matches)
Copy-Item $build $prot -Recurse -Force
Copy-Item (Join-Path $obfOut "ListDemo.dll") (Join-Path $prot "ListDemo.dll") -Force
Remove-Item (Join-Path $prot "ListDemo.pdb") -Force -ErrorAction SilentlyContinue

# 3. X11 runtime libraries for Ubuntu (downloaded and unpacked into out\linux\syslibs, no root)
"=== 3. X11 runtime libraries ==="
$syslibsWsl = To-WslPath $syslibs
$setupWsl   = To-WslPath $setupSh
& wsl.exe -d Ubuntu --cd /tmp -- bash $setupWsl $syslibsWsl
if ($LASTEXITCODE -ne 0) { Write-Host "[setup of X11 libraries failed]" -ForegroundColor Red; exit 3 }

# 4. UI tests through WSLg
"=== 4. UI test: Linux plain build ==="
$buildWsl = To-WslPath $build
$protWsl  = To-WslPath $prot
$linuxEnv = "DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1 LD_LIBRARY_PATH=$syslibsWsl/usr/lib/x86_64-linux-gnu"
# Known issue: under WSLg the plain build sometimes logs only 3 of 5 wheel notches.
# The 600 ms pause did not remove it in every run; the protected build logged 5 of 5 in every run so far.
$common = @("-LinuxEnv", $linuxEnv, "-ButtonX", "95", "-ButtonY", "87", "-WheelDelayMs", "600", "-OutDir", $out)
& powershell -NoProfile -ExecutionPolicy Bypass -File $uiTest -ExePath (Join-Path $build "ListDemo") -LinuxExe "$buildWsl/ListDemo" -Label linux_plain @common
$plainCode = $LASTEXITCODE

"=== 5. UI test: Linux protected build ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File $uiTest -ExePath (Join-Path $prot "ListDemo") -LinuxExe "$protWsl/ListDemo" -Label linux_protected @common
$protCode = $LASTEXITCODE

"=== Summary ==="
"Linux plain UI test:     exit $plainCode"
"Linux protected UI test: exit $protCode"
if ($plainCode -eq 0 -and $protCode -eq 0) { exit 0 } else { exit 1 }
