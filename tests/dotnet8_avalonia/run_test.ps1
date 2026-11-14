# End-to-end test for the .NET 8 Avalonia list app:
#   1. build ListDemo with MSBuild (Visual Studio 2022)
#   2. UI test on the plain build
#   3. protect with Obfuscar 3.0.0-beta.22 (SkipNamespace Avalonia* and CompiledAvaloniaXaml*)
#   4. assemble a runnable protected folder (all runtime files + protected ListDemo.dll)
#   5. UI test on the protected build
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run_test.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
#   (or set the environment variable BS_OBFUSCAR_DLL to that path)
#
# Requirements: Visual Studio 2022 with MSBuild, .NET 8 runtime, an interactive Windows desktop
# (the UI test sends real mouse input). Obfuscar package: see ../../dependencies.md.
#
# Exit codes: 0 = all PASS | 1 = a UI test FAIL | 2 = prerequisite missing | 3 = build or protect failed

param([string]$ObfuscarDll = $env:BS_OBFUSCAR_DLL)

$ErrorActionPreference = "Stop"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj    = Join-Path $here "ListDemo\ListDemo.csproj"
$binDir  = Join-Path $here "ListDemo\bin\Release\net8.0"
$out     = Join-Path $here "out"
$obfOut  = Join-Path $out "obf_out"
$protDir = Join-Path $out "protected"
$cfg     = Join-Path $out "obf.xml"
$uiTest  = Join-Path $here "ui_test.ps1"

if (-not $ObfuscarDll -or -not (Test-Path -LiteralPath $ObfuscarDll)) {
    Write-Host "[missing] Obfuscar GlobalTools.dll: pass -ObfuscarDll or set BS_OBFUSCAR_DLL" -ForegroundColor Red
    exit 2
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = $null
if (Test-Path $vswhere) {
    $msbuild = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
}
if (-not $msbuild) {
    Write-Host "[missing] MSBuild.exe: install Visual Studio 2022 with the .NET desktop / MSBuild components" -ForegroundColor Red
    exit 2
}

# 1. Build
"=== 1. Build (MSBuild: $msbuild) ==="
& $msbuild $proj /restore /p:Configuration=Release /v:minimal /nologo
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed]" -ForegroundColor Red; exit 3 }

# 2. UI test, plain build
"=== 2. UI test: plain build ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File $uiTest -ExePath (Join-Path $binDir "ListDemo.exe") -OutDir $out -Label plain
$plainCode = $LASTEXITCODE

# 3. Protect with Obfuscar
"=== 3. Obfuscar 3.0.0-beta.22 ==="
Remove-Item $obfOut, $protDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $obfOut | Out-Null
# Obfuscar needs absolute paths and InPath, otherwise it cannot resolve the Avalonia dependencies.
$cfgText = @"
<?xml version='1.0'?>
<Obfuscator>
  <Var name="InPath" value="$binDir" />
  <Var name="OutPath" value="$obfOut" />
  <Module file="$(Join-Path $binDir 'ListDemo.dll')">
    <SkipNamespace name="Avalonia*" />
    <SkipNamespace name="CompiledAvaloniaXaml*" />
  </Module>
</Obfuscator>
"@
[IO.File]::WriteAllText($cfg, $cfgText, (New-Object Text.UTF8Encoding $false))
& dotnet $ObfuscarDll $cfg
if ($LASTEXITCODE -ne 0) { Write-Host "[obfuscar failed]" -ForegroundColor Red; exit 3 }
if (-not (Test-Path (Join-Path $obfOut "ListDemo.dll"))) { Write-Host "[obfuscar produced no ListDemo.dll]" -ForegroundColor Red; exit 3 }

# 4. Assemble a runnable protected folder: all runtime files from the build, protected ListDemo.dll on top.
"=== 4. Assemble protected folder ==="
New-Item -ItemType Directory -Force -Path $protDir | Out-Null
Get-ChildItem $binDir -Force |
    Where-Object { $_.Name -notlike "shots_*" -and $_.Name -ne "app_test.log" -and $_.Name -ne "ListDemo.pdb" } |
    Copy-Item -Destination $protDir -Recurse -Force
Copy-Item (Join-Path $obfOut "ListDemo.dll") (Join-Path $protDir "ListDemo.dll") -Force
"plain ListDemo.dll     SHA256: " + (Get-FileHash (Join-Path $binDir "ListDemo.dll") -Algorithm SHA256).Hash
"protected ListDemo.dll SHA256: " + (Get-FileHash (Join-Path $protDir "ListDemo.dll") -Algorithm SHA256).Hash

# 5. UI test, protected build
"=== 5. UI test: protected build ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File $uiTest -ExePath (Join-Path $protDir "ListDemo.exe") -OutDir $out -Label protected
$protCode = $LASTEXITCODE

"=== Summary ==="
"plain UI test:     exit $plainCode"
"protected UI test: exit $protCode"
if ($plainCode -eq 0 -and $protCode -eq 0) { exit 0 } else { exit 1 }
