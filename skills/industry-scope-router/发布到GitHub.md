# 发布到 GitHub：让用户一条命令安装

> 本文档是**发布者操作手册**。核对了 `skills` CLI 官方 README（Vercel Labs，2026-03 快照）并**在本机实测通过**。
> 对应技能：`industry-deep-research`（也可用同样方式发布 `industry-lifecycle-analyzer`）。

---

## 一、先明确一件事：DSH 没有内建 GitHub 安装器

| 工具 | 能否 `install from github` | 实际机制 |
|---|---|---|
| **CodeBuddy / Claude Code / Cursor / Codex 等 80 个 agent** | ✅ 能 | 社区标准 CLI `npx skills add <owner>/<repo>`，支持 `-a` 指定 agent |
| **DSH（DeepSeek Harness）** | ❌ 无内建命令 | 只扫本地技能目录（源码核实：**4 个根**，见第十节）。CLI 的共享落点 `~/.agents/skills/` 恰好在扫描列表内（rank 500），所以**能借道，但不如直接放进 `~/.dsh/skills/` 稳** |

**⚠️ 三个必须说清的坑**（源码核实 + 实测）：

1. **`~/.codebuddy/skills/` DSH 完全不扫描**（源码里没有这个根）。"用 CLI 装到 codebuddy，DSH 也能用"是**错的**——两件事互不相通。
2. **同名时 `~/.dsh/skills`（rank 400）会静默压制 `~/.agents/skills`（rank 500）**。所以从 CLI 装进 `.agents` 后，如果你本地 `.dsh` 里有同名技能，**行为与你刚装的那份无关**，且不会有任何提示。
3. **装到哪≠哪都能用**：给 DSH 就装 `~/.dsh/skills/`，给 WorkBuddy 就装 `~/.codebuddy/skills/`。想两边都有，就装两次（或用 CLI 的 `-a codebuddy -a codex` 一次装到两个目标）。

---

## 二、三条安装路径（按用户类型）

### 路径 A：CodeBuddy / WorkBuddy 用户（一行命令）

```bash
npx skills add <你的用户名>/<仓库名> --skill industry-deep-research -g -a codebuddy -y
```

装到 `~/.codebuddy/skills/industry-deep-research/`（或共享的 `~/.agents/skills/`，CLI 会选共享位置再链接过去）。

### 路径 B：DSH 用户（两种都行）

**B1 一行命令**（复用 CLI，装到 DSH 也扫的 `~/.agents/skills/`）：

```bash
### 路径 B：DSH 用户（**推荐 B2 纯 git，直接装进 `.dsh`**）

**B2 纯 git 方式**（零 Node 依赖，直接落到 DSH 扫描的 rank 400 目录，**没有同名压制问题**）：

```bash
# macOS / Linux
git clone --depth 1 https://github.com/<你的用户名>/<仓库名>.git /tmp/ids \
  && cp -r /tmp/ids/skills/industry-deep-research ~/.dsh/skills/ \
  && rm -rf /tmp/ids
```

```powershell
# Windows PowerShell —— 含防覆盖判重（不要用 Move-Item，见下方警告）
$Stage = Join-Path $env:TEMP ("ids-" + [guid]::NewGuid().ToString("N").Substring(0,8))
git clone --depth 1 https://github.com/<你的用户名>/<仓库名>.git (Join-Path $Stage "repo")
if ($LASTEXITCODE -ne 0) { throw "clone 失败，未改动任何现有技能" }
$src = Join-Path $Stage "repo\skills\industry-deep-research"
$dst = Join-Path $env:USERPROFILE ".dsh\skills\industry-deep-research"
if (Test-Path $dst) { Write-Warning "已存在，跳过（不覆盖）: $dst" }
else { Copy-Item $src $dst -Recurse }
Remove-Item $Stage -Recurse -Force
```

> ⚠️ **别用 `Move-Item` 当防覆盖守卫**：目标已存在时它**不报错**，而是把源目录**嵌套**进去，产生 `dst\industry-deep-research\SKILL.md` 这种多一层的垃圾结构——技能能加载但目录已污染。必须用 `Test-Path` 显式判重。

**B1 借道 CLI**（如果用户已有 Node，可用；但注意落点是 rank 500）：

```bash
npx skills add <你的用户名>/<仓库名> --skill industry-deep-research -g -a codex -y --copy
```

> 用 `-a codex` 是因为它指向共享的 `.agents/skills/`。**CLI 不认识 `-a dsh`**（DSH 不在它的 agent 列表里）。
> ⚠️ 落到 `.agents/skills`（rank 500）后，若 `~/.dsh/skills` 有同名技能会**被静默压制**。所以只在你确定本地没有同名技能时用这条。

### 路径 C：只想用提示词、不装技能

让用户打开仓库里的 `skills/industry-deep-research/单文件通用版提示词.md`，**在 GitHub 页面上直接复制**（点文件右上角 Raw 更稳），粘进任何支持联网的 AI。这条路径**不需要装任何东西**，是获取门槛最低的。

---

## 三、仓库结构（已实测可被 `npx skills add` 发现）

CLI 的发现规则：在这些容器目录里**向下走最多 3 层**找 `SKILL.md`——`skills/`、`.agents/skills/`、`.claude/skills/`、`.codebuddy/skills/`、`.dsh/skills/` 等。**推荐用 `skills/`**：

```
<仓库名>/
├── README.md                          ← 仓库门面：介绍 + 一行安装命令（见第五节模板）
├── LICENSE                            ← 建议 MIT
├── .gitattributes                     ← 保护 .ps1 的 BOM（见第六节）
└── skills/
    ├── industry-deep-research/
    │   ├── SKILL.md                   ← 必须，含 name + description frontmatter
    │   ├── README.md
    │   ├── 使用说明.md
    │   ├── 单文件通用版提示词.md
    │   ├── 自检.ps1
    │   ├── references/ ×3
    │   └── assets/ ×1
    └── industry-lifecycle-analyzer/    ← 同一仓库可以放多个技能
        └── ...
