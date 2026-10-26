#!/usr/bin/env bash
# pyenv.sh —— book-smith-skill 的统一 Python 环境
#
# 所有需要 Python 依赖的步骤共用 skill 目录下的同一个 venv（默认 .venv）：
#   pdfplumber + pillow    pdf2md.py     PDF → Markdown
#   weasyprint             build-pdf.sh  Markdown → PDF
#   ebook-converter-lib    build-azw3.sh Markdown → EPUB / AZW3 / MOBI
#
# 依赖按需装进这同一个 venv：第一次用到哪一步就装哪一组，之后复用，
# 不再出现多个环境（旧版 .venv-azw3 会在下次运行时自动迁移过来）。
#
# 用法（命令行）:
#   ./pyenv.sh status                          查看 venv 与依赖状态
#   ./pyenv.sh ensure [--md] [--pdf] [--ebook] [--all]
#   ./pyenv.sh python [--ebook] [--all]        准备后打印 venv python 路径
#   ./pyenv.sh run [--ebook] [--all] CMD...    在 venv 里执行命令
#
# 也可被其他脚本 source，复用 venv_python / has_module / ensure_* 等函数。
# 环境变量:
#   BOOKSMITH_VENV    自定义 venv 目录（默认 <skill>/.venv）
#   BOOKSMITH_PYTHON  指定创建 venv 的基础解释器（默认找 3.11+）
set -uo pipefail

_pyenv_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOKSMITH_SKILL_DIR="${BOOKSMITH_SKILL_DIR:-$(cd "$_pyenv_self/.." && pwd)}"
BOOKSMITH_VENV="${BOOKSMITH_VENV:-$BOOKSMITH_SKILL_DIR/.venv}"
BOOKSMITH_LEGACY_VENV="$BOOKSMITH_SKILL_DIR/.venv-azw3"

PYENV_MD_PACKAGES=('pdfplumber>=0.10' 'pillow')
PYENV_PDF_PACKAGES=('weasyprint')
PYENV_EBOOK_PACKAGES=('ebook-converter-lib>=1.2,<2')
PYENV_MIN_VERSION='3.11'

# --------------------------------------------------------------------------- #
# 基础查询
# --------------------------------------------------------------------------- #
venv_python() { printf '%s/bin/python' "$BOOKSMITH_VENV"; }

venv_ready() { [ -x "$(venv_python)" ]; }

# has_module <python> <module...> —— 用 find_spec 判断，不真正 import
has_module() {
  local py="$1"
  shift
  [ -x "$py" ] || return 1
  "$py" - "$@" >/dev/null 2>&1 <<'PY'
import importlib.util
import sys

missing = [name for name in sys.argv[1:] if importlib.util.find_spec(name) is None]
sys.exit(0 if not missing else 1)
PY
}

# find_python —— 找到可用来建 venv 的 Python 3.11+
find_python() {
  local candidate path
  if [ -n "${BOOKSMITH_PYTHON:-}" ] && [ -x "${BOOKSMITH_PYTHON}" ]; then
    printf '%s\n' "$BOOKSMITH_PYTHON"
    return 0
  fi
  for candidate in python3.13 python3.12 python3.14 python3.11 python3; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if "$candidate" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3, 11) else 1)' 2>/dev/null; then
      command -v "$candidate"
      return 0
    fi
  done
  if command -v uv >/dev/null 2>&1; then
    path="$(uv python find '>=3.11' 2>/dev/null || true)"
    if [ -n "$path" ] && [ -x "$path" ]; then
      printf '%s\n' "$path"
      return 0
    fi
  fi
  return 1
}

