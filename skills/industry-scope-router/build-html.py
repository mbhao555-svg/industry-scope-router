#!/usr/bin/env python3
"""把 Markdown 主报告转为自包含的 HTML 阅读版。

特点：
  - 自包含：CSS/JS 全部内联，无 CDN、无外部字体，离线可读
  - 阅读优化：正文限宽、行高 1.85、中文系统字体栈、表格横向滚动
  - 左侧粘性目录 + 滚动高亮 + 阅读进度条 + 返回顶部
  - 深浅色自适应（prefers-color-scheme）
  - 打印样式（隐藏目录、避免表格跨页断裂）
  - **交付前校验**：重复锚点、失效目录锚点、空表格 —— 有问题直接报错退出

用法：
  python build-html.py 报告.md 报告.html
  python build-html.py 报告.md 报告.html --title "自定义标题" --no-toc
"""

from __future__ import annotations

import argparse
import html
import re
import sys
from pathlib import Path

try:
    import markdown
except ImportError:
    sys.exit("需要 markdown 库：pip install markdown")


# ---------------------------------------------------------------- 元信息抽取

META_PAT = re.compile(r"^\|\s*\*\*(?P<key>[^*]+?)\*\*\s*\|\s*(?P<val>.+?)\s*\|\s*$")
# 引用块格式：> **调研类型**：产业链调研｜**判定依据**：…
QUOTE_META_PAT = re.compile(r"\*\*(?P<key>[^*｜|]{1,14}?)\*\*\s*[：:]\s*(?P<val>[^｜|\n]+)")
# 报告最前面若干行里可能出现的独立字段
LOOSE_META_PAT = re.compile(r"\*\*(?P<key>调研类型|报告类型|报告范围|数据截止|报告日期|报告定位)\*\*\s*[：:]\s*(?P<val>[^\n｜|]+)")


def extract_meta(text: str) -> dict[str, str]:
    """从正文抽取元信息，同时支持三种写法：
    1) 表格：| **报告日期** | 2026-10-17 |
    2) 引用块：> **调研类型**：产业链调研｜**判定依据**：…
    3) 松散行：**数据截止**：2026-10-17
    """
    meta: dict[str, str] = {}

    def put(key: str, val: str) -> None:
        key = key.strip().strip("*：:")
        val = re.sub(r"\*\*|`", "", val).strip()
        val = val.strip("｜|").strip()
        if key and val and key not in meta and len(val) <= 160:
            meta[key] = val

    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = META_PAT.match(line)
        if m:
            put(m.group("key"), m.group("val"))
            continue
        if line.startswith(">"):
            body = line.lstrip("> ").strip()
            for qm in QUOTE_META_PAT.finditer(body):
                put(qm.group("key"), qm.group("val"))
            continue
        for lm in LOOSE_META_PAT.finditer(line):
            put(lm.group("key"), lm.group("val"))
    return meta


def first_heading(text: str, fallback: str) -> str:
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return fallback


# ---------------------------------------------------------------- 渲染

MD_EXTENSIONS = [
    "tables",
    "fenced_code",
    "sane_lists",
    "attr_list",
    "toc",
    "md_in_html",
]


def render_body(text: str) -> tuple[str, list[tuple[int, str, str]]]:
    """渲染正文，返回 (html, [(level, title, id)])。

    ⚠️ 会先剥掉文首的 H1——标题由模板单独渲染，否则页面上会出现两个同名标题。
    """
    text = strip_leading_h1(text)
    md = markdown.Markdown(extensions=MD_EXTENSIONS, extension_configs={
        "toc": {"slugify": lambda value, _: slugify(value), "toc_depth": "2-3"},
        "fenced_code": {"lang_prefix": "language-"},
    })
    body = md.convert(text)

    toc: list[tuple[int, str, str]] = []
    for token in md.toc_tokens:  # type: ignore[attr-defined]
        toc.append((token["level"], token["name"], token["id"]))
        for child in token.get("children", []):
            toc.append((child["level"], child["name"], child["id"]))
    return body, toc


def strip_leading_h1(text: str) -> str:
    """去掉文首第一个 `# 标题`（保留其后内容）。"""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not line.strip():
            continue
        if line.startswith("# ") and not line.startswith("## "):
            return "\n".join(lines[:i] + lines[i + 1:])
        break  # 第一行非空不是 H1，就不动
    return text


