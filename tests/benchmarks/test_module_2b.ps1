# Benchmark for Module 2B (bs.exe, unified CLI). Written before the feature code (STEP 2).
#
#   Group R  argument checks, routing and refusals. Nothing is protected in this group.
#   Group E  .NET 8 route end to end: 1A -> 2A -> Obfuscar -> checks. Needs dotnet and Obfuscar.
#   Group F  .NET Framework route: a full run with ConfuserEx2 1.6.0 (F2), a ConfuserEx2 failure mapped
#            to 75 (F3), and the pass-through of 1C's refusal (F1). ConfuserEx2 comes from -ConfuserCli
#            (default tools\ConfuserEx-1.6.0\Confuser.CLI.exe); if it is missing, F2 and F3 print NOT RUN.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File test_module_2b.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
#   (or set the environment variable BS_OBFUSCAR_DLL)
#
# Exit codes: 0 = all PASS | 1 = at least one FAIL | 2 = prerequisite missing (dotnet, Obfuscar, csc, sample)
#             3 = bs.exe or a child tool (1A, 1B, 1C, 2A) is not built yet (nothing was run)

param([string]$ObfuscarDll = $env:BS_OBFUSCAR_DLL, [string]$ConfuserCli = $env:BS_CONFUSER_CLI)

$ErrorActionPreference = "Stop"
$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo       = (Resolve-Path (Join-Path $here "..\..")).Path
$dotnetDir  = Join-Path $repo "src\dotnet"
$bsBuilt    = Join-Path $dotnetDir "module_2b\bs.exe"
$fixtureSrc = Join-Path $here "module_2a_fixture\Sample"
$fxRepoSample = Join-Path $repo "tests\test_files\sample.dll"   # built by csc without TargetFrameworkAttribute (see R17)
$csc        = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$skipRegex  = '^(Avalonia|CompiledAvaloniaXaml)(\..*)?$'
$utf8NoBom  = New-Object Text.UTF8Encoding($false)
if (-not $ConfuserCli) { $ConfuserCli = Join-Path $repo "tools\ConfuserEx-1.6.0\Confuser.CLI.exe" }

# ---------- prerequisites ----------
if (-not $ObfuscarDll -or -not (Test-Path -LiteralPath $ObfuscarDll)) {
    Write-Host "[missing] Obfuscar GlobalTools.dll: pass -ObfuscarDll or set BS_OBFUSCAR_DLL" -ForegroundColor Red
    exit 2
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "[missing] dotnet SDK (8.0 or newer)" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $csc)) {
    Write-Host "[missing] csc.exe (.NET Framework 4.x)" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path -LiteralPath $fxRepoSample)) {
    Write-Host "[missing] sample: $fxRepoSample" -ForegroundColor Red
    exit 2
}

