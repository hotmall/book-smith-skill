#!/usr/bin/env bash
# install.sh —— 安装 book-smith-skill，并同步安装 chinese-style-guide
#
# 用法:
#   bash scripts/install.sh [--target SKILLS_DIR] [--force]
#
# 默认装到 OpenCode 的全局技能目录 ~/.config/opencode/skills：
#   <SKILLS_DIR>/book-smith-skill/
#   <SKILLS_DIR>/chinese-style-guide/
#
# Claude Code 用:
#   bash scripts/install.sh --target ~/.claude/skills
#
# 也可以设置环境变量 OPENCODE_SKILLS_DIR 覆盖默认目录。
set -euo pipefail

self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target="${OPENCODE_SKILLS_DIR:-$HOME/.config/opencode/skills}"
force=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --force)
      force=1
      shift
      ;;
    -h | --help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "未知选项: $1" >&2
      exit 1
      ;;
  esac
done

mkdir -p "$target"
target="$(cd "$target" && pwd)"
skill_target="$target/book-smith-skill"
guide_target="$target/chinese-style-guide"

copy_tree() {
  local from="$1" to="$2"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude '.git' --exclude '.DS_Store' --exclude '__pycache__' \
      --exclude '.venv*' --exclude 'dist' \
      "$from/" "$to/"
  else
    mkdir -p "$to"
    cp -R "$from/." "$to/"
    rm -rf "$to/.git" "$to/dist" "$to"/.venv* "$to"/scripts/__pycache__
  fi
}

# --------------------------------------------------------------------------- #
# 1. 安装本 skill
# --------------------------------------------------------------------------- #
if [ "$self_dir" = "$skill_target" ]; then
  echo "book-smith-skill 已在目标目录: $skill_target"
elif [ -e "$skill_target" ] && [ "$force" = 0 ]; then
  echo "错误: $skill_target 已存在。加 --force 覆盖，或手动更新。" >&2
  exit 1
else
  [ "$force" = 1 ] && rm -rf "$skill_target"
  copy_tree "$self_dir" "$skill_target"
  echo "已安装 book-smith-skill -> $skill_target"
fi

# --------------------------------------------------------------------------- #
# 2. 同步安装 chinese-style-guide
# --------------------------------------------------------------------------- #
if [ -f "$guide_target/SKILL.md" ] && [ "$force" = 0 ]; then
  echo "chinese-style-guide 已安装: $guide_target"
else
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/csg-install.XXXXXX")"
  trap 'rm -rf "$tmpdir"' EXIT
  echo "正在获取 chinese-style-guide ..."
  if ! git clone --depth 1 --quiet \
    https://github.com/RightCapitalHQ/chinese-style-guide.git "$tmpdir/repo"; then
    if [ -f "$guide_target/SKILL.md" ]; then
      echo "警告: 获取失败，保留现有 chinese-style-guide: $guide_target" >&2
    else
      echo "错误: 无法克隆 chinese-style-guide，请检查网络后重试。" >&2
      echo "也可手动安装到: $guide_target" >&2
      exit 1
    fi
  else
    source_dir="$tmpdir/repo/.claude/skills/chinese-style-guide"
    if [ ! -f "$source_dir/SKILL.md" ]; then
      echo "错误: 仓库结构不符合预期，未找到 $source_dir/SKILL.md" >&2
      exit 1
    fi
    [ "$force" = 1 ] && rm -rf "$guide_target"
    copy_tree "$source_dir" "$guide_target"
    echo "已安装 chinese-style-guide -> $guide_target"
  fi
fi

echo
echo "安装完成。重新打开会话（或刷新技能列表）后即可使用。"
echo "自检: bash $skill_target/scripts/doctor.sh"