def slugify(value: str) -> str:
    """中文标题也要有稳定、可读的锚点。"""
    value = re.sub(r"<[^>]+>", "", value)
    value = re.sub(r"[\s\u3000]+", "-", value.strip())
    value = re.sub(r"[^\w\-\u4e00-\u9fff]", "", value)
    value = re.sub(r"-{2,}", "-", value).strip("-")
    return value or "section"


# ---------------------------------------------------------------- 校验

def validate(body: str, toc: list[tuple[int, str, str]]) -> list[str]:
    """交付前校验：重复锚点、失效目录锚点、空表格。"""
    problems: list[str] = []

    ids = re.findall(r'\sid="([^"]+)"', body)
    seen: dict[str, int] = {}
    for i in ids:
        seen[i] = seen.get(i, 0) + 1
    dup = [k for k, v in seen.items() if v > 1]
    if dup:
        problems.append("重复锚点：" + "、".join(dup[:8]))

    id_set = set(ids)
    broken = [h for _, _, h in toc if h not in id_set]
    if broken:
        problems.append("失效目录锚点：" + "、".join(broken[:8]))

    empty = re.findall(r"<table>\s*</table>", body)
    if empty:
        problems.append(f"存在 {len(empty)} 个空表格")

    return problems


# ---------------------------------------------------------------- 模板

