# Benchmark for Module 2A (Obfuscar 3.0 config generator). Written before the feature code (STEP 2).
#
#   Group P  Obfuscar 3.0.0-beta.22 against the SkipNamespace rules we plan to generate.
#            Uses hand-written configs, so it runs without module_2a.exe. Compares the regex form
#            (decision A, confirmed) with the four-wildcard fallback.
#   Group A  module_2a.exe on synthetic Module 1A manifests: exit codes, XML content, edge cases.
#   Group B  end to end: module_2a.exe -> obf.xml -> Obfuscar -> protected sample runs with the same output.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File test_module_2a.ps1 -ObfuscarDll <path>\tools\net8.0\any\GlobalTools.dll
#   (or set the environment variable BS_OBFUSCAR_DLL)
#
# Exit codes: 0 = all PASS | 1 = at least one FAIL | 2 = prerequisite missing (dotnet or Obfuscar)
#             3 = src\dotnet\module_2a\module_2a.exe not built yet (group P still ran; its results are printed)

param([string]$ObfuscarDll = $env:BS_OBFUSCAR_DLL)

$ErrorActionPreference = "Stop"
$here       = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo       = (Resolve-Path (Join-Path $here "..\..")).Path
$fixtureSrc = Join-Path $here "module_2a_fixture\Sample"
$moduleExe  = Join-Path $repo "src\dotnet\module_2a\module_2a.exe"
$rxPattern  = '^(Avalonia|CompiledAvaloniaXaml)(\..*)?$'

# ---------- prerequisites ----------
if (-not $ObfuscarDll -or -not (Test-Path -LiteralPath $ObfuscarDll)) {
    Write-Host "[missing] Obfuscar GlobalTools.dll: pass -ObfuscarDll or set BS_OBFUSCAR_DLL" -ForegroundColor Red
    exit 2
}
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Host "[missing] dotnet SDK (8.0 or newer)" -ForegroundColor Red
    exit 2
}

