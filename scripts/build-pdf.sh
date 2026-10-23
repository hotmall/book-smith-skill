#!/bin/bash
# 用法: ./build-pdf.sh <input.md>
# 依赖: pandoc + weasyprint + assets/pdf-style.html
#
# 流程严格照搬 jpm/build-pdf.sh：
#   Markdown --pandoc--> 单文件 HTML（内嵌图片/CSS）--weasyprint--> PDF
# 输出固定为 dist/<md 文件名>.pdf，样式固定为 assets/pdf-style.html。
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
style="$self_dir/../assets/pdf-style.html"

src="${1:-}"
if [ -z "$src" ]; then
  echo "用法: ./build-pdf.sh <input.md>" >&2
  exit 1
fi
if [ ! -f "$src" ]; then
  echo "错误: 找不到文件 $src" >&2
  exit 1
fi
if [ ! -f "$style" ]; then
  echo "错误: 缺少样式文件 $style" >&2
  exit 1
fi
command -v pandoc >/dev/null 2>&1 || {
  echo "错误: 需要 pandoc（brew install pandoc）" >&2
  exit 1
}
command -v weasyprint >/dev/null 2>&1 || {
  echo "错误: 需要 weasyprint（pip install weasyprint）" >&2
  exit 1
}

base="$(basename "${src%.md}")"
srcdir="$(cd "$(dirname "$src")" && pwd)"
mkdir -p dist

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/qs-pdf.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
tmphtml="$tmpdir/book.html"

pandoc "$src" -o "$tmphtml" --standalone --embed-resources \
  --resource-path="$srcdir" -f markdown-implicit_figures -H "$style"

python3 - "$tmphtml" <<'EOF'
import re
import sys

p = sys.argv[1]
html = open(p, encoding="utf-8").read()
head_start = html.find("<head>")
head_end = html.find("</head>")
head = html[head_start:head_end]
# 保留含自定义标记的 <style>（我们的），移除 pandoc 默认模板样式
parts = re.split(r"(<style>.*?</style>)", head, flags=re.S)
out, marker = [], "PingFang SC"
for part in parts:
    if part.startswith("<style>"):
        if marker in part:
            out.append(part)
    else:
        out.append(part)
html = html[:head_start] + "".join(out) + html[head_end:]
open(p, "w", encoding="utf-8").write(html)
EOF

weasyprint "$tmphtml" "dist/${base}.pdf"
echo "已生成: dist/${base}.pdf"
