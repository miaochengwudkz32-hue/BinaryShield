# Checks a demo executable for plaintext secrets, and checks that it prints them.
#
#   verify.ps1 -Exe <path>             protected build: each secret must be ABSENT from the file
#                                      (as ASCII and as UTF-16LE), and the program must PRINT it.
#   verify.ps1 -Exe <path> -Control    control build (plain literals): each secret must be PRESENT
#                                      in the file. This proves the search can see strings at all.
#
# Exit codes: 0 = all checks PASS | 1 = at least one check FAIL | 2 = executable missing

param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [switch]$Control,
    [string]$SecretsFile = ""
)

$ErrorActionPreference = "Stop"
# $PSScriptRoot is empty inside a param default in Windows PowerShell 5.1, so resolve the default here.
if (-not $SecretsFile) { $SecretsFile = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "secrets.txt" }
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "[missing] $Exe" -ForegroundColor Red; exit 2 }
$exePath = (Resolve-Path -LiteralPath $Exe).Path

$secrets = @(Get-Content -LiteralPath $SecretsFile -Encoding UTF8 | Where-Object { $_.Trim() -ne "" })
$bytes = [IO.File]::ReadAllBytes($exePath)

# ISO-8859-1 maps every byte to exactly one char, so byte patterns can be searched with an ordinal string search.
$latin1 = [Text.Encoding]::GetEncoding(28591)
$haystack = $latin1.GetString($bytes)

# What the program prints (the secrets must be printed by both builds).
$output = (& $exePath | Out-String)
$exitCode = $LASTEXITCODE

$results = @()
$mode = "protected"
if ($Control) { $mode = "control" }
foreach ($s in $secrets) {
    $ascii = $latin1.GetString([Text.Encoding]::ASCII.GetBytes($s))
    $wide  = $latin1.GetString([Text.Encoding]::Unicode.GetBytes($s))
    $inFile = ($haystack.IndexOf($ascii, [StringComparison]::Ordinal) -ge 0) -or ($haystack.IndexOf($wide, [StringComparison]::Ordinal) -ge 0)
    $printed = $output.Contains($s)

    if ($Control) { $fileOk = $inFile } else { $fileOk = -not $inFile }
    $ok = $fileOk -and $printed
    if ($Control) { $fileDetail = "in file: $inFile (control: must be present)" } else { $fileDetail = "in file: $inFile (must be absent)" }
    $results += [pscustomobject]@{ Name = $s; Pass = $ok; Detail = "$fileDetail; printed: $printed" }
}

$checks = @()
$checks += [pscustomobject]@{ Name = "program exit code is 0"; Pass = ($exitCode -eq 0); Detail = "exit $exitCode" }
$checks += $results

$fail = 0
foreach ($c in $checks) {
    if ($c.Pass) { $tag = "PASS" } else { $tag = "FAIL"; $fail++ }
    "{0}  {1}  [{2}] {3}" -f $tag, $c.Name, $mode, $c.Detail
}
if ($fail -eq 0) { "SUMMARY: PASS ($mode) - $($checks.Count) checks"; exit 0 }
"SUMMARY: FAIL ($mode) - $fail of $($checks.Count) checks failed"
exit 1