# --------------------------------------------------------------------------- #
# 创建 / 迁移
# --------------------------------------------------------------------------- #
# 旧版把电子书环境单独放在 .venv-azw3；搬家到统一 .venv 时修掉 bin/ 脚本里的
# 绝对路径 shebang（venv 可能来自别的位置，所以不按旧路径匹配，而是按 python 判定）。
migrate_legacy_venv() {
  [ "$BOOKSMITH_VENV" = "$BOOKSMITH_SKILL_DIR/.venv" ] || return 0
  [ -d "$BOOKSMITH_VENV" ] && return 0
  [ -x "$BOOKSMITH_LEGACY_VENV/bin/python" ] || return 0
  echo "迁移旧环境: $BOOKSMITH_LEGACY_VENV → $BOOKSMITH_VENV" >&2
  mv "$BOOKSMITH_LEGACY_VENV" "$BOOKSMITH_VENV" || return 1
  "$(venv_python)" - "$BOOKSMITH_VENV" >/dev/null 2>&1 <<'PY'
import sys
from pathlib import Path

venv = Path(sys.argv[1])
new_py = str(venv / "bin" / "python").encode()
for path in (venv / "bin").iterdir():
    if path.is_symlink() or not path.is_file():
        continue
    try:
        data = path.read_bytes()
    except OSError:
        continue
    if not data.startswith(b"#!"):
        continue
    end = data.find(b"\n")
    if end < 0 or b"python" not in data[:end]:
        continue
    path.write_bytes(b"#!" + new_py + data[end:])
PY
  return 0
}

ensure_venv() {
  migrate_legacy_venv
  venv_ready && return 0
  local py
  if ! py="$(find_python)"; then
    cat >&2 <<'EOF'
错误: 需要 Python 3.11 或更新版本来创建统一 venv
  macOS: brew install python@3.12   （或 brew install uv）
  Linux: sudo apt install python3.11-venv
EOF
    return 1
  fi
  echo "首次运行: 用 $py 创建统一 venv $BOOKSMITH_VENV" >&2
  "$py" -m venv "$BOOKSMITH_VENV" || {
    echo "错误: 创建 venv 失败: $BOOKSMITH_VENV" >&2
    return 1
  }
  "$(venv_python)" -m pip install --quiet --disable-pip-version-check --upgrade pip >&2 ||
    echo "提示: pip 升级失败，继续使用自带版本" >&2
  return 0
}

venv_pip_install() {
  local packages=("$@")
  echo "安装 Python 依赖（$(basename "$BOOKSMITH_VENV")）: ${packages[*]}" >&2
  "$(venv_python)" -m pip install --quiet --disable-pip-version-check "${packages[@]}"
}

# --------------------------------------------------------------------------- #
# 按需安装：全部装进同一个 venv
# --------------------------------------------------------------------------- #
# PDF → Markdown：pdfplumber + pillow（必需）
ensure_md_deps() {
  ensure_venv || return 1
  has_module "$(venv_python)" pdfplumber PIL && return 0
  venv_pip_install "${PYENV_MD_PACKAGES[@]}"
}

# Markdown → PDF：weasyprint（可选，macOS 还需系统 pango）
ensure_pdf_deps() {
  ensure_venv || return 1
  has_module "$(venv_python)" weasyprint && return 0
  venv_pip_install "${PYENV_PDF_PACKAGES[@]}"
}

# Markdown → 电子书：ebook-converter-lib（体积较大，首次较慢）
ensure_ebook_deps() {
  ensure_venv || return 1
  has_module "$(venv_python)" ebook_converter_lib && return 0
  venv_pip_install "${PYENV_EBOOK_PACKAGES[@]}"
}

ensure_all_deps() {
  local status=0
  ensure_md_deps || status=1
  ensure_pdf_deps || status=1
  ensure_ebook_deps || status=1
  return "$status"
}

