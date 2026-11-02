#!/usr/bin/env python3
"""Builds the in-app help page from docs/user-guide.md.

    pip3 install markdown
    python3 tools/build_help.py

Writes SevenTerm/Resources/Help/help.html. Run it after editing the guide
and commit both files. The page takes its colours from CSS variables that
7 Term sets to match the current theme (red, or green for 6 Bits).
"""
import pathlib
import re
import markdown

root = pathlib.Path(__file__).resolve().parent.parent
source = (root / "docs/user-guide.md").read_text(encoding="utf-8")

# The guide's own title becomes the page header; the contents list becomes the sidebar.
title_line, _, rest = source.partition("\n")
toc_match = re.search(r"\n((?:- \[.*\]\(#.*\)\n)+)", rest)
toc_md = toc_match.group(1) if toc_match else ""
body_md = rest.replace(toc_md, "", 1) if toc_md else rest

def loosen_lists(text):
    """GitHub starts a list right after a line of text; Python-Markdown needs
    a blank line first. Add one so the guide renders the same in both."""
    out = []
    for line in text.split("\n"):
        is_item = bool(re.match(r"\s*(?:[-*] |\d+\. )", line))
        if is_item and out and out[-1].strip() and not re.match(r"\s*(?:[-*] |\d+\. )", out[-1]):
            out.append("")
        out.append(line)
    return "\n".join(out)


body_md = loosen_lists(body_md)
md = markdown.Markdown(extensions=["tables", "toc", "fenced_code", "sane_lists"])
body = md.convert(body_md)
toc = markdown.markdown(toc_md)

CSS = """
:root {
  --accent: #FF3434; --bg: #0D0909; --panel: #150F0F; --line: rgba(255,255,255,.08);
  --text: #E8E2E2; --dim: #9A9090;
}
* { box-sizing: border-box; }
html, body { margin: 0; background: var(--bg); color: var(--text);
  font: 14px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; -webkit-font-smoothing: antialiased; }
.mono, h1, h2, h3, nav, code, th { font-family: "SF Mono", ui-monospace, Menlo, monospace; }
header { display: flex; align-items: center; gap: 14px; padding: 22px 28px 18px;
  border-bottom: 1px solid var(--line); background: var(--panel); }
header .glyph { display: grid; grid-template-columns: repeat(5, 4px); gap: 2px; }
header .glyph i { width: 4px; height: 4px; background: transparent; }
header .glyph i.on { background: var(--accent); box-shadow: 0 0 4px var(--accent); }
header h1 { margin: 0; font-size: 20px; font-weight: 700; color: var(--accent); letter-spacing: .02em; }
header p { margin: 0; color: var(--dim); font-size: 12px; }
.wrap { display: grid; grid-template-columns: 210px 1fr; min-height: calc(100vh - 80px); }
nav { position: sticky; top: 0; align-self: start; padding: 18px 0 18px 20px; font-size: 12px; }
nav ul { list-style: none; margin: 0; padding: 0; }
nav a { display: block; padding: 5px 10px; color: var(--dim); text-decoration: none;
  border-left: 2px solid transparent; }
nav a:hover, nav a.active { color: var(--accent); border-left-color: var(--accent); }
main { padding: 8px 40px 60px 28px; max-width: 820px; }
h2 { margin: 34px 0 10px; font-size: 15px; text-transform: uppercase; letter-spacing: .08em;
  color: var(--accent); border-bottom: 1px solid var(--line); padding-bottom: 6px; }
h2::before { content: "> "; opacity: .7; }
h3 { margin: 22px 0 6px; font-size: 13px; color: var(--text); }
a { color: var(--accent); }
strong { color: #fff; }
code { background: var(--panel); border: 1px solid var(--line); padding: 1px 5px; border-radius: 2px;
  font-size: 12px; color: var(--accent); }
table { border-collapse: collapse; width: 100%; margin: 10px 0 16px; font-size: 13px; }
th { text-align: left; font-size: 11px; text-transform: uppercase; letter-spacing: .06em;
  color: var(--dim); font-weight: 600; }
th, td { padding: 7px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
td:first-child { white-space: nowrap; }
tr:hover td { background: var(--panel); }
ul, ol { padding-left: 22px; } li { margin: 3px 0; }
@media (max-width: 680px) { .wrap { grid-template-columns: 1fr; } nav { display: none; } main { padding: 8px 20px 40px; } }
"""

GLYPH = ["11111", "00001", "00010", "00100", "01000", "01000", "01000"]  # the pixel 7
glyph = "".join(f'<i class="{"on" if c == "1" else ""}"></i>' for row in GLYPH for c in row)

SCRIPT = """
const links = [...document.querySelectorAll('nav a')];
const heads = links.map(a => document.querySelector(a.getAttribute('href')));
function mark() {
  let i = heads.findIndex(h => h && h.getBoundingClientRect().top > 120) - 1;
  if (i < 0) i = window.scrollY > 100 ? heads.length - 1 : 0;
  links.forEach((a, j) => a.classList.toggle('active', j === i));
}
document.addEventListener('scroll', mark, { passive: true }); mark();
"""

page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>7 Term Help</title><style>{CSS}</style></head>
<body>
<header><div class="glyph" aria-hidden="true">{glyph}</div>
<div><h1 aria-label="7 Term Help">Term Help</h1><p class="mono">ssh · sftp · logs, the quick way</p></div></header>
<div class="wrap"><nav aria-label="Contents">{toc}</nav><main>{body}</main></div>
<script>{SCRIPT}</script>
</body></html>
"""
out = root / "SevenTerm/Resources/Help/help.html"
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(page, encoding="utf-8")
print(f"wrote {out.relative_to(root)} ({len(page)} bytes)")
