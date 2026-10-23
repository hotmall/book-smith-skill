# book-smith-skill

English | [简体中文](README.zh-CN.md)

> An ebook workshop for AI agents: **Markdown ⇄ PDF / EPUB / AZW3**.
> Every output goes through a single-file HTML step before WeasyPrint or
> Calibre.

`book-smith-skill` is a self-contained skill package: `SKILL.md` tells an agent
when to use it and how to tune it, `scripts/` contains runnable utilities,
`assets/` contains the typography, and `reference/` contains the PDF tuning
guide and style notes. Everything runs locally; no cloud service is required.

## Features

- **PDF → Markdown**: infers body font size, margins, and heading levels; merges
  paragraphs and restores blockquotes, lists, code blocks, tables, images, and a
  table of contents; strips page numbers and repeated headers/footers.
- **Markdown → HTML → PDF**: pandoc produces a standalone HTML file with images
  and CSS embedded, then WeasyPrint renders an A4 PDF. A4, PingFang SC, paragraph
  spacing, page footers, h1–h4 bookmarks, and zebra-striped tables come from
  `assets/pdf-style.html`.
- **Markdown → HTML → ebook**: the same HTML goes to Calibre to produce EPUB /
  AZW3 / MOBI, with reader navigation, cover detection, and title/author
  metadata. Styling comes from `assets/ebook-style.html`.
- **Markdown cleanup**: every generated Markdown file is checked by
  `chinese-style-guide` first, then structurally fixed by `markdownlint --fix`.
