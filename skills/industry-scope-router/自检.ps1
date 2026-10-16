# industry-scope-router 技能自检
#
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File .\自检.ps1
# 退出码：0 全过；1 有失败
#
# ⚠️ 本文件必须存为 UTF-8 带 BOM。PowerShell 5.1 读无 BOM 的中文脚本会按 GBK 解析并语法报错。

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$pass = 0; $fail = 0; $failures = @()

function Assert {
    param([string]$Name, $Ok, [string]$Detail = '')
    if ([bool]$Ok) { $script:pass++ }
    else {
        $script:fail++
        $script:failures += "$Name$(if ($Detail) { "  →  $Detail" })"
        Write-Host "  [FAIL] $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkRed }
    }
}
function Read-Utf8 { param([string]$Path) [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)) }
function Has { param([string]$Text, [string]$Pattern) [bool]($Text -match $Pattern) }
function CountOf { param([string]$Text, [string]$Pattern) ([regex]::Matches($Text, $Pattern)).Count }

Write-Host ''
Write-Host '==== industry-scope-router 技能自检 ====' -ForegroundColor Cyan
Write-Host "技能目录：$Root"
Write-Host ''

# ---------- A. 自身编码与文件 ----------
Write-Host '[A] 自身编码与文件'
$selfPath = $MyInvocation.MyCommand.Path
if (-not $selfPath) { $selfPath = Join-Path $Root '自检.ps1' }
$sb = [System.IO.File]::ReadAllBytes($selfPath)
$hasBom = $sb.Length -ge 3 -and $sb[0] -eq 0xEF -and $sb[1] -eq 0xBB -and $sb[2] -eq 0xBF
Assert '自检.ps1 自身为 UTF-8 带 BOM' $hasBom 'BOM 丢失会让 PowerShell 5.1 按 GBK 解析中文并语法报错'
$skillPath = Join-Path $Root 'SKILL.md'
Assert 'SKILL.md 存在' (Test-Path $skillPath)

# ---------- A2. 技能引用的资源必须真实存在 ----------
Write-Host '[A2] 引用资源存在性'
# ⚠️ 这条防的是一类真错误：SKILL.md 里写了 references/xxx，但那个文件没跟着复制到技能目录
#    —— 技能运行时会解析不到，而自检此前也不会报错
foreach ($r in @('references\行业与产业-定义.md', 'references\两类报告-定义.md')) {
    Assert ("引用资源存在：$r") (Test-Path (Join-Path $Root $r)) 'SKILL.md 引用了它，但文件不在技能目录里'
}
if (-not (Test-Path $skillPath)) { Write-Host '缺少 SKILL.md'; exit 1 }
$skill = Read-Utf8 $skillPath

# ---------- B. frontmatter ----------
Write-Host '[B] frontmatter'
$fm = [regex]::Match($skill, '(?s)\A---\r?\n(.*?)\r?\n---')
Assert 'frontmatter 存在且闭合' ([bool]$fm.Success)
if ($fm.Success) {
    $body = $fm.Groups[1].Value
    $nameM = [regex]::Match($body, '(?m)^name:\s*(.+)$')
    $descM = [regex]::Match($body, '(?m)^description:\s*(.+)$')
    Assert 'frontmatter 含 name' ([bool]$nameM.Success)
    Assert 'frontmatter 含 description' ([bool]$descM.Success)
    if ($nameM.Success) {
        $nm = $nameM.Groups[1].Value.Trim()
        Assert "name 合法（当前：$nm）" ([bool]($nm -match '^[a-z0-9]+(-[a-z0-9]+)*$'))
        Assert 'name 为 industry-scope-router' ($nm -eq 'industry-scope-router')
    }
    if ($descM.Success) {
        $dsc = $descM.Groups[1].Value.Trim()
        Assert "description 不超 500 字符（当前 $($dsc.Length)）" ($dsc.Length -le 500)
        Assert 'description 含触发场景' ((Has $dsc '当用户提到') -or (Has $dsc '当'))
    }
}

# ---------- C. 章节完整性 ----------
Write-Host '[C] 章节完整性'
foreach ($s in @('先分清：本技能不做什么','类型判定判据表','两种报告的结构骨架','术语禁写','强制规则：两层判断混用时必须声明','执行流程','输出格式','边界')) {
    Assert "含章节：$s" ((CountOf $skill ([regex]::Escape($s))) -ge 1)
}

