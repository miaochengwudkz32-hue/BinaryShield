# Module 1B 验收测试 —— 对照 src/dotnet/module_1b/spec.md 第 8 节
# 用法:  powershell -ExecutionPolicy Bypass -File tests\benchmarks\test_module_1b.ps1
# 退出码:  0 = 全部通过 | 1 = 有失败 | 2 = 前置缺失(sample.dll / module_1a.exe) | 3 = 功能待构建

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$root    = (Resolve-Path (Join-Path $here '..\..')).Path
$sample  = Join-Path $root 'tests\test_files\sample.dll'
$tool1a  = Join-Path $root 'src\dotnet\module_1a\module_1a.exe'
$tool1b  = Join-Path $root 'src\dotnet\module_1b\module_1b.exe'
$work    = Join-Path ([IO.Path]::GetTempPath()) ('bs_1b_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$exclPattern = "namespace('Avalonia(\..*)?') or namespace('CompiledAvaloniaXaml(\..*)?')"
$protIds     = @('anti debug','anti dump','anti ildasm','anti tamper','constants','ctrl flow','harden','invalid metadata','ref proxy','resources','typescramble','rename')
$utf8     = New-Object System.Text.UTF8Encoding($false)
$results  = @()

function Check($name, $cond, $detail = '') {
    $script:results += [pscustomobject]@{ Test = $name; Pass = [bool]$cond; Detail = $detail }
}

# 运行 module_1b.exe,返回退出码与 stderr 文本
function Invoke-1B($inJson, $outCrproj) {
    $so = Join-Path $work 'stdout.txt'
    $se = Join-Path $work 'stderr.txt'
    $p = Start-Process -FilePath $tool1b -ArgumentList @("`"$inJson`"", "`"$outCrproj`"") `
         -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $err = ''
    if (Test-Path $se) { $err = Get-Content $se -Raw -Encoding UTF8 }
    return [pscustomobject]@{ Code = $p.ExitCode; Err = $err }
}

# 能否被 XML 解析器读取;返回 XmlDocument 或 $null
function Read-Xml($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return [xml](Get-Content $path -Raw -Encoding UTF8) } catch { return $null }
}

# --- 前置检查 ---
if (-not (Test-Path $sample) -or -not (Test-Path $tool1a)) {
    Write-Host "[前置缺失] 需要 sample.dll 与 module_1a.exe(Module 1A 产物)" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $tool1b)) {
    Write-Host "[待构建] 找不到功能程序: $tool1b" -ForegroundColor Yellow
    Write-Host "这是预期的 —— 按工作流，测试先于功能编写。" -ForegroundColor Yellow
    exit 3
}

# --- 用 Module 1A 从样本生成真实清单（含 skip:true 的 Avalonia 类型）---
$skipJson = Join-Path $work 'skip.json'
& $tool1a $sample $skipJson | Out-Null
$base = [IO.File]::ReadAllText($skipJson, [Text.Encoding]::UTF8)

