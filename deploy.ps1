# deploy.ps1 - 编译 BinaryShield 各模块，组装扁平的部署目录（bs.exe 与它调用的子模块放在同一目录）。
#
# 用法:
#   powershell -ExecutionPolicy Bypass -File deploy.ps1
#   powershell -ExecutionPolicy Bypass -File deploy.ps1 -ObfuscarNupkg <路径>\obfuscar.globaltool.3.0.0-beta.22.nupkg
#
# 输出（默认 <仓库>\dist）:
#   bs.exe, module_1a.exe, module_1b.exe, module_1c.exe, module_2a.exe, dnlib.dll   扁平放置
#   ConfuserEx-1.6.0\     ConfuserEx2 CLI（先核对 Confuser.CLI.exe / Confuser.Core.dll 的 SHA256）
#   obfuscar\             Obfuscar 运行文件（仅在给出 -ObfuscarNupkg 时；先核对 nupkg 的 SHA256）
#   deploy-manifest.txt   dist 中每个文件的 SHA256
#
# 本脚本不联网、不下载。ConfuserEx2 必须已经在 -ConfuserDir 中（默认 <仓库>\tools\ConfuserEx-1.6.0）。
# 编译输出写回 src\dotnet\<模块>\，与 USAGE.md 的构建命令一致。

param(
    [string]$OutDir = "",
    [string]$ConfuserDir = "",
    [string]$ObfuscarNupkg = ""
)

$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$dotnetSrc = Join-Path $repo "src\dotnet"
if (-not $OutDir) { $OutDir = Join-Path $repo "dist" }
if (-not $ConfuserDir) { $ConfuserDir = Join-Path $repo "tools\ConfuserEx-1.6.0" }
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$dnlib = Join-Path $dotnetSrc "module_1a\dnlib.dll"

# 与 dependencies.md 及 module_1c 中的常量一致
$expectedCli = "0790671F930BD1375FA06ECE29A776404CEE44695E083CACE46C905433644130"
$expectedCore = "12193041A68CBBABB4A9EA7A7C14621407739F613516FEA5CC19D1BD1257C8ED"
$expectedObfNupkg = "36EA43A84D83642ADEE9ECEE3D370F36687602B24FEDCF98FCDB572A5A873709"

