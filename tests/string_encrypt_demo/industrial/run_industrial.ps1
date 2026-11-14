# Builds the simulated industrial program in C++ (ADVobfuscator) and Rust (obfstr), each as a normal build
# (encrypted strings) and a control build (plain literals), then runs verify_pair.ps1 on each language.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run_industrial.ps1
#   powershell -ExecutionPolicy Bypass -File run_industrial.ps1 -Repeat 10
#
#   -Repeat N   build the C++ normal build N times and verify each one against the control build (default 1).
#
# Requirements: g++ (C++20, MinGW-w64 GCC 11+) on PATH; rustup stable-x86_64-pc-windows-gnu;
# third_party\ADVobfuscator cloned under tests\string_encrypt_demo\third_party (see ..\README.md).
#
# Exit codes: 0 = all checks PASS | 1 = a verification check FAIL | 2 = prerequisite missing | 3 = build failed

param([int]$Repeat = 1)

$ErrorActionPreference = "Stop"
$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$demo    = Split-Path -Parent $here
$advInc  = Join-Path $demo "third_party\ADVobfuscator\include"
$cppSrc  = Join-Path $here "cpp\industrial.cpp"
$rustDir = Join-Path $here "rust"
$out     = Join-Path $here "out"
$verify  = Join-Path $here "verify_pair.ps1"
$secrets = Join-Path $here "secrets.txt"
$rustToolchain = "stable-x86_64-pc-windows-gnu"

# 0. Prerequisites
$missing = @()
if (-not (Get-Command g++ -ErrorAction SilentlyContinue)) { $missing += "g++ (C++20; e.g. MinGW-w64 GCC 11+)" }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { $missing += "cargo (Rust, rustup)" }
elseif (-not ((& rustup toolchain list) -match [regex]::Escape($rustToolchain))) { $missing += "Rust toolchain $rustToolchain (rustup toolchain install $rustToolchain)" }
if (-not (Test-Path (Join-Path $advInc "advobfuscator\string.h"))) { $missing += "third_party\ADVobfuscator (git clone https://github.com/andrivet/ADVobfuscator)" }
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { Write-Host "[missing] $m" -ForegroundColor Red }
    exit 2
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1. Build C++
"=== 1. Build C++ (g++ $((& g++ -dumpfullversion 2>$null)), ADVobfuscator fixed-parameter XOR) ==="
$codes = [ordered]@{}
& g++ -std=c++20 -O2 -DPLAIN_STRINGS -I $advInc $cppSrc -o (Join-Path $out "cpp_control.exe")
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] C++ control" -ForegroundColor Red; exit 3 }
for ($i = 1; $i -le $Repeat; $i++) {
    $exe = Join-Path $out ("cpp_normal_{0:D2}.exe" -f $i)
    & g++ -std=c++20 -O2 -I $advInc $cppSrc -o $exe
    if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] C++ normal $i" -ForegroundColor Red; exit 3 }
}

# 2. Build Rust
"=== 2. Build Rust (cargo, obfstr) ==="
& cargo "+$rustToolchain" build --release --manifest-path (Join-Path $rustDir "Cargo.toml")
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] Rust normal" -ForegroundColor Red; exit 3 }
$rustBin = Join-Path $rustDir "target\release\industrial_demo_rust.exe"
Copy-Item $rustBin (Join-Path $out "rust_normal.exe") -Force
& cargo "+$rustToolchain" build --release --no-default-features --features plain --manifest-path (Join-Path $rustDir "Cargo.toml")
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] Rust control" -ForegroundColor Red; exit 3 }
Copy-Item $rustBin (Join-Path $out "rust_control.exe") -Force

# 3. Verify
"=== 3. Verify C++ (normal vs control) ==="
for ($i = 1; $i -le $Repeat; $i++) {
    $exe = Join-Path $out ("cpp_normal_{0:D2}.exe" -f $i)
    & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Normal $exe -Control (Join-Path $out "cpp_control.exe") -SecretsFile $secrets | Out-Host
    $codes["C++ normal #$i"] = $LASTEXITCODE
}
"=== 4. Verify Rust (normal vs control) ==="
& powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Normal (Join-Path $out "rust_normal.exe") -Control (Join-Path $out "rust_control.exe") -SecretsFile $secrets | Out-Host
$codes["Rust"] = $LASTEXITCODE

"=== Summary ==="
foreach ($k in $codes.Keys) { "{0,-16} exit {1}" -f $k, $codes[$k] }
if (($codes.Values | Where-Object { $_ -ne 0 }).Count -eq 0) { exit 0 } else { exit 1 }
