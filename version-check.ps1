param([switch]$SkipRemote)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# version-check.ps1 -- 校验三份插件清单 version 与 git tag、CHANGELOG 三处一致（含远程同步）
# 用法：.\version-check.ps1              全量
#       .\version-check.ps1 -SkipRemote  离线

$Root = $PSScriptRoot
$problems = @(); $warnings = @()

Write-Host '=== 1. 插件清单版本 ==='
$versions = @{}
foreach ($rel in @('plugin.json', '.codex-plugin\plugin.json', '.codebuddy-plugin\plugin.json')) {
    $p = Join-Path $Root $rel
    if (-not (Test-Path $p)) { $problems += "缺少清单：$rel"; continue }
    $c = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
    $m = [regex]::Match($c, '"version"\s*:\s*"([^"]+)"')
    if (-not $m.Success) { $problems += "清单无 version：$rel"; continue }
    $versions[$rel] = $m.Groups[1].Value
}
foreach ($k in ($versions.Keys | Sort-Object)) { $v = ([string]$versions[$k]); Write-Host ("  {0,-34} {1}" -f $k, $v) }
$uniq = @($versions.Values | Sort-Object -Unique)
if ($uniq.Count -ne 1) { $problems += "清单版本不一致：$($versions.Values -join ' / ')" }
$current = if ($uniq.Count -ge 1) { ([string]$uniq[0]) } else { '' }
if ($current -and $current -notmatch '^\d+\.\d+\.\d+$') { $problems += "非语义化版本：$current" }

Write-Host ''
Write-Host '=== 2. CHANGELOG ==='
$cl = Join-Path $Root 'CHANGELOG.md'
if (-not (Test-Path $cl)) { $problems += '缺少 CHANGELOG.md' }
else {
    $clc = [System.IO.File]::ReadAllText($cl, [System.Text.UTF8Encoding]::new($false))
    if ($current -and -not ($clc -match ('\[' + [regex]::Escape($current) + '\]'))) { $problems += "CHANGELOG 未登记 [$current]" }
    else { Write-Host "  [$current] 条目存在" }
}

Write-Host ''
Write-Host '=== 3. 本地 git tag ==='
Push-Location $Root
$gitOk = $false
try { $null = git rev-parse --git-dir 2>$null; if ($LASTEXITCODE -eq 0) { $gitOk = $true } } catch { }
$localTags = @()
if ($gitOk) {
    $localTags = @(git tag --sort=-v:refname 2>$null | Where-Object { $_ })
    $latest = if ($localTags.Count) { $localTags[0] } else { '' }
    Write-Host ("  本地 tag 数：{0}；最新：{1}" -f $localTags.Count, $(if ($latest) { $latest } else { '（无）' }))
    if (-not $latest) { $problems += '没有任何 tag' }
    elseif ($current -and $latest -ne "v$current") { $problems += "最新 tag ($latest) 与清单版本 (v$current) 不一致" }
} else { $warnings += '非 git 仓库，跳过 tag 校验' }

