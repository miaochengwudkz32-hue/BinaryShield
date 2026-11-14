# Builds both demos (C++ with ADVobfuscator, Rust with obfstr), each as a normal build and as a control
# build with plain literals, then runs verify.ps1 on the executables.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File run_demo.ps1
#   powershell -ExecutionPolicy Bypass -File run_demo.ps1 -Repeat 15 -RandomParamsRepeat 15
#
#   -Repeat N               build the C++ normal build N times and verify each one (default 1).
#                           Any failing build fails the run.
#   -RandomParamsRepeat N   build the C++ "_obf" variant (parameters chosen at compile time from __TIME__)
#                           N times and count how many leave a secret in plain text. Informational only:
#                           the count is printed but does not change the exit code.
#
# Requirements:
#   - C++: g++ with C++20 support (MinGW-w64 GCC 11 or newer), on PATH
#   - Rust: rustup with the stable-x86_64-pc-windows-gnu toolchain (cargo, rustc 1.85+ because obfstr uses edition 2024)
#   - third_party\ADVobfuscator and third_party\obfstr: clone them from GitHub (see README.md)
#
# Exit codes: 0 = all checks PASS | 1 = a verification check FAIL | 2 = prerequisite missing | 3 = build failed

param(
    [int]$Repeat = 1,
    [int]$RandomParamsRepeat = 0
)

$ErrorActionPreference = "Stop"
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$third  = Join-Path $here "third_party"
$advInc = Join-Path $third "ADVobfuscator\include"
$out    = Join-Path $here "out"
$verify = Join-Path $here "verify.ps1"
$cppSrc = Join-Path $here "cpp\main.cpp"
$rustManifest = Join-Path $here "rust\Cargo.toml"

# 0. Prerequisites
$missing = @()
if (-not (Get-Command g++ -ErrorAction SilentlyContinue)) { $missing += "g++ (C++20; e.g. MinGW-w64 GCC 11+)" }
# Rust is built with the GNU toolchain: the default MSVC toolchain needs link.exe (Visual Studio C++ tools),
# which this machine does not have. The GNU toolchain links with the MinGW GCC found above.
$rustToolchain = "stable-x86_64-pc-windows-gnu"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { $missing += "cargo (Rust stable 1.85+)" }
elseif (-not ((& rustup toolchain list) -match [regex]::Escape($rustToolchain))) { $missing += "Rust toolchain $rustToolchain (rustup toolchain install $rustToolchain)" }
if (-not (Test-Path (Join-Path $advInc "advobfuscator\string.h"))) { $missing += "third_party\ADVobfuscator (git clone https://github.com/andrivet/ADVobfuscator)" }
if ($missing.Count -gt 0) {
    foreach ($m in $missing) { Write-Host "[missing] $m" -ForegroundColor Red }
    exit 2
}
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Runs verify.ps1 and returns only its exit code (its output goes to the host, not to the return value).
function Invoke-Verify([string]$exe, [switch]$Control) {
    if ($Control) { & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Exe $exe -Control | Out-Host }
    else { & powershell -NoProfile -ExecutionPolicy Bypass -File $verify -Exe $exe | Out-Host }
    return $LASTEXITCODE
}

# 1. Build C++ normal (Repeat times) and control
"=== 1. Build C++ (g++ $((& g++ -dumpfullversion 2>$null)), ADVobfuscator) ==="
$codes = [ordered]@{}
for ($i = 1; $i -le $Repeat; $i++) {
    $exe = Join-Path $out ("cpp_obf_{0:D2}.exe" -f $i)
    & g++ -std=c++20 -O2 -I $advInc $cppSrc -o $exe
    if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] C++ normal $i" -ForegroundColor Red; exit 3 }
    Start-Sleep -Milliseconds 1100   # __TIME__ has one-second resolution; keep builds in different seconds
}
& g++ -std=c++20 -O2 -DPLAIN_STRINGS -I $advInc $cppSrc -o (Join-Path $out "cpp_plain.exe")
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] C++ control" -ForegroundColor Red; exit 3 }

# 2. Build Rust (normal and control)
"=== 2. Build Rust (cargo, obfstr) ==="
& cargo "+$rustToolchain" build --release --manifest-path $rustManifest
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] Rust normal" -ForegroundColor Red; exit 3 }
$rustBin = Join-Path $here "rust\target\release\string_encrypt_demo_rust.exe"
Copy-Item $rustBin (Join-Path $out "rust_obf.exe") -Force
& cargo "+$rustToolchain" build --release --no-default-features --features plain --manifest-path $rustManifest
if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] Rust control" -ForegroundColor Red; exit 3 }
Copy-Item $rustBin (Join-Path $out "rust_plain.exe") -Force

# 3. Verify
"=== 3. Verify C++ normal builds (secrets must be absent from the file) ==="
for ($i = 1; $i -le $Repeat; $i++) {
    $exe = Join-Path $out ("cpp_obf_{0:D2}.exe" -f $i)
    $codes["C++ normal #$i"] = Invoke-Verify $exe
}
"=== 4. Verify C++ control (secrets must be present) ==="
$codes["C++ control"] = Invoke-Verify (Join-Path $out "cpp_plain.exe") -Control
"=== 5. Verify Rust normal (secrets must be absent from the file) ==="
$codes["Rust normal"] = Invoke-Verify (Join-Path $out "rust_obf.exe")
"=== 6. Verify Rust control (secrets must be present) ==="
$codes["Rust control"] = Invoke-Verify (Join-Path $out "rust_plain.exe") -Control

# 7. Optional: how often the library's default "_obf" literal leaves a secret in plain text
$randomLeaks = $null
if ($RandomParamsRepeat -gt 0) {
    "=== 7. Measure the default _obf variant ($RandomParamsRepeat builds; informational) ==="
    $randomLeaks = 0
    for ($i = 1; $i -le $RandomParamsRepeat; $i++) {
        $exe = Join-Path $out ("cpp_random_{0:D2}.exe" -f $i)
        & g++ -std=c++20 -O2 -DRANDOM_PARAMS -I $advInc $cppSrc -o $exe
        if ($LASTEXITCODE -ne 0) { Write-Host "[build failed] C++ random-params $i" -ForegroundColor Red; exit 3 }
        $null = Invoke-Verify $exe
        if ($LASTEXITCODE -ne 0) { $randomLeaks++ }
        Start-Sleep -Milliseconds 1100
    }
    "_obf variant: $randomLeaks of $RandomParamsRepeat builds left at least one secret in plain text (verify exit != 0)"
}

"=== Summary ==="
foreach ($k in $codes.Keys) { "{0,-18} exit {1}" -f $k, $codes[$k] }
if ($null -ne $randomLeaks) { "{0,-18} {1} of {2} builds leaked (informational)" -f "_obf variant", $randomLeaks, $RandomParamsRepeat }
if (($codes.Values | Where-Object { $_ -ne 0 }).Count -eq 0) { exit 0 } else { exit 1 }
