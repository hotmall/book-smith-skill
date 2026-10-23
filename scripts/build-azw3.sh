#!/usr/bin/env bash
# 用 Pandoc 先生成单文件 HTML（内嵌 CSS/图片），再用 ebook-converter-lib 转电子书。
#
# 用法:
#   ./build-azw3.sh <input.md> [-o output.azw3] [-a 作者] [-t 书名] [--keep-toc]
#
# 默认输出到 dist/<文件名>.azw3。首次运行会在本 skill 目录内创建 .venv-azw3
# 并安装 ebook-converter-lib（需要 Python 3.11+）。
#
# 流程与选项照搬 jpm/build-azw3.sh：同一份 HTML 可输出 AZW3 / MOBI / EPUB，
# 只是默认扩展名是 .azw3。样式固定为 assets/ebook-style.html。
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$self_dir/../.venv-azw3"
STYLE="$self_dir/../assets/ebook-style.html"

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

find_python() {
  for candidate in python3.12 python3.13 python3.11 python3.14; do
    if command -v "$candidate" >/dev/null 2>&1 &&
      "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' 2>/dev/null; then
      command -v "$candidate"
      return 0
    fi
  done
  if command -v uv >/dev/null 2>&1; then
    uv python find '>=3.11' 2>/dev/null && return 0
  fi
  return 1
}

setup_venv() {
  if [ -x "$VENV/bin/python" ] && "$VENV/bin/python" -c 'import ebook_converter_lib' 2>/dev/null; then
    return 0
  fi
  local py
  if ! py="$(find_python)"; then
    echo "错误: 需要 Python 3.11 或更新版本" >&2
    exit 1
  fi
  echo "首次运行: 用 $py 创建 $VENV 并安装 ebook-converter-lib ..."
  "$py" -m venv "$VENV"
  "$VENV/bin/python" -m pip install --quiet --upgrade pip
  "$VENV/bin/python" -m pip install --quiet 'ebook-converter-lib>=1.2,<2'
}

src=""
out=""
author=""
title=""
keep_toc=0

while [ $# -gt 0 ]; do
  case "$1" in
    -o | --output)
      out="$2"
      shift 2
      ;;
    -a | --author)
      author="$2"
      shift 2
      ;;
    -t | --title)
      title="$2"
      shift 2
      ;;
    --keep-toc)
      keep_toc=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      echo "未知选项: $1" >&2
      usage
      exit 1
      ;;
    *)
      if [ -n "$src" ]; then
        echo "只能指定一个输入文件" >&2
        exit 1
      fi
      src="$1"
      shift
      ;;
  esac
done

if [ -z "$src" ]; then
  usage
  exit 1
fi
if [ ! -f "$src" ]; then
  echo "错误: 找不到文件 $src" >&2
  exit 1
fi
if [ ! -f "$STYLE" ]; then
  echo "错误: 缺少样式文件 $STYLE" >&2
  exit 1
fi

if [ -z "$out" ]; then
  base="$(basename "$src")"
  out="dist/${base%.md}.azw3"
fi
mkdir -p "$(dirname "$out")"

setup_venv

"$VENV/bin/python" - "$src" "$out" "$title" "$author" "$keep_toc" "$STYLE" <<'PY'
import io
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from ebook_converter_lib import convert

src, out, title, author, keep_toc, style = sys.argv[1:7]
src_path = Path(src).resolve()
src_dir = src_path.parent
text = src_path.read_text(encoding="utf-8")

if not title.strip():
    match = re.search(r"^#\s+(.+?)\s*$", text, re.M)
    title = match.group(1) if match else src_path.stem

language = "zh" if re.search(r"[\u4e00-\u9fff]", text) else "en"
style = Path(style)
if not style.exists():
    sys.exit(f"错误: 缺少样式文件 {style}")
if shutil.which("pandoc") is None:
    sys.exit("错误: 需要 pandoc，请先安装")

with tempfile.TemporaryDirectory() as tmp:
    tmp = Path(tmp)

    # AZW3 阅读器自带导航目录，默认去掉手写目录；--keep-toc 可保留
    if keep_toc == "1":
        md_path = src_path
    else:
        lines, skip = [], False
        for line in text.split("\n"):
            if re.match(r"^##\s+目录\s*$", line):
                skip = True
                continue
            if skip:
                if re.match(r"^##\s+", line):
                    skip = False
                else:
                    continue
            lines.append(line)
        md_path = tmp / "book.md"
        md_path.write_text("\n".join(lines), encoding="utf-8")

    html_path = tmp / "book.html"
    print(f"正在转换: {src} -> {out}")

    # Markdown -> 单个 HTML，CSS 与图片全部内嵌
    pandoc_cmd = [
        "pandoc", str(md_path),
        "-o", str(html_path),
        "-f", "markdown-implicit_figures",
        "--standalone",
        "--embed-resources",
        "--resource-path", str(src_dir),
        "--metadata", f"lang={language}",
        "--metadata", f"pagetitle={title}",
        "-H", str(style),
    ]
    proc = subprocess.run(pandoc_cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout + proc.stderr)
        sys.exit(1)

    args = [
        "--title", title,
        "--language", language,
        "--input-encoding", "utf-8",
        "--level1-toc", "//h:h2",
        "--level2-toc", "//h:h3",
        "--level3-toc", "//h:h4",
        "--max-toc-links", "0",
        "--no-inline-toc",
    ]
    if Path(out).suffix.lower() in (".azw3", ".mobi"):
        args += ["--output-profile", "kindle"]
    if author.strip():
        args += ["--authors", author]

    assets = src_dir / (src_path.stem + ".assets")
    for ext in ("png", "jpg", "jpeg"):
        cover = assets / f"cover.{ext}"
        if cover.exists():
            args += ["--cover", str(cover)]
            break

    stdout, stderr = io.StringIO(), io.StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        result = convert(str(html_path), out, *args)

if not result["success"]:
    sys.stderr.write(stdout.getvalue())
    sys.stderr.write(stderr.getvalue())
    sys.stderr.write(result["message"] + "\n")
    sys.exit(1)

print(f"已生成: {out}")
PY
