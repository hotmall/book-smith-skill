#!/usr/bin/env bash
# md2pdf.sh —— Markdown → 印刷级 PDF（pandoc + WeasyPrint）
#
# 用法:
#   md2pdf.sh INPUT.md [-o OUT.pdf] [-s STYLE.html] [--paper A4] [--margin "18mm 16mm"]
#             [--toc] [--toc-depth N] [--title T] [--author A] [--lang zh|en]
#             [--keep-html PATH]
#
# 说明:
#   * 默认使用 assets/pdf-style.html（可用 -s 换样式，或用环境变量 BOOKSMITH_PDF_STYLE）
#   * 样式文件是 HTML 片段（内含 <style>…</style>），会作为 pandoc 的 header-includes 注入
#   * 页面尺寸/页边距建议用 --paper / --margin 覆盖，不要改样式里的 @page
#   * Markdown 里已有 "## 目录" 时不要加 --toc，避免出现两份目录
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
assets_dir="$self_dir/../assets"
template="$assets_dir/template.html"
style="${BOOKSMITH_PDF_STYLE:-$assets_dir/pdf-style.html}"

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
  echo "错误: $*" >&2
  exit 1
}

src=""
out=""
paper=""
margin=""
title=""
author=""
lang=""
keep_html=""
toc=0
toc_depth=2

while [ $# -gt 0 ]; do
  case "$1" in
    -o | --output) out="${2:-}"; shift 2 ;;
    -s | --style) style="${2:-}"; shift 2 ;;
    --paper) paper="${2:-}"; shift 2 ;;
    --margin) margin="${2:-}"; shift 2 ;;
    -t | --title) title="${2:-}"; shift 2 ;;
    -a | --author) author="${2:-}"; shift 2 ;;
    --lang) lang="${2:-}"; shift 2 ;;
    --toc) toc=1; shift ;;
    --toc-depth) toc_depth="${2:-}"; shift 2 ;;
    --keep-html) keep_html="${2:-}"; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "未知选项: $1" ;;
    *)
      [ -n "$src" ] && die "只能指定一个输入文件"
      src="$1"
      shift
      ;;
  esac
done

[ -n "$src" ] || { usage; exit 1; }
[ -f "$src" ] || die "找不到文件 $src"
command -v pandoc >/dev/null 2>&1 || die "需要 pandoc（brew install pandoc）"
command -v weasyprint >/dev/null 2>&1 || die "需要 weasyprint（pip install weasyprint）"
[ -f "$style" ] || die "找不到样式文件 $style"
[ -f "$template" ] || die "找不到模板 $template"

if [ -z "$out" ]; then
  mkdir -p dist
  out="dist/$(basename "${src%.*}").pdf"
fi
mkdir -p "$(dirname "$out")"
src_dir="$(cd "$(dirname "$src")" && pwd)"

# 未显式指定标题时，用 Markdown 的首个一级标题（仅作 <title>，不再生成标题块）
user_title="$title"
if [ -z "$title" ]; then
  title="$(sed -n 's/^# \{1,\}\([^#].*\)$/\1/p' "$src" | head -n 1)"
fi
[ -n "$title" ] || title="$(basename "${src%.*}")"

# 语言：显式指定 > 正文含中日韩字符则 zh > en
if [ -z "$lang" ]; then
  if python3 -c 'import sys,re; sys.exit(0 if re.search(r"[\u3400-\u9fff]", open(sys.argv[1], encoding="utf-8", errors="ignore").read()) else 1)' "$src"; then
    lang=zh
  else
    lang=en
  fi
fi

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/booksmith-pdf.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT
tmphtml="$tmpdir/book.html"

# 样式文件允许是纯 CSS：没有 <style> 标签就自动包一层
style_arg="$style"
if ! grep -qi '<style' "$style"; then
  {
    echo "<style>"
    cat "$style"
    echo "</style>"
  } >"$tmpdir/style.html"
  style_arg="$tmpdir/style.html"
fi

pandoc_args=(
  "$src"
  -o "$tmphtml"
  -f markdown-implicit_figures
  --standalone
  --embed-resources
  --resource-path="$src_dir"
  --template="$template"
  --metadata "lang=$lang"
  --metadata "pagetitle=$title"
  -H "$style_arg"
)

if [ -n "$user_title" ]; then
  pandoc_args+=(--metadata "title=$user_title")
fi
if [ -n "$author" ]; then
  pandoc_args+=(--metadata "author=$author")
fi
if [ "$toc" = 1 ]; then
  pandoc_args+=(--toc "--toc-depth=$toc_depth")
fi

# 用第二个 header-includes 追加 @page 覆盖，后写的规则优先生效
if [ -n "$paper" ] || [ -n "$margin" ]; then
  {
    echo "<style>"
    echo "@page {"
    [ -n "$paper" ] && echo "  size: $paper;"
    [ -n "$margin" ] && echo "  margin: $margin;"
    echo "}"
    echo "</style>"
  } >"$tmpdir/page.html"
  pandoc_args+=(-H "$tmpdir/page.html")
fi

echo "正在生成: $src -> $out"
pandoc "${pandoc_args[@]}"

weasyprint "$tmphtml" "$out"

if [ -n "$keep_html" ]; then
  cp "$tmphtml" "$keep_html"
  echo "已保留中间 HTML: $keep_html"
fi

echo "已生成: $out"
