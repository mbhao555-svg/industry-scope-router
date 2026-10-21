param(
    [ValidateSet('sync', 'check')]
    [string]$Mode = 'sync'
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# sync-root.ps1 —— 把 skills/industry-scope-router/ 镜像到仓库根
#
# 为什么要镜像：
#   TRAE 要求「包含根级 SKILL.md 的 zip 或 .skill 文件」，否则报
#   "Invalid skill package: SKILL.md not found"。
#   而 agent-plugins.org / Codex / WorkBuddy / npx skills 需要 skills/<name>/SKILL.md。
#   两种布局无法共存于同一位置，故：skills/ 为权威，根目录为生成镜像。
#
# 用法：
#   .\sync-root.ps1          生成/更新根目录镜像
#   .\sync-root.ps1 -Mode check   只校验两者是否一致（不一致则退出码 1）

$Root = $PSScriptRoot
$Src = Join-Path $Root 'skills/industry-scope-router'
if (-not (Test-Path $Src)) { Write-Host "RESULT: 找不到源目录 $Src" -ForegroundColor Red; exit 2 }

# 需要镜像到根的条目（相对技能目录）
# 不含 .gitattributes / .gitignore（仓库根已有同名文件）与三份开发者文档
$Items = @(
    'SKILL.md',
    'assets',
    'references',
    'build-html.py',
    'count-body.ps1',
    'verify-bom.ps1',
    '自检.ps1'
)

function Get-RelFiles([string]$base, [string[]]$items) {
    $out = @()
    foreach ($it in $items) {
        $p = Join-Path $base $it
        if (-not (Test-Path $p)) { continue }
        if ((Get-Item $p).PSIsContainer) {
            Get-ChildItem $p -Recurse -File | ForEach-Object {
                $out += $_.FullName.Substring($base.Length + 1)
            }
        } else {
            $out += $it
        }
    }
    return $out | Sort-Object -Unique
}

$rel = Get-RelFiles $Src $Items

if ($Mode -eq 'check') {
    $bad = @()
    foreach ($f in $rel) {
        $a = Join-Path $Src $f
        $b = Join-Path $Root $f
        if (-not (Test-Path $b)) { $bad += "根目录缺：$f"; continue }
        if ((Get-FileHash $a -Algorithm MD5).Hash -ne (Get-FileHash $b -Algorithm MD5).Hash) { $bad += "内容不同：$f" }
    }
    # 根目录多出的（本不该存在的同名镜像文件）
    foreach ($f in $rel) {
        $b = Join-Path $Root $f
        if (Test-Path $b) {
            $a = Join-Path $Src $f
            if (-not (Test-Path $a)) { $bad += "根目录多出：$f" }
        }
    }
    if ($bad.Count) {
        Write-Host "RESULT: root mirror out of sync ($($bad.Count))" -ForegroundColor Red
        $bad | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
        Write-Host "  修复：.\sync-root.ps1" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "RESULT: root mirror in sync ($($rel.Count) files)" -ForegroundColor Green
    exit 0
}

# ---- sync ----
$n = 0
foreach ($f in $rel) {
    $a = Join-Path $Src $f
    $b = Join-Path $Root $f
    $dir = Split-Path $b -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $need = $true
    if (Test-Path $b) {
        if ((Get-FileHash $a -Algorithm MD5).Hash -eq (Get-FileHash $b -Algorithm MD5).Hash) { $need = $false }
    }
    if ($need) { Copy-Item $a $b -Force; $n++ }
}
Write-Host "=== 根目录镜像已更新 ==="
Write-Host ("  源      : skills/industry-scope-router/")
Write-Host ("  目标    : 仓库根")
Write-Host ("  条目    : {0} 个（本次更新 {1} 个）" -f $rel.Count, $n)
Write-Host ""
Write-Host "  根目录现有（与技能相关的）:"
$rel | ForEach-Object { Write-Host ("    " + $_) }

# 校验根级 SKILL.md 的 YAML frontmatter（TRAE 的硬要求）
$sk = Join-Path $Root 'SKILL.md'
$lines = [System.IO.File]::ReadAllLines($sk, [System.Text.UTF8Encoding]::new($false))
$fmOk = ($lines[0].Trim() -eq '---')
$hasName = $false; $hasDesc = $false; $closed = $false
for ($i = 1; $i -lt [Math]::Min(40, $lines.Count); $i++) {
    if ($lines[$i].Trim() -eq '---') { $closed = $true; break }
    if ($lines[$i] -match '^name:\s*\S') { $hasName = $true }
    if ($lines[$i] -match '^description:') { $hasDesc = $true }
}
Write-Host ""
Write-Host "=== 根级 SKILL.md frontmatter 校验（TRAE 要求）==="
Write-Host ("  以 --- 开头        : " + $(if ($fmOk) { 'OK' } else { '★失败' }))
Write-Host ("  含 name:           : " + $(if ($hasName) { 'OK' } else { '★失败' }))
Write-Host ("  含 description:    : " + $(if ($hasDesc) { 'OK' } else { '★失败' }))
Write-Host ("  frontmatter 已闭合 : " + $(if ($closed) { 'OK' } else { '★失败' }))

if (-not ($fmOk -and $hasName -and $hasDesc -and $closed)) {
    Write-Host "RESULT: root SKILL.md frontmatter invalid" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: root SKILL.md valid for TRAE" -ForegroundColor Green
exit 0