function Get-Sha([string]$path) {
    return (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
}

function Build-Tool([string]$folder, [string]$outName, [string[]]$extra) {
    $src = Join-Path (Join-Path $dotnetSrc $folder) "Program.cs"
    $out = Join-Path (Join-Path $dotnetSrc $folder) $outName
    $cscArgs = @("/nologo", "/target:exe", "/platform:anycpu", ("/out:" + $out)) + $extra + @($src)
    Write-Host ("编译 " + $folder + " -> " + $outName + " ...")
    & $csc @cscArgs
    if ($LASTEXITCODE -ne 0) { throw ("编译失败: " + $folder) }
    return $out
}

# --- 1. 检查前提 ---
if (-not (Test-Path -LiteralPath $csc)) { throw "找不到 csc.exe: $csc" }
if (-not (Test-Path -LiteralPath $dnlib)) { throw "找不到 dnlib.dll: $dnlib" }
$cliPath = Join-Path $ConfuserDir "Confuser.CLI.exe"
$corePath = Join-Path $ConfuserDir "Confuser.Core.dll"
if (-not (Test-Path -LiteralPath $cliPath) -or -not (Test-Path -LiteralPath $corePath)) {
    throw "ConfuserEx2 目录中缺少 Confuser.CLI.exe 或 Confuser.Core.dll: $ConfuserDir"
}
if ((Get-Sha $cliPath) -ne $expectedCli) { throw "Confuser.CLI.exe 的 SHA256 与 1.6.0 不符，部署中止。" }
if ((Get-Sha $corePath) -ne $expectedCore) { throw "Confuser.Core.dll 的 SHA256 与 1.6.0 不符，部署中止。" }
if ($ObfuscarNupkg) {
    if (-not (Test-Path -LiteralPath $ObfuscarNupkg)) { throw "找不到 Obfuscar nupkg: $ObfuscarNupkg" }
    if ((Get-Sha $ObfuscarNupkg) -ne $expectedObfNupkg) { throw "Obfuscar nupkg 的 SHA256 与 dependencies.md 不符，部署中止。" }
}

# --- 2. 编译 ---
$exe1a = Build-Tool "module_1a" "module_1a.exe" @("/reference:" + $dnlib)
$exe1b = Build-Tool "module_1b" "module_1b.exe" @()
$exe1c = Build-Tool "module_1c" "module_1c.exe" @("/reference:" + $dnlib)
$exe2a = Build-Tool "module_2a" "module_2a.exe" @()
$exe2b = Build-Tool "module_2b" "bs.exe" @("/reference:System.Web.Extensions.dll")

# --- 3. 组装扁平目录 ---
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
foreach ($f in @($exe2b, $exe1a, $exe1b, $exe1c, $exe2a, $dnlib)) {
    Copy-Item -LiteralPath $f -Destination $OutDir -Force
}

$confDest = Join-Path $OutDir "ConfuserEx-1.6.0"
if (Test-Path -LiteralPath $confDest) { Remove-Item -LiteralPath $confDest -Recurse -Force }
Copy-Item -LiteralPath $ConfuserDir -Destination $confDest -Recurse -Force

# --- 4. Obfuscar（可选）：只取 tools/net8.0/any 下的文件 ---
$obfDest = Join-Path $OutDir "obfuscar"
if ($ObfuscarNupkg) {
    if (Test-Path -LiteralPath $obfDest) { Remove-Item -LiteralPath $obfDest -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $obfDest | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $prefix = "tools/net8.0/any/"
    $zip = [IO.Compression.ZipFile]::OpenRead($ObfuscarNupkg)
    try {
        $count = 0
        foreach ($e in $zip.Entries) {
            if (-not $e.FullName.StartsWith($prefix, [StringComparison]::Ordinal)) { continue }
            if ($e.FullName.EndsWith("/", [StringComparison]::Ordinal)) { continue }
            $rel = $e.FullName.Substring($prefix.Length) -replace "/", "\"
            $dest = Join-Path $obfDest $rel
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dest) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
            $count++
        }
    }
    finally { $zip.Dispose() }
    if (-not (Test-Path -LiteralPath (Join-Path $obfDest "GlobalTools.dll"))) { throw "nupkg 中没有 tools/net8.0/any/GlobalTools.dll" }
    Write-Host ("Obfuscar: 解压 " + $count + " 个文件到 " + $obfDest)
}

# --- 5. 冒烟测试：bs.exe 能运行，并且能调用同目录的 module_1a.exe ---
$bs = Join-Path $OutDir "bs.exe"
$ErrorActionPreference = "Continue"
& $bs | Out-Null
$usageCode = $LASTEXITCODE
$smokeJson = Join-Path $env:TEMP ("bs_deploy_smoke_" + [guid]::NewGuid().ToString("N").Substring(0, 8) + ".json")
& $bs analyze (Join-Path $OutDir "module_2a.exe") $smokeJson | Out-Null
$analyzeCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
$smokeOk = (Test-Path -LiteralPath $smokeJson)
if (Test-Path -LiteralPath $smokeJson) { Remove-Item -LiteralPath $smokeJson -Force }
Write-Host ("冒烟测试: bs.exe（无参数）退出码 " + $usageCode + "（应为 64）；analyze 退出码 " + $analyzeCode + "（应为 0）")
if ($usageCode -ne 64 -or $analyzeCode -ne 0 -or -not $smokeOk) { throw "冒烟测试失败。" }

# --- 6. 清单：dist 中每个文件的 SHA256 ---
$manifestPath = Join-Path $OutDir "deploy-manifest.txt"
$lines = @()
Get-ChildItem -LiteralPath $OutDir -Recurse -File | Where-Object { $_.Name -ne "deploy-manifest.txt" } | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($OutDir.Length).TrimStart("\")
    $lines += ((Get-Sha $_.FullName) + "  " + $rel)
}
[IO.File]::WriteAllLines($manifestPath, [string[]]$lines, (New-Object Text.UTF8Encoding($false)))

Write-Host ""
Write-Host ("部署完成: " + $OutDir)
Write-Host ("清单: " + $manifestPath + "（" + $lines.Count + " 个文件）")
Write-Host "用法示例:"
Write-Host ("  " + (Join-Path $OutDir "bs.exe") + " protect <程序.dll|exe> --out <输出目录> --bin-dir """ + $OutDir + """ --confuser """ + (Join-Path $OutDir "ConfuserEx-1.6.0\Confuser.CLI.exe") + """")
if ($ObfuscarNupkg) {
    Write-Host ("  .NET 8 程序加 --obfuscar """ + (Join-Path $OutDir "obfuscar\GlobalTools.dll") + """")
} else {
    Write-Host "  .NET 8 程序需要 Obfuscar：用 -ObfuscarNupkg 重新部署，或在 --obfuscar 中指定 GlobalTools.dll。"
}