CSS = """
:root{
  --ink:#1a1a1a; --ink-2:#4a4a4a; --ink-3:#767676;
  --bg:#fdfdfc; --bg-soft:#f5f5f3; --line:#e3e3df;
  --accent:#1f6feb; --warn:#b45309; --danger:#b91c1c;
  --max:46rem;
}
@media (prefers-color-scheme:dark){
  :root{ --ink:#e8e8e6; --ink-2:#b4b4b0; --ink-3:#8a8a86;
         --bg:#161615; --bg-soft:#1f1f1e; --line:#333331;
         --accent:#6ea8fe; --warn:#fbbf24; --danger:#f87171; }
}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{
  margin:0; background:var(--bg); color:var(--ink);
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",
    "Hiragino Sans GB","Microsoft YaHei","Source Han Sans SC",sans-serif;
  font-size:16.5px; line-height:1.85;
  -webkit-font-smoothing:antialiased; text-rendering:optimizeLegibility;
}
#progress{position:fixed;top:0;left:0;height:3px;width:0;background:var(--accent);z-index:100;transition:width .1s}
.shell{display:flex;gap:2.5rem;max-width:calc(var(--max) + 19rem);margin:0 auto;padding:0 1.5rem}
nav.toc{
  position:sticky;top:0;align-self:flex-start;flex:0 0 15rem;
  max-height:100vh;overflow-y:auto;padding:2.5rem 0 3rem;
  font-size:13.5px;line-height:1.6;
}
nav.toc h2{font-size:11px;letter-spacing:.12em;text-transform:uppercase;
  color:var(--ink-3);margin:0 0 .8rem;font-weight:600}
nav.toc a{display:block;color:var(--ink-2);text-decoration:none;border-bottom:none;
  padding:.28rem 0 .28rem .7rem;border-left:2px solid transparent;transition:.15s}
nav.toc a:hover{color:var(--accent);border-bottom:none}
nav.toc a.active{color:var(--accent);border-left-color:var(--accent);font-weight:600}
nav.toc a.lv3{padding-left:1.6rem;font-size:12.5px;color:var(--ink-3)}
main{flex:1 1 auto;min-width:0;max-width:var(--max);padding:2.5rem 0 6rem}
h1{font-size:1.9rem;line-height:1.35;margin:0 0 .6rem;letter-spacing:-.01em;font-weight:700}
.meta{display:flex;flex-wrap:wrap;gap:.4rem .9rem;font-size:13px;color:var(--ink-3);
  padding-bottom:1.4rem;margin-bottom:2rem;border-bottom:1px solid var(--line)}
.meta span{white-space:nowrap}
.meta b{color:var(--ink-2);font-weight:600}
h2{font-size:1.32rem;line-height:1.45;margin:3.2rem 0 1rem;padding-top:.4rem;
  border-top:1px solid var(--line);font-weight:700;letter-spacing:-.005em}
h3{font-size:1.08rem;line-height:1.5;margin:2.1rem 0 .7rem;font-weight:650;color:var(--ink)}
h4{font-size:.98rem;margin:1.6rem 0 .5rem;font-weight:650;color:var(--ink-2)}
p{margin:.85rem 0}
a{color:var(--accent);text-decoration:none;border-bottom:1px solid color-mix(in srgb,var(--accent) 35%,transparent)}
a:hover{border-bottom-color:var(--accent)}
strong{font-weight:650}
ul,ol{margin:.85rem 0;padding-left:1.5rem}
li{margin:.4rem 0}
li>ul,li>ol{margin:.3rem 0}
blockquote{margin:1.4rem 0;padding:.9rem 1.1rem;background:var(--bg-soft);
  border-left:3px solid var(--accent);border-radius:0 6px 6px 0;color:var(--ink-2)}
blockquote p{margin:.4rem 0}
blockquote p:first-child{margin-top:0}
blockquote p:last-child{margin-bottom:0}
.table-wrap{overflow-x:auto;margin:1.3rem 0;-webkit-overflow-scrolling:touch}
/* 窄表填满宽度；宽表按自然宽度展开并由 .table-wrap 横向滚动，避免列被压窄 */
table{border-collapse:collapse;width:auto;min-width:100%;font-size:14px;line-height:1.6}
th,td{border:1px solid var(--line);padding:.5rem .7rem;text-align:left;vertical-align:top}
th{background:var(--bg-soft);font-weight:650;white-space:nowrap}
td{min-width:4.5em}
tbody tr:nth-child(even){background:color-mix(in srgb,var(--bg-soft) 55%,transparent)}
code{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;
  font-size:.88em;background:var(--bg-soft);padding:.12em .38em;border-radius:4px}
pre{background:var(--bg-soft);border:1px solid var(--line);border-radius:8px;
  padding:1rem 1.1rem;overflow-x:auto;line-height:1.6;margin:1.3rem 0}
pre code{background:none;padding:0;font-size:13px}
hr{border:0;border-top:1px solid var(--line);margin:2.5rem 0}
#top{position:fixed;right:1.5rem;bottom:1.5rem;width:42px;height:42px;border-radius:50%;
  border:1px solid var(--line);background:var(--bg);color:var(--ink-2);cursor:pointer;
  display:none;align-items:center;justify-content:center;font-size:18px;z-index:90}
#top.show{display:flex}
#top:hover{color:var(--accent);border-color:var(--accent)}
@media (max-width:1040px){
  nav.toc{display:none}
  .shell{padding:0 1.1rem}
  main{padding-top:1.6rem}
  body{font-size:16px}
  h1{font-size:1.6rem}
  h2{font-size:1.2rem}
}
/* 窄屏：抬高单元格最小宽度，让宽表横向滚动而不是把中文压成细列 */
@media (max-width:640px){
  .shell{padding:0 .85rem}
  table{font-size:13px}
  th,td{padding:.42rem .55rem}
  td{min-width:5.6em}
  th{white-space:normal}
  .table-wrap{border:1px solid var(--line);border-radius:6px}
  .table-wrap table{border:0}
  h2{margin-top:2.4rem}
  blockquote{padding:.75rem .85rem}
}
@media print{
  nav.toc,#progress,#top{display:none!important}
  body{font-size:11pt;line-height:1.7;background:#fff;color:#000}
  .shell{display:block;max-width:none;padding:0}
  main{max-width:none;padding:0}
  h2{break-after:avoid;page-break-after:avoid;margin-top:1.6rem}
  h3,h4{break-after:avoid}
  tr,img,pre,blockquote{break-inside:avoid;page-break-inside:avoid}
  a{color:#000;border:0}
  .table-wrap{overflow:visible}
  table{font-size:9.5pt}
}
"""

JS = """
(function(){
  var bar=document.getElementById('progress'),top=document.getElementById('top');
  var links=[].slice.call(document.querySelectorAll('nav.toc a'));
  var targets=links.map(function(a){return document.getElementById(a.getAttribute('href').slice(1));});
  function onScroll(){
    var d=document.documentElement;
    var max=d.scrollHeight-d.clientHeight;
    bar.style.width=(max>0?(d.scrollTop/max*100):0)+'%';
    top.classList.toggle('show',d.scrollTop>600);
    var idx=-1;
    for(var i=0;i<targets.length;i++){
      var t=targets[i];
      if(t&&t.getBoundingClientRect().top<=120) idx=i;
    }
    links.forEach(function(a,i){a.classList.toggle('active',i===idx);});
  }
  document.addEventListener('scroll',onScroll,{passive:true});
  onScroll();
  top.addEventListener('click',function(){window.scrollTo({top:0,behavior:'smooth'});});
})();
"""