# --------------------------------------------------------------------------- #
# 状态输出
# --------------------------------------------------------------------------- #
pyenv_status() {
  local py
  py="$(venv_python)"
  echo "统一 Python 环境"
  if venv_ready; then
    printf '  ✓ venv: %s（%s）\n' "$BOOKSMITH_VENV" "$("$py" -V 2>&1)"
  else
    printf '  · venv: %s（尚未创建）\n' "$BOOKSMITH_VENV"
    if base="$(find_python)"; then
      printf '  ✓ 基础解释器: %s（%s）\n' "$base" "$("$base" -V 2>&1)"
    else
      printf '  ✗ 缺少 Python 3.11+ → brew install python@3.12 或 brew install uv\n'
    fi
  fi

  printf '依赖\n'
  if has_module "$py" pdfplumber PIL; then
    printf '  ✓ pdfplumber + pillow（pdf2md.py）\n'
  else
    printf '  · pdfplumber + pillow 未装（首次运行 pdf2md.py 时自动安装）\n'
  fi
  if [ -x "$BOOKSMITH_VENV/bin/weasyprint" ] &&
    "$BOOKSMITH_VENV/bin/weasyprint" --version >/dev/null 2>&1; then
    printf '  ✓ weasyprint（build-pdf.sh）\n'
  elif has_module "$py" weasyprint; then
    printf '  · weasyprint 已安装但无法运行（macOS 需要 brew install pango）\n'
  elif command -v weasyprint >/dev/null 2>&1; then
    printf '  ✓ weasyprint（系统 PATH，build-pdf.sh 会优先用 venv 内的版本）\n'
  else
    printf '  · weasyprint 未装（首次运行 build-pdf.sh 时自动安装；macOS 还需 brew install pango）\n'
  fi
  if has_module "$py" ebook_converter_lib; then
    printf '  ✓ ebook-converter-lib（build-azw3.sh）\n'
  else
    printf '  · ebook-converter-lib 未装（首次运行 build-azw3.sh 时自动安装）\n'
  fi
  if [ -x "$BOOKSMITH_LEGACY_VENV/bin/python" ]; then
    printf '  · 发现旧环境 .venv-azw3，下次运行会自动迁移到 .venv\n'
  fi
}

usage() { sed -n '2,23p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

# --------------------------------------------------------------------------- #
# 命令行入口
# --------------------------------------------------------------------------- #
_pyenv_main() {
  local cmd="${1:-status}"
  [ $# -gt 0 ] && shift

  local want_md=0 want_pdf=0 want_ebook=0 want_all=0
  local args=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --md) want_md=1 ;;
      --pdf) want_pdf=1 ;;
      --ebook) want_ebook=1 ;;
      --all) want_all=1 ;;
      -h | --help) usage; return 0 ;;
      *) args+=("$1") ;;
    esac
    shift
  done

  prepare() {
    if [ "$want_all" = 1 ]; then
      ensure_all_deps
    else
      local status=0
      # 未指定任何分组时按命令给最小依赖：run/python 默认 --md
      if [ "$want_md" = 0 ] && [ "$want_pdf" = 0 ] && [ "$want_ebook" = 0 ]; then
        want_md=1
      fi
      [ "$want_md" = 1 ] && { ensure_md_deps || status=1; }
      [ "$want_pdf" = 1 ] && { ensure_pdf_deps || status=1; }
      [ "$want_ebook" = 1 ] && { ensure_ebook_deps || status=1; }
      return "$status"
    fi
  }

  case "$cmd" in
    status) pyenv_status ;;
    ensure) prepare ;;
    python)
      prepare || return 1
      venv_python
      echo
      ;;
    run)
      if [ ${#args[@]} -eq 0 ]; then
        echo "用法: ./pyenv.sh run [--ebook] CMD..." >&2
        return 1
      fi
      prepare || return 1
      exec env -u PYTHONHOME \
        BOOKSMITH_BOOTSTRAPPED=1 \
        VIRTUAL_ENV="$BOOKSMITH_VENV" \
        PATH="$BOOKSMITH_VENV/bin:$PATH" \
        "${args[@]}"
      ;;
    -h | --help | help) usage ;;
    *)
      echo "未知命令: $cmd" >&2
      usage >&2
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _pyenv_main "$@"
  exit $?
fi
