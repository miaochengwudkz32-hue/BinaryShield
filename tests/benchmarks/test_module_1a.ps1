# Module 1A 自动化验收测试
# 用法:  powershell -ExecutionPolicy Bypass -File tests\benchmarks\test_module_1a.ps1
# 退出码:  0 = 全部通过 | 1 = 有失败 | 2 = 缺样本 | 3 = 功能尚未构建
#
# 对照 README 的 4 条验收标准:
#   1. 解析测试 .dll 不崩溃
#   2. 输出是合法、可解析的 JSON
#   3. 输出至少包含一条字符串字面量
#   4. 所有 Avalonia 命名空间 skip = true
#   5. 所有 CompiledAvaloniaXaml 与 CompiledAvaloniaXaml.* 命名空间 skip = true（第二份样本 sample_xaml.dll）
#   6. 陷阱命名空间（AvaloniaApp、CompiledAvaloniaXamlHelper、MyApp.Avalonia）skip = false

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$root    = (Resolve-Path (Join-Path $here '..\..')).Path
$sample  = Join-Path $root 'tests\test_files\sample.dll'
$outJson = Join-Path $root 'tests\test_files\sample.output.json'
$tool    = Join-Path $root 'src\dotnet\module_1a\module_1a.exe'
$sampleXaml = Join-Path $root 'tests\test_files\sample_xaml.dll'
$xamlJson   = Join-Path $root 'tests\test_files\sample_xaml.output.json'

$results = @()
function Check($name, $cond, $detail = '') {
    $script:results += [pscustomobject]@{ Test = $name; Pass = [bool]$cond; Detail = $detail }
}

# --- 前置检查 ---
if (-not (Test-Path $sample)) {
    Write-Host "[缺样本] 找不到测试 .dll: $sample" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $tool)) {
    Write-Host "[待构建] 找不到功能程序: $tool" -ForegroundColor Yellow
    Write-Host "这是预期的 —— 按工作流，测试先于功能编写。" -ForegroundColor Yellow
    Write-Host "构建 Module 1A 后，重跑本脚本即可验收。" -ForegroundColor Yellow
    exit 3
}

# --- 运行被测工具 ---
if (Test-Path $outJson) { Remove-Item $outJson -Force }
& $tool $sample $outJson
$toolExit = $LASTEXITCODE

# 标准 1: 不崩溃（退出码 0 且产出了 JSON 文件）
Check '1. 解析测试 .dll 不崩溃' (($toolExit -eq 0) -and (Test-Path $outJson)) "工具退出码=$toolExit"

# 标准 2: 合法 JSON
$json = $null
$validJson = $false
if (Test-Path $outJson) {
    try { $json = Get-Content $outJson -Raw -Encoding UTF8 | ConvertFrom-Json; $validJson = $true }
    catch { $validJson = $false }
}
Check '2. 输出是合法可解析 JSON' $validJson

# 收集所有 type 条目
$types = @()
if ($json) {
    foreach ($asm in @($json.assemblies)) {
        foreach ($mod in @($asm.modules)) {
            foreach ($t in @($mod.types)) { $types += $t }
        }
    }
}

# 标准 3: 至少一条字符串字面量
$strCount = 0
foreach ($t in $types) {
    foreach ($m in @($t.methods)) { $strCount += @($m.stringLiterals).Count }
}
Check '3. 至少包含一条字符串字面量' ($strCount -ge 1) "共 $strCount 条"

# 标准 4: 所有 Avalonia 命名空间 skip = true
$avTypes = @($types | Where-Object { $_.namespace -eq 'Avalonia' -or $_.namespace -like 'Avalonia.*' })
$avBad   = @($avTypes | Where-Object { -not $_.skip })
Check '4. 所有 Avalonia 命名空间 skip=true' (($avTypes.Count -ge 1) -and ($avBad.Count -eq 0)) "Avalonia 类型 $($avTypes.Count) 个, 违规 $($avBad.Count) 个"

# --- 第二份样本：CompiledAvaloniaXaml 规则（与 Avalonia 规则一致，见 CLAUDE.md）---
$xamlTypes = @()
if (-not (Test-Path $sampleXaml)) {
    Check '5. CompiledAvaloniaXaml 与 CompiledAvaloniaXaml.* 命名空间 skip=true' $false "缺少样本 sample_xaml.dll（用 csc 由 sample_xaml_src.cs 编译）"
    Check '6. 陷阱命名空间 skip=false' $false "缺少样本 sample_xaml.dll"
} else {
    if (Test-Path $xamlJson) { Remove-Item $xamlJson -Force }
    & $tool $sampleXaml $xamlJson
    $xamlExit = $LASTEXITCODE
    $xj = $null
    try { $xj = Get-Content $xamlJson -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $xj = $null }
    if ($xj) {
        foreach ($asm in @($xj.assemblies)) {
            foreach ($mod in @($asm.modules)) {
                foreach ($t in @($mod.types)) { $xamlTypes += $t }
            }
        }
    }
    $cxTypes = @($xamlTypes | Where-Object { $_.namespace -eq 'CompiledAvaloniaXaml' -or $_.namespace -like 'CompiledAvaloniaXaml.*' })
    $cxBad   = @($cxTypes | Where-Object { -not $_.skip })
    Check '5. CompiledAvaloniaXaml 与 CompiledAvaloniaXaml.* 命名空间 skip=true' (($xamlExit -eq 0) -and ($cxTypes.Count -ge 2) -and ($cxBad.Count -eq 0)) "工具退出码=$xamlExit, CompiledAvaloniaXaml 类型 $($cxTypes.Count) 个, 违规 $($cxBad.Count) 个"

    $traps   = @($xamlTypes | Where-Object { $_.namespace -in @('AvaloniaApp', 'CompiledAvaloniaXamlHelper', 'MyApp.Avalonia') })
    $trapBad = @($traps | Where-Object { $_.skip })
    Check '6. 陷阱命名空间（AvaloniaApp / CompiledAvaloniaXamlHelper / MyApp.Avalonia）skip=false' (($traps.Count -eq 3) -and ($trapBad.Count -eq 0)) "陷阱类型 $($traps.Count) 个, 误排除 $($trapBad.Count) 个"
}

# --- 汇总 ---
Write-Host ""
Write-Host "==== Module 1A 验收结果 ===="
foreach ($r in $results) {
    $mark  = if ($r.Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($r.Pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}  {2}" -f $mark, $r.Test, $r.Detail) -ForegroundColor $color
}
$fail = @($results | Where-Object { -not $_.Pass }).Count
Write-Host ""
if ($fail -eq 0) { Write-Host "全部通过 ✅" -ForegroundColor Green; exit 0 }
else { Write-Host ("$fail 项失败 ❌") -ForegroundColor Red; exit 1 }
