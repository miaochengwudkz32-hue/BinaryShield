# Compares a normal build (encrypted strings) with a control build (plain literals).
#
#   verify_pair.ps1 -Normal <exe> -Control <exe> [-SecretsFile <path>]
#
# Checks:
#   - both programs exit with code 0
#   - stdout of the two programs is identical
#   - every secret is FOUND in the control file (ASCII or UTF-16LE): the search can see the strings
#   - no secret is found in the normal file (ASCII or UTF-16LE)
#
# Exit codes: 0 = all checks PASS | 1 = at least one check FAIL | 2 = a file is missing

param(
    [Parameter(Mandatory = $true)][string]$Normal,
    [Parameter(Mandatory = $true)][string]$Control,
    [string]$SecretsFile = ""
)

$ErrorActionPreference = "Stop"
if (-not $SecretsFile) { $SecretsFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "secrets.txt" }
foreach ($p in @($Normal, $Control, $SecretsFile)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Host "[missing] $p" -ForegroundColor Red; exit 2 }
}

$secrets = @(Get-Content -LiteralPath $SecretsFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })

# ISO-8859-1 maps every byte to one char, so byte patterns can be found with an ordinal string search.
$latin1 = [Text.Encoding]::GetEncoding(28591)
function Get-Haystack([string]$path) {
    return $latin1.GetString([IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $path).Path))
}
function Test-InFile([string]$haystack, [string]$text) {
    $a = $latin1.GetString([Text.Encoding]::ASCII.GetBytes($text))
    $w = $latin1.GetString([Text.Encoding]::Unicode.GetBytes($text))
    return ($haystack.IndexOf($a, [StringComparison]::Ordinal) -ge 0) -or ($haystack.IndexOf($w, [StringComparison]::Ordinal) -ge 0)
}

$hayNormal = Get-Haystack $Normal
$hayControl = Get-Haystack $Control

$outNormal = (& (Resolve-Path -LiteralPath $Normal).Path | Out-String)
$codeNormal = $LASTEXITCODE
$outControl = (& (Resolve-Path -LiteralPath $Control).Path | Out-String)
$codeControl = $LASTEXITCODE
$outNormal = $outNormal -replace "`r`n", "`n"
$outControl = $outControl -replace "`r`n", "`n"

$checks = @()
$checks += [pscustomobject]@{ Name = "normal exits with code 0"; Pass = ($codeNormal -eq 0); Detail = "exit $codeNormal" }
$checks += [pscustomobject]@{ Name = "control exits with code 0"; Pass = ($codeControl -eq 0); Detail = "exit $codeControl" }
$lines = @($outControl -split "`n" | Where-Object { $_ -ne "" }).Count
$checks += [pscustomobject]@{ Name = "stdout identical (normal vs control)"; Pass = ($outNormal -ceq $outControl); Detail = "$lines output lines" }
foreach ($s in $secrets) {
    $inControl = Test-InFile $hayControl $s
    $inNormal = Test-InFile $hayNormal $s
    $checks += [pscustomobject]@{ Name = "control contains: $s"; Pass = $inControl; Detail = "" }
    $checks += [pscustomobject]@{ Name = "normal has none of: $s"; Pass = (-not $inNormal); Detail = "" }
}

$fail = 0
foreach ($c in $checks) {
    if ($c.Pass) { $tag = "PASS" } else { $tag = "FAIL"; $fail++ }
    if ($c.Detail) { "{0}  {1}  ({2})" -f $tag, $c.Name, $c.Detail } else { "{0}  {1}" -f $tag, $c.Name }
}
if ($fail -eq 0) { "SUMMARY: PASS - $($checks.Count) checks"; exit 0 }
"SUMMARY: FAIL - $fail of $($checks.Count) checks failed"
exit 1
