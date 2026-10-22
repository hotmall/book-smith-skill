#!/usr/bin/env bash
# doctor.sh —— 检查 booksmith 的外部依赖，缺什么就打印安装命令。
set -uo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
missing=0

say_ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
say_no() { printf '  \033[31m✗\033[0m %s\n' "$*"; missing=$((missing + 1)); }

has() { command -v "$1" >/dev/null 2>&1; }

echo "pandoc / 排版"
if has pandoc; then say_ok "pandoc $(pandoc --version | head -n 1 | awk '{print $2}')"; else
  say_no "pandoc        → brew install pandoc"; fi

if has weasyprint; then say_ok "weasyprint $(weasyprint --version 2>/dev/null | awk '{print $NF}')"; else
  say_no "weasyprint    → pip install weasyprint"; fi

echo "PDF → Markdown"
if python3 -c 'import pdfplumber, PIL' >/dev/null 2>&1; then
  say_ok "pdfplumber + pillow"
else
  say_no "pdfplumber/pillow → pip install pdfplumber pillow"
fi

echo "Markdown → EPUB/AZW3"
if has ebook-convert; then
  say_ok "calibre ebook-convert"
elif [ -x "${BOOKSMITH_VENV:-$HOME/.cache/booksmith/venv-ebook}/bin/python" ] &&
  "${BOOKSMITH_VENV:-$HOME/.cache/booksmith/venv-ebook}/bin/python" -c 'import ebook_converter_lib' >/dev/null 2>&1; then
  say_ok "ebook-converter-lib（缓存虚拟环境）"
else
  say_ok "ebook-converter-lib 未安装（首次转换时自动安装，需 Python 3.11+）"
  if ! has python3.12 && ! has python3.13 && ! has python3.11 && ! has uv; then
    say_no "Python 3.11+  → brew install python@3.12 或 brew install --cask calibre"
  fi
fi

echo "字体（影响中文 PDF 观感）"
if has fc-list; then
  found=0
  for font in "PingFang SC" "Songti SC" "Noto Serif CJK" "Source Han Serif"; do
    if fc-list 2>/dev/null | grep -qi "$font"; then
      say_ok "$font"
      found=$((found + 1))
    fi
  done
  if [ "$found" -eq 0 ]; then
    say_ok "未匹配到脚本默认字体名，WeasyPrint 会回退到系统字体（可改样式里的 font-family）"
  fi
else
  say_ok "macOS 系统字体（PingFang SC / Songti SC）可直接使用"
fi

echo
if [ "$missing" -eq 0 ]; then
  echo "依赖齐全，可以开始。"
else
  echo "缺少 $missing 项依赖，按上面的提示安装后重跑 doctor.sh。"
  exit 1
fi
