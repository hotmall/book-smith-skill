#!/usr/bin/env python3
"""md2ebook.py —— Markdown → EPUB / AZW3 / MOBI（pandoc + Calibre 引擎）

用法:
    md2ebook.py INPUT.md [-o OUT.azw3] [-f epub|azw3|mobi|docx] [选项]

选项:
    -o, --output PATH     输出文件（扩展名决定格式，默认 dist/<名字>.azw3）
    -f, --format FMT      显式指定格式（epub / azw3 / mobi / docx）
    -t, --title TEXT      书名（默认取 Markdown 首个一级标题）
    -a, --author TEXT     作者
    -s, --style PATH      样式文件（默认 assets/ebook-style.html）
    --cover PATH          封面图（默认找 <md 名>.assets/cover.*）
    --keep-toc            保留 Markdown 里手写的「## 目录」章节
    --toc-depth N         导航目录层级（默认 3 → h2/h3/h4）
    --series NAME         系列名
    --series-index N      系列序号
    --arg OPT            追加传给 Calibre 的参数（可重复），如 --arg=--publisher=xx
    --keep-html PATH      保留中间 HTML 便于排查
    --venv DIR            指定 ebook-converter-lib 的虚拟环境目录
    --debug               打印执行细节

依赖: pandoc；Calibre 的 ebook-convert，或 Python 3.11+（会自动建缓存虚拟环境
      并安装 ebook-converter-lib）。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

SELF_DIR = Path(__file__).resolve().parent
ASSETS = SELF_DIR.parent / "assets"
LIB_SPEC = "ebook-converter-lib>=1.2,<2"
TOC_TITLE_RE = re.compile(r"^#{1,3}\s+(目\s*录|contents|table of contents)\s*$", re.I | re.M)
HEADING_RE = re.compile(r"^(#{1,6})\s+", re.M)
CJK_RE = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
FORMATS = ("epub", "azw3", "mobi", "docx")


# --------------------------------------------------------------------------- #
# 依赖与虚拟环境
# --------------------------------------------------------------------------- #
def cache_home() -> Path:
    if os.environ.get("BOOKSMITH_CACHE"):
        return Path(os.environ["BOOKSMITH_CACHE"]).expanduser()
    base = os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache"
    return Path(base).expanduser() / "booksmith"


def find_python() -> str | None:
    for name in ("python3.13", "python3.12", "python3.11", "python3.14", "python3"):
        candidate = shutil.which(name)
        if not candidate:
            continue
        probe = subprocess.run(
            [candidate, "-c", "import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)"],
            capture_output=True,
        )
        if probe.returncode == 0:
            return candidate
    uv = shutil.which("uv")
    if uv:
        probe = subprocess.run([uv, "python", "find", ">=3.11"], capture_output=True, text=True)
        if probe.returncode == 0 and probe.stdout.strip():
            return probe.stdout.strip()
    return None


def ensure_library(venv: Path) -> None:
    """导入 Calibre 的转换库；当前解释器没有就换到缓存虚拟环境重跑。"""
    try:
        import ebook_converter_lib  # noqa: F401

        return
    except ImportError:
        pass

    venv_python = venv / "bin" / "python"
    if venv_python.exists():
        probe = subprocess.run(
            [str(venv_python), "-c", "import ebook_converter_lib"], capture_output=True
        )
        if probe.returncode == 0:
            os.execv(str(venv_python), [str(venv_python), __file__, *sys.argv[1:]])

    python = find_python()
    if not python:
        sys.exit(
            "错误: 需要 Python 3.11+（或已安装 Calibre 的 ebook-convert）\n"
            "  macOS: brew install python@3.12  或  brew install --cask calibre"
        )

    print(f"首次运行: 用 {python} 创建 {venv} 并安装 {LIB_SPEC} ...", file=sys.stderr)
    venv.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([python, "-m", "venv", str(venv)], check=True)
    pip = [str(venv_python), "-m", "pip", "install", "--quiet", "--upgrade", "pip"]
    subprocess.run(pip, check=True)
    uv = shutil.which("uv")
    install = (
        [uv, "pip", "install", "--quiet", "--python", str(venv_python), LIB_SPEC]
        if uv
        else [str(venv_python), "-m", "pip", "install", "--quiet", LIB_SPEC]
    )
    subprocess.run(install, check=True)

    probe = subprocess.run([str(venv_python), "-c", "import ebook_converter_lib"], capture_output=True)
    if probe.returncode != 0:
        sys.exit("错误: ebook-converter-lib 安装失败，请检查网络后重试，或改用 Calibre 的 ebook-convert")
    os.execv(str(venv_python), [str(venv_python), __file__, *sys.argv[1:]])


# --------------------------------------------------------------------------- #
# Markdown 预处理与渲染
# --------------------------------------------------------------------------- #
def expand_args(items: list[str]) -> list[str]:
    """把 --arg=--publisher=某社 这种写法拆成 Calibre 需要的两个参数。"""
    expanded: list[str] = []
    for item in items:
        if item.startswith("--") and "=" in item and not item.startswith("--="):
            name, value = item.split("=", 1)
            expanded.extend([name, value])
        else:
            expanded.append(item)
    return expanded


def strip_manual_toc(text: str) -> str:
    """删掉手写的「## 目录」章节：电子书阅读器会自己生成导航目录。"""
    match = TOC_TITLE_RE.search(text)
    if not match:
        return text
    level = len(match.group(0)) - len(match.group(0).lstrip("#"))
    rest = text[match.end() :]
    end = len(rest)
    for heading in HEADING_RE.finditer(rest):
        if len(heading.group(1)) <= level:
            end = heading.start()
            break
    return text[: match.start()] + rest[end:]