$work = Join-Path $env:TEMP ("bs_2a_" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null
"work folder: $work"

$results = New-Object System.Collections.ArrayList
function Check([string]$group, [string]$name, [bool]$ok, [string]$detail = "") {
    [void]$results.Add([pscustomobject]@{ Group = $group; Name = $name; Pass = $ok; Detail = $detail })
    if ($ok) { $tag = "PASS" } else { $tag = "FAIL" }
    "{0}  {1}  {2}  {3}" -f $tag, $group, $name, $detail
}

# ---------- build the sample (.NET 8) ----------
$sampleDir = Join-Path $work "sample"
Copy-Item $fixtureSrc $sampleDir -Recurse
$sampleOut = Join-Path $work "sample_out"
$ErrorActionPreference = "Continue"
$buildLog = (& dotnet build (Join-Path $sampleDir "Sample.csproj") -c Release -o $sampleOut --nologo 2>&1 | Out-String)
$buildCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
$sampleDll = Join-Path $sampleOut "Sample.dll"
if ($buildCode -ne 0 -or -not (Test-Path -LiteralPath $sampleDll)) {
    Write-Host "[fixture build failed]" -ForegroundColor Red
    $buildLog
    exit 2
}

# ---------- expected behaviour of the probe program ----------
$keepTypes      = @("SkipProbeFoo", "SkipProbeRoot", "SkipProbeQux")
$renameTypes    = @("RenameProbeBar")
$keepLiterals   = @("PROBE-SKIP-CONTROLS-7731", "PROBE-SKIP-ROOT-7732", "PROBE-SKIP-XAML-7733")
$renameLiterals = @("PROBE-RENAME-APP-7734")
$expectedOutput = (@("PROBE-SKIP-CONTROLS-7731", "PROBE-SKIP-ROOT-7732", "PROBE-SKIP-XAML-7733", "PROBE-RENAME-APP-7734", "probe done") -join "`n")

# ISO-8859-1 maps each byte to one char, so byte patterns can be found with an ordinal string search.
$latin1 = [Text.Encoding]::GetEncoding(28591)
function Test-Contains([string]$haystack, [string]$text, [bool]$utf16) {
    if ($utf16) { $pattern = $latin1.GetString([Text.Encoding]::Unicode.GetBytes($text)) }
    else        { $pattern = $latin1.GetString([Text.Encoding]::ASCII.GetBytes($text)) }
    return ($haystack.IndexOf($pattern, [StringComparison]::Ordinal) -ge 0)
}
function Get-Haystack([string]$path) {
    return $latin1.GetString([IO.File]::ReadAllBytes($path))
}

# Control: the unprotected sample must contain every marker, otherwise the search proves nothing.
$plainHay = Get-Haystack $sampleDll
$controlOk = $true
foreach ($n in ($keepTypes + $renameTypes)) { if (-not (Test-Contains $plainHay $n $false)) { $controlOk = $false } }
foreach ($l in ($keepLiterals + $renameLiterals)) { if (-not (Test-Contains $plainHay $l $true)) { $controlOk = $false } }
Check "P" "P0 control: unprotected sample contains all probe names and literals" $controlOk

# Plain run output (baseline for the output comparison).
$ErrorActionPreference = "Continue"
$plainOut = ((& dotnet $sampleDll 2>&1) | Out-String).Trim() -replace "`r`n", "`n"
$ErrorActionPreference = "Stop"
Check "P" "P0b control: unprotected sample prints the expected output" ($plainOut -ceq $expectedOutput)

# ---------- helpers for Obfuscar ----------
function Write-Config([string]$path, [string]$inDir, [string]$outDir, [string]$dll, [string[]]$skipXml) {
    $mods = ($skipXml | ForEach-Object { "    " + $_ }) -join "`r`n"
    $text = @"
<?xml version="1.0" encoding="utf-8"?>
<Obfuscator>
  <Var name="InPath" value="$inDir" />
  <Var name="OutPath" value="$outDir" />
  <Var name="KeepPublicApi" value="true" />
  <Var name="HidePrivateApi" value="true" />
  <Module file="$dll">
$mods
  </Module>
</Obfuscator>
"@
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Invoke-Obfuscar([string]$cfg, [string]$logPath) {
    $ErrorActionPreference = "Continue"
    $out = (& dotnet $ObfuscarDll $cfg 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    [IO.File]::WriteAllText($logPath, $out, (New-Object Text.UTF8Encoding($false)))
    return $code
}

function Test-Protected([string]$group, [string]$tag, [string]$protDll) {
    if (-not (Test-Path -LiteralPath $protDll)) {
        foreach ($n in @("skipped types keep their names", "renamed type loses its name", "skipped literals kept", "renamed literal hidden")) {
            Check $group "$tag $n" $false "protected DLL missing: $protDll"
        }
        return
    }
    $hay = Get-Haystack $protDll
    $keepOk = $true; foreach ($n in $keepTypes) { if (-not (Test-Contains $hay $n $false)) { $keepOk = $false } }
    Check $group "$tag skipped types keep their names" $keepOk
    $renOk = $true; foreach ($n in $renameTypes) { if (Test-Contains $hay $n $false) { $renOk = $false } }
    Check $group "$tag renamed type loses its name" $renOk
    $litKeepOk = $true; foreach ($l in $keepLiterals) { if (-not (Test-Contains $hay $l $true)) { $litKeepOk = $false } }
    Check $group "$tag skipped literals kept" $litKeepOk
    $litRenOk = $true; foreach ($l in $renameLiterals) { if (Test-Contains $hay $l $true) { $litRenOk = $false } }
    Check $group "$tag renamed literal hidden" $litRenOk
}

function Test-ProtectedRuns([string]$group, [string]$tag, [string]$protDir) {
    $protDll = Join-Path $protDir "Sample.dll"
    if (-not (Test-Path -LiteralPath $protDll)) { Check $group "$tag protected program prints the expected output" $false "protected DLL missing"; return }
    # Obfuscar writes only the DLL; copy the runtime config files next to it so the program can start.
    Copy-Item (Join-Path $sampleOut "Sample.runtimeconfig.json") $protDir -Force
    Copy-Item (Join-Path $sampleOut "Sample.deps.json") $protDir -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = "Continue"
    $out = ((& dotnet $protDll 2>&1) | Out-String).Trim() -replace "`r`n", "`n"
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    Check $group "$tag protected program prints the expected output (exit $code)" (($code -eq 0) -and ($out -ceq $expectedOutput)) $(if ($out -ne $expectedOutput) { "got: " + ($out -replace "`n", " | ") } else { "" })
}

$wildSkip = @(
    '<SkipNamespace name="Avalonia" />',
    '<SkipNamespace name="Avalonia.*" />',
    '<SkipNamespace name="CompiledAvaloniaXaml" />',
    '<SkipNamespace name="CompiledAvaloniaXaml.*" />'
)
$rxSkip = @('<SkipNamespace rx="' + $rxPattern + '" />')

# ============================================================
# Group P: Obfuscar against the planned rules (no module needed)
# ============================================================
$pRx = Join-Path $work "p_rx"
$pWild = Join-Path $work "p_wild"
foreach ($d in @($pRx, $pWild)) { New-Item -ItemType Directory -Force -Path (Join-Path $d "protected") | Out-Null }

Write-Config (Join-Path $pRx "obf.xml") $sampleOut (Join-Path $pRx "protected") $sampleDll $rxSkip
$codeRx = Invoke-Obfuscar (Join-Path $pRx "obf.xml") (Join-Path $pRx "obf.log")
Check "P" "P1 rx form: Obfuscar accepts the config (exit 0)" ($codeRx -eq 0) "exit $codeRx"
Test-Protected "P" "P2 rx form:" (Join-Path $pRx "protected\Sample.dll")
Test-ProtectedRuns "P" "P3 rx form:" (Join-Path $pRx "protected")

Write-Config (Join-Path $pWild "obf.xml") $sampleOut (Join-Path $pWild "protected") $sampleDll $wildSkip
$codeWild = Invoke-Obfuscar (Join-Path $pWild "obf.xml") (Join-Path $pWild "obf.log")
Check "P" "P4 wildcard fallback: Obfuscar accepts the config (exit 0)" ($codeWild -eq 0) "exit $codeWild"
Test-Protected "P" "P5 wildcard fallback:" (Join-Path $pWild "protected\Sample.dll")
Test-ProtectedRuns "P" "P6 wildcard fallback:" (Join-Path $pWild "protected")

# Negative control: the same regex WITHOUT the anchors ^ and $ must over-match. This shows the anchors matter:
# the unanchored form also skips AvaloniaApp47, so RenameProbeBar keeps its name.
$pNeg = Join-Path $work "p_unanchored"
New-Item -ItemType Directory -Force -Path (Join-Path $pNeg "protected") | Out-Null
Write-Config (Join-Path $pNeg "obf.xml") $sampleOut (Join-Path $pNeg "protected") $sampleDll @('<SkipNamespace rx="(Avalonia|CompiledAvaloniaXaml)(\..*)?" />')
$codeNeg = Invoke-Obfuscar (Join-Path $pNeg "obf.xml") (Join-Path $pNeg "obf.log")
$negDll = Join-Path $pNeg "protected\Sample.dll"
$negOver = $false
if (($codeNeg -eq 0) -and (Test-Path -LiteralPath $negDll)) {
    $negOver = Test-Contains (Get-Haystack $negDll) "RenameProbeBar" $false
}
Check "P" "P7 control: unanchored regex over-matches (AvaloniaApp47 is skipped), so the anchors are needed" $negOver "exit $codeNeg"

# ============================================================
# Module-dependent groups (A and B). Run only when module_2a.exe exists.
# ============================================================
$moduleBuilt = Test-Path -LiteralPath $moduleExe

function New-Manifest {
    param(
        [string]$inputPath,
        [object[]]$types = @(),
        [bool]$isManaged = $true,
        [string]$tfm = ".NETCoreApp,Version=v8.0",
        [string]$schema = "0.1"
    )
    $list = @()
    foreach ($t in $types) {
        $list += @{ namespace = $t.ns; name = $t.name; fullName = ($t.ns + "." + $t.name); isNested = $false; skip = [bool]$t.skip; methods = @() }
    }
    $input = @{ path = $inputPath; fileName = (Split-Path -Leaf $inputPath); sha256 = ("0" * 64); isManaged = $isManaged }
    if ($null -ne $tfm) { $input["targetFramework"] = $tfm }
    $skipCount = @($list | Where-Object { $_.skip }).Count
    return @{
        tool = "BinaryShield"; module = "1a"; schemaVersion = $schema
        input = $input
        assemblies = @( @{ fullName = "Sample, Version=1.0.0.0"; modules = @( @{ name = "Sample.dll"; types = $list } ) } )
        summary = @{ typeCount = $list.Count; methodCount = 0; stringLiteralCount = 0; skippedTypeCount = $skipCount }
    }
}

function Write-Text([string]$path, [string]$text) {
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))
}

function Write-Manifest([string]$path, $manifest) {
    Write-Text $path ($manifest | ConvertTo-Json -Depth 12)
}

function Invoke-Module([string]$manifest, [string]$cfg) {
    $ErrorActionPreference = "Continue"
    $out = (& $moduleExe $manifest $cfg 2>&1 | Out-String)
    $code = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    return [pscustomobject]@{ Code = $code; Out = $out }
}

function Test-Xml([string]$path) {
    try { $doc = New-Object System.Xml.XmlDocument; $doc.Load($path); return $true } catch { return $false }
}
function Get-Doc([string]$path) {
    $doc = New-Object System.Xml.XmlDocument
    $doc.Load($path)
    return $doc
}
function Get-VarValue($doc, [string]$name) {
    foreach ($v in @($doc.SelectNodes("//Var"))) {
        if ($v.GetAttribute("name") -ceq $name) { return $v.GetAttribute("value") }
    }
    return $null
}

if (-not $moduleBuilt) {
    "[not built] src\dotnet\module_2a\module_2a.exe does not exist: groups A and B were not run."
} else {
    # ---------- Group A: module_2a.exe on synthetic manifests ----------
    $aRoot = Join-Path $work "A"
    New-Item -ItemType Directory -Force -Path $aRoot | Out-Null
    $dummyIn = Join-Path $aRoot "in\Sample.dll"
    Write-Text $dummyIn ""
    $typesStd = @(
        @{ ns = "Avalonia.Controls"; name = "Foo"; skip = $true },
        @{ ns = "MyApp"; name = "Program"; skip = $false }
    )

    $d = Join-Path $aRoot "a01"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    $r = Invoke-Module $man $cfg
    Check "A" "A01 normal manifest: exit 0 and well-formed XML" (($r.Code -eq 0) -and (Test-Xml $cfg)) "exit $($r.Code)"

    if (Test-Path -LiteralPath $cfg) {
        $doc = Get-Doc $cfg
        $inPath = Get-VarValue $doc "InPath"; $outPath = Get-VarValue $doc "OutPath"
        $cfgDir = Split-Path -Parent $cfg
        $okPaths = ([IO.Path]::IsPathRooted($inPath)) -and ([IO.Path]::IsPathRooted($outPath)) -and ($outPath -eq (Join-Path $cfgDir "protected")) -and ($inPath -eq (Split-Path -Parent $dummyIn))
        Check "A" "A02 InPath/OutPath absolute; OutPath = <config dir>\protected" $okPaths "InPath=$inPath OutPath=$outPath"

        $mod = $doc.SelectSingleNode("//Module")
        Check "A" "A03 Module file is the absolute input path" (($null -ne $mod) -and ($mod.GetAttribute("file") -ceq $dummyIn))

        $sk = @($doc.SelectNodes("//SkipNamespace"))
        $okRx = ($sk.Count -eq 1) -and ($sk[0].GetAttribute("rx") -ceq $rxPattern) -and (-not $sk[0].HasAttribute("name"))
        Check "A" "A04 exactly one SkipNamespace, rx = planned regex, no name attribute" $okRx "count=$($sk.Count)"

        Check "A" "A05 KeepPublicApi and HidePrivateApi present and true" ((Get-VarValue $doc "KeepPublicApi") -eq "true" -and (Get-VarValue $doc "HidePrivateApi") -eq "true")

        $comments = (@($doc.SelectNodes("//comment()")) | ForEach-Object { $_.Value }) -join " "
        Check "A" "A06 comment lists the skipped namespace (Avalonia.Controls)" ($comments -match 'Avalonia\.Controls')
    } else {
        foreach ($n in @("A02", "A03", "A04", "A05", "A06")) { Check "A" "$n skipped: A01 produced no config" $false }
    }

    $d = Join-Path $aRoot "a07"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types @(@{ ns = "MyApp"; name = "Program"; skip = $false }))
    $r = Invoke-Module $man $cfg
    Check "A" "A07 no skipped types: exit 0, prints WARNING:, still well-formed" (($r.Code -eq 0) -and ($r.Out -match 'WARNING:') -and (Test-Xml $cfg)) "exit $($r.Code)"

    $d = Join-Path $aRoot "a08"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd -isManaged $false)
    $r = Invoke-Module $man $cfg
    Check "A" "A08 isManaged false: exit 65, no config written" (($r.Code -eq 65) -and (-not (Test-Path -LiteralPath $cfg))) "exit $($r.Code)"

    $d = Join-Path $aRoot "a09"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd -tfm ".NETFramework,Version=v4.7")
    $r = Invoke-Module $man $cfg
    Check "A" "A09 .NET Framework 4.7 target: exit 65, no config written" (($r.Code -eq 65) -and (-not (Test-Path -LiteralPath $cfg))) "exit $($r.Code)"

    $d = Join-Path $aRoot "a10"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd -tfm $null)
    $r = Invoke-Module $man $cfg
    Check "A" "A10 targetFramework missing: exit 65" ($r.Code -eq 65) "exit $($r.Code)"

    $d = Join-Path $aRoot "a11"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath "Sample.dll" -types $typesStd)
    $r = Invoke-Module $man $cfg
    Check "A" "A11 input.path relative: exit 65" ($r.Code -eq 65) "exit $($r.Code)"

    $d = Join-Path $aRoot "a12"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath (Join-Path $aRoot "missing\Nope.dll") -types $typesStd)
    $r = Invoke-Module $man $cfg
    Check "A" "A12 input file missing: exit 66" ($r.Code -eq 66) "exit $($r.Code)"

    $d = Join-Path $aRoot "a13"; $man = Join-Path $d "does_not_exist.json"; $cfg = Join-Path $d "obf.xml"
    $r = Invoke-Module $man $cfg
    Check "A" "A13 manifest file missing: exit 66" ($r.Code -eq 66) "exit $($r.Code)"

    $d = Join-Path $aRoot "a14"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Text $man "{ this is not json"
    $r = Invoke-Module $man $cfg
    Check "A" "A14 manifest is not valid JSON: exit 65" ($r.Code -eq 65) "exit $($r.Code)"

    $d = Join-Path $aRoot "a15"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd -schema "0.2")
    $r = Invoke-Module $man $cfg
    Check "A" "A15 schemaVersion other than 0.1: exit 65" ($r.Code -eq 65) "exit $($r.Code)"

    $d = Join-Path $aRoot "a16"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types @(@{ ns = "Foo.Bar"; name = "Baz"; skip = $true }))
    $r = Invoke-Module $man $cfg
    Check "A" "A16 skip:true namespace not covered by the rules: exit 65, no config (decision D)" (($r.Code -eq 65) -and (-not (Test-Path -LiteralPath $cfg))) "exit $($r.Code)"

    $d = Join-Path $aRoot "a17"
    $odd = Join-Path $d "dir with space & 测试\Sam ple & 名.dll"
    Write-Text $odd ""
    $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $odd -types $typesStd)
    $r = Invoke-Module $man $cfg
    $okOdd = ($r.Code -eq 0) -and (Test-Xml $cfg)
    if ($okOdd) {
        $doc = Get-Doc $cfg
        $okOdd = ($doc.SelectSingleNode("//Module").GetAttribute("file") -ceq $odd) -and ((Get-VarValue $doc "InPath") -ceq (Split-Path -Parent $odd))
    }
    Check "A" "A17 path with spaces, '&' and Chinese: well-formed and restored exactly" $okOdd "exit $($r.Code)"

    $d = Join-Path $aRoot "a18"; $man = Join-Path $d "manifest.json"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    $cfg1 = Join-Path $d "run1.xml"; $cfg2 = Join-Path $d "run2.xml"
    $r1 = Invoke-Module $man $cfg1; $r2 = Invoke-Module $man $cfg2
    $same = $false
    if ((Test-Path -LiteralPath $cfg1) -and (Test-Path -LiteralPath $cfg2)) {
        $same = ([IO.File]::ReadAllBytes($cfg1) -join ",") -ceq ([IO.File]::ReadAllBytes($cfg2) -join ",")
    }
    Check "A" "A18 same manifest twice: byte-identical output" ($same -and ($r1.Code -eq 0) -and ($r2.Code -eq 0))

    $d = Join-Path $aRoot "a19"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    Write-Text $cfg "old content"
    $r = Invoke-Module $man $cfg
    Check "A" "A19 existing config is replaced by the new one" (($r.Code -eq 0) -and (Test-Xml $cfg) -and (-not ((Get-Content -LiteralPath $cfg -Raw) -match "old content"))) "exit $($r.Code)"

    $d = Join-Path $aRoot "a20"; $man = Join-Path $d "manifest.json"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    Push-Location $d
    try {
        $r = Invoke-Module $man "rel.xml"
        $okRel = ($r.Code -eq 0) -and (Test-Path -LiteralPath (Join-Path $d "rel.xml"))
        if ($okRel) {
            $doc = Get-Doc (Join-Path $d "rel.xml")
            $okRel = ([IO.Path]::IsPathRooted((Get-VarValue $doc "OutPath"))) -and ((Get-VarValue $doc "OutPath") -ceq (Join-Path $d "protected"))
        }
    } finally { Pop-Location }
    Check "A" "A20 relative config path: OutPath written as absolute (decision I)" $okRel "exit $($r.Code)"

    $d = Join-Path $aRoot "a21"; $man = Join-Path $d "manifest.json"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    $before = [IO.File]::ReadAllBytes($man) -join ","
    $r = Invoke-Module $man $man
    $after = [IO.File]::ReadAllBytes($man) -join ","
    Check "A" "A21 config path equals manifest path: exit 64, manifest unchanged" (($r.Code -eq 64) -and ($before -ceq $after)) "exit $($r.Code)"

    $d = Join-Path $aRoot "a22"; $man = Join-Path $d "manifest.json"
    Write-Manifest $man (New-Manifest -inputPath $dummyIn -types $typesStd)
    $cfg = Join-Path $d "no_such_dir\obf.xml"
    $r = Invoke-Module $man $cfg
    Check "A" "A22 config directory missing: exit 73" ($r.Code -eq 73) "exit $($r.Code)"

    # One argument only (the manifest). Passing two empty strings would be the correct count, so it would not test this.
    $ErrorActionPreference = "Continue"
    $out23 = (& $moduleExe $man 2>&1 | Out-String)
    $code23 = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    Check "A" "A23 too few arguments (one argument): exit 64" ($code23 -eq 64) "exit $code23"

    # Added after the self-review of the code: a rooted path without a drive is not absolute.
    $d = Join-Path $aRoot "a24"; $man = Join-Path $d "manifest.json"; $cfg = Join-Path $d "obf.xml"
    Write-Manifest $man (New-Manifest -inputPath "\Sample\Sample.dll" -types $typesStd)
    $r = Invoke-Module $man $cfg
    Check "A" "A24 input.path starts with a single slash (no drive): exit 65" (($r.Code -eq 65) -and (-not (Test-Path -LiteralPath $cfg))) "exit $($r.Code)"

    # Added after the self-review of the code: a config path with no directory part (drive root) cannot be written.
    $man = Join-Path $aRoot "a24\manifest.json"
    $r = Invoke-Module $man "C:\"
    Check "A" "A25 config path is a drive root (no directory part): exit 73" ($r.Code -eq 73) "exit $($r.Code)"

    # Added after the DeepSeek cross-review: the config path must not be the input binary itself.
    $d = Join-Path $aRoot "a26"; $man = Join-Path $d "manifest.json"
    $in26 = Join-Path $d "Sample.dll"
    Write-Text $in26 "ORIGINAL-INPUT"
    Write-Manifest $man (New-Manifest -inputPath $in26 -types $typesStd)
    $before26 = [IO.File]::ReadAllBytes($in26) -join ","
    $r = Invoke-Module $man $in26
    $after26 = [IO.File]::ReadAllBytes($in26) -join ","
    Check "A" "A26 config path equals input file: exit 64, input unchanged" (($r.Code -eq 64) -and ($before26 -ceq $after26)) "exit $($r.Code)"

    # ---------- Group B: end to end with the sample ----------
    $bRoot = Join-Path $work "B"
    New-Item -ItemType Directory -Force -Path $bRoot | Out-Null
    $man = Join-Path $bRoot "manifest.json"; $cfg = Join-Path $bRoot "obf.xml"
    $typesB = @(
        @{ ns = "Avalonia.Controls"; name = "SkipProbeFoo"; skip = $true },
        @{ ns = "Avalonia"; name = "SkipProbeRoot"; skip = $true },
        @{ ns = "CompiledAvaloniaXaml.Sub"; name = "SkipProbeQux"; skip = $false },
        @{ ns = "AvaloniaApp47"; name = "RenameProbeBar"; skip = $false },
        @{ ns = "MyApp"; name = "Program"; skip = $false }
    )
    Write-Manifest $man (New-Manifest -inputPath $sampleDll -types $typesB)
    $r = Invoke-Module $man $cfg
    Check "B" "B1 module: exit 0 for the sample manifest" ($r.Code -eq 0) "exit $($r.Code)"
    $bProt = Join-Path $bRoot "protected"
    if ($r.Code -eq 0) {
        $codeB = Invoke-Obfuscar $cfg (Join-Path $bRoot "obf.log")
        Check "B" "B2 Obfuscar accepts the generated config (exit 0)" ($codeB -eq 0) "exit $codeB"
        Check "B" "B3 Obfuscar creates the OutPath when it does not exist (decision E)" (Test-Path -LiteralPath $bProt) ""
        Test-Protected "B" "B4 generated config:" (Join-Path $bProt "Sample.dll")
        Test-ProtectedRuns "B" "B5 generated config:" $bProt
    } else {
        foreach ($n in @("B2", "B3", "B4", "B5")) { Check "B" "$n skipped: B1 failed" $false }
    }
}

# ---------- summary ----------
$fails = @($results | Where-Object { -not $_.Pass }).Count
"---"
foreach ($g in @("P", "A", "B")) {
    $rows = @($results | Where-Object { $_.Group -eq $g })
    if ($rows.Count -gt 0) {
        $p = @($rows | Where-Object { $_.Pass }).Count
        "group ${g}: $p of $($rows.Count) PASS"
    }
}
if ($fails -gt 0) { "SUMMARY: FAIL - $fails check(s) failed"; exit 1 }
if (-not $moduleBuilt) { "SUMMARY: group P PASS; module_2a.exe not built yet (exit 3)"; exit 3 }
"SUMMARY: PASS - all checks"
exit 0