# 派生的测试清单
$noskipJson     = Join-Path $work 'noskip.json'
$unmanagedJson  = Join-Path $work 'unmanaged.json'
$weirdJson      = Join-Path $work 'weird.json'
$samplePathJson = $sample.Replace('\', '/')
[IO.File]::WriteAllText($noskipJson,    $base.Replace('"skip": true', '"skip": false'), $utf8)
[IO.File]::WriteAllText($unmanagedJson, $base.Replace('"isManaged": true', '"isManaged": false'), $utf8)
[IO.File]::WriteAllText($weirdJson,     $base.Replace($samplePathJson, 'C:/测试 & 目录/a b.dll'), $utf8)

# --- 标准 2 / 3 / 1：主路径（含 skip 类型）---
$crA = Join-Path $work 'skip.crproj'
$r = Invoke-1B $skipJson $crA
Check '退出码为 0（含 skip 类型）' ($r.Code -eq 0) "exit=$($r.Code)"
Check '生成 .crproj 文件' (Test-Path $crA)

$xml = Read-Xml $crA
Check '1. .crproj 是合法 XML' ($null -ne $xml)

$rules = @()
$mods  = @()
$comments = @()
if ($xml) {
    $rules    = @($xml.SelectNodes("//*[local-name()='rule']"))
    $mods     = @($xml.SelectNodes("//*[local-name()='module']"))
    $comments = @($xml.SelectNodes("//comment()"))
}

$baseRules = @($rules | Where-Object { $_.GetAttribute('pattern') -eq 'true' -and $_.GetAttribute('preset') -eq 'normal' })
$exclRules = @($rules | Where-Object { $_.GetAttribute('pattern') -eq $exclPattern })
Check '2a. 共 2 条 rule：基础规则(normal) + 排除规则' (($rules.Count -eq 2) -and ($baseRules.Count -eq 1)) "rule 总数=$($rules.Count), 基础规则=$($baseRules.Count)"
if ($baseRules.Count -eq 1) {
    $bp = @($baseRules[0].SelectNodes("./*[local-name()='protection'][@action='remove']") | ForEach-Object { $_.GetAttribute('id') })
    Check '2g. 基础规则去掉 resources 保护（XAML 必须可读）' ($bp -contains 'resources') "基础规则移除=$($bp -join ', ')"
    Check '2h. 基础规则去掉 ref proxy（ConfuserEx2 无法解析 Avalonia 11 编译 XAML 的引用）' ($bp -contains 'ref proxy') "基础规则移除=$($bp -join ', ')"
}

Check '2b. 排除规则恰好 1 条（决定点 A）' ($exclRules.Count -eq 1) "匹配数=$($exclRules.Count)"
if ($exclRules.Count -eq 1) {
    $ri = $exclRules[0].GetAttribute('inherit')
    Check '2c. 排除规则 inherit="false"' ($ri -eq 'false') "实际=$ri"
    $removed = @($exclRules[0].SelectNodes("./*[local-name()='protection'][@action='remove']") | ForEach-Object { $_.GetAttribute('id') })
    $missing = @($protIds | Where-Object { $removed -notcontains $_ })
    Check '2d. 排除规则移除全部 12 项保护' ($missing.Count -eq 0) "缺失=$($missing -join ', ')"
}

if ($xml) {
    $proj = $xml.DocumentElement
    $outDir = $proj.GetAttribute('outputDir')
    $baseDir = $proj.GetAttribute('baseDir')
    Check '2e. outputDir="protected"、baseDir="."（决定点 F）' (($outDir -eq 'protected') -and ($baseDir -eq '.')) "outputDir=$outDir baseDir=$baseDir"
}

if ($xml) {
    Check '2f. 根命名空间为 ConfuserEx2 项目格式 http://confuser.codeplex.com' ($xml.DocumentElement.NamespaceURI -eq 'http://confuser.codeplex.com') "实际=$($xml.DocumentElement.NamespaceURI)"
}

Check '3a. <module path> 指向目标程序（单个）' (($mods.Count -eq 1) -and ($mods[0].GetAttribute('path') -eq $samplePathJson)) "module 数=$($mods.Count)"

$cText = ($comments | ForEach-Object { $_.Value }) -join "`n"
Check '3b. 注释列出被排除的 Avalonia 命名空间（决定点 B）' (($cText -match [regex]::Escape('Avalonia.Controls.Internal')) -and ($cText -match 'Avalonia')) "注释片段=$($cText.Trim())"

# --- 标准 4：无 skip 类型 → 退出码 0、合法 XML、有 WARNING（决定点 C）---
$crB = Join-Path $work 'noskip.crproj'
$r2 = Invoke-1B $noskipJson $crB
Check '4a. 无 skip 类型：退出码 0' ($r2.Code -eq 0) "exit=$($r2.Code)"
Check '4b. 无 skip 类型：仍生成合法 XML' ($null -ne (Read-Xml $crB))
Check '4c. 无 skip 类型：输出 WARNING:' ($r2.Err -match 'WARNING:') "stderr=$($r2.Err.Trim())"

# --- 标准 5：isManaged=false → 非零退出，且不生成 .crproj ---
$crC = Join-Path $work 'unmanaged.crproj'
$r3 = Invoke-1B $unmanagedJson $crC
Check '5a. isManaged=false：非零退出' ($r3.Code -ne 0) "exit=$($r3.Code)"
Check '5b. isManaged=false：未生成 .crproj' (-not (Test-Path $crC))

# --- 标准 6：输入 JSON 不存在 → 非零退出 ---
$r4 = Invoke-1B (Join-Path $work 'nope.json') (Join-Path $work 'x.crproj')
Check '6. 输入 JSON 不存在：非零退出' ($r4.Code -ne 0) "exit=$($r4.Code)"

# --- 标准 7：路径含 & 空格 中文 → 合法 XML，路径原样还原 ---
$crD = Join-Path $work 'weird.crproj'
$r5 = Invoke-1B $weirdJson $crD
$wxml = Read-Xml $crD
Check '7a. 路径含 & 空格 中文：仍是合法 XML' ($null -ne $wxml)
if ($wxml) {
    $wm = @($wxml.SelectNodes("//*[local-name()='module']"))
    Check '7b. 路径原样还原（无双重转义）' (($wm.Count -eq 1) -and ($wm[0].GetAttribute('path') -eq 'C:/测试 & 目录/a b.dll')) "实际=$(if ($wm.Count) { $wm[0].GetAttribute('path') })"
}

# --- 标准 8：同一输入运行两次，输出逐字节相同 ---
$crA2 = Join-Path $work 'skip2.crproj'
Invoke-1B $skipJson $crA2 | Out-Null
$h1 = if (Test-Path $crA)  { (Get-FileHash $crA  -Algorithm SHA256).Hash } else { '' }
$h2 = if (Test-Path $crA2) { (Get-FileHash $crA2 -Algorithm SHA256).Hash } else { '' }
Check '8. 同一输入两次输出逐字节相同' (($h1 -ne '') -and ($h1 -eq $h2)) "h1=$h1 h2=$h2"

# --- 标准 9：输入与输出为同一文件 → 拒绝（退出码 64），且输入清单不被改动（DeepSeek 审查项 3）---
$beforeHash = (Get-FileHash $skipJson -Algorithm SHA256).Hash
$r6 = Invoke-1B $skipJson $skipJson
$afterHash = (Get-FileHash $skipJson -Algorithm SHA256).Hash
Check '9a. 输入与输出相同：退出码 64' ($r6.Code -eq 64) "exit=$($r6.Code)"
Check '9b. 输入与输出相同：清单内容未被改动' ($beforeHash -eq $afterHash)

# --- 标准 10：input.path 不是绝对路径 → 退出码 65（DeepSeek 审查项 7）---
$relJson = Join-Path $work 'relative.json'
[IO.File]::WriteAllText($relJson, $base.Replace($samplePathJson, 'relative/sample.dll'), $utf8)
$r7 = Invoke-1B $relJson (Join-Path $work 'rel.crproj')
Check '10. input.path 不是绝对路径：退出码 65' ($r7.Code -eq 65) "exit=$($r7.Code)"

# --- 标准 11：assemblies 不是数组 → 退出码 65，结构错误不静默跳过（DeepSeek 审查项 6）---
$badJson = Join-Path $work 'badschema.json'
[IO.File]::WriteAllText($badJson, $base.Replace('"assemblies": [', '"assemblies": "bad", "_unused": ['), $utf8)
$r8 = Invoke-1B $badJson (Join-Path $work 'bad.crproj')
Check '11. assemblies 不是数组：退出码 65' ($r8.Code -eq 65) "exit=$($r8.Code)"

# --- 标准 12：命名空间含连续 "---"，注释仍为合法 XML 且不含 "--"（DeepSeek 审查项 9）---
$dashJson = Join-Path $work 'dash.json'
[IO.File]::WriteAllText($dashJson, $base.Replace('"namespace": "Avalonia.Controls.Internal"', '"namespace": "Avalonia.---x"'), $utf8)
$crE = Join-Path $work 'dash.crproj'
$r9 = Invoke-1B $dashJson $crE
Check '12a. 命名空间含 "---"：退出码 0' ($r9.Code -eq 0) "exit=$($r9.Code)"
$dx = Read-Xml $crE
$dashOk = $false
if ($dx) {
    $dc = @($dx.SelectNodes('//comment()'))
    $dashOk = ($dc.Count -ge 1) -and (@($dc | Where-Object { $_.Value -match '--' }).Count -eq 0)
}
Check '12b. 命名空间含 "---"：仍是合法 XML，注释不含 "--"' $dashOk

# --- 汇总 ---
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== Module 1B 验收结果 ===="
foreach ($x in $results) {
    $mark  = if ($x.Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($x.Pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}  {2}" -f $mark, $x.Test, $x.Detail) -ForegroundColor $color
}
$fail = @($results | Where-Object { -not $_.Pass }).Count
Write-Host ""
if ($fail -eq 0) { Write-Host "全部通过" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail 项失败" -ForegroundColor Red; exit 1 }