- **One-step install**: `scripts/install.sh` installs this skill and
  [`chinese-style-guide`](https://github.com/RightCapitalHQ/chinese-style-guide)
  together.
- **Low friction**: `doctor.sh` checks dependencies; `pdf2md.py` bootstraps a
  temporary `uv` environment if `pdfplumber` / `pillow` are missing; the ebook
  script creates `.venv-azw3` on first use.

## Installation

Point your agent at the repository and ask it to install the skill. **Install
`chinese-style-guide` at the same time.** The simplest path is the bundled
installer:

```bash
# OpenCode (default: ~/.config/opencode/skills)
bash scripts/install.sh

# Claude Code
bash scripts/install.sh --target ~/.claude/skills
```

The script installs both:

```text
<SKILLS_DIR>/
├── book-smith-skill/
└── chinese-style-guide/      from RightCapitalHQ/chinese-style-guide
```

Open a new session (or refresh the skill list) after installation. You should
see both `book-smith-skill` and `chinese-style-guide` in the skill list.

Let the agent handle dependencies. On first use it runs
`bash scripts/doctor.sh` and installs whatever is missing. Required components:
pandoc, WeasyPrint, Python (pdfplumber / pillow), markdownlint, and Python 3.11+
(the ebook script installs `ebook-converter-lib`, which bundles the Calibre
engine). On Linux you also need CJK fonts (Noto CJK) and pango; on Windows,
use WSL.

## Pipeline

```text
PDF ──pdf2md.py──▶ Markdown ──chinese-style-guide fixes → markdownlint --fix──▶ final Markdown
                                                                  │
                                                        pandoc (standalone HTML)
                                                        ├── WeasyPrint ──▶ PDF
                                                        └── Calibre ─────▶ AZW3 / EPUB
```

### 1. PDF → Markdown

> Convert `~/Downloads/some-book.pdf` to Markdown, keeping images, tables, and
> the table of contents.

```bash
python3 scripts/pdf2md.py book.pdf -o book.md --debug
```

The script measures body font size and page margins, splits paragraphs and
blockquotes by indentation, restores lists and code blocks, removes page
numbers and repeated headers/footers, rebuilds the table of contents, and
extracts images into `<name>.assets/` (the largest image on the first page
becomes the cover). Paragraphs are separated by blank lines; no first-line
indent is written. After generation it runs `md-lint.sh`:

- `chinese-style-guide` checks Chinese typography first;
- `markdownlint --fix` performs the final structural pass.

### 2. Markdown → PDF

> Export `book.md` to PDF with page numbers.

```bash
bash scripts/build-pdf.sh book.md
```

The output is `dist/book.pdf`. The default style is `assets/pdf-style.html`:
A4, PingFang SC at 10.5pt, paragraph spacing, blue-gray headings, light-blue
blockquotes, a “Page N of M” footer, PDF bookmarks, and zebra-striped tables.
Chinese body text has no first-line indent.

### 3. Markdown → ebook

> Build a Kindle-ready AZW3 from `book.md`; the author is ….

```bash
bash scripts/build-azw3.sh book.md -a "Author Name"
bash scripts/build-azw3.sh book.md -o dist/book.epub
```

The same HTML can produce EPUB, AZW3, or MOBI based on the `-o` extension. The
script creates reader navigation, looks for `<name>.assets/cover.*`, and writes
title/author metadata.

### 4. Markdown cleanup

```bash
bash scripts/md-lint.sh book.md
```

The order matters:

1. `chinese-style-guide` checks Chinese spacing, full-width/half-width
   punctuation, numbers, and dates. It reports issues but does not rewrite text.
2. Fix the reported issues and rerun.
3. `markdownlint --fix` performs the final structural pass (blank lines,
   blank lines around headings, horizontal rules, etc.), followed by a
   `markdownlint` check.

Chinese typography fixes can change line structure, so `markdownlint` must run
last. `pdf2md.py` runs this step automatically; use `--no-lint` to skip it while
tuning.

### Combined workflow

> Rebuild this PDF as both a PDF and an ebook.

A typical run: `pdf2md.py` → sample and tune → `md-lint.sh` and
`chinese-style-guide` fixes → `build-pdf.sh` and `build-azw3.sh` from the same
Markdown → verify file sizes, TOC entries, and image counts.

## Conventions

- Heading levels: `#` book title, `##` chapter, `###` section, `####`
  subsection. PDF bookmarks and ebook navigation follow this hierarchy.
- Chinese paragraphs: no first-line indent; separate paragraphs with a blank
  line. Spacing is controlled by styles, not `text-indent`.
- Chinese typography: follow `chinese-style-guide` (CJK/Latin spacing,
  punctuation, numbers).
- Image directory: `<output-name>.assets/`; the cover is always `cover.*`.
- Image syntax: `![alt](<path>)`, which survives paths containing spaces.
- Outputs: `dist/` by default.
- Styles and scripts: keep the built-in implementation; change typography only
  in `assets/*.html`.

## Styles

`assets/pdf-style.html` defines the print layout:

- **PDF**: A4, margins `18mm 16mm 16mm 16mm`, PingFang SC 10.5pt / 1.75 line
  height, `1.75em` paragraph spacing, h1–h4 bookmarks, page footer, blockquotes
  with `#f4f7fb` background and a 4pt blue rule, zebra-striped tables, muted
  `.note` paragraphs, and task-list checkboxes.

`assets/ebook-style.html` defines the reader layout:

- **Ebook**: Songti SC body at 1.7 line height, dark-blue headings with bottom
  rules, blockquotes with a 3px blue rule, bordered tables with a tinted header.
  No `@page` or print-only rules.

Both build scripts share one pipeline: pandoc renders Markdown to a standalone
HTML file with images and CSS embedded; WeasyPrint turns it into PDF, and
Calibre turns it into EPUB/AZW3/MOBI. See `reference/styles.md` for details.

## Directory layout

```text
.
├── SKILL.md                 agent entry point
├── README.md                this file (English)
├── README.zh-CN.md          Chinese README
├── assets/
│   ├── pdf-style.html       print style
│   └── ebook-style.html     ebook style
├── scripts/
│   ├── pdf2md.py            PDF → Markdown
│   ├── build-pdf.sh         Markdown → HTML → PDF
│   ├── build-azw3.sh        Markdown → HTML → EPUB/AZW3/MOBI
│   ├── md-lint.sh           chinese-style-guide → markdownlint cleanup
│   ├── install.sh           install this skill + chinese-style-guide
│   └── doctor.sh            dependency check
├── reference/
│   ├── pdf2md-tuning.md     tuning guide for messy PDFs
│   └── styles.md            style notes
└── examples/demo.md         runnable demo document
```

## Known limitations

- Two-column / multi-column and vertical PDFs are not handled. Crop the pages
  first or use `pdftotext -layout`.
- Scanned PDFs need OCR first (for example `ocrmypdf`); this repository does not
  include OCR.
- Heading detection is font-size based. Documents where all headings share the
  body size cannot be segmented automatically.
- Tables are extracted page by page; cross-page tables are not merged.
- Footnotes stay in reading order in the body.
- `chinese-style-guide` only covers machine-checkable rules (spacing,
  punctuation, numbers). Semantics and word choice still need an agent review.

## FAQ

| Symptom | Fix |
| --- | --- |
| `weasyprint: command not found` | Install WeasyPrint (macOS also needs pango) |
| Chinese characters render as boxes | Change `font-family` or install Source Han / Noto CJK |
| Body text has a first-line indent | Remove `text-indent` from a custom style |
| pandoc warns about `translations for zh` | Harmless; ignore it |
| The first ebook conversion is slow | It is creating `.venv-azw3` and installing `ebook-converter-lib`; later runs reuse it |
| The ebook has no TOC | Make sure the body uses `##` or higher-level headings |
| PDF→Markdown merges or splits paragraphs | Follow `reference/pdf2md-tuning.md` to adjust thresholds |
| The TOC appears twice | Do not generate it twice; skip the PDF's own TOC pages |
| The cover is not detected | Pass a cover explicitly; by default only a large first-page image is used |
| Chinese check says the guide is missing | Run `bash scripts/install.sh` |
| markdownlint still reports problems | Fix by line number and rerun `md-lint.sh` |

## Notes

- The `[booksmith]` prefix and `BOOKSMITH_*` environment variables are internal
  identifiers used by the same scripts.
- Verified on macOS (pandoc 3.9 / WeasyPrint 68 / Calibre engine):
  Markdown→PDF→Markdown round trips, Chinese paragraph segmentation,
  blockquotes, lists, code blocks, tables, TOC rebuilding, cover detection, and
  EPUB/AZW3 metadata, navigation, and covers.