```

**⚠️ 三个硬要求**

1. **`SKILL.md` 的 frontmatter 必须有 `name` 和 `description`**，`name` 全小写 kebab-case——否则 CLI 报 "No skills found"，DSH 也会拒绝加载。
2. **技能文件夹要整个提交**，不能只提交 `SKILL.md`——它引用 `references/` 和 `assets/`。
3. **不要把一个技能拆到仓库根目录的散文件里**。如果你只发布一个技能，也可以直接把技能内容放在仓库根（根目录有 `SKILL.md` 就是合法单技能仓库），但**`skills/<name>/` 布局更好**：便于以后加技能、也让 `repo` 与 `skill 名` 解耦。

---

## 四、发布步骤

```bash
# 1. 建仓库（本地）
mkdir industry-skills && cd industry-skills
git init
mkdir -p skills
# 把技能文件夹拷进 skills/
cp -r /path/to/industry-deep-research skills/
# 补仓库门面文件
# README.md / LICENSE / .gitattributes（见第五、六节）

# 2. 提交并推送
git add -A
git commit -m "feat: add industry-deep-research skill"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main

# 3. 打标签（便于用户锁定版本，也让 skills update 有据可依）
git tag -a v1.0.0 -m "industry-deep-research v1.0.0"
git push --tags
```

**发布后自检（用你自己的仓库当远端跑一遍）**：

```bash
npx skills add <你的用户名>/<仓库名> --list      # 应列出技能名与描述
```

---

## 五、仓库 README 模板（复制到仓库根 `README.md`）

> 注意：这与技能文件夹里的 `README.md` 不是同一份——技能内那份是"接收方使用说明"，这份是**仓库门面**。

```markdown
# 行业调研 Agent Skills

