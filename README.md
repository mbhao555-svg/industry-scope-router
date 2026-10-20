# industry-scope-router —— 行业 / 产业链 调研路由器

**先判层面 → 判不出就问 → 按类型出对应报告。** 自足技能：判据、模板、检索法、核验法、范例、守卫工具全部内置。

## 它回答的问题不一样

| | **行业调研** | **产业链调研** |
|---|---|---|
| 分析单位 | 行业（统计分类口径） | 产业链（价值流转） |
| 回答 | 这个行业**整体**值不值得进 | 这条链上**投哪一段、绕开哪一段** |
| 一句话 | 判**这门生意** | 判**这条链的位置** |

**行业与产业不是包含关系，而是两条正交的轴**——穿过同一批企业的两个不同坐标。

## 关键判据：先决条件核查（四步）

⚠️ 常见误解：以为"对象没有专门行业代码"就不能做行业报告。**这是错的。**

| | 预制菜 | 虾滑 |
|---|---|---|
| 专门代码 | 无 | 无 |
| **归属路径** | ⚠️ 边界有争议 | ✅ **清晰**（C136 水产品加工 / C1432 速冻食品制造） |
| **目标行业统计** | ⚠️ 模糊 | ✅ **两个行业都有官方统计** |
| 结论 | 行业报告数据基础不足 | ✅ **行业报告可行** |

**四步**：① 有无专门代码？无则继续 ② **能否明确归入有效代码？** ③ **目标行业有无官方统计？** ④ 是否真是一条链？

## 两种报告骨架

| | 行业调研报告 | 产业链调研报告 |
|---|---|---|
| 节数 | **11 节 + 4 附录** | **11 节 + 4 附录** |
| 核心 | 阶段判定（五指标＋渗透率校准）／**行业级壁垒与关键依赖**／区域分布／**机会点与竞争策略** | **环节级利润分布**／**逐环节出清机制**／技术壁垒逐环节／关键零部件与国产替代／**逐环节落点** |
| 不要求 | 逐环节落点、环节级利润分布 | 行业阶段标签、**渗透率**（单环节没有渗透率） |

**两者都含**：区域分布（条件节）、政策与监管、趋势与风险、投资结论含失效条件。

## 内含资源

| 资源 | 用途 |
|---|---|
| `references/行业与产业-定义.md` | 分析单位的权威定义（两轴正交） |
| `references/两类报告-定义.md` | 两类报告的权威定义 |
| `references/阶段判定与投资含义.md` | 阶段判定完整方法（驱动力、五指标、渗透率校准、共线检查、出清五问、投资含义矩阵） |
| `references/产业链与出清机制.md` | 产业链拆解、利润池、价值分布、M1–M5 与 S1–S6 |
| `references/来源核验与证据台账.md` | 来源分级、双源独立性、冲突处理、时效、置信度 |
| `references/检索作战包.md` | **检索深度要求、缺口驱动补检索法、官方接口、两类型检索方向清单** |
| `assets/report-template.md` | **两套报告模板** + 通用纪律（排版、禁词、口径、过程性标注） |
| `references/example-report.md` | 完整范例（虾滑行业调研） |
| `自检.ps1` | **163 项断言** |
| `verify-bom.ps1` | BOM/EOL 守卫 |
| `单文件通用版提示词.md` | 给不加载技能的场景用 |

## 安装

### 一、DeepSeek Harness（DSH）

```bash
git clone --depth 1 https://github.com/mbhao555-svg/industry-scope-router.git /tmp/isr \
  && cp -r /tmp/isr/skills/industry-scope-router ~/.dsh/skills/ \
  && rm -rf /tmp/isr
```

```powershell
# Windows PowerShell
$Stage = Join-Path $env:TEMP ("isr-" + [guid]::NewGuid().ToString("N").Substring(0,8))
git clone --depth 1 https://github.com/mbhao555-svg/industry-scope-router.git (Join-Path $Stage "repo")
$dst = Join-Path $env:USERPROFILE ".dsh\skills\industry-scope-router"
if (Test-Path $dst) { Write-Warning "已存在，跳过（不覆盖）: $dst" }
else { Copy-Item (Join-Path $Stage "repo\skills\industry-scope-router") $dst -Recurse }
Remove-Item $Stage -Recurse -Force
```

**不用重启、不用新开会话**——DSH 会热刷新技能目录。

### 二、Codex

**方式 A：插件包（推荐）**

