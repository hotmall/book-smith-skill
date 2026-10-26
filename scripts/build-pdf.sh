#!/bin/bash
# 用法: ./build-pdf.sh <input.md>
# 依赖: pandoc + weasyprint + assets/pdf-style.html
#
# 处理流程：
#   Markdown --pandoc--> 单文件 HTML（内嵌图片/CSS）--weasyprint--> PDF
# 输出固定为 dist/<md 文件名>.pdf，样式固定为 assets/pdf-style.html。
# weasyprint 优先用统一 venv .venv 内的版本，没有则用系统 PATH 上的版本。
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
style="$self_dir/../assets/pdf-style.html"

# 统一 Python 环境（与 pdf2md.py / build-azw3.sh 共用同一 venv）
# shellcheck source=./pyenv.sh
source "$self_dir/pyenv.sh"

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

# weasyprint：统一 venv 优先，其次是系统安装
weasyprint_bin=""
venv_weasyprint="$BOOKSMITH_VENV/bin/weasyprint"
if [ -x "$venv_weasyprint" ] && "$venv_weasyprint" --version >/dev/null 2>&1; then
  weasyprint_bin="$venv_weasyprint"
elif command -v weasyprint >/dev/null 2>&1; then
  weasyprint_bin="$(command -v weasyprint)"
else
  echo "未找到 weasyprint，正在装进统一 venv $BOOKSMITH_VENV ..." >&2
  if ensure_pdf_deps && [ -x "$venv_weasyprint" ] && "$venv_weasyprint" --version >/dev/null 2>&1; then
    weasyprint_bin="$venv_weasyprint"
  fi
fi
if [ -z "$weasyprint_bin" ]; then
  echo "错误: 需要 weasyprint（pip install weasyprint；macOS 还需 brew install pango）" >&2
  exit 1
fi

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

"$weasyprint_bin" "$tmphtml" "dist/${base}.pdf"
echo "已生成: dist/${base}.pdf"