Write-Host ''
if ($gitOk -and -not $SkipRemote) {
    Write-Host '=== 4. 远程同步 ==='
    $remoteUrl = $null
    try { $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $remoteUrl = (git remote get-url origin 2>$null); $ErrorActionPreference = $prev } catch { $remoteUrl = $null }
    if (-not $remoteUrl) { $warnings += '未配置 origin，跳过远程校验'; Write-Host '  （无 origin）' }
    else {
        $raw = $null; $ok = $false
        try { $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $raw = (git ls-remote --tags origin 2>$null); $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $prev } catch { $ok = $false }
        if (-not ($ok -and $null -ne $raw)) { $warnings += '无法访问远程 origin，远程校验未执行'; Write-Host '  （远程不可达）' }
        else {
            $rt = @($raw | ForEach-Object { ($_ -split "`t")[1] } | Where-Object { $_ } | ForEach-Object { $_ -replace '^refs/tags/','' -replace '\^\{\}$','' } | Sort-Object -Unique)
            Write-Host ("  远程 tag 数：{0}" -f $rt.Count)
            $np = @($localTags | Where-Object { $rt -notcontains $_ })
            if ($np.Count) { $problems += "本地有但远程缺失的 tag：$($np -join '、')" } else { Write-Host '  OK 本地 tag 均已推送' }
            $nl = @($rt | Where-Object { $localTags -notcontains $_ })
            if ($nl.Count) { $warnings += "远程有本地缺失的 tag：$($nl -join '、')" }
            $ahead = $null
            try { $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'; $ahead = (git rev-list --count 'origin/main..HEAD' 2>$null); $ErrorActionPreference = $prev } catch { $ahead = $null }
            if ($ahead -and [int]$ahead -gt 0) { $problems += "有 $ahead 个提交未推送" } else { Write-Host '  OK HEAD 已推送' }
        }
    }
} elseif ($SkipRemote) { Write-Host '=== 4. 远程同步（已跳过）===' }
Pop-Location

Write-Host ''
Write-Host '=== 5. 根目录镜像（TRAE 需要根级 SKILL.md）==='
# 根目录是 skills/industry-scope-router/ 的生成镜像；两者必须逐文件一致，否则会漂移
$srcSkill = Join-Path $Root 'skills\industry-scope-router'
$mirrorItems = @('SKILL.md','assets','references','build-html.py','count-body.ps1','verify-bom.ps1','自检.ps1')
$mirrorFiles = @()
foreach ($it in $mirrorItems) {
    $p = Join-Path $srcSkill $it
    if (-not (Test-Path $p)) { $problems += "镜像源缺失：$it"; continue }
    if ((Get-Item $p).PSIsContainer) {
        Get-ChildItem $p -Recurse -File | ForEach-Object { $mirrorFiles += $_.FullName.Substring($srcSkill.Length + 1) }
    } else { $mirrorFiles += $it }
}
$mirrorBad = @()
foreach ($f in ($mirrorFiles | Sort-Object -Unique)) {
    $a = Join-Path $srcSkill $f
    $b = Join-Path $Root $f
    if (-not (Test-Path $b)) { $mirrorBad += "根目录缺 $f"; continue }
    if ((Get-FileHash $a -Algorithm MD5).Hash -ne (Get-FileHash $b -Algorithm MD5).Hash) { $mirrorBad += "内容不同 $f" }
}
if ($mirrorBad.Count) {
    $problems += "根目录镜像与 skills/ 不一致（$($mirrorBad.Count) 个）：$($mirrorBad -join '；')"
} else {
    Write-Host ("  OK 根目录镜像一致（{0} 个文件）" -f @($mirrorFiles | Sort-Object -Unique).Count)
}

# 根级 SKILL.md 必须是 TRAE 可识别的 YAML frontmatter
$rootSkill = Join-Path $Root 'SKILL.md'
if (-not (Test-Path $rootSkill)) { $problems += '根级 SKILL.md 缺失（TRAE 会报 SKILL.md not found）' }
else {
    $rl = [System.IO.File]::ReadAllLines($rootSkill, [System.Text.UTF8Encoding]::new($false))
    $fmOk = $rl.Count -gt 3 -and $rl[0].Trim() -eq '---'
    $hasName = $false; $hasDesc = $false; $closed = $false
    if ($fmOk) {
        for ($i = 1; $i -lt [Math]::Min(40, $rl.Count); $i++) {
            if ($rl[$i].Trim() -eq '---') { $closed = $true; break }
            if ($rl[$i] -match '^name:\s*\S') { $hasName = $true }
            if ($rl[$i] -match '^description:') { $hasDesc = $true }
        }
    }
    if (-not ($fmOk -and $hasName -and $hasDesc -and $closed)) {
        $problems += '根级 SKILL.md 的 frontmatter 不合规（需 --- 包裹，且含 name 与 description）'
    } else {
        Write-Host '  OK 根级 SKILL.md frontmatter 合规（TRAE 可识别）'
    }
}

Write-Host ''
foreach ($w in $warnings) { Write-Host "WARN: $w" -ForegroundColor Yellow }
if ($problems.Count) {
    Write-Host 'RESULT: version mismatch' -ForegroundColor Red
    foreach ($x in $problems) { Write-Host "  - $x" -ForegroundColor Red }
    exit 1
}
Write-Host "RESULT: version consistent ($current)" -ForegroundColor Green
exit 0
