#!/usr/bin/env bash
# md-lint.sh —— 生成 Markdown 后的固定收尾步骤
#
# 用法:
#   ./md-lint.sh <input.md> [--check-only]
#
# 顺序很重要：先中文排版，后结构 lint。
#   1. chinese-style-guide 的 check_format.py：检查中英文空格、标点、数字与日期
#      格式。这一步只报告、不自动改，避免改坏正文语义；按它的规则修正后重跑。
#   2. markdownlint --fix：按修正后的文本做最后的结构整理（空行、标题包围空行、
#      分隔线写法等），再跑一次 markdownlint 确认没有残留。
#
# 因为中文排版修正可能影响行结构，最终应以最后一次 md-lint.sh 的结果为准。
# 脚本退出码：0 = 全部通过；1 = 仍有需要人工确认的问题。
set -uo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config="$self_dir/../.markdownlint.json"

file=""
check_only=0
for arg in "$@"; do
  case "$arg" in
    --check-only) check_only=1 ;;
    -h | --help)
      sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      [ -n "$file" ] && {
        echo "只能指定一个 Markdown 文件" >&2
        exit 1
      }
      file="$arg"
      ;;
  esac
done

if [ -z "$file" ] || [ ! -f "$file" ]; then
  echo "用法: ./md-lint.sh <input.md> [--check-only]" >&2
  exit 1
fi

status=0

# 0) 统一分隔线：*** / ___ / * * * → ---（jpm 的输出约定）
if [ "$check_only" = 0 ]; then
  python3 - "$file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").split("\n")
rule = re.compile(r"^[ \t]*(?:(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|(?:\+[ \t]*){3,})$")
in_code = False
changed = False
for index, line in enumerate(lines):
    if line.strip().startswith("```"):
        in_code = not in_code
        continue
    if not in_code and rule.match(line):
        lines[index] = "---"
        changed = True
if changed:
    path.write_text("\n".join(lines), encoding="utf-8")
    print("已统一分隔线: *** / ___ → ---")
PY
fi

# --------------------------------------------------------------------------- #
# 1. 中文排版检查（先做；修正后需要重跑本脚本）
# --------------------------------------------------------------------------- #
guide=""
for candidate in \
  "${BOOKSMITH_CHINESE_GUIDE:-}" \
  "$self_dir/../vendor/chinese-style-guide/scripts/check_format.py" \
  "${BOOKSMITH_SKILLS_DIR:-$HOME/.config/opencode/skills}/chinese-style-guide/scripts/check_format.py" \
  "$HOME/.claude/skills/chinese-style-guide/scripts/check_format.py"; do
  [ -z "$candidate" ] && continue
  if [ -d "$candidate" ]; then
    candidate="$candidate/scripts/check_format.py"
  fi
  if [ -f "$candidate" ]; then
    guide="$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")"
    break
  fi
done

echo "== chinese-style-guide =="
if [ -n "$guide" ]; then
  # 给检查器一份临时副本：忽略 YAML frontmatter、HTML 注释和行内代码。
  # 上游检查器把行内代码替换成空格，会把「（`code`）」误报成括号内多余空格。
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/md-check.XXXXXX")"
  trap 'rm -rf "$tmpdir"' EXIT
  tmp_check="$tmpdir/$(basename "$file")"
  python3 - "$file" "$tmp_check" <<'PY'
import re
import sys
from pathlib import Path

src, dst = sys.argv[1], sys.argv[2]
lines = Path(src).read_text(encoding="utf-8").split("\n")

# 1) YAML frontmatter 整段留空（保留行数/行号）
if lines and lines[0].strip() == "---":
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            for blank in range(index + 1):
                lines[blank] = ""
            break

text = "\n".join(lines)

# 2) HTML 注释留空（保留换行数）
text = re.sub(
    r"<!--.*?-->",
    lambda match: "\n" * match.group(0).count("\n"),
    text,
    flags=re.S,
)

# 3) 行内代码替换成等长占位符（不检查代码内容，也不触发空格/括号误报）
text = re.sub(r"``[^`\n]+``", lambda m: "□" * len(m.group(0)), text)
text = re.sub(r"`[^`\n]+`", lambda m: "□" * len(m.group(0)), text)

Path(dst).write_text(text, encoding="utf-8")
PY
  if (cd "$tmpdir" && python3 "$guide" "$(basename "$file")"); then
    echo "中文排版: 通过"
  else
    echo "中文排版: 仍有问题。按 chinese-style-guide 的规则修正后重跑本脚本，" >&2
    echo "          让 markdownlint 在最终文本上做最后一遍结构检查。" >&2
    status=1
  fi
else
  echo "未安装 chinese-style-guide。先运行: bash $self_dir/install.sh" >&2
  status=1
fi

# --------------------------------------------------------------------------- #
# 2. 结构 lint（最后做，基于中文排版修正后的文本）
# --------------------------------------------------------------------------- #
if command -v markdownlint >/dev/null 2>&1; then
  lint=(markdownlint)
elif command -v npx >/dev/null 2>&1; then
  lint=(npx --yes markdownlint-cli)
else
  echo "警告: 未安装 markdownlint（npm install -g markdownlint-cli），跳过结构检查" >&2
  lint=()
fi

echo
echo "== markdownlint =="
if [ ${#lint[@]} -gt 0 ]; then
  if [ "$check_only" = 0 ]; then
    "${lint[@]}" --config "$config" --fix "$file" >/dev/null 2>&1 || true
  fi
  if "${lint[@]}" --config "$config" "$file"; then
    echo "markdown lint: 通过"
  else
    echo "markdown lint: 仍有问题，按上面的行号修正后重跑" >&2
    status=1
  fi
fi

exit "$status"