HTML_TMPL = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{title}</title>
<style>{css}</style>
</head>
<body>
<div id="progress"></div>
<div class="shell">
{toc}
<main>
<h1>{title}</h1>
{meta}
{body}
</main>
</div>
<button id="top" title="返回顶部" aria-label="返回顶部">↑</button>
<script>{js}</script>
</body>
</html>
"""


def build_toc(toc: list[tuple[int, str, str]]) -> str:
    if not toc:
        return ""
    out = ['<nav class="toc"><h2>目录</h2>']
    for level, name, hid in toc:
        cls = ' class="lv3"' if level >= 3 else ""
        out.append(f'<a href="#{hid}"{cls}>{html.escape(name)}</a>')
    out.append("</nav>")
    return "\n".join(out)


def build_meta(meta: dict[str, str]) -> str:
    # 按展示优先级排列；同义字段互相兜底
    slots: list[tuple[str, list[str]]] = [
        ("报告日期", ["报告日期"]),
        ("数据截止", ["数据截止日", "数据截止"]),
        ("对象", ["行业", "产业", "报告范围"]),
        ("调研类型", ["调研类型", "报告类型"]),
        ("报告模式", ["报告模式"]),
    ]
    parts: list[str] = []
    used: set[str] = set()
    for label, keys in slots:
        for k in keys:
            if k in meta:
                parts.append(f"<span><b>{html.escape(label)}</b> {html.escape(meta[k])}</span>")
                used.add(k)
                break
    # 正文实测字数单独显示（它是质量证据）
    for k in meta:
        if "正文实测字数" in k:
            parts.append(f"<span><b>正文实测</b> {html.escape(meta[k])}</span>")
            used.add(k)
            break
    return f'<div class="meta">{"".join(parts)}</div>' if parts else ""


def convert(src: Path, dst: Path, title: str | None, with_toc: bool) -> int:
    text = src.read_text(encoding="utf-8")
    if not text.strip():
        print("RESULT: 源文件为空", file=sys.stderr)
        return 2

    body, toc = render_body(text)
    problems = validate(body, toc)
    if problems:
        print("RESULT: HTML 校验失败", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        return 1

    # 表格包一层，便于窄屏横向滚动
    body = re.sub(r"(<table>)", r'<div class="table-wrap">\1', body)
    body = re.sub(r"(</table>)", r"\1</div>", body)

    meta = extract_meta(text)
    page_title = title or first_heading(text, src.stem)

    # 正文已有「元信息」表时不再显示顶部摘要条，避免同一屏出现两遍
    has_meta_table = bool(re.search(r"\|\s*元信息\s*\|", text))
    meta_bar = "" if has_meta_table else build_meta(meta)

    out = HTML_TMPL.format(
        title=html.escape(page_title),
        css=CSS,
        js=JS,
        toc=build_toc(toc) if with_toc else "",
        meta=meta_bar,
        body=body,
    )
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(out, encoding="utf-8")

    size_kb = dst.stat().st_size / 1024
    headings = len(toc)
    tables = body.count("<table>")
    print("=== HTML 阅读版已生成 ===")
    print(f"  源文件   : {src.name}")
    print(f"  输出     : {dst.name}（{size_kb:.1f} KB）")
    print(f"  标题     : {page_title}")
    print(f"  目录项   : {headings}")
    print(f"  表格     : {tables}")
    print(f"  自包含   : 是（无 CDN、无外部字体、离线可读）")
    print("RESULT: OK")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Markdown → 自包含 HTML 阅读版")
    ap.add_argument("input", type=Path)
    ap.add_argument("output", type=Path)
    ap.add_argument("--title", default=None)
    ap.add_argument("--no-toc", action="store_true")
    args = ap.parse_args()
    if not args.input.exists():
        print(f"RESULT: 输入不存在 — {args.input}", file=sys.stderr)
        return 2
    return convert(args.input, args.output, args.title, not args.no_toc)


if __name__ == "__main__":
    raise SystemExit(main())
