#!/usr/bin/env bash
# doctor.sh —— 检查 book-smith-skill 的外部依赖，缺什么就打印安装命令。
set -uo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill_dir="$(cd "$self_dir/.." && pwd)"
missing=0

say_ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
say_no() { printf '  \033[31m✗\033[0m %s\n' "$*"; missing=$((missing + 1)); }
say_info() { printf '  \033[33m·\033[0m %s\n' "$*"; }

has() { command -v "$1" >/dev/null 2>&1; }

echo "pandoc / 排版"
if has pandoc; then say_ok "pandoc $(pandoc --version | head -n 1 | awk '{print $2}')"; else
  say_no "pandoc        → brew install pandoc"; fi

if has weasyprint; then say_ok "weasyprint $(weasyprint --version 2>/dev/null | awk '{print $NF}')"; else
  say_no "weasyprint    → pip install weasyprint"; fi

echo "Markdown 收尾"
if has markdownlint; then
  say_ok "markdownlint $(markdownlint --version 2>/dev/null)"
elif has npx; then
  say_ok "markdownlint 未全局安装，脚本会用 npx 临时调用"
else
  say_no "markdownlint  → npm install -g markdownlint-cli"; fi

guide=""
for candidate in \
  "${BOOKSMITH_CHINESE_GUIDE:-}" \
  "$skill_dir/../chinese-style-guide/scripts/check_format.py" \
  "$skill_dir/vendor/chinese-style-guide/scripts/check_format.py" \
  "${BOOKSMITH_SKILLS_DIR:-$HOME/.config/opencode/skills}/chinese-style-guide/scripts/check_format.py" \
  "$HOME/.claude/skills/chinese-style-guide/scripts/check_format.py"; do
  [ -z "$candidate" ] && continue
  [ -d "$candidate" ] && candidate="$candidate/scripts/check_format.py"
  if [ -f "$candidate" ]; then guide="$candidate"; break; fi
done
if [ -n "$guide" ]; then
  say_ok "chinese-style-guide（${guide}）"
else
  say_no "chinese-style-guide → bash $self_dir/install.sh"
fi

echo "PDF → Markdown"
if python3 -c 'import pdfplumber, PIL' >/dev/null 2>&1; then
  say_ok "pdfplumber + pillow"
else
  say_no "pdfplumber/pillow → pip install pdfplumber pillow"; fi

echo "Markdown → 电子书"
if [ -x "$skill_dir/.venv-azw3/bin/python" ] &&
  "$skill_dir/.venv-azw3/bin/python" -c 'import ebook_converter_lib' >/dev/null 2>&1; then
  say_ok "ebook-converter-lib（$skill_dir/.venv-azw3）"
else
  say_info "ebook-converter-lib 未安装（首次运行 build-azw3.sh 时自动安装，需 Python 3.11+）"
  if ! has python3.12 && ! has python3.13 && ! has python3.11 && ! has uv; then
    say_no "Python 3.11+  → brew install python@3.12 或 brew install --cask calibre"
  fi
fi
if has ebook-convert; then
  say_info "检测到 Calibre ebook-convert；脚本仍使用 ebook-converter-lib"
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
    say_info "未匹配到脚本默认字体名，WeasyPrint 会回退到系统字体（可改 assets/*.html）"
  fi
else
  say_info "macOS 系统字体（PingFang SC / Songti SC）可直接使用"
fi

echo
if [ "$missing" -eq 0 ]; then
  echo "依赖齐全，可以开始。"
else
  echo "缺少 $missing 项依赖，按上面的提示安装后重跑 doctor.sh。"
  exit 1
fi