def first_heading(text: str) -> str:
    match = re.search(r"^#\s+(.+?)\s*$", text, re.M)
    return match.group(1) if match else ""


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="md2ebook.py",
        description="Markdown → EPUB / AZW3 / MOBI（pandoc + Calibre）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
        "  md2ebook.py book.md -o dist/book.epub -a 作者\n"
        "  md2ebook.py book.md -f azw3 --cover cover.jpg --series 系列名 --series-index 1",
    )
    parser.add_argument("input", help="输入 Markdown")
    parser.add_argument("-o", "--output", help="输出文件（默认 dist/<名字>.azw3）")
    parser.add_argument("-f", "--format", choices=FORMATS, help="输出格式")
    parser.add_argument("-t", "--title", default="", help="书名")
    parser.add_argument("-a", "--author", default="", help="作者")
    parser.add_argument("-s", "--style", help="样式文件（HTML 片段）")
    parser.add_argument("--cover", help="封面图")
    parser.add_argument("--keep-toc", action="store_true", help="保留手写目录章节")
    parser.add_argument("--toc-depth", type=int, default=3, help="导航目录层级（默认 3）")
    parser.add_argument("--series", default="", help="系列名")
    parser.add_argument("--series-index", default="", help="系列序号")
    parser.add_argument("--arg", action="append", default=[], help="追加 Calibre 参数")
    parser.add_argument("--keep-html", help="保留中间 HTML")
    parser.add_argument("--venv", help="ebook-converter-lib 的虚拟环境目录")
    parser.add_argument("--debug", action="store_true", help="打印执行细节")
    args = parser.parse_args()

    src = Path(args.input).expanduser()
    if not src.is_file():
        sys.exit(f"错误: 找不到文件 {src}")

    fmt = args.format or (Path(args.output).suffix.lower().lstrip(".") if args.output else "azw3")
    if fmt not in FORMATS:
        sys.exit(f"错误: 不支持的格式 {fmt}（可选: {', '.join(FORMATS)}）")
    out = Path(args.output).expanduser() if args.output else Path("dist") / f"{src.stem}.{fmt}"
    out.parent.mkdir(parents=True, exist_ok=True)

    if shutil.which("pandoc") is None:
        sys.exit("错误: 需要 pandoc（brew install pandoc）")

    style = Path(args.style).expanduser() if args.style else Path(
        os.environ.get("BOOKSMITH_EBOOK_STYLE", ASSETS / "ebook-style.html")
    )
    template = ASSETS / "template.html"
    for required in (style, template):
        if not required.is_file():
            sys.exit(f"错误: 找不到 {required}")

    text = src.read_text(encoding="utf-8")
    title = args.title.strip() or first_heading(text) or src.stem
    language = "zh" if CJK_RE.search(text[:5000]) else "en"

    use_cli = shutil.which("ebook-convert") is not None
    if not use_cli:
        ensure_library(Path(args.venv).expanduser() if args.venv else cache_home() / "venv-ebook")

    with tempfile.TemporaryDirectory(prefix="booksmith-ebook.") as tmp:
        tmpdir = Path(tmp)
        # 样式文件允许是纯 CSS：没有 <style> 标签就自动包一层
        if "<style" not in style.read_text(encoding="utf-8", errors="ignore").lower():
            wrapped = tmpdir / "style.html"
            wrapped.write_text(f"<style>\n{style.read_text(encoding='utf-8')}\n</style>", encoding="utf-8")
            style = wrapped

        md_path = src
        if not args.keep_toc:
            stripped = strip_manual_toc(text)
            if stripped != text:
                md_path = tmpdir / "book.md"
                md_path.write_text(stripped, encoding="utf-8")

        html_path = tmpdir / "book.html"
        pandoc_cmd = [
            "pandoc",
            str(md_path),
            "-o",
            str(html_path),
            "-f",
            "markdown-implicit_figures",
            "--standalone",
            "--embed-resources",
            "--resource-path",
            str(src.parent),
            "--template",
            str(template),
            "--metadata",
            f"lang={language}",
            "--metadata",
            f"pagetitle={title}",
            "-H",
            str(style),
        ]
        if args.debug:
            print("pandoc:", " ".join(pandoc_cmd), file=sys.stderr)
        proc = subprocess.run(pandoc_cmd, capture_output=True, text=True)
        if proc.returncode != 0:
            sys.stderr.write(proc.stdout + proc.stderr)
            sys.exit("错误: pandoc 转换失败")

        convert_args = [
            "--title",
            title,
            "--language",
            language,
            "--input-encoding",
            "utf-8",
        ]
        # 导航目录按标题层级生成：h2 → level1，h3 → level2，h4 → level3
        for level in range(1, min(max(args.toc_depth, 1), 3) + 1):
            convert_args += [f"--level{level}-toc", f"//h:h{level + 1}"]
        if args.toc_depth != 3:
            for index in range(min(args.toc_depth, 3) + 1, 4):
                convert_args.extend([f"--level{index}-toc", ""])
        if args.author.strip():
            convert_args += ["--authors", args.author.strip()]
        if args.series.strip():
            convert_args += ["--series", args.series.strip()]
        if args.series_index.strip():
            convert_args += ["--series-index", args.series_index.strip()]
        if fmt in ("azw3", "mobi"):
            convert_args += ["--output-profile", "kindle"]

        cover = Path(args.cover).expanduser() if args.cover else None
        if cover is None:
            for ext in ("png", "jpg", "jpeg", "webp"):
                candidate = src.with_name(src.stem + ".assets") / f"cover.{ext}"
                if candidate.is_file():
                    cover = candidate
                    break
        if cover is not None:
            if not cover.is_file():
                sys.exit(f"错误: 找不到封面 {cover}")
            convert_args += ["--cover", str(cover)]

        convert_args += expand_args(args.arg)

        print(f"正在转换: {src} -> {out}")
        if use_cli:
            proc = subprocess.run(
                ["ebook-convert", str(html_path), str(out), *convert_args],
                capture_output=True,
                text=True,
            )
            if proc.returncode != 0:
                sys.stderr.write(proc.stdout + proc.stderr)
                sys.exit("错误: ebook-convert 转换失败")
        else:
            from ebook_converter_lib import convert

            stdout, stderr = StringIO(), StringIO()
            with redirect_stdout(stdout), redirect_stderr(stderr):
                result = convert(str(html_path), str(out), *convert_args)
            if not result.get("success"):
                sys.stderr.write(stdout.getvalue() + stderr.getvalue())
                sys.exit(result.get("message") or "错误: 转换失败")

        if args.keep_html:
            shutil.copy(html_path, args.keep_html)
            print(f"已保留中间 HTML: {args.keep_html}")

    size = out.stat().st_size / 1024 if out.exists() else 0
    print(f"已生成: {out}（{size:.0f} KB）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
