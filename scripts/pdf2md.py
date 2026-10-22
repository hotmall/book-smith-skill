#!/usr/bin/env python3
"""pdf2md.py —— 通用 PDF → Markdown 转换器（含图片抽取）。

不绑定某本书的固定版式，而是从 PDF 自身统计出版式规律：

* 正文号：按字符数加权统计出现最多的字号；
* 首行缩进：相对页面左边距的偏移量，换算成"字"判断新段落；
* 引文块：缩进更深的行（诗词、引语），用 `>` 块输出；
* 折行：上一行顶到右边距时，下一行视为续行直接拼接；
* 标题：比正文大的字号按大小映射为 h2、h3…（h1 留给书名）；
* 页眉 / 页脚 / 页码：位于页面上下边缘且在多页重复的行自动剔除；
* 目录：不再照抄 PDF 目录页，用识别出的标题重新生成；
* 图片：按页面位置插入正文，同图去重，首页大图作为 `cover.*`。

用法:
    pdf2md.py INPUT.pdf [-o OUT.md] [选项]

常用选项:
    -o, --output PATH        输出文件（默认与输入同名 .md）
    --title TEXT             书名（默认取 PDF 元数据或首个标题）
    --author TEXT            作者（配合 --frontmatter 写入）
    --frontmatter            输出 YAML frontmatter
    --assets-dir DIR         图片目录（默认 <输出名>.assets）
    --no-images              不导出图片
    --no-cover               不识别封面
    --no-toc                 不生成目录
    --toc-depth N            目录收录到第几级标题（默认 2 → h2/h3）
    --skip-pages RANGE       跳过页面，如 1-2,5（页码从 1 起）
    --body-size PT           强制正文号（默认自动统计）
    --heading-scale F        标题字号阈值倍数（默认 1.12）
    --heading-depth N        标题最多映射几级（默认 3 → h2..h4）
    --heading-base N         最大字号对应的标题级别（默认 2，h1 留给书名）
    --indent-chars N         段落首行缩进字数阈值（默认 2）
    --quote-indent-chars N   引文缩进字数阈值（默认 4）
    --chapter-regex RE       章标题正则，命中则强制作为标题
    --keep-page-numbers      保留页眉页脚与页码
    --no-tables              不抽取表格（默认抽取为 Markdown 表格）
    --paragraph-gap F        段间距达到行高 F 倍算新段（默认 1.2）
    --drop-regex RE          丢弃匹配该正则的行，可重复
    --no-polish              关闭中文标点整理
    --debug                  打印识别到的版式参数

依赖: pip install pdfplumber pillow
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import statistics
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from pathlib import Path

CJK_RE = re.compile(r"[\u3400-\u9fff\uf900-\ufaff]")
DEFAULT_CHAPTER_RE = (
    r"^\s*(第[0-9一二三四五六七八九十百千零〇两]+[章节回卷部篇讲]|Chapter\s+[0-9IVXLC]+)\b"
)
PAGE_NUMBER_RE = re.compile(
    r"^\s*(?:[-—–\s]*\d{1,4}[-—–\s]*"
    r"|第\s*\d+\s*页(?:\s*/\s*共\s*\d+\s*页)?"
    r"|\d+\s*/\s*\d+"
    r"|[ivxlcdm]{1,7})\s*$",
    re.I,
)
TOC_TITLE_RE = re.compile(r"^(目\s*录|contents|table of contents)$", re.I)
TOC_ENTRY_RE = re.compile(
    r"(?:[.·…]{2,}|\s\s+|\s)\s*[0-9ivxlcdm]{1,6}\s*$"  # 点前导符 / 末尾页码
    r"|^\s*[0-9]{1,4}\s+\S",  # 页码在前
    re.I,
)
LIST_RE = re.compile(
    r"^(?P<marker>[-*•·▪◦–—]|\(?\d{1,3}[.)]|[a-zA-Z][.)])\s+(?P<text>.+)$"
)
MONO_RE = re.compile(r"(mono|menlo|courier|consolas|monaco|code|fixed)", re.I)


# --------------------------------------------------------------------------- #
# 数据结构
# --------------------------------------------------------------------------- #
@dataclass
class Line:
    page: int
    text: str
    size: float
    x0: float
    x1: float
    top: float
    bottom: float
    level: int = 0  # 0 = 正文，>=2 = 标题级别
    font: str = ""
    mono_ratio: float = 0.0  # 等宽字体的字符占比（代码行判据）
    code: bool = False


@dataclass
class PageInfo:
    number: int
    width: float
    height: float
    lines: list[Line] = field(default_factory=list)
    tables: list[dict] = field(default_factory=list)

    def is_edge(self, line: Line, ratio: float = 0.1) -> bool:
        """行是否落在页面上/下边缘（页眉页脚区）。"""
        return line.bottom < self.height * ratio or line.top > self.height * (1 - ratio)


# --------------------------------------------------------------------------- #
# 读入、清理与版式统计
# --------------------------------------------------------------------------- #
def load_pages(pdf, skip: set[int], with_tables: bool = True) -> list[PageInfo]:
    pages: list[PageInfo] = []
    for number, page in enumerate(pdf.pages, 1):
        if number in skip:
            continue
        info = PageInfo(number=number, width=page.width, height=page.height)
        for raw in page.extract_text_lines(strip=True, return_chars=True):
            text = raw["text"].strip()
            chars = raw.get("chars") or []
            if not text or not chars:
                continue
            size = round(statistics.median(c.get("size", 0) for c in chars), 1)
            if size <= 0:
                continue
            faces = Counter(c.get("fontname", "") for c in chars)
            font = faces.most_common(1)[0][0] if faces else ""
            mono = sum(1 for c in chars if MONO_RE.search(c.get("fontname", "") or ""))
            info.lines.append(
                Line(
                    page=number,
                    text=text,
                    size=size,
                    x0=raw["x0"],
                    x1=raw["x1"],
                    top=raw["top"],
                    bottom=raw["bottom"],
                    font=font,
                    mono_ratio=mono / len(chars),
                )
            )
        if with_tables:
            info.tables = read_tables(page)
        pages.append(info)
    return pages


def read_tables(page) -> list[dict]:
    """抽取页面里的表格；失败时静默跳过（不是所有 PDF 都有表格结构）。"""
    try:
        found = page.find_tables()
    except Exception:
        return []
    tables = []
    for table in found:
        try:
            rows = table.extract()
        except Exception:
            continue
        rows = [
            [(cell or "").replace("\n", " ").strip() for cell in row]
            for row in rows
            if row
        ]
        rows = [row for row in rows if any(row)]
        if len(rows) < 2 or max(len(row) for row in rows) < 2:
            continue  # 单列或单行不算表格
        tables.append({"bbox": table.bbox, "rows": rows})
    return tables


def _inside(line: Line, bbox) -> bool:
    x0, top, x1, bottom = bbox
    cx, cy = (line.x0 + line.x1) / 2, (line.top + line.bottom) / 2
    return x0 <= cx <= x1 and top <= cy <= bottom


def clean_lines(pages: list[PageInfo], keep_page_numbers: bool) -> None:
    """剔除页码、重复的页眉页脚，以及 PDF 自带的目录页。"""
    # 表格区域内的文字改为结构化表格输出，不再逐行重复
    for page in pages:
        boxes = [table["bbox"] for table in page.tables]
        if boxes:
            page.lines = [line for line in page.lines if not any(_inside(line, b) for b in boxes)]

    if not keep_page_numbers:
        for page in pages:
            page.lines = [
                line
                for line in page.lines
                if not (page.is_edge(line) and PAGE_NUMBER_RE.match(line.text))
            ]

        # 在多页同一区域重复出现的短行，几乎都是书名 / 章节名页眉
        seen: dict[str, set[int]] = defaultdict(set)
        for page in pages:
            for line in page.lines:
                if page.is_edge(line) and len(line.text) <= 40:
                    seen[re.sub(r"\d+", "#", line.text)].add(page.number)
        threshold = max(3, int(len(pages) * 0.25))
        repeated = {key for key, nums in seen.items() if len(nums) >= threshold}
        if repeated:
            for page in pages:
                page.lines = [
                    line
                    for line in page.lines
                    if not (
                        page.is_edge(line)
                        and len(line.text) <= 40
                        and re.sub(r"\d+", "#", line.text) in repeated
                    )
                ]

    drop_pdf_toc(pages)


def drop_pdf_toc(pages: list[PageInfo]) -> None:
    """删掉 PDF 自带的目录页（后面会按识别到的标题重新生成目录）。

    只在出现「目录 / Contents」标题后，连续命中「点前导符或末尾页码」的行
    才会被当作目录项，避免误删正文。
    """
    dropping = False
    for page in pages:
        kept: list[Line] = []
        for line in page.lines:
            if TOC_TITLE_RE.match(line.text):
                dropping = True
                continue
            if dropping:
                if not TOC_ENTRY_RE.search(line.text):
                    dropping = False
                else:
                    continue
            kept.append(line)
        page.lines = kept


def cluster(values: list[float], tolerance: float = 0.4) -> list[float]:
    """把相近的字号（如 21.19 / 21.2）合并成一个代表值。"""
    out: list[float] = []
    for value in sorted(values):
        if not out or value - out[-1] > tolerance:
            out.append(value)
    return out


class Layout:
    """从整篇文档统计出的版式参数。"""

    def __init__(self, pages: list[PageInfo], args: argparse.Namespace):
        self.pages = pages
        self.body_size = args.body_size or self._detect_body_size()
        self.heading_sizes = self._detect_heading_sizes(
            args.heading_scale, args.heading_depth, args.heading_base
        )
        self.left, self.right = self._detect_margins()
        self.indent_chars = args.indent_chars
        self.quote_chars = args.quote_indent_chars
        self.paragraph_gap = args.paragraph_gap

    def _detect_body_size(self) -> float:
        weight: Counter[float] = Counter()
        for page in self.pages:
            for line in page.lines:
                weight[round(line.size, 1)] += len(line.text)
        if not weight:
            return 10.0
        representatives = cluster(list(weight), tolerance=0.4)
        totals = {size: 0 for size in representatives}
        for size, count in weight.items():
            target = min(representatives, key=lambda s: abs(s - size))
            totals[target] += count
        return max(totals, key=totals.get)

    def _detect_heading_sizes(self, scale: float, depth: int, base: int) -> dict[float, int]:
        sizes = [line.size for page in self.pages for line in page.lines]
        candidates = cluster([s for s in sizes if s >= self.body_size * scale])
        candidates.reverse()  # 从大到小，依次 h2、h3…
        return {size: min(base + i, 6) for i, size in enumerate(candidates[:depth])}

    def _detect_margins(self) -> tuple[float, float]:
        lefts, rights = [], []
        for page in self.pages:
            body = [l for l in page.lines if abs(l.size - self.body_size) < 0.5]
            if not body:
                continue
            lefts.append(min(l.x0 for l in body))
            rights.append(max(l.x1 for l in body))
        return (
            statistics.median(lefts) if lefts else 0.0,
            statistics.median(rights) if rights else 0.0,
        )

    def level_for(self, size: float) -> int:
        if not self.heading_sizes:
            return 0
        nearest = min(self.heading_sizes, key=lambda s: abs(s - size))
        return self.heading_sizes[nearest] if abs(nearest - size) <= 0.6 else 0


# --------------------------------------------------------------------------- #
# 图片
# --------------------------------------------------------------------------- #
class ImageExtractor:
    def __init__(self, assets_dir: Path, assets_rel: str):
        self.dir = assets_dir
        self.rel = assets_rel
        self.paths: list[str] = []
        self.count = 0
        for pattern in ("image*.png", "image*.jpg", "cover.*"):
            for old in assets_dir.glob(pattern):
                old.unlink()

    def save(self, page, image, stem: str | None = None) -> str | None:
        key = None
        stream = image.get("stream")
        if stream is not None:
            try:
                key = hashlib.sha1(stream.get_data()).hexdigest()
            except Exception:
                key = None
        if key is None:
            key = f"{page.page_number}:{image['x0']:.1f},{image['top']:.1f}"

        x0, top = max(0, image["x0"]), max(0, image["top"])
        x1, bottom = min(page.width, image["x1"]), min(page.height, image["bottom"])
        if x1 - x0 < 8 or bottom - top < 8:
            return None

        # 按图片原始像素密度渲染，避免无谓放大
        src_w, src_h = image.get("srcsize") or (0, 0)
        resolution = 150.0
        if src_w and src_h:
            resolution = 72 * max(src_w / (x1 - x0), src_h / (bottom - top))
        resolution = max(72, min(300, resolution))

        try:
            pil = page.crop((x0, top, x1, bottom)).to_image(resolution=resolution).original
        except Exception:
            return None

        if stem is None:
            self.count += 1
            stem = f"image{self.count:03d}"

        rgb = pil.convert("RGB")
        colors = rgb.getcolors(maxcolors=1024)
        is_gray = colors is not None and all(max(c) - min(c) <= 8 for _, c in colors)
        if is_gray:
            name = f"{stem}.png"
            rgb.convert("L").quantize(colors=8).save(self.dir / name, "PNG", optimize=True)
        elif rgb.width * rgb.height > 200_000:
            name = f"{stem}.jpg"
            rgb.save(self.dir / name, "JPEG", quality=90, optimize=True)
        else:
            name = f"{stem}.png"
            rgb.save(self.dir / name, "PNG", optimize=True)

        rel = f"{self.rel}/{name}"
        self.paths.append(rel)
        return rel


# --------------------------------------------------------------------------- #
# 组装文档结构
# --------------------------------------------------------------------------- #
def is_monospace(line: Line) -> bool:
    """强等宽行：通常就是代码行（中文注释行等宽占比会低一些）。"""
    return line.mono_ratio >= 0.55


def _same_code_column(prev: Line, nxt: Line, gap_scale: float = 2.8) -> bool:
    if prev.page != nxt.page or prev.level or nxt.level:
        return False
    if abs(prev.x0 - nxt.x0) > 2:
        return False
    return nxt.top - prev.bottom <= gap_scale * max(prev.size, nxt.size)


def mark_code_lines(lines: list[Line]) -> None:
    """标记代码行：强等宽行，以及夹在两条等宽行之间的中文注释行。"""
    for line in lines:
        line.code = is_monospace(line)

    for index, line in enumerate(lines):
        if line.code or line.mono_ratio < 0.25:
            continue
        prev = lines[index - 1] if index > 0 else None
        nxt = lines[index + 1] if index + 1 < len(lines) else None
        if (
            prev is not None
            and nxt is not None
            and prev.code
            and nxt.code
            and _same_code_column(prev, line)
            and _same_code_column(line, nxt)
        ):
            line.code = True


def join_text(left: str, right: str) -> str:
    if not left:
        return right
    if left.endswith("-") and right[:1].islower():
        return left[:-1] + right
    if CJK_RE.search(left[-1]) or CJK_RE.search(right[0]):
        return left + right
    return f"{left} {right}"


def merge_heading_runs(lines: list[Line]) -> list[Line]:
    """把「章回标题 + 紧邻的下一级副标题」合并成一条标题。"""
    merged: list[Line] = []
    for line in lines:
        prev = merged[-1] if merged else None
        if (
            prev
            and prev.level
            and line.level > prev.level
            and prev.page == line.page
            and line.top - prev.bottom < max(6.0, 1.2 * prev.size)
        ):
            prev.text = join_text(prev.text, line.text)
            prev.x1, prev.bottom = line.x1, line.bottom
            continue
        merged.append(line)
    return merged


def build_blocks(items: list[tuple], layout: Layout) -> list[dict]:
    """把行与图片按阅读顺序合并成标题 / 段落 / 引文 / 图片块。"""
    blocks: list[dict] = []
    cur: dict | None = None

    def flush():
        nonlocal cur
        if cur is not None:
            blocks.append(cur)
            cur = None

    for page, top, x0, kind, payload in items:
        if kind == "image":
            flush()
            blocks.append({"kind": "image", "payload": payload})
            continue

        if kind == "table":
            flush()
            blocks.append({"kind": "table", "rows": payload["rows"]})
            continue

        line: Line = payload
        if line.level:
            flush()
            blocks.append({"kind": "heading", "level": line.level, "text": line.text})
            continue

        size = line.size
        indent = line.x0 - layout.left

        # 等宽字体：整行按代码块处理（保留缩进）
        if line.code:
            char_width = max(3.0, 0.6 * size)
            if cur is not None and cur["kind"] == "code":
                pad = int(max(0.0, round((line.x0 - cur["origin"]) / char_width)))
                cur["lines"].append(" " * pad + line.text)
                cur["bottom"] = line.bottom
            else:
                flush()
                cur = {
                    "kind": "code",
                    "lines": [line.text],
                    "origin": line.x0,
                    "bottom": line.bottom,
                }
            continue

        # 行首列表标记：每个条目独立成块
        marker = LIST_RE.match(line.text)
        if marker:
            flush()
            raw = marker.group("marker")
            ordered = raw[0].isdigit()
            number = int(re.match(r"\d+", raw).group()) if ordered else 1
            cur = {
                "kind": "li",
                "ordered": ordered,
                "number": number,
                "text": marker.group("text"),
                "x1": line.x1,
                "bottom": line.bottom,
            }
            continue

        # 列表项的折行：不在页边、间距正常就并回条目
        if cur is not None and cur["kind"] == "li":
            if indent > 1.5 and line.top - cur["bottom"] <= layout.paragraph_gap * size:
                cur["text"] = join_text(cur["text"], line.text)
                cur["x1"], cur["bottom"] = line.x1, line.bottom
                continue

        wrapped = (
            cur is not None
            and cur["kind"] in ("p", "quote")
            and cur["x1"] >= layout.right - 1.5 * size
        )
        if wrapped:
            if cur["kind"] == "quote":
                cur["lines"][-1] = join_text(cur["lines"][-1], line.text)
            else:
                cur["text"] = join_text(cur["text"], line.text)
            cur["x1"], cur["bottom"] = line.x1, line.bottom
            continue

        # 已经在引文块里：短行、间距正常、且没有回到页边，就继续算引文
        if cur is not None and cur["kind"] == "quote":
            short = (line.x1 - line.x0) < 0.55 * (layout.right - layout.left)
            gap_small = line.top - cur["bottom"] <= 1.8 * size
            if short and gap_small and indent >= size * layout.indent_chars * 0.8:
                cur["lines"].append(line.text)
                cur["x1"], cur["bottom"] = line.x1, line.bottom
                continue

        if indent >= size * layout.quote_chars:
            if cur is not None and cur["kind"] == "quote":
                cur["lines"].append(line.text)
                cur["x1"], cur["bottom"] = line.x1, line.bottom
            else:
                flush()
                cur = {
                    "kind": "quote",
                    "lines": [line.text],
                    "x1": line.x1,
                    "bottom": line.bottom,
                }
        elif indent >= size * layout.indent_chars * 0.8:
            flush()
            cur = {"kind": "p", "text": line.text, "x1": line.x1, "bottom": line.bottom}
        else:
            gap = line.top - cur["bottom"] if cur is not None else 0.0
            if cur is not None and cur["kind"] == "p" and gap <= layout.paragraph_gap * size:
                cur["text"] = join_text(cur["text"], line.text)
                cur["x1"], cur["bottom"] = line.x1, line.bottom
            else:
                flush()
                cur = {"kind": "p", "text": line.text, "x1": line.x1, "bottom": line.bottom}

    flush()
    return blocks


# --------------------------------------------------------------------------- #
# 渲染
# --------------------------------------------------------------------------- #
def polish_cn(text: str, collapse_spaces: bool = True) -> str:
    """修正 PDF 带出的中文标点问题，不改动用词。"""
    text = text.replace("──", "——")
    text = re.sub(r"(?<!…)…(?!…)", "……", text)
    text = re.sub(
        r"\(([^()]*)\)",
        lambda m: f"（{m.group(1)}）" if CJK_RE.search(m.group(1)) else m.group(0),
        text,
    )
    if collapse_spaces:
        # PDF 提取常在字与字之间塞入空格（对齐排版导致），中文语境内应去掉
        cjk = r"\u3400-\u9fff\u3000-\u303f\uff00-\uffef“”‘’—…《》「」『』（）【】"
        text = re.sub(rf"(?<=[{cjk}])[ \t]+(?=[{cjk}])", "", text)
        text = re.sub(r"[ \t]{2,}", " ", text)
    return text


def slugify(text: str, used: set[str]) -> str:
    slug = re.sub(r"<[^>]+>", "", text.strip().lower())
    slug = re.sub(r"[^\w\u3400-\u9fff\- ]", "", slug).replace(" ", "-") or "section"
    base, index = slug, 1
    while slug in used:
        index += 1
        slug = f"{base}-{index}"
    used.add(slug)
    return slug


def render(
    blocks: list[dict],
    *,
    title: str,
    author: str,
    lang: str,
    cover: str | None,
    frontmatter: bool,
    toc_depth: int,
    polish: bool,
) -> str:
    fix = polish_cn if polish else (lambda text: text)
    fix_heading = (
        (lambda text: polish_cn(text, collapse_spaces=False)) if polish else (lambda text: text)
    )
    out: list[str] = []

    if frontmatter:
        fields = [(k, v) for k, v in (("title", title), ("author", author), ("lang", lang)) if v]
        out.append(
            "---\n"
            + "\n".join(f"{key}: {json.dumps(value, ensure_ascii=False)}" for key, value in fields)
            + "\n---"
        )

    if cover:
        # 封面在书名之前；首行不是标题，显式关闭 MD041
        out.append("<!-- markdownlint-disable MD041 -- 封面图位于书名之前 -->")
        out.append(f"![封面](<{cover}>)")

    out.append(f"# {title}")

    headings = [(b["level"], b["text"]) for b in blocks if b["kind"] == "heading"]
    entries = [(level, text) for level, text in headings if level <= 1 + toc_depth]
    if toc_depth > 0 and entries:
        used: set[str] = set()
        top_level = min(level for level, _ in entries)
        toc = ["## 目录", ""]
        for level, text in entries:
            label = fix_heading(text)
            toc.append(f"{'  ' * (level - top_level)}- [{label}](#{slugify(label, used)})")
        out.append("\n".join(toc))

    index = 0
    while index < len(blocks):
        block = blocks[index]

        if block["kind"] == "li":
            ordered = block["ordered"]
            start = block["number"]
            items: list[str] = []
            while (
                index < len(blocks)
                and blocks[index]["kind"] == "li"
                and blocks[index]["ordered"] == ordered
            ):
                current = blocks[index]
                prefix = f"{start + len(items)}. " if ordered else "- "
                items.append(prefix + fix(current["text"]))
                index += 1
            out.append("\n".join(items))
            continue

        if block["kind"] == "code":
            out.append("```\n" + "\n".join(block["lines"]).rstrip() + "\n```")
        elif block["kind"] == "heading":
            out.append(f"{'#' * block['level']} {fix_heading(block['text'])}")
        elif block["kind"] == "p":
            out.append(fix(block["text"]))
        elif block["kind"] == "quote":
            out.append("> " + "\\\n> ".join(fix(line) for line in block["lines"]))
        elif block["kind"] == "table":
            out.append(render_table(block["rows"], fix))
        elif block["kind"] == "image":
            out.append(f"![{block['payload']['alt']}](<{block['payload']['path']}>)")
        index += 1

    return "\n\n".join(out).rstrip() + "\n"


def render_table(rows: list[list[str]], fix) -> str:
    width = max(len(row) for row in rows)
    cells = [[fix(cell).replace("|", "\\|").replace("\n", " ") for cell in row] for row in rows]
    cells = [row + [""] * (width - len(row)) for row in cells]
    lines = ["| " + " | ".join(cells[0]) + " |"]
    lines.append("| " + " | ".join(["---"] * width) + " |")
    lines.extend("| " + " | ".join(row) + " |" for row in cells[1:])
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #
def parse_pages(spec: str | None) -> set[int]:
    pages: set[int] = set()
    if not spec:
        return pages
    for part in spec.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            start, end = part.split("-", 1)
            pages.update(range(int(start), int(end) + 1))
        else:
            pages.add(int(part))
    return pages


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="pdf2md.py",
        description="通用 PDF → Markdown 转换器（自动识别标题、段落、引文与图片）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
        "  pdf2md.py book.pdf -o book.md --title 书名 --frontmatter\n"
        "  pdf2md.py scan.pdf --skip-pages 1-2 --debug",
    )
    parser.add_argument("input", help="输入 PDF")
    parser.add_argument("-o", "--output", help="输出 Markdown（默认同名 .md）")
    parser.add_argument("--title", default="", help="书名（默认取 PDF 元数据或首个标题）")
    parser.add_argument("--author", default="", help="作者（配合 --frontmatter）")
    parser.add_argument("--frontmatter", action="store_true", help="输出 YAML frontmatter")
    parser.add_argument("--assets-dir", help="图片目录（默认 <输出名>.assets）")
    parser.add_argument("--no-images", action="store_true", help="不导出图片")
    parser.add_argument("--no-cover", action="store_true", help="不识别封面")
    parser.add_argument("--no-toc", action="store_true", help="不生成目录")
    parser.add_argument("--toc-depth", type=int, default=2, help="目录收录层级（默认 2 → h2/h3）")
    parser.add_argument("--skip-pages", help="跳过页面，如 1-2,5")
    parser.add_argument("--body-size", type=float, help="强制正文号（pt）")
    parser.add_argument("--heading-scale", type=float, default=1.12, help="标题字号阈值倍数（默认 1.12）")
    parser.add_argument("--heading-depth", type=int, default=3, help="标题最多映射几级（默认 3）")
    parser.add_argument(
        "--heading-base",
        type=int,
        default=2,
        choices=range(1, 6),
        metavar="N",
        help="最大字号映射到几级标题（默认 2：h1 留给书名；设 1 可保留原 h1）",
    )
    parser.add_argument("--no-tables", action="store_true", help="不抽取表格，按普通文本输出")
    parser.add_argument(
        "--paragraph-gap",
        type=float,
        default=1.2,
        metavar="F",
        help="段间距超过行高的多少倍算新段（默认 1.2，无缩进排版时调小）",
    )
    parser.add_argument(
        "--drop-regex",
        action="append",
        default=[],
        metavar="RE",
        help="丢弃匹配该正则的行（水印、页边批注等），可重复使用",
    )
    parser.add_argument("--indent-chars", type=float, default=2.0, help="首行缩进字数阈值（默认 2）")
    parser.add_argument("--quote-indent-chars", type=float, default=4.0, help="引文缩进字数阈值（默认 4）")
    parser.add_argument("--chapter-regex", default=DEFAULT_CHAPTER_RE, help="章标题正则")
    parser.add_argument("--keep-page-numbers", action="store_true", help="保留页眉页脚")
    parser.add_argument("--no-polish", action="store_true", help="关闭中文标点整理")
    parser.add_argument("--debug", action="store_true", help="打印识别到的版式参数")
    return parser


def _plain(text: str) -> str:
    return re.sub(r"[\s\W_]+", "", text, flags=re.UNICODE).lower()


def bootstrap_with_uv() -> None:
    """当前解释器缺依赖时，若有 uv 就临时拉一个环境重跑自己。"""
    if os.environ.get("BOOKSMITH_BOOTSTRAPPED") == "1":
        return
    uv = shutil.which("uv")
    if not uv:
        return
    print("首次运行: 用 uv 准备 pdfplumber / pillow ...", file=sys.stderr)
    env = dict(os.environ, BOOKSMITH_BOOTSTRAPPED="1")
    os.execve(
        uv,
        [
            uv, "run", "--no-project", "--quiet",
            "--with", "pdfplumber>=0.10", "--with", "pillow",
            "python", str(Path(__file__).resolve()), *sys.argv[1:],
        ],
        env,
    )


def main() -> int:
    args = build_parser().parse_args()

    try:
        import pdfplumber  # noqa: F401
        import PIL  # noqa: F401
    except ImportError:
        bootstrap_with_uv()
        print("错误: 需要 pdfplumber 和 pillow\n  pip install pdfplumber pillow", file=sys.stderr)
        return 1

    src = Path(args.input).expanduser()
    if not src.is_file():
        print(f"错误: 找不到文件 {src}", file=sys.stderr)
        return 1
    dst = Path(args.output).expanduser() if args.output else src.with_suffix(".md")
    dst.parent.mkdir(parents=True, exist_ok=True)

    assets_dir = (
        Path(args.assets_dir).expanduser()
        if args.assets_dir
        else dst.with_name(dst.stem + ".assets")
    )
    try:
        assets_rel = assets_dir.resolve().relative_to(dst.parent.resolve()).as_posix()
    except ValueError:
        assets_rel = assets_dir.resolve().as_posix()
    if not args.no_images:
        assets_dir.mkdir(parents=True, exist_ok=True)
    extractor = None if args.no_images else ImageExtractor(assets_dir, assets_rel)

    skip = parse_pages(args.skip_pages)
    with pdfplumber.open(src) as pdf:
        pages = load_pages(pdf, skip, with_tables=not args.no_tables)
        if not pages:
            print("错误: 没有可处理的页面", file=sys.stderr)
            return 1

        if args.drop_regex:
            try:
                drop = re.compile("|".join(f"(?:{p})" for p in args.drop_regex))
            except re.error as error:
                print(f"错误: --drop-regex 不合法: {error}", file=sys.stderr)
                return 1
            for page in pages:
                page.lines = [line for line in page.lines if not drop.search(line.text)]

        clean_lines(pages, args.keep_page_numbers)
        layout = Layout(pages, args)

        # 标题级别；章标题正则命中但字号不够时，仍按标题处理
        chapter_re = re.compile(args.chapter_regex, re.M) if args.chapter_regex else None
        lines = [line for page in pages for line in page.lines]
        for line in lines:
            line.level = layout.level_for(line.size)
            if chapter_re and chapter_re.match(line.text) and line.size >= layout.body_size * 0.95:
                line.level = line.level or args.heading_base
        lines.sort(key=lambda line: (line.page, line.top))
        lines = merge_heading_runs(lines)
        mark_code_lines(lines)

        # 图片（首页大图作封面，且不再重复插入正文）
        images: list[tuple] = []
        cover_rel = None
        cover_rect: tuple[float, float] | None = None
        if extractor is not None:
            first = pages[0]
            if first.number == 1 and not args.no_cover:
                page = pdf.pages[0]
                if page.images:
                    biggest = max(
                        page.images,
                        key=lambda im: (im["x1"] - im["x0"]) * (im["bottom"] - im["top"]),
                    )
                    area = (biggest["x1"] - biggest["x0"]) * (biggest["bottom"] - biggest["top"])
                    if area >= 0.4 * page.width * page.height:
                        cover_rel = extractor.save(page, biggest, stem="cover")
                        if cover_rel:
                            cover_rect = (biggest["x0"], biggest["top"])

            for info in pages:
                page = pdf.pages[info.number - 1]
                for image in page.images:
                    if cover_rect is not None and abs(image["x0"] - cover_rect[0]) < 0.5 and abs(
                        image["top"] - cover_rect[1]
                    ) < 0.5:
                        continue
                    rel = extractor.save(page, image)
                    if rel:
                        images.append(
                            (info.number, image["top"], image["x0"], "image", {"alt": "插图", "path": rel})
                        )

        metadata = getattr(pdf, "metadata", None) or {}
        meta_title = (metadata.get("Title") or "").strip() if isinstance(metadata, dict) else ""

    items: list[tuple] = [(line.page, line.top, line.x0, "text", line) for line in lines] + images
    for page in pages:
        for table in page.tables:
            items.append((page.number, table["bbox"][1], table["bbox"][0], "table", table))
    items.sort(key=lambda item: (item[0], item[1], 0 if item[3] in ("image", "table") else 1, item[2]))
    blocks = build_blocks(items, layout)

    title = args.title.strip() or meta_title
    if not title or title.lower().endswith(".pdf"):
        first_heading = next((b["text"] for b in blocks if b["kind"] == "heading"), "")
        title = first_heading or dst.stem

    # PDF 正文里的书名如果和解析出的标题相同，就不再重复输出一条标题
    if blocks and blocks[0]["kind"] == "heading" and _plain(blocks[0]["text"]) == _plain(title):
        blocks = blocks[1:]

    sample = "\n".join(line.text for page in pages for line in page.lines[:5])[:2000]
    lang = "zh" if CJK_RE.search(sample) else "en"

    markdown = render(
        blocks,
        title=title,
        author=args.author.strip(),
        lang=lang,
        cover=cover_rel,
        frontmatter=args.frontmatter,
        toc_depth=0 if args.no_toc else args.toc_depth,
        polish=not args.no_polish,
    )
    dst.write_text(markdown, encoding="utf-8")

    if args.debug:
        print(
            f"[booksmith] 正文号 {layout.body_size}pt  左边距 {layout.left:.1f}pt  "
            f"右边距 {layout.right:.1f}pt  标题字号 {layout.heading_sizes}\n"
            f"[booksmith] 页面 {len(pages)}  文本行 {len(lines)}  图片 {len(images)}  块 {len(blocks)}",
            file=sys.stderr,
        )

    print(
        f"已生成: {dst}（页面 {len(pages)}，内容块 {len(blocks)}，"
        f"图片 {len(images)} 张{'，含封面' if cover_rel else ''}）"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