$childBuilt = @(
    (Join-Path $dotnetDir "module_1a\module_1a.exe"),
    (Join-Path $dotnetDir "module_1a\dnlib.dll"),
    (Join-Path $dotnetDir "module_1b\module_1b.exe"),
    (Join-Path $dotnetDir "module_1c\module_1c.exe"),
    (Join-Path $dotnetDir "module_2a\module_2a.exe")
)
$required = @($bsBuilt) + $childBuilt
$notBuilt = @($required | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($notBuilt.Count -gt 0) {
    Write-Host "[not built] these files are missing, so nothing was run:" -ForegroundColor Yellow
    foreach ($m in $notBuilt) { Write-Host "  $m" -ForegroundColor Yellow }
    exit 3
}

$work = Join-Path $env:TEMP ("bs_2b_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
"work folder: $work"

$results = New-Object System.Collections.ArrayList
function Check([string]$grp, [string]$name, [bool]$ok, [string]$detail = "") {
    [void]$results.Add([pscustomobject]@{ Group = $grp; Name = $name; Pass = $ok })
    if ($ok) { $tag = "PASS" } else { $tag = "FAIL" }
    "{0}  {1}  {2}  {3}" -f $tag, $grp, $name, $detail
}
function NotRun([string]$grp, [string]$name, [string]$why) {
    "NOT RUN  {0}  {1}  ({2})" -f $grp, $name, $why
}
function Invoke-Tool([string]$exe, [string[]]$argList) {
    $ErrorActionPreference = "Continue"
    $out = (& $exe @argList 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    return [pscustomobject]@{ Code = $code; Out = $out }
}
function Get-Sha([string]$path) { return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
function Read-Json([string]$path) { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) }

# Flat tool folder: this is what --bin-dir should point to (bs.exe and its children side by side).
$dist = Join-Path $work "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Copy-Item -LiteralPath $bsBuilt -Destination $dist
foreach ($f in $childBuilt) { Copy-Item -LiteralPath $f -Destination $dist }
$bs = Join-Path $dist "bs.exe"

# ---------- fixtures ----------
$fx = Join-Path $work "fixtures"
New-Item -ItemType Directory -Force -Path $fx | Out-Null

# .NET 8 sample: the same fixture as module 2A group B.
$sample8 = Join-Path $fx "sample8"
Copy-Item $fixtureSrc $sample8 -Recurse
$sample8Out = Join-Path $fx "sample8_out"
$ErrorActionPreference = "Continue"
$buildLog = (& dotnet build (Join-Path $sample8 "Sample.csproj") -c Release -o $sample8Out --nologo 2>&1 | Out-String)
$buildCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
$dll8 = Join-Path $sample8Out "Sample.dll"
if ($buildCode -ne 0 -or -not (Test-Path -LiteralPath $dll8)) {
    Write-Host "[fixture build failed]" -ForegroundColor Red
    $buildLog
    exit 2
}
$ErrorActionPreference = "Continue"
$plainRun = (& dotnet $dll8 2>&1 | Out-String)
$ErrorActionPreference = "Stop"

# Tiny assemblies that carry a TargetFrameworkAttribute for another framework.
# They need no SDK packages, so they build offline.
function New-FakeTfmDll([string]$name, [string]$tfm) {
    $src = Join-Path $fx ($name + ".cs")
    $dst = Join-Path $fx ($name + ".dll")
    $code = '[assembly: System.Runtime.Versioning.TargetFramework("' + $tfm + '")]' + "`r`n" + 'public static class ' + $name + ' { }'
    [IO.File]::WriteAllText($src, $code, $utf8NoBom)
    $ErrorActionPreference = "Continue"
    $cscOut = (& $csc /nologo /target:library ("/out:" + $dst) $src 2>&1 | Out-String)
    $cscCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    if ($cscCode -ne 0 -or -not (Test-Path -LiteralPath $dst)) {
        Write-Host "[csc failed] $cscOut" -ForegroundColor Red
        exit 2
    }
    return $dst
}
$fake6   = New-FakeTfmDll "Fake6" ".NETCoreApp,Version=v6.0"
$fake9   = New-FakeTfmDll "Fake9" ".NETCoreApp,Version=v9.0"
$fakeStd = New-FakeTfmDll "FakeStd" ".NETStandard,Version=v2.0"
# A .NET Framework 4.7 assembly that carries the attribute, as a VS build does. This is the FX fixture.
$fxSample = New-FakeTfmDll "Fx47" ".NETFramework,Version=v4.7"

# F2 fixture: a .NET Framework 4.7 console app that prints one line. The protected build must print the same line.
$fxAppSrc = Join-Path $fx "Fx47App.cs"
[IO.File]::WriteAllText($fxAppSrc, '[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.7")]' + "`r`n" + 'public static class Program { public static void Main() { System.Console.WriteLine("hello from fx47"); } }', $utf8NoBom)
$fxApp = Join-Path $fx "Fx47App.exe"
$ErrorActionPreference = "Continue"
$appBuild = (& $csc /nologo /target:exe ("/out:" + $fxApp) $fxAppSrc 2>&1 | Out-String)
$appBuildCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($appBuildCode -ne 0 -or -not (Test-Path -LiteralPath $fxApp)) { Write-Host "[csc failed] $appBuild" -ForegroundColor Red; exit 2 }

# F3 fixture: RefApp.exe references Helper.dll. The benchmark copies only RefApp.exe to its input folder,
# so ConfuserEx2 cannot resolve the reference and fails.
$helperSrc = Join-Path $fx "Helper.cs"
[IO.File]::WriteAllText($helperSrc, 'public static class Helper { public static string Name() { return "helper"; } }', $utf8NoBom)
$helperDll = Join-Path $fx "Helper.dll"
$refSrc = Join-Path $fx "RefApp.cs"
[IO.File]::WriteAllText($refSrc, '[assembly: System.Runtime.Versioning.TargetFramework(".NETFramework,Version=v4.7")]' + "`r`n" + 'public static class Program { public static void Main() { System.Console.WriteLine(Helper.Name()); } }', $utf8NoBom)
$refExe = Join-Path $fx "RefApp.exe"
$ErrorActionPreference = "Continue"
$libBuild = (& $csc /nologo /target:library ("/out:" + $helperDll) $helperSrc 2>&1 | Out-String)
$libBuildCode = $LASTEXITCODE
$refBuild = (& $csc /nologo /target:exe ("/reference:" + $helperDll) ("/out:" + $refExe) $refSrc 2>&1 | Out-String)
$refBuildCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($libBuildCode -ne 0 -or $refBuildCode -ne 0 -or -not (Test-Path -LiteralPath $refExe)) { Write-Host "[csc failed] $libBuild $refBuild" -ForegroundColor Red; exit 2 }

# Not a .NET program: an MZ header followed by zeros, with no CLI metadata.
$native = Join-Path $fx "native.dll"
$nativeBytes = New-Object byte[] 1024
$nativeBytes[0] = 0x4D
$nativeBytes[1] = 0x5A
[IO.File]::WriteAllBytes($native, $nativeBytes)

# Stand-ins for a broken Obfuscar (not an assembly, so dotnet exits non-zero) and a broken ConfuserEx2.
$stubDir = Join-Path $fx "stub"
New-Item -ItemType Directory -Force -Path $stubDir | Out-Null
$stubObf = Join-Path $stubDir "GlobalTools.dll"
[IO.File]::WriteAllText($stubObf, "this is not an assembly", $utf8NoBom)
$fakeConfDir = Join-Path $fx "fakeconf"
New-Item -ItemType Directory -Force -Path $fakeConfDir | Out-Null
$fakeConf = Join-Path $fakeConfDir "Confuser.CLI.exe"
[IO.File]::WriteAllText($fakeConf, "not confuser", $utf8NoBom)   # no Confuser.Core.dll next to it

$missingConf = Join-Path $fx "nope\Confuser.CLI.exe"
$missingObf  = Join-Path $fx "nope\GlobalTools.dll"

# A bin folder that lacks most of the children.
$partial = Join-Path $work "partial"
New-Item -ItemType Directory -Force -Path $partial | Out-Null
Copy-Item -LiteralPath (Join-Path $dotnetDir "module_1a\module_1a.exe") -Destination $partial
Copy-Item -LiteralPath (Join-Path $dotnetDir "module_1a\dnlib.dll") -Destination $partial

# bs.exe alone in its own folder: tests the default --bin-dir (the exe's own folder).
$solo = Join-Path $work "solo"
New-Item -ItemType Directory -Force -Path $solo | Out-Null
Copy-Item -LiteralPath $bsBuilt -Destination $solo
$soloBs = Join-Path $solo "bs.exe"

$rRoot = Join-Path $work "R"
New-Item -ItemType Directory -Force -Path $rRoot | Out-Null

# ---------- Group R: arguments, routing, refusals ----------

$rj = Join-Path $rRoot "r1.json"
$x = Invoke-Tool $bs @("analyze", $fxSample, $rj)
$r1ok = ($x.Code -eq 0) -and (Test-Path -LiteralPath $rj) -and ((Get-Content -LiteralPath $rj -Raw) -match 'NETFramework,Version=v4')
Check "R" "R1 analyze forwards to module_1a: exit 0, JSON has the .NET Framework target" $r1ok "exit $($x.Code)"

$x = Invoke-Tool $bs @("analyze", (Join-Path $rRoot "missing.dll"))
Check "R" "R2 analyze with a missing input: exit 66" ($x.Code -eq 66) "exit $($x.Code)"

$x = Invoke-Tool $bs @()
Check "R" "R3 no arguments: exit 64" ($x.Code -eq 64) "exit $($x.Code)"

$x = Invoke-Tool $bs @("frobnicate")
Check "R" "R4 unknown command: exit 64" ($x.Code -eq 64) "exit $($x.Code)"

$o = Join-Path $rRoot "r5_out"
$x = Invoke-Tool $bs @("protect", $native, "--out", $o, "--bin-dir", $dist, "--confuser", $fakeConf)
Check "R" "R5 non-managed input: exit 65, output not created" (($x.Code -eq 65) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$cases = @(
    @{ id = "R6"; dll = $fake6;   tfm = "NETCoreApp,Version=v6.0" },
    @{ id = "R7"; dll = $fake9;   tfm = "NETCoreApp,Version=v9.0" },
    @{ id = "R8"; dll = $fakeStd; tfm = "NETStandard,Version=v2.0" }
)
foreach ($c in $cases) {
    $o = Join-Path $rRoot ($c.id + "_out")
    $x = Invoke-Tool $bs @("protect", $c.dll, "--out", $o, "--bin-dir", $dist, "--confuser", $fakeConf, "--obfuscar", $stubObf)
    $ok = ($x.Code -eq 65) -and ($x.Out -match [regex]::Escape($c.tfm)) -and (-not (Test-Path -LiteralPath $o))
    Check "R" ($c.id + " unsupported target " + $c.tfm + ": exit 65, names the framework, output not created") $ok "exit $($x.Code)"
}

$o = Join-Path $rRoot "r9_out"
New-Item -ItemType Directory -Force -Path $o | Out-Null
[IO.File]::WriteAllText((Join-Path $o "keep.txt"), "x", $utf8NoBom)
$x = Invoke-Tool $bs @("protect", $fxSample, "--out", $o, "--bin-dir", $dist, "--confuser", $fakeConf)
$keepOk = (Test-Path -LiteralPath (Join-Path $o "keep.txt")) -and (-not (Test-Path -LiteralPath (Join-Path $o "protected")))
Check "R" "R9 --out is not empty: exit 64, existing file untouched" (($x.Code -eq 64) -and $keepOk) "exit $($x.Code)"

$ov = Join-Path $rRoot "r10in"
New-Item -ItemType Directory -Force -Path $ov | Out-Null
Copy-Item -LiteralPath $fxSample -Destination (Join-Path $ov "sample.dll")
$o = Join-Path $ov "out"
$x = Invoke-Tool $bs @("protect", (Join-Path $ov "sample.dll"), "--out", $o, "--bin-dir", $dist, "--confuser", $fakeConf)
Check "R" "R10 --out inside the input folder: exit 64, output not created" (($x.Code -eq 64) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r11_out"
$x = Invoke-Tool $bs @("protect", $fxSample, "--out", $o, "--bin-dir", $dist)
Check "R" "R11 .NET Framework route without --confuser: exit 64, output not created" (($x.Code -eq 64) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r12_out"
$x = Invoke-Tool $bs @("protect", $dll8, "--out", $o, "--bin-dir", $dist)
Check "R" ".NET 8 route without --obfuscar: exit 64, output not created" (($x.Code -eq 64) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r13_out"
$x = Invoke-Tool $bs @("protect", $fxSample, "--out", $o, "--bin-dir", $dist, "--confuser", $missingConf)
Check "R" "R13 --confuser file does not exist: exit 66, output not created" (($x.Code -eq 66) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r14_out"
$x = Invoke-Tool $bs @("protect", $dll8, "--out", $o, "--bin-dir", $dist, "--obfuscar", $missingObf)
Check "R" "R14 --obfuscar file does not exist: exit 66, output not created" (($x.Code -eq 66) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r15_out"
$x = Invoke-Tool $bs @("protect", $dll8, "--out", $o, "--bin-dir", $partial, "--obfuscar", $stubObf)
Check "R" "R15 --bin-dir lacks module_1b/1c/2a: exit 66, output not created" (($x.Code -eq 66) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

$o = Join-Path $rRoot "r16_out"
$x = Invoke-Tool $soloBs @("protect", $fxSample, "--out", $o, "--confuser", $fakeConf)
Check "R" "R16 default --bin-dir (bs.exe folder) lacks the children: exit 66, output not created" (($x.Code -eq 66) -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

# Added after the first run: tests\test_files\sample.dll has no TargetFrameworkAttribute. 1A then reports the
# runtime version (v4.0.30319), which is not a target framework, so 2B refuses it (missing field -> 65).
$o = Join-Path $rRoot "r17_out"
$x = Invoke-Tool $bs @("protect", $fxRepoSample, "--out", $o, "--bin-dir", $dist, "--confuser", $fakeConf)
Check "R" "R17 assembly without TargetFrameworkAttribute (1A reports v4.0.30319): exit 65, output not created" (($x.Code -eq 65) -and ($x.Out -match 'v4\.0\.30319') -and (-not (Test-Path -LiteralPath $o))) "exit $($x.Code)"

# ---------- Group E: .NET 8 route end to end ----------

$eRoot = Join-Path $work "E"
New-Item -ItemType Directory -Force -Path $eRoot | Out-Null
$e1Out = Join-Path $eRoot "out"
$hashBefore = Get-Sha $dll8
$x = Invoke-Tool $bs @("protect", $dll8, "--out", $e1Out, "--bin-dir", $dist, "--obfuscar", $ObfuscarDll)
$hashAfter = Get-Sha $dll8
Check "E" "E1 .NET 8 route: exit 0" ($x.Code -eq 0) "exit $($x.Code)"

$protDll = Join-Path $e1Out "protected\Sample.dll"
Check "E" "E2 out\protected\Sample.dll exists" (Test-Path -LiteralPath $protDll)

$ErrorActionPreference = "Continue"
$protRun = (& dotnet $protDll 2>&1 | Out-String)
$ErrorActionPreference = "Stop"
Check "E" "E3 protected program prints the same output as the plain build" ($protRun.Trim() -ceq $plainRun.Trim())

$mpPath = Join-Path $e1Out "work\manifest-protected.json"
$mpOk = $false
if (Test-Path -LiteralPath $mpPath) {
    $mp = Read-Json $mpPath
    $typesP = @()
    foreach ($a in @($mp.assemblies)) { foreach ($m in @($a.modules)) { $typesP += @($m.types) } }
    $probeKept    = @($typesP | Where-Object { $_.namespace -eq 'Avalonia.Controls' -and $_.name -eq 'SkipProbeFoo' }).Count -eq 1
    $probeRenamed = @($typesP | Where-Object { $_.namespace -eq 'AvaloniaApp47' -and $_.name -eq 'RenameProbeBar' }).Count -eq 0
    $mpOk = $probeKept -and $probeRenamed
}
Check "E" "E4 protected manifest: Avalonia.Controls.SkipProbeFoo keeps its name; AvaloniaApp47.RenameProbeBar is renamed" $mpOk

Check "E" "E5 input DLL unchanged (SHA256 before and after)" ($hashBefore -eq $hashAfter)

$rep = Join-Path $e1Out "bs-report.json"
$repOk = $false
if (Test-Path -LiteralPath $rep) {
    $rj2 = Read-Json $rep
    $ids = @($rj2.checks | ForEach-Object { $_.id })
    $noFail = @($rj2.checks | Where-Object { $_.status -eq 'FAIL' }).Count -eq 0
    $allIds = @($ids | Where-Object { $_ -in @('n1', 'n2', 'n3', 'n4', 'n5', 'n6') }).Count -eq 6
    $repOk = ($rj2.route -eq 'net8') -and ($rj2.exitCode -eq 0) -and $noFail -and $allIds
}
Check "E" "E6 bs-report.json: route net8, exitCode 0, checks n1-n6 present, none FAIL" $repOk

$cfgPath = Join-Path $e1Out "work\obf.xml"
$cfgOk = $false
if (Test-Path -LiteralPath $cfgPath) {
    $cx = New-Object System.Xml.XmlDocument
    $cx.Load($cfgPath)
    $sk = @($cx.SelectNodes("//SkipNamespace"))
    $cfgOk = ($sk.Count -eq 1) -and ($sk[0].GetAttribute("rx") -ceq $skipRegex)
}
Check "E" "E7 work\obf.xml has one SkipNamespace rx rule (module 2A rule)" $cfgOk

Check "E" "E8 work\ kept, including work\in and Obfuscar's raw output (N4)" ((Test-Path -LiteralPath (Join-Path $e1Out "work\in")) -and (Test-Path -LiteralPath (Join-Path $e1Out "work\protected")))

$runtimeOk = (Test-Path -LiteralPath (Join-Path $e1Out "protected\Sample.runtimeconfig.json")) -and (Test-Path -LiteralPath (Join-Path $e1Out "protected\Sample.deps.json"))
Check "E" "E9 out\protected has Sample.runtimeconfig.json and Sample.deps.json (needed to run with dotnet)" $runtimeOk

$e10Out = Join-Path $eRoot "out_fail"
$x = Invoke-Tool $bs @("protect", $dll8, "--out", $e10Out, "--bin-dir", $dist, "--obfuscar", $stubObf)
$rep10Ok = $false
$rep10 = Join-Path $e10Out "bs-report.json"
if (Test-Path -LiteralPath $rep10) { $rep10Ok = ((Read-Json $rep10).exitCode -eq 75) }
Check "E" "E10 Obfuscar cannot run: exit 75, bs-report.json says 75" (($x.Code -eq 75) -and $rep10Ok) "exit $($x.Code)"

# ---------- Group F: .NET Framework route, pass-through only ----------

$fo = Join-Path $rRoot "f1_out"
$x = Invoke-Tool $bs @("protect", $fxSample, "--out", $fo, "--bin-dir", $dist, "--confuser", $fakeConf)
Check "F" "F1 .NET Framework route, ConfuserEx2 without Confuser.Core.dll: exit 2 from 1C, output not created" (($x.Code -eq 2) -and (-not (Test-Path -LiteralPath $fo))) "exit $($x.Code)"

$fRoot = Join-Path $work "F"
New-Item -ItemType Directory -Force -Path $fRoot | Out-Null

if (Test-Path -LiteralPath $ConfuserCli) {
    # F2: full .NET Framework run with the real ConfuserEx2 1.6.0.
    $f2Out = Join-Path $fRoot "f2_out"
    $sha2Before = Get-Sha $fxApp
    $x = Invoke-Tool $bs @("protect", $fxApp, "--out", $f2Out, "--bin-dir", $dist, "--confuser", $ConfuserCli)
    $sha2After = Get-Sha $fxApp
    Check "F" "F2 .NET Framework route, full run: exit 0" ($x.Code -eq 0) "exit $($x.Code)"

    $f2Prot = Join-Path $f2Out "protected\Fx47App.exe"
    $plainFx = (& $fxApp 2>&1 | Out-String)
    $protFx = ""
    if (Test-Path -LiteralPath $f2Prot) { $protFx = (& $f2Prot 2>&1 | Out-String) }
    Check "F" "F2 protected program prints the same output as the plain build" ((Test-Path -LiteralPath $f2Prot) -and ($protFx.Trim() -ceq $plainFx.Trim()))

    $f2Rep = Join-Path $f2Out "bs-report.json"
    $f2RepOk = $false
    if (Test-Path -LiteralPath $f2Rep) {
        $r2j = Read-Json $f2Rep
        $f2RepOk = ($r2j.route -eq 'netfx') -and ($r2j.exitCode -eq 0)
    }
    Check "F" "F2 bs-report.json: route netfx, exitCode 0" $f2RepOk
    Check "F" "F2 input EXE unchanged (SHA256 before and after)" ($sha2Before -eq $sha2After)

    # F3: the helper reference is missing from the input folder, so ConfuserEx2 fails.
    # 1A and 1B succeed; 1C returns 70 because its ConfuserEx2 step failed; 2B must map that to 75.
    $f3In = Join-Path $fRoot "f3_in"
    New-Item -ItemType Directory -Force -Path $f3In | Out-Null
    Copy-Item -LiteralPath $refExe -Destination $f3In
    $f3Out = Join-Path $fRoot "f3_out"
    $x = Invoke-Tool $bs @("protect", (Join-Path $f3In "RefApp.exe"), "--out", $f3Out, "--bin-dir", $dist, "--confuser", $ConfuserCli)

    $c1cRep = Join-Path $f3Out "report.json"
    $c1cOk = $false
    if (Test-Path -LiteralPath $c1cRep) {
        $c1 = Read-Json $c1cRep
        $c1cOk = ($c1.steps.module_1a.exit -eq 0) -and ($c1.steps.module_1b.exit -eq 0) -and ($c1.steps.confuser.exit -ne 0)
    }
    Check "F" "F3 precondition: 1C report shows 1A and 1B ok and the ConfuserEx2 step failed" $c1cOk
    Check "F" "F3 .NET Framework route, ConfuserEx2 step fails: exit 75" ($x.Code -eq 75) "exit $($x.Code)"

    $f3Rep = Join-Path $f3Out "bs-report.json"
    $f3RepOk = $false
    if (Test-Path -LiteralPath $f3Rep) { $f3RepOk = ((Read-Json $f3Rep).exitCode -eq 75) }
    Check "F" "F3 bs-report.json says 75" $f3RepOk
} else {
    NotRun "F" "F2 .NET Framework route, full run: exit 0 and protected output" ("ConfuserEx2 not found at " + $ConfuserCli)
    NotRun "F" "F3 .NET Framework route: ConfuserEx2 failure maps to 75" ("ConfuserEx2 not found at " + $ConfuserCli)
}

# ---------- summary ----------
Write-Output ""
Write-Output "---"
foreach ($g in @("R", "E", "F")) {
    $items = @($results | Where-Object { $_.Group -eq $g })
    $p = @($items | Where-Object { $_.Pass }).Count
    Write-Output ("group {0}: {1} of {2} PASS" -f $g, $p, $items.Count)
}
$fails = @($results | Where-Object { -not $_.Pass }).Count
if ($fails -eq 0) {
    Write-Output "SUMMARY: PASS - all checks"
    exit 0
}
Write-Output "SUMMARY: FAIL - $fails check(s)"
exit 1