# ---------- C. 跨文件交叉引用与语义一致性 ----------
Write-Host '[C] 跨文件交叉引用与语义一致性'
# 参照 industry-deep-research 的做法：不只看字样在不在，还要看跨文件是否一致、引用是否双向

# --- C1 资源文件双向一致：被引用的必须存在，存在的必须被引用 ---
$defA = Join-Path $Root 'references\行业与产业-定义.md'
$defB = Join-Path $Root 'references\两类报告-定义.md'
Assert '两份定义文件都存在' ((Test-Path $defA) -and (Test-Path $defB)) 'SKILL.md 引用了它们，缺一即运行期解析失败'
$refPaths = @([regex]::Matches($skill, 'references[/\\][^\s`）】|]+?\.md') | ForEach-Object { $_.Value -replace '\\', '/' } | Sort-Object -Unique)
Assert "SKILL.md 引用的资源文件数 >= 2（当前 $($refPaths.Count)）" ($refPaths.Count -ge 2)
foreach ($r in $refPaths) { Assert "引用路径存在：$r" (Test-Path (Join-Path $Root ($r -replace '/', '\'))) }
$resFiles = @(Get-ChildItem (Join-Path $Root 'references') -File -ErrorAction SilentlyContinue)
foreach ($f in $resFiles) {
    $rel = ($f.FullName.Replace($Root, '').TrimStart('\')) -replace '\\', '/'
    Assert "资源文件被引用：$rel" ([bool]($refPaths -contains $rel)) '存在但从未被 SKILL.md 引用，可能是遗留文件'
}

# --- C2 跨文件语义一致性：同一判据在 SKILL 与定义文件里必须一致 ---
$defText = (Read-Utf8 $defA) + "`n" + (Read-Utf8 $defB)
Assert 'SKILL 与定义文件都写明两轴正交' ((Has $skill '两轴正交') -and (Has $defText '正交')) '这是最核心的定义，两处必须一致'
Assert 'SKILL 与定义文件都声明不是包含关系' ((Has $skill '不是包含关系') -and (Has $defText '不是包含关系'))
Assert 'SKILL 与定义文件都写明单环节没有渗透率' ((Has $skill '单环节没有渗透率') -and (Has $defText '单环节没有渗透率'))
Assert '定义文件写明行业级数据不得用偏环节' (Has $defText '行业级数据不得直接用偏环节') '概念权威在定义文件'
Assert 'SKILL 含概念锚点（行业/产业各自的切法）' ((Has $skill '统计分类口径') -and (Has $skill '价值流转') -and (Has $skill '有产业，无行业'))
Assert '定义文件含核心口诀' ((Has $defText '这门生意') -and (Has $defText '这条链的位置')) '两类报告的核心区分'

# --- C3 阈值类数字全库唯一（防规则被改歪）---
$allText = $skill + "`n" + $defText
$thWin = @([regex]::Matches($allText, '不得超\s*(\d+)\s*字符') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert "引用块宽度阈值唯一（实测：$($thWin -join ' / ')）" ($thWin.Count -le 1)
$thCell = @([regex]::Matches($allText, '单元格本身\s*>\s*(\d+)\s*字符') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
Assert "单元格宽度阈值唯一（实测：$($thCell -join ' / ')）" ($thCell.Count -le 1)

# --- C4 负向一致性：禁写表之外不得出现被禁止的说法 ---
$i34 = $skill.IndexOf('术语禁写')
$i35 = $skill.IndexOf('过程性标注禁写')
$outside = if ($i34 -ge 0 -and $i35 -gt $i34) { $skill.Substring(0, $i34) + $skill.Substring($i35) } else { $skill }
Assert '禁写表之外未出现「行业产业链」' (-not (Has $outside '行业产业链'))
Assert '禁写表之外未出现「行业的上游」' (-not (Has $outside '行业的上游'))
# ---------- C5. 符号容错：标题里夹 emoji 也能被定位 ----------
Write-Host '[C5] 符号容错'
# ⚠️ 实测：标题 ### 3.7 🔴 口径分层 里的 emoji 让 `3\.7 口径分层` 匹配失败。
#    约定：断言引用带编号的小节标题时，须用 .{0,4} 跨过可能的符号。
$numHeads = @([regex]::Matches($skill, '(?m)^#{3,4}\s+(\d+\.\d+)[^\r\n]*') | ForEach-Object { $_.Groups[1].Value })
Assert "带编号的小节共 $($numHeads.Count) 个" ($numHeads.Count -ge 12)
foreach ($h in $numHeads) {
    $pat = [regex]::Escape($h) + '.{0,4}'
    Assert "小节 $h 可定位（容错 emoji）" ([bool]($skill -match ($pat + '\S')))
}

# ---------- D. 三层判定判据 ----------
Write-Host '[D] 三层判定判据'
Assert '第一层：显式词表' ((Has $skill '第一层：显式词') -and (Has $skill '产业链、产业、供应链、价值链、上下游') -and (Has $skill '行业、行业前景、行业格局'))
Assert '第二层：问题指向表（行业侧 5 项）' ((Has $skill '这个行业\*\*整体\*\*值不值得进') -and (Has $skill '渗透率多少、还有多少空间') -and (Has $skill '集中度如何、几家头部'))
Assert '第二层：问题指向表（产业链侧 5 项）' ((Has $skill '\*\*钱在哪一段\*\*') -and (Has $skill '哪一段有\*\*定价权\*\*') -and (Has $skill '某个\*\*零部件/材料/设备\*\*能否国产替代'))
Assert '先决条件核查的执行时机（须在判定前）' ((Has $skill '只要问题里出现了具体对象名') -and (Has $skill '不要等类型判出来') -and (Has $skill '在询问用户之前就把限制说出来'))
Assert '含由核查直接改类型的两种情形' ((Has $skill '由本核查直接改类型的两种情形') -and (Has $skill '选项 A 行业调研对本对象数据基础不足'))
Assert '询问模板含无代码前置说明' ((Has $skill '选项 A（行业调研）在数据上没有官方统计基础'))
Assert '第三层：先决条件核查（四步判据）' ((Has $skill '第三层：先决条件核查') -and (Has $skill '能否明确归入某个有效代码') -and (Has $skill '是否真是一条链') -and (Has $skill '改用替代拆法'))

# ---------- E. 询问逻辑 ----------
Write-Host '[E] 判不出时的询问逻辑'
Assert '含 4 个触发条件' ((Has $skill '问题\*\*笼统\*\*，两层都说得通') -and (Has $skill '只给了\*\*一个名称\*\*') -and (Has $skill '显式词\*\*冲突\*\*') -and (Has $skill '先决条件核查\*\*结论改变了类型\*\*'))
Assert '含标准询问模板（含三选项）' ((Has $skill 'A 行业调研') -and (Has $skill 'B 产业链调研') -and (Has $skill 'C 两者都要'))
Assert '询问模板含各自代价' ((Has $skill '报告会给出') -and (Has $skill '行业阶段、渗透率、集中度') -and (Has $skill '环节级利润分布、逐环节出清'))
Assert '含先决条件改变类型时的模板' ((Has $skill '没有对应代码') -and (Has $skill '行业调研报告在数据上不成立') -and (Has $skill '你确认吗'))
Assert '纪律：不要猜' ((Has $skill '不要猜') -and (Has $skill '一次问清，问一次'))

# ---------- F. 两种报告骨架 ----------
Write-Host '[F] 两种报告骨架'
Assert '含行业调研报告骨架（十一节 + 三附录）' ((Has $skill '3\.1 行业调研报告骨架') -and (Has $skill '三 行业阶段判定') -and (Has $skill '四 渗透率与空间') -and (Has $skill '五 竞争格局与集中度') -and (Has $skill '六 行业级壁垒与关键依赖') -and (Has $skill '七 区域分布') -and (Has $skill '九 机会点、进入门槛与竞争策略') -and (Has $skill '十一 行业级投资结论'))
Assert '含环节结构字段（11 个必填字段）' ((Has $skill '每环节结构字段') -and (Has $skill '认证与验证周期') -and (Has $skill '替代风险') -and (Has $skill '证据状态') -and (Has $skill '供需格局') -and (Has $skill '议价能力'))
Assert '含壁垒三层判断' ((Has $skill '壁垒的三层判断') -and (Has $skill '技术层') -and (Has $skill '规模层') -and (Has $skill '认证／渠道层') -and (Has $skill '利润再厚也不可持续'))
Assert '含国产替代字段（6 项）' ((Has $skill '国产替代字段') -and (Has $skill '卡点名称') -and (Has $skill '替代进度') -and (Has $skill '不得只说"存在卡脖子"'))
Assert '产业链骨架含技术壁垒与国产替代两节' ((Has $skill '五 技术壁垒与竞争壁垒') -and (Has $skill '六 关键零部件/材料与国产替代'))
Assert '必备产出含逐环节技术壁垒' (Has $skill '③ \*\*逐环节技术壁垒\*\*')
Assert '对照表含技术壁垒与国产替代' ((Has $skill '技术壁垒／竞争壁垒') -and (Has $skill '关键零部件与国产替代'))
Assert '含术语禁写 8 条' ((Has $skill '术语禁写（写报告时逐条核对）') -and (Has $skill '行业产业链') -and (Has $skill '产业增速') -and (Has $skill '自检\*\*：交稿前全文搜这 8 个禁写模式'))
Assert '含产业链调研报告骨架（十一节 + 三附录）' ((Has $skill '3\.2 产业链调研报告骨架') -and (Has $skill '一 链的界定与环节结构') -and (Has $skill '二 环节级利润分布') -and (Has $skill '五 技术壁垒与竞争壁垒') -and (Has $skill '六 关键零部件/材料与国产替代') -and (Has $skill '七 投资含义矩阵') -and (Has $skill '九 环节区域分布') -and (Has $skill '十一 环节级投资结论'))
Assert '含各自"必备产出（缺一即不合格）"' ((CountOf $skill '必备产出（缺一即不合格）') -ge 2)
# 原文写法是 **⚠️ 不要求的**（emoji 在粗体内），断言不写 emoji 位置以免脆断言
Assert '含各自"不要求的"清单' ((CountOf $skill '不要求的\*\*：') -ge 2) '两份骨架都须写明"不要求什么"，否则会混用两层'
Assert '含两者对照表' ((Has $skill '两者都用 / 都不用清单') -and (Has $skill '渗透率') -and (Has $skill '单环节没有渗透率'))
Assert '产业链报告禁止写行业阶段与渗透率' ((Has $skill '\*\*不给行业阶段标签\*\*') -and (Has $skill '\*\*渗透率不出现\*\*'))
Assert '产业链报告缺环节数据的处置' ((Has $skill '该环节结论不成立') -and (Has $skill '不得给可投性判断'))

# ---------- G. 混合报告强制规则 ----------
Write-Host '[G] 混合报告强制规则'
Assert '含实测教训（5/6 份混合未声明）' ((Has $skill '5 份是"混合报告"') -and (Has $skill '无一加过声明'))
Assert '含混合报告判定标准' ((Has $skill '什么算"混合报告"') -and (Has $skill '同时出现'))
Assert '含三种合规做法' ((Has $skill '纯行业报告') -and (Has $skill '纯产业链报告') -and (Has $skill '混合报告'))
Assert '含标准声明段（可直接复制）' ((Has $skill '关于本报告两个层面判断的关系') -and (Has $skill '两者不矛盾，也不可互相推导') -and (Has $skill '渗透率校准仅适用于行业层，未跨层套用到任何环节'))
Assert '含交稿前必查三项' ((Has $skill '交稿前必查三项') -and (Has $skill '类型明确吗') -and (Has $skill '把行业数据用到环节结论'))

# ---------- H. 边界与不重复 ----------
Write-Host '[H] 边界与不复制判据'
Assert '声明不复制判据' ((Has $skill '本技能不复制第三份') -and (Has $skill '不复制判据'))
Assert '指向判据所在技能' ((Has $skill 'industry-report-structure') -and (Has $skill 'industry-deep-research') -and (Has $skill 'industry-lifecycle-analyzer'))
Assert '声明两份定义权威' ((Has $skill '行业与产业-定义') -and (Has $skill '两类报告-定义') -and (Has $skill '以定义文件为准'))
Assert '输出结尾声明义务' ((Has $skill '本次调研的\*\*类型选择依据\*\*'))

# ---------- I. 输出格式 ----------
Write-Host '[I] 输出格式'
Assert '含路由确认格式' ((Has $skill '【调研类型】') -and (Has $skill '【判定依据】') -and (Has $skill '【先决条件】') -and (Has $skill '【将产出】'))
Assert '含交付物表' ((Has $skill '行业调研报告（3\.1 骨架）') -and (Has $skill '产业链调研报告（3\.2 骨架）'))

# ---------- I2. 节编号连续性 ----------
Write-Host '[I2] 节编号连续性'
$topNums = @()
foreach ($ln in ($skill -split "`r?`n")) { if ($ln -match '^##\s([一二三四五六七八九十]+)、') { $topNums += $Matches[1] } }
$expectNums = @('一','二','三','四','五','六','七')
$contOk = ($topNums.Count -eq $expectNums.Count)
if ($contOk) { for ($i = 0; $i -lt $expectNums.Count; $i++) { if ($topNums[$i] -ne $expectNums[$i]) { $contOk = $false } } }
Assert '顶级节编号连续无缺号' $contOk ("实际：" + ($topNums -join ' → '))

# ---------- D2. 先决条件核查判据（2.3） ----------
Write-Host '[D2] 先决条件核查判据（2.3）'
Assert '含正确判据（归属路径清晰度 + 统计可达性）' ((Has $skill '归属路径是否清晰 ＋ 目标行业统计是否可达') -and (Has $skill '问错了问题'))
Assert '含四步核查' ((Has $skill '① 有无专门代码？') -and (Has $skill '② 能否明确归入某个有效代码？') -and (Has $skill '③ 目标行业有无官方汇总数据？') -and (Has $skill '④ 该对象是否真是一条链？'))
Assert '明确无专门代码不等于不能出行业报告' ((Has $skill '不得直接判') -and (Has $skill '虾滑') -and (Has $skill '预制菜'))
Assert '含两条归属路径并存的处置规则' ((Has $skill '两条归属路径并存时怎么办') -and (Has $skill '取主归属') -and (Has $skill '分别标注两个版本的数字') -and (Has $skill '整个代码归属标'))
Assert '含归属清晰时直接产出行业报告' (Has $skill '直接产出行业报告')
Assert '改类型情形含争议与清晰两类' ((Has $skill '归属边界有争议') -and (Has $skill '归属清晰'))

# ---------- I3. 过程性标注与引用块排版 ----------
Write-Host '[I3] 过程性标注与引用块排版'
Assert '含过程性标注禁写清单' ((Has $skill '过程性标注禁写') -and (Has $skill '读者不需要知道') -and (Has $skill '括号里的内容如果换成'))
Assert '禁写清单含 6 类' ((Has $skill '应纳入，但有两处边界') -and (Has $skill '必须声明') -and (Has $skill '缺一即不合格') -and (Has $skill '条件节'))
Assert '含（推断）（估算）的规范处理' ((Has $skill '这类要保留但须规范') -and (Has $skill '不散落'))
Assert '含元信息块必须表格化' ((Has $skill '元信息块（类型／判定依据／先决核查）必须表格化') -and (Has $skill '挤在一个引用块里 9 行'))
Assert '含引用块宽度与行数纪律' ((Has $skill '不得超 150 字符') -and (Has $skill '引用块不超过 5 行连续') -and (Has $skill '不要一行塞多个要点') -and (Has $skill '引用块') -and (Has $skill '不享有长行豁免'))

# ---------- F3. 机会点与竞争策略 ----------
Write-Host '[F3] 机会点与竞争策略'
Assert '含 3.1.3 机会点与竞争策略' ((Has $skill '3\.1\.3 机会点、进入门槛与竞争策略') -and (Has $skill '新进入者的竞争策略'))
Assert '机会点表含六项字段' ((Has $skill '为什么是机会') -and (Has $skill '可投性') -and (Has $skill '当前竞争强度') -and (Has $skill '反面证据'))
Assert '置信度四档不得自造' (Has $skill '不得自造')
Assert '含四种竞争策略情形' ((Has $skill '巨头靠\*\*规模与成本\*\*领先') -and (Has $skill '巨头靠\*\*渠道与品牌\*\*领先') -and (Has $skill '巨头\*\*尚未覆盖\*\*的细分') -and (Has $skill '行业标准刚落地'))
Assert '竞争策略含四项输出要求' ((Has $skill '给出 2–3 条可行策略') -and (Has $skill '为什么这条路对巨头不划算') -and (Has $skill '所需资源') -and (Has $skill '失效条件'))
Assert '禁止只说差异化不说在哪' (Has $skill '那是空话')
Assert '必备产出含竞争策略' (Has $skill '机会点与竞争策略（含新进入者的可行路径）')

# ---------- I4. 口径分层 ----------
Write-Host '[I4] 口径分层'
Assert '含 3.7 口径分层节' ((Has $skill '3\.7 .{0,4}口径分层') -and (Has $skill '先判') -and (Has $skill '再决定'))
Assert '含三种情形（分层/真冲突/同源）' ((Has $skill '口径分层（不是冲突）') -and (Has $skill '真冲突') -and (Has $skill '同源（伪独立）'))
Assert '含三条必做动作' ((Has $skill '回溯到最早出处') -and (Has $skill '检查署名') -and (Has $skill '检查层级'))
Assert '含实测教训（500亿 vs 173.1亿）' ((Has $skill '无任何机构署名') -and (Has $skill '无署名转引'))
Assert '含术语禁写三条' ((Has $skill '两个冲突口径相差') -and (Has $skill '无机构署名') -and (Has $skill '不得直接跨层级比较或相减'))

# ---------- J. 排版 ----------
Write-Host '[J] 排版规范'
Assert '无 HTML 换行标签残留' (-not (Has $skill '<br\s*/?>'))
Assert '无对象替换字符（U+FFFC）' ((CountOf $skill ([string][char]0xFFFC)) -eq 0) '撰写时混入的不可见字符'
Assert '含表格行' ((CountOf $skill '(?m)^\|') -ge 20)
$fm2 = [regex]::Match($skill, '(?s)\A---\r?\n(.*?)\r?\n---')
$bodyOnly = if ($fm2.Success) { $skill.Substring($fm2.Index + $fm2.Length) } else { $skill }
Assert '正文单行不超 300 字符（frontmatter 除外）' ((CountOf $bodyOnly '(?m)^.{301,}$') -eq 0)

# ---------- F2. 区域分布与行业级壁垒 ----------
Write-Host '[F2] 区域分布与行业级壁垒'
Assert '行业骨架含行业级壁垒与关键依赖' ((Has $skill '六 行业级壁垒与关键依赖') -and (Has $skill '3\.1\.1 行业级壁垒与关键依赖'))
Assert '行业级壁垒含三问' ((Has $skill '技术壁垒（行业级）') -and (Has $skill '认证／验证周期（行业级）') -and (Has $skill '关键零部件／材料依赖'))
Assert '行业级壁垒含关键依赖字段表（6 项）' ((Has $skill '当前进口依赖度') -and (Has $skill '海外主导方') -and (Has $skill '国产替代进度') -and (Has $skill '不得只说"存在卡脖子"'))
Assert '行业级壁垒与产业链壁垒的区分写明' ((Has $skill '这门生意别人能不能进来抢') -and (Has $skill '具体卡在哪一环节') -and (Has $skill '两者不可互相替代'))
Assert '行业报告含区域分布条件节' ((Has $skill '3\.1\.2 区域分布（第七节，条件节）') -and (Has $skill '无集聚时写明') -and (Has $skill '不要留空节'))
Assert '行业级区域分布多答一个问题' (Has $skill '行业的地理集中度是否本身就是壁垒')
Assert '产业链含环节区域分布条件节' ((Has $skill '3\.2\.4 环节区域分布（第九节，条件节）') -and (Has $skill '单点依赖风险') -and (Has $skill '一地独占'))
Assert '区域分布四条填写纪律' ((Has $skill '规模列口径必须统一') -and (Has $skill '国家级头衔') -and (Has $skill '升级方向') -and (Has $skill '表下写 2–3 条横向结论'))
Assert '对照表含区域分布与技术壁垒两行' ((Has $skill '\*\*区域分布\*\*') -and (Has $skill '\*\*关键零部件与国产替代\*\*'))



# ---------- 结果 ----------
Write-Host ''
Write-Host '==== 结果 ====' -ForegroundColor Cyan
Write-Host ("通过 {0} 项，失败 {1} 项" -f $pass, $fail) $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) {
    Write-Host ''
    Write-Host '失败清单：' -ForegroundColor Red
    $i = 1
    foreach ($f in $failures) { Write-Host ("  {0}. {1}" -f $i, $f) -ForegroundColor Red; $i++ }
    exit 1
}
Write-Host '路由判据、两种骨架与混合声明规则均通过。' -ForegroundColor Green
exit 0