本仓库符合 [agent-plugins.org](https://agent-plugins.org) 规范，仓库根带 `.codex-plugin/plugin.json`。

```bash
git clone --depth 1 https://github.com/mbhao555-svg/industry-scope-router.git
# 然后在 Codex 里：导入插件 → 选择刚 clone 下来的目录
```

清单里的 `"skills": "./skills"` 会自动指向技能目录。

**方式 B：CLI 一条命令**

```bash
npx skills add mbhao555-svg/industry-scope-router --skill industry-scope-router -g -a codex -y
```

### 三、WorkBuddy

**方式 A：插件包（推荐）**

仓库根带 `.codebuddy-plugin/plugin.json`（WorkBuddy 与 CodeBuddy 共用这一渠道）。在 WorkBuddy 的插件导入界面选择仓库目录或打包 zip 即可。

**方式 B：CLI**

```bash
npx skills add mbhao555-svg/industry-scope-router --skill industry-scope-router -g -a codebuddy -y
```

> 装到 `.codebuddy/skills/`。**DSH 不扫描该目录**——DSH 用户请用方式一。

**一次装多个平台**：`-a codex -a codebuddy` 可同时装。

### 四、三份清单对照

| 清单文件 | 面向平台 | 备注 |
|---|---|---|
| `plugin.json` | agent-plugins.org 规范 / **ChatGPT** | 含 `com.openai` 界面扩展：显示名、分类、默认提示词 |
| `.codex-plugin/plugin.json` | **Codex** | — |
| `.codebuddy-plugin/plugin.json` | **WorkBuddy** / **CodeBuddy** | 含 `category` 字段 |

> ⚠️ **打包时的结构要求**：三份清单与 `skills/` 必须**在同一层**（都在包根）。若把清单放进技能目录内，`"./skills"` 会指错位置，**插件无法加载技能**。
>
> ⚠️ **DSH 用户不必用插件包**——DSH 的插件系统是另一套体系（Cordis / npm），**不读取上述清单**。DSH 请用方式一。

### 五、不装任何工具（任意联网 AI）

打开 [`skills/industry-scope-router/单文件通用版提示词.md`](skills/industry-scope-router/单文件通用版提示词.md)，点 **Raw** 后整段复制，粘进 ChatGPT / Claude / Kimi / Gemini 等**支持联网搜索**的 AI 即可。

## 安装后验证

装完请确认技能**出现在你的 AI 工具的技能列表里**，而不只是命令回了成功。

如果命令提示成功但列表里没有——多半是文件没放对位置。检查 `<技能目录>/industry-scope-router/SKILL.md` 是否存在。

**技能目录里应当有这些**（缺任一即不完整）：

| 项 | 说明 |
|---|---|
| `SKILL.md` | 技能主体 |
| `自检.ps1` / `verify-bom.ps1` | 163 项自检 / BOM-EOL 守卫 |
| `assets/report-template.md` | 两套报告模板 |
| `references/` 7 个文件 | 定义 ×2、阶段判定、产业链与出清、来源核验、检索作战包、范例报告 |
| `使用说明.md` / `单文件通用版提示词.md` / `发布到GitHub.md` | 使用与发布 |

## 三条硬规则

**一、混合报告必须声明两层关系**——实测曾产出 6 份报告，**5 份是"行业级阶段 + 环节级落点"的混合报告，无一加过声明**。故设标准声明段（附录 D）。

**二、口径分层优先于"口径冲突"**——差异可由统计层级（终端／出厂／TAM／零售）解释的，**写分层不写冲突**；无机构署名的数字须**显式标注**；多家媒体互相转引的**按共线处理**。

**三、过程性标注禁写**——`（应纳入，但有两处边界）`、`（必须声明）`、`（缺一即不合格）` 这类括号讲的是"我怎么处理的"，**对读者是噪音**。判据：**括号里的内容如果换成"任何读者都不需要知道"，就删。**

## 实测案例

- **预制菜** → 无专门代码且归属边界有争议 → 先告知限制，产出**产业链调研报告**（上游调味品 37.90%–50.44% 为中游 9.03%–20.24% 的 2–5 倍）
- **虾滑** → 无专门代码但归属清晰 → 产出**行业调研报告**（阶段：成长期后段；核心变量：**GB/T 44980-2024** 2025-07-01 实施，强制虾肉 ≥50%；核心发现：**C 端零售已收敛〔CR5 78%〕而 B 端餐饮未收敛**）

## 版本

`2.4.1`　｜　更新日志见 `CHANGELOG.md`　｜　`version-check.ps1` 校验三处版本一致（含远程 tag）

## 许可

MIT