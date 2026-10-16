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
foreach ($w in $warnings) { Write-Host "WARN: $w" -ForegroundColor Yellow }
if ($problems.Count) {
    Write-Host 'RESULT: version mismatch' -ForegroundColor Red
    foreach ($x in $problems) { Write-Host "  - $x" -ForegroundColor Red }
    exit 1
}
Write-Host "RESULT: version consistent ($current)" -ForegroundColor Green
exit 0
