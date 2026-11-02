# Module 1C 验收测试 —— 对照 src/dotnet/module_1c/spec.md 第 10 节
# 用法:  powershell -ExecutionPolicy Bypass -File tests\benchmarks\test_module_1c.ps1 -Confuser <Confuser.CLI.exe 路径>
#        也可设置环境变量 BS_CONFUSER_CLI 代替 -Confuser。
# 退出码:  0 = 全部通过 | 1 = 有失败 | 2 = 前置缺失(sample.dll / module_1a.exe / module_1b.exe / ConfuserEx2 CLI) | 3 = 功能待构建

param([string]$Confuser = $env:BS_CONFUSER_CLI)

$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$root   = (Resolve-Path (Join-Path $here '..\..')).Path
$sample = Join-Path $root 'tests\test_files\sample.dll'
$tool1a = Join-Path $root 'src\dotnet\module_1a\module_1a.exe'
$tool1b = Join-Path $root 'src\dotnet\module_1b\module_1b.exe'
$tool1c = Join-Path $root 'src\dotnet\module_1c\module_1c.exe'
$work   = Join-Path ([IO.Path]::GetTempPath()) ('bs_1c_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$utf8    = New-Object System.Text.UTF8Encoding($false)
$results = @()

function Check($name, $cond, $detail = '') {
    $script:results += [pscustomobject]@{ Test = $name; Pass = [bool]$cond; Detail = $detail }
}

# 给参数加引号（路径可能含空格）
function Q($s) { return "`"$s`"" }

# 运行 module_1c.exe，返回退出码与 stderr 文本
function Invoke-1C([string[]]$argList) {
    $so = Join-Path $work ('so_' + [guid]::NewGuid().ToString('N') + '.txt')
    $se = Join-Path $work ('se_' + [guid]::NewGuid().ToString('N') + '.txt')
    $p = Start-Process -FilePath $tool1c -ArgumentList $argList -NoNewWindow -Wait -PassThru -RedirectStandardOutput $so -RedirectStandardError $se
    $err = ''
    if (Test-Path $se) { $err = [string](Get-Content $se -Raw -Encoding UTF8) }
    return [pscustomobject]@{ Code = $p.ExitCode; Err = $err }
}

# 读取输出目录下的 report.json；不存在或不是合法 JSON 时返回 $null
function Read-Report($dir) {
    $path = Join-Path $dir 'report.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return (Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

# --- 前置检查 ---
if (-not (Test-Path $sample) -or -not (Test-Path $tool1a) -or -not (Test-Path $tool1b)) {
    Write-Host "[前置缺失] 需要 sample.dll、module_1a.exe、module_1b.exe" -ForegroundColor Red
    exit 2
}
if (-not (Test-Path $tool1c)) {
    Write-Host "[待构建] 找不到功能程序: $tool1c" -ForegroundColor Yellow
    Write-Host "这是预期的 —— 按工作流，测试先于功能编写。" -ForegroundColor Yellow
    exit 3
}
if (-not $Confuser -or -not (Test-Path -LiteralPath $Confuser)) {
    Write-Host "[前置缺失] 需要 ConfuserEx2 CLI：用 -Confuser <Confuser.CLI.exe 路径> 指定，或设置环境变量 BS_CONFUSER_CLI" -ForegroundColor Red
    exit 2
}

# 记录仓库状态，用于检查 11（运行前后仓库无改动）
$gitBefore = (& git -C $root status --porcelain) -join "`n"

# 输入副本放在临时目录，原始 sample.dll 不参与运行
$inDir = Join-Path $work 'in'
New-Item -ItemType Directory -Force -Path $inDir | Out-Null
$inDll = Join-Path $inDir 'sample.dll'
Copy-Item -LiteralPath $sample -Destination $inDll
$hashBefore = (Get-FileHash -LiteralPath $inDll -Algorithm SHA256).Hash

# --- 1–5：正常运行 ---
$out1 = Join-Path $work 'out1'
$r1 = Invoke-1C @('protect', (Q $inDll), '--out', (Q $out1), '--confuser', (Q $Confuser))
Check '1a. 正常运行：退出码 0' ($r1.Code -eq 0) ("exit=$($r1.Code) stderr=" + ([string]$r1.Err).Trim())
Check '1b. protected\sample.dll 存在' (Test-Path -LiteralPath (Join-Path $out1 'protected\sample.dll'))
$rep1 = Read-Report $out1
Check '1c. report.json 存在且为合法 JSON' ($null -ne $rep1)

$hashAfter = (Get-FileHash -LiteralPath $inDll -Algorithm SHA256).Hash
Check '2a. 输入 SHA256 运行前后相同' ($hashBefore -eq $hashAfter)
Check '2b. report 记录输入未变（input.unchanged）' ($rep1 -and $rep1.input.unchanged -eq $true) "unchanged=$($rep1.input.unchanged)"

Check '3. 1A、1B、ConfuserEx2 退出码均为 0' ($rep1 -and $rep1.steps.module_1a.exit -eq 0 -and $rep1.steps.module_1b.exit -eq 0 -and $rep1.steps.confuser.exit -eq 0)

$checks = @()
if ($rep1) { $checks = @($rep1.checks) }
foreach ($id in @('a', 'b', 'c', 'd', 'f')) {
    $c = $checks | Where-Object { $_.id -eq $id } | Select-Object -First 1
    Check "4$id. 复核 $id 为 PASS" ($c -and $c.status -eq 'PASS') "status=$($c.status)"
}
$ce = $checks | Where-Object { $_.id -eq 'e' } | Select-Object -First 1
Check '4e. 复核 e 为 PASS 或 WARN（不计入失败）' ($ce -and ($ce.status -eq 'PASS' -or $ce.status -eq 'WARN')) "status=$($ce.status)"

Check '5. 保留 work\manifest.json 与 work\config.crproj' ((Test-Path -LiteralPath (Join-Path $out1 'work\manifest.json')) -and (Test-Path -LiteralPath (Join-Path $out1 'work\config.crproj')))

# --- 6：非托管输入 → 65，且不生成 protected\ ---
$badIn = Join-Path $inDir 'notpe.dll'
[IO.File]::WriteAllText($badIn, 'this is not a PE file', $utf8)
$out2 = Join-Path $work 'out2'
$r2 = Invoke-1C @('protect', (Q $badIn), '--out', (Q $out2), '--confuser', (Q $Confuser))
Check '6a. 非托管输入：退出码 65' ($r2.Code -eq 65) "exit=$($r2.Code)"
Check '6b. 非托管输入：不生成 protected\' (-not (Test-Path -LiteralPath (Join-Path $out2 'protected')))

# --- 7：输出目录已存在且非空 → 64，原有文件不被改动 ---
$out3 = Join-Path $work 'out3'
New-Item -ItemType Directory -Force -Path $out3 | Out-Null
$keep = Join-Path $out3 'keep.txt'
[IO.File]::WriteAllText($keep, 'keep', $utf8)
$r3 = Invoke-1C @('protect', (Q $inDll), '--out', (Q $out3), '--confuser', (Q $Confuser))
Check '7a. 输出目录非空：退出码 64' ($r3.Code -eq 64) "exit=$($r3.Code)"
Check '7b. 输出目录非空：原有文件未被改动' ((Test-Path -LiteralPath $keep) -and ((Get-Content -LiteralPath $keep -Raw) -eq 'keep'))

# --- 8：输出位于输入目录内 → 64 ---
$r4 = Invoke-1C @('protect', (Q $inDll), '--out', (Q (Join-Path $inDir 'out')), '--confuser', (Q $Confuser))
Check '8. 输出位于输入目录内：退出码 64' ($r4.Code -eq 64) "exit=$($r4.Code)"

# --- 9：--confuser 路径不存在 → 2 ---
$r5 = Invoke-1C @('protect', (Q $inDll), '--out', (Q (Join-Path $work 'out5')), '--confuser', (Q (Join-Path $work 'nope\Confuser.CLI.exe')))
Check '9. --confuser 路径不存在：退出码 2' ($r5.Code -eq 2) "exit=$($r5.Code)"

# --- 10：ConfuserEx2 版本不是 1.6.0 → 2（用空文件伪造，只检查版本信息，不运行）---
$fakeDir = Join-Path $work 'fake'
New-Item -ItemType Directory -Force -Path $fakeDir | Out-Null
[IO.File]::WriteAllBytes((Join-Path $fakeDir 'Confuser.CLI.exe'), [byte[]]@())
[IO.File]::WriteAllBytes((Join-Path $fakeDir 'Confuser.Core.dll'), [byte[]]@())
$r6 = Invoke-1C @('protect', (Q $inDll), '--out', (Q (Join-Path $work 'out6')), '--confuser', (Q (Join-Path $fakeDir 'Confuser.CLI.exe')))
Check '10. ConfuserEx2 版本不是 1.6.0：退出码 2' ($r6.Code -eq 2) "exit=$($r6.Code)"

# --- 12：Confuser.Core.dll 正确但 Confuser.CLI.exe 被替换 → 2（D4 的 CLI 本身校验）---
$fakeCliDir = Join-Path $work 'fakecli'
New-Item -ItemType Directory -Force -Path $fakeCliDir | Out-Null
Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $Confuser) 'Confuser.Core.dll') -Destination $fakeCliDir
[IO.File]::WriteAllBytes((Join-Path $fakeCliDir 'Confuser.CLI.exe'), [byte[]]@())
$r7 = Invoke-1C @('protect', (Q $inDll), '--out', (Q (Join-Path $work 'out7')), '--confuser', (Q (Join-Path $fakeCliDir 'Confuser.CLI.exe')))
Check '12. Confuser.CLI.exe 被替换（Core.dll 正确）：退出码 2' ($r7.Code -eq 2) "exit=$($r7.Code)"

