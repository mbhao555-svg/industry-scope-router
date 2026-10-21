param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path,
    [ValidateSet('industry', 'chain', 'mixed')]
    [string]$Type = 'industry',
    [int]$Floor = 0,
    [int]$Ceil = 0
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# count-body.ps1 — 实测报告「正文汉字数」，用于 6.4.1 的体量门槛
#
# 用途：把「正文体量门槛」变成可测量的检查，而不是只写在文档里的要求。
# 计数口径（与 report-template.md 6.4.1 一致）：
#   计入：摘要 + 正文各节 + 表格中的分析性内容 + 图注说明
#   不计入：附录 A–D、方法与数据来源说明、来源清单、原文摘录、代码块、验收记录
#
# 用法：
#   .\count-body.ps1 报告.md                        # 按行业版默认门槛判定
#   .\count-body.ps1 -Path 报告.md -Type chain      # 产业链版
#   .\count-body.ps1 -Path 报告.md -Type mixed      # 混合版
#   .\count-body.ps1 -Path 报告.md -Floor 8000 -Ceil 15000   # 自定义门槛
#
# 退出码：0 = 达标（或允许偏差内）；1 = 不达标；2 = 文件问题

$thresholds = @{
    industry = @{ Floor = 8000;  Ceil = 15000; Label = '行业调研报告' }
    chain    = @{ Floor = 8000;  Ceil = 15000; Label = '产业链调研报告' }
    mixed    = @{ Floor = 12000; Ceil = 20000; Label = '混合报告' }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Write-Host "RESULT: 文件不存在 — $Path" -ForegroundColor Red
    exit 2
}

$t = $thresholds[$Type]
if ($Floor -le 0) { $Floor = $t.Floor }
if ($Ceil -le 0) { $Ceil = $t.Ceil }

$raw = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path, [System.Text.UTF8Encoding]::new($false))
$lines = $raw -split "`r?`n"

# 切掉不计入区：附录 / 方法与数据来源说明 / 来源清单
$stopAt = @()
for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^##\s*(附录\s*[A-Z]|方法与数据来源说明|来源清单|信息源清单)') { $stopAt += $i }
}
$bodyEnd = if ($stopAt.Count) { ($stopAt | Measure-Object -Minimum).Minimum } else { $lines.Count }
$body = @($lines[0..($bodyEnd - 1)])

# 去掉代码块（``` 围栏内不计）
$kept = @()
$inFence = $false
foreach ($ln in $body) {
    if ($ln -match '^\s*```') { $inFence = -not $inFence; continue }
    if (-not $inFence) { $kept += $ln }
}

# 去掉 markdown 结构符号，只留内容
$clean = ($kept -join "`n")
$clean = $clean -replace '(?m)^\s*#{1,6}\s*', ''          # 标题井号
$clean = $clean -replace '(?m)^\s*>\s?', ''                # 引用
$clean = $clean -replace '(?m)^\s*[-*+]\s+', ''            # 列表符
$clean = $clean -replace '(?m)^\s*\d+\.\s+', ''            # 有序列表
$clean = $clean -replace '\*\*|__|\*|~~|`', ''             # 强调与行内代码
$clean = $clean -replace '\[([^\]]*)\]\([^\)]*\)', '$1'     # 链接留文字
$clean = $clean -replace '(?m)^\s*\|?[\s:\-\|]+\|?\s*$', '' # 表格分隔行
$clean = $clean -replace '\|', ' '                         # 表格竖线

# 只数中日韩统一表意文字 + 中文标点
$han = ([regex]::Matches($clean, '[\u4e00-\u9fff\u3400-\u4dbf]')).Count
$punct = ([regex]::Matches($clean, '[\uff00-\uffef\u3000-\u303f]')).Count
$total = $han + $punct

Write-Host ''
Write-Host '=== 正文体量实测 ==='
Write-Host ("  文件            : {0}" -f (Split-Path $Path -Leaf))
Write-Host ("  报告类型        : {0}（门槛 {1}–{2} 汉字）" -f $t.Label, $Floor, $Ceil)
Write-Host ("  正文范围        : 第 1–{0} 行（附录与方法说明已排除）" -f $bodyEnd)
Write-Host ("  汉字            : {0}" -f $han)
Write-Host ("  中文标点        : {0}" -f $punct)
Write-Host ("  正文合计        : {0} 个中文字符" -f $total)
Write-Host ''

$diff = $Floor - $total
$ok = ($total -ge $Floor) -and ($total -le $Ceil)

if ($total -gt $Ceil) {
    Write-Host ("RESULT: 超出上限 {0} 字 — 检查重复结论与同义改写，不得为凑篇幅补无效解释" -f ($total - $Ceil)) -ForegroundColor Yellow
    exit 1
}
elseif ($total -ge $Floor) {
    $pct = [math]::Round(($total / $Floor - 1) * 100, 1)
    Write-Host ("RESULT: 达标（高于下限 {0}%）" -f $pct) -ForegroundColor Green
    exit 0
}
else {
    $gapPct = [math]::Round($diff / $Floor * 100, 1)
    if ($gapPct -le 10) {
        Write-Host ("RESULT: 低于下限 {0} 字（差距 {1}%，≤10%）— 可在记录偏差后交付" -f $diff, $gapPct) -ForegroundColor Yellow
        Write-Host '        须在《方法与数据来源说明》写明实际字数并说明实质分析已完整' -ForegroundColor Yellow
        exit 0
    }
    Write-Host ("RESULT: 不达标 — 低于下限 {0} 字（差距 {1}%，>10%）" -f $diff, $gapPct) -ForegroundColor Red
    Write-Host '        不得作为完整报告交付；先逐项复查补足被压缩的核心能力' -ForegroundColor Red
    Write-Host '        仍不足则降级为「有限披露报告」并在封面标明' -ForegroundColor Red
    exit 1
}
