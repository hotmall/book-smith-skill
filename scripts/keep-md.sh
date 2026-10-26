#!/usr/bin/env bash
# keep-md.sh —— 把定稿 Markdown 留存在源文档旁边
#
# 用法:
#   ./keep-md.sh <源文档> <定稿.md> [--no-check]
#
# Markdown 当中间产物时（如 a.pdf → a.md → HTML → PDF/AZW3），定稿
# （md-lint.sh 通过）后必须留存在源文档旁边：
#   <源文档目录>/<源文件名>.md
#   <源文档目录>/<源文件名>.assets/    有图片时一起留存
#
# 默认先跑 md-lint.sh --check-only，确认 chinese-style-guide 与
# markdownlint 都通过后才留存；--no-check 跳过（例如刚刚已经跑过）。
# assets 目录名随源文档改变时，会同步改写 Markdown 里的图片链接。
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source_doc=""
md=""
check=1
for arg in "$@"; do
  case "$arg" in
    --no-check) check=0 ;;
    -h | --help)
      sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      if [ -z "$source_doc" ]; then
        source_doc="$arg"
      elif [ -z "$md" ]; then
        md="$arg"
      else
        echo "只能指定 <源文档> 和 <定稿.md> 两个参数" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$source_doc" ] || [ -z "$md" ]; then
  echo "用法: ./keep-md.sh <源文档> <定稿.md> [--no-check]" >&2
  exit 1
fi
[ -f "$source_doc" ] || {
  echo "错误: 找不到源文档 $source_doc" >&2
  exit 1
}
[ -f "$md" ] || {
  echo "错误: 找不到 Markdown $md" >&2
  exit 1
}

source_dir="$(cd "$(dirname "$source_doc")" && pwd)"
source_base="$(basename "$source_doc")"
source_stem="${source_base%.*}"
if [ -z "$source_stem" ]; then
  echo "错误: 源文档文件名无法派生 Markdown 文件名: $source_base" >&2
  exit 1
fi
target="$source_dir/$source_stem.md"

md_dir="$(cd "$(dirname "$md")" && pwd)"
md_base="$(basename "$md")"
md_stem="${md_base%.md}"
md="$md_dir/$md_base"

src_assets="$md_dir/$md_stem.assets"
dst_assets="$source_dir/$source_stem.assets"

# 已经在源文档旁边：只确认 assets 目录符合约定
if [ "$md" = "$target" ]; then
  echo "定稿 Markdown 已在源文档旁边: $target"
  if [ -d "$src_assets" ]; then
    echo "图片目录已在: $src_assets"
  elif grep -q '!\[' "$md"; then
    echo "提示: Markdown 含图片，但未找到 $md_stem.assets/，请确认图片链接有效" >&2
  fi
  exit 0
fi

# 定稿确认：chinese-style-guide 与 markdownlint 都通过才留存
if [ "$check" = 1 ]; then
  if ! bash "$self_dir/md-lint.sh" --check-only "$md"; then
    echo "错误: Markdown 收尾未通过。修正后重跑，或加 --no-check 跳过检查。" >&2
    exit 1
  fi
  echo
fi

if [ -e "$target" ]; then
  echo "已覆盖旧文件: $target"
fi
cp "$md" "$target"
echo "已留存: $target"

if [ -d "$src_assets" ] && [ "$src_assets" != "$dst_assets" ]; then
  rm -rf "$dst_assets"
  cp -R "$src_assets" "$dst_assets"
  echo "已留存图片目录: $dst_assets"
fi

# assets 目录名变了（md 文件名 ≠ 源文档名）：同步改写图片链接
if [ "$md_stem" != "$source_stem" ]; then
  rewritten="$(python3 - "$target" "$md_stem.assets" "$source_stem.assets" <<'PY'
import sys
from pathlib import Path

path, old, new = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
text = path.read_text(encoding="utf-8")
out = text
for token in (f"](<{old}/", f"]({old}/", f'src="{old}/', f"src='{old}/"):
    out = out.replace(token, token.replace(old, new))
if out != text:
    path.write_text(out, encoding="utf-8")
    print("yes")
PY
)"
  if [ "$rewritten" = "yes" ]; then
    echo "已改写图片链接: $md_stem.assets/ → $source_stem.assets/"
  fi
elif [ ! -d "$dst_assets" ] && grep -q '!\[' "$target"; then
  echo "提示: Markdown 含图片，但未找到 $md_stem.assets/，请确认图片链接有效" >&2
fi

echo "完成。后续 build-pdf.sh / build-azw3.sh 请用这份留存的 Markdown。"