# --- 13：输入旁边有 .config（绑定重定向）→ protected\ 中也必须有 ---
$cfgDir = Join-Path $work 'cfgin'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
$cfgIn = Join-Path $cfgDir 'sample.dll'
Copy-Item -LiteralPath $sample -Destination $cfgIn
[IO.File]::WriteAllText((Join-Path $cfgDir 'sample.dll.config'), '<configuration />', $utf8)
$out8 = Join-Path $work 'out13'
$r8 = Invoke-1C @('protect', (Q $cfgIn), '--out', (Q $out8), '--confuser', (Q $Confuser))
Check '13. 输入有 .config：protected\sample.dll.config 存在' ($r8.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $out8 'protected\sample.dll.config'))) "exit=$($r8.Code)"

# --- 14：依赖子目录（如 x64\ 下的原生库）→ protected\ 中也必须有 ---
$subDir = Join-Path $cfgDir 'x64'
New-Item -ItemType Directory -Force -Path $subDir | Out-Null
[IO.File]::WriteAllBytes((Join-Path $subDir 'libnative.dll'), [byte[]]@(1,2,3))
$out9 = Join-Path $work 'out14'
$r9 = Invoke-1C @('protect', (Q $cfgIn), '--out', (Q $out9), '--confuser', (Q $Confuser))
Check '14. 依赖子目录 x64\libnative.dll 被复制到 protected\x64\' ($r9.Code -eq 0 -and (Test-Path -LiteralPath (Join-Path $out9 'protected\x64\libnative.dll'))) "exit=$($r9.Code)"

# --- 11：仓库内没有任何文件被改动 ---
$gitAfter = (& git -C $root status --porcelain) -join "`n"
Check '11. 仓库内没有文件被改动（git status 前后一致）' ($gitBefore -eq $gitAfter)

# --- 汇总 ---
Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host "==== Module 1C 验收结果 ===="
foreach ($x in $results) {
    $mark  = if ($x.Pass) { 'PASS' } else { 'FAIL' }
    $color = if ($x.Pass) { 'Green' } else { 'Red' }
    Write-Host ("[{0}] {1}  {2}" -f $mark, $x.Test, $x.Detail) -ForegroundColor $color
}
$fail = @($results | Where-Object { -not $_.Pass }).Count
Write-Host ""
if ($fail -eq 0) { Write-Host "全部通过" -ForegroundColor Green; exit 0 }
else { Write-Host "$fail 项失败" -ForegroundColor Red; exit 1 }
