param(
    [string]$OutDir = '',
    [switch]$NoSkill
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# build-package.ps1 —— 产出可给 TRAE 等工具直接安装的包
#
# TRAE 的要求：**包含根级 SKILL.md 的 zip 或 .skill 文件**，且 SKILL.md 内要有
# YAML 格式的 name 与 description。本仓库根目录已镜像了一份 SKILL.md（见 sync-root.ps1），
# 因此整个仓库打成的 zip / .skill 都满足该要求。
#
# 用法：
#   .\build-package.ps1                    产出到仓库父目录
#   .\build-package.ps1 -OutDir D:\dist     指定输出目录
#   .\build-package.ps1 -NoSkill            只出 zip

$Root = $PSScriptRoot
if (-not $OutDir) { $OutDir = Split-Path $Root -Parent }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

# 版本号取自 plugin.json
$pj = Join-Path $Root 'plugin.json'
$ver = ([regex]::Match([System.IO.File]::ReadAllText($pj, [System.Text.UTF8Encoding]::new($false)), '"version"\s*:\s*"([^"]+)"')).Groups[1].Value
if (-not $ver) { Write-Host 'RESULT: 读不到版本号' -ForegroundColor Red; exit 2 }

$baseName = "industry-scope-router-v$ver"
$stage = Join-Path $env:TEMP ("isr-pack-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$stageDir = Join-Path $stage 'industry-scope-router'
New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

Write-Host '=== 1. 暂存（排除 .git / __pycache__ / 输出目录）==='
Get-ChildItem $Root -Force | Where-Object { $_.Name -notin @('.git', '__pycache__') } | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $stageDir $_.Name) -Recurse -Force
}
$n = @(Get-ChildItem $stageDir -Recurse -File).Count
Write-Host ("  暂存文件数 = {0}" -f $n)

Write-Host ''
Write-Host '=== 2. 打包前校验根级 SKILL.md（TRAE 硬要求）==='
$sk = Join-Path $stageDir 'SKILL.md'
if (-not (Test-Path $sk)) {
    Write-Host '  ★根级 SKILL.md 不存在 —— 先跑 .\sync-root.ps1' -ForegroundColor Red
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
$lines = [System.IO.File]::ReadAllLines($sk, [System.Text.UTF8Encoding]::new($false))
$fmOk = $lines.Count -gt 3 -and $lines[0].Trim() -eq '---'
$hasName = $false; $hasDesc = $false; $closed = $false
if ($fmOk) {
    for ($i = 1; $i -lt [Math]::Min(40, $lines.Count); $i++) {
        if ($lines[$i].Trim() -eq '---') { $closed = $true; break }
        if ($lines[$i] -match '^name:\s*\S') { $hasName = $true }
        if ($lines[$i] -match '^description:\s*\S') { $hasDesc = $true }
    }
}
Write-Host ("  --- 开头={0}  name={1}  description={2}  已闭合={3}" -f $fmOk, $hasName, $hasDesc, $closed)
if (-not ($fmOk -and $hasName -and $hasDesc -and $closed)) {
    Write-Host '  ★frontmatter 不合规，TRAE 会拒绝' -ForegroundColor Red
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
    exit 1
}
Write-Host '  OK 可被 TRAE 识别' -ForegroundColor Green

Write-Host ''
Write-Host '=== 3. 生成 zip 与 .skill ==='
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $OutDir "$baseName.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip)
Write-Host ("  {0}  ({1:N1} KB)" -f (Split-Path $zip -Leaf), ((Get-Item $zip).Length / 1KB))

$skill = Join-Path $OutDir "$baseName.skill"
if (-not $NoSkill) {
    if (Test-Path $skill) { Remove-Item $skill -Force }
    Copy-Item $zip $skill
    Write-Host ("  {0}  ({1:N1} KB)  ← 与 zip 同内容，仅扩展名不同" -f (Split-Path $skill -Leaf), ((Get-Item $skill).Length / 1KB))
}

Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ''
Write-Host ("RESULT: package built (v{0}, {1} files)" -f $ver, $n) -ForegroundColor Green
exit 0