一组用于行业研究的 Agent Skills，遵循 [Agent Skills 规范](https://agentskills.io)。

## 安装

### Claude Code / CodeBuddy / Cursor / Codex 等

    npx skills add <你的用户名>/<仓库名> -g -y

### DeepSeek Harness（DSH）

    npx skills add <你的用户名>/<仓库名> --skill industry-deep-research -g -a codex -y --copy
    # 或纯 git：
    git clone --depth 1 https://github.com/<你的用户名>/<仓库名>.git /tmp/ids
    cp -r /tmp/ids/skills/industry-deep-research ~/.dsh/skills/

### 不装任何工具

打开 `skills/industry-deep-research/单文件通用版提示词.md`，整段复制粘进任意**支持联网**的 AI。

## 包含的技能

| 技能 | 用途 |
|---|---|
| `industry-deep-research` | 输入「行业，特别关注点」，产出带来源标注、双源核验、冲突并列、信息缺口清单的深度调研报告 |
| `industry-lifecycle-analyzer` | 判断行业处于导入/成长/成熟/衰退期（五指标投票 + 渗透率校准） |

## 这两套技能的特点

- **不编数据**：查不到就写"未披露/待验证"，并标明检索范围
- **关键数字双源印证**，单一来源标"待核实"
- **来源冲突并列展示**，不取平均值
- **每个核心判断给反面证据**，找不到就明说并下调置信度
- **报告末尾附信息缺口清单**：缺什么、影响哪个结论、下次怎么查

## 许可

MIT
```

---

## 六、`.gitattributes`（保护 PowerShell 脚本的 BOM）

`自检.ps1` 的中文如果没有 BOM，Windows PowerShell 5.1 会按 GBK 解析并语法报错。加一行防止 Git 在检出时改动编码：

```gitattributes
*.ps1 text working-tree-encoding=UTF-8 eol=crlf
*.md  text eol=lf
```

---

## 七、更新与版本

| 场景 | 做法 |
|---|---|
| 改了技能内容 | `git commit && git push`；用户 `npx skills update industry-deep-research` 即可拉新版 |
| 想发大版本 | `git tag -a v1.1.0 -m "..."` 并 push tags；README 里可注明"锁定版本请用 `@v1.0.0`" |
| 用户手工装的（git clone / 拷文件夹） | 没有自动更新，需要重新 clone 或覆盖文件夹。**建议在仓库 README 里说明这一点** |

---

## 八、发布前检查清单

- [ ] `SKILL.md` frontmatter 的 `name` 是全小写 kebab-case，且与文件夹名一致
- [ ] `description` ≤ 500 字符（超了会被模型目录截断，触发词丢失）
- [ ] **`description` 里的触发词要同时覆盖"名词"和"动词"**（见下方 8.1）
- [ ] 技能文件夹里 `references/`、`assets/` 全部提交（不是只提交 SKILL.md）
- [ ] 仓库根 README 写明**三种安装方式**（CLI / git / 只用提示词）
- [ ] 加了 `LICENSE`
- [ ] 加了 `.gitattributes` 保护 `.ps1`
- [ ] 本地跑过技能自检：`& .\skills\industry-deep-research\自检.ps1`，退出码 0
- [ ] **推送后**跑 `npx skills add <owner>/<repo> --list`，确认能列出技能
- [ ] 在干净环境（另一台机器或新用户）实测一次安装命令
- [ ] **用真实提问实测触发**（不是看描述写没写，而是看技能加载没加载，见 8.2）

### 8.1 触发词要覆盖动词，不只是名词

**实测教训**：`description` 里写了"产业链"这个名词，但用户问"**研究**中国光伏产业链，**找出**……"时技能**没有被加载**；换成"**帮我调研一下**中国光伏产业链"就加载了。

原因：`description` 当时列的全是"行业调研 / 深度调研 / 行业分析 / 评估 X 行业"，**唯独没有裸的"研究 X"**。模型匹配的是**用户会怎么问**，不是**这个技能是干什么的**。

写 description 时逐条问自己：

| 问法类型 | 示例 | 你的描述里有吗 |
|---|---|---|
| 名词类 | 行业调研、产业链、利润池、技术壁垒 | ? |
| **动词类** | **研究** X 行业、**调研**一下 X、**分析** X、**评估** X、**看看** X | ? |
| 句式类 | X 能不能投、X 值不值得做、X 前景如何 | ? |
| 结构类 | "行业，关注点"式输入 | ? |

**动词类最容易漏**——因为写描述时人在想"我的技能做什么"，而用户在说"你帮我做点什么"。

### 8.2 怎么验证触发真的生效（不能靠猜）

光看描述写得好不好没用，要看**技能加载没加载**。查会话记录：

```powershell
# 会话文件：<dshHome>\sessions\<工作目录转义名>\<sessionId>\session.v4.jsonl.zstd
# 是 266+ 个拼接的 zstd 帧，需逐帧解压（用 engine.bytesWritten 推进）
```

判断依据（按可靠性排序）：

1. **会话里出现技能的实质内容**——例如本技能特有的规则句（"必产出的三样"）。**出现 = 真加载了**
2. 出现 `Base directory for this skill` 字样 = 加载了
3. 报告里出现**技能专属**产物（结构图、矩阵、三情景）= 大概率加载了
4. ❌ **不能只看"待核实"这类标注判断**——那是通用好习惯，没加载也会写

### 8.3 ⚠️ 行数统计陷阱（PowerShell 对中文文件会少算）

用 `Get-Content <中文文件> | Measure-Object` 数行数会**严重少算**：

```
同一文件：PowerShell 报 74 行，字节级 LF 计数为 110 行
```

实测复现过多次。**校验行数请用字节级计数**：

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$n = 0; foreach ($b in $bytes) { if ($b -eq 10) { $n++ } }
$n
```

或直接数换行符：`([regex]::Matches($text, "`n")).Count`。**别用 `Get-Content | Measure-Object` 做行数验收。**

---

## 九、⚠️ 装完必须验证（否则可能"装了个寂寞"）

**这是发布者最容易忽略、用户最容易踩的一点**：仓库结构不规范时，安装命令**不会报错**——退出码 0、提示 "Installation complete"，但技能根本没被识别。

### 为什么会静默失败

DSH 对不合规的 `SKILL.md` 只写进程日志警告、然后**忽略该技能**，不向用户报错：

```
skill file ...\SKILL.md ignored: missing YAML frontmatter
skill file ...\SKILL.md ignored: frontmatter requires name and description
skill file ...\SKILL.md ignored: invalid YAML frontmatter: <yaml 错误>
skill file ...\SKILL.md ignored: invalid skill name "<原样名字>"
```

唯一会真抛错的情况是 `description` 存在但为空串。

### 发布者自查清单（推送后逐条过）

- [ ] 仓库里 `SKILL.md` 位于 `skills/<name>/SKILL.md`（**深度 2**）。DSH 的 watcher 只覆盖"技能根 + 下一级"，**深度 ≥3 的 `skills/a/b/SKILL.md` 永远不会被发现——这不是重启能救的**
- [ ] frontmatter 有 `name`（全小写 kebab-case，匹配 `/^[a-z0-9]+(?:-[a-z0-9]+)*$/`）与 `description`（**非空**、≤500 字符）
- [ ] `name` 与文件夹名一致
- [ ] 用**干净环境**实测一次：`npx skills add <owner>/<repo> --list` 能列出技能名与描述（这一步会 clone 真实远端，能验证 `.gitignore` 没误排除文件）
- [ ] 装完后在目标 agent 里确认技能**出现在技能清单中**，而不只是命令回了 "Installation complete"

### 给用户的验证话术（写进 README）

> 装完请确认技能**出现在你的 AI 工具的技能列表里**。如果命令提示成功但列表里没有，多半是 `SKILL.md` 的 frontmatter 不合规——把报错贴给我。

---

## 十、各 agent 的实际扫描路径（源码核实，2026-10）

**DSH 只扫描这 4 个根**（同一层内 rank 小者胜，同名时 rank 小的静默压制 rank 大的）：

| 根 | rank | 说明 |
|---|---|---|
| `<项目>/.dsh/skills` | 100 | 项目级，最高优先级 |
| `<项目>/.agents/skills` | 200 | 项目级 |
| `customSkillDirs`（profile 配置） | 300 | 需配置 |
| **`%USERPROFILE%\.dsh\skills`** | **400** | 用户级，推荐安装目标 |
| `%USERPROFILE%\.agents\skills` | 500 | 用户级，CLI 的共享位置 |

**关键推论**：

- ⚠️ **`~/.codebuddy/skills/` DSH 完全不扫描**（源码里没有这个根）。所以"用 CLI 装到 codebuddy 再指望 DSH 也能用"是**错的**——那两件事互不相通
- 用 `-a codex` 装到 `~/.agents/skills`（rank 500）**DSH 能用**；但若 `~/.dsh/skills`（rank 400）里有同名技能，**会被静默压制**，表现为"装成功了但行为和预期不一样"
- 想给 DSH 装，最稳的是**直接放进 `~/.dsh/skills/`**，不要绕

---

## 十一、安全提示（值得写进 README）

Skill 会让 AI 按仓库里的指令行动——**这本质上是在执行别人写的提示词**。建议在 README 里明确一句：

> 本仓库的技能只包含研究流程指令与报告模板，**不含任何安装脚本、不发起网络请求、不读写本地文件**（唯一的本地脚本 `自检.ps1` 仅用于校验技能自身结构，可选、只读）。技能运行时使用的联网检索由你的 AI 工具自身提供。

这条声明对建立信任很有用——尤其 `自检.ps1` 会让谨慎的用户犹豫，说清它做什么能消除顾虑。

### 官方 CLI 自己也会打这句警告

装第三方技能时 `skills` CLI 会输出：

> **Done! Review skills before use; they run with full agent permissions.**

把它抄进你的 README 是好事——**主动提醒用户审查，比假装没有风险更能建立信任**。另外值得说清：DSH 侧**没有安装技能的授权弹窗**，所以"能不能装"完全由用户的文件沙箱策略决定（`workspace-write` 策略下写用户级技能目录会触发审批或被拒），**"装完之后要不要信任"则是用户自己的判断，没有任何机制替他拦一道**。
