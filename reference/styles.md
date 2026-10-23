# 样式说明

## 约定

- `assets/pdf-style.html`、`assets/ebook-style.html` 都是 **HTML 片段**：
  以 `<style>` 开头、`</style>` 结尾，由 pandoc 作为 `header-includes` 注入。
- 两份样式分别原样移植自 `jpm/pdf-style.html`、`jpm/ebook-style.html`。
  改样式只改这两个文件，不要改脚本里的排版规则。
- `build-pdf.sh` 固定使用 `assets/pdf-style.html`，输出 `dist/<md 文件名>.pdf`；
  `build-azw3.sh` 固定使用 `assets/ebook-style.html`，输出由 `-o` 决定。
- 想换样式：直接替换 `assets/*.html` 的内容。脚本不提供额外的样式参数。

## 转换链路

```text
Markdown
  │  pandoc --standalone --embed-resources -f markdown-implicit_figures -H <style>
  ▼
单文件 HTML（图片、CSS 全内嵌）
  ├── weasyprint ──▶ PDF
  └── Calibre ─────▶ EPUB / AZW3 / MOBI
```

`build-pdf.sh` 在 pandoc 生成 HTML 后，会移除 pandoc 默认模板自带的 `<style>`，
只保留包含 `PingFang SC` 标记的自定义样式，避免默认 CSS 覆盖 jpm 样式。

## PDF 样式要点

```css
@page {
  size: A4;
  margin: 18mm 16mm 16mm 16mm;
  @bottom-center {
    content: "第 " counter(page) " 页 / 共 " counter(pages) " 页";
  }
}
body {
  font-family: "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei",
    "Noto Sans CJK SC", sans-serif;
  font-size: 10.5pt;
  line-height: 1.75;
  color: #2b2f36;
}
```

- **字体**：PingFang SC（无衬线）。换宋体：
  `font-family: "Songti SC", "Noto Serif CJK SC", serif;`
- **段落**：中文正文 `margin: 0 0 1.75em 0`，无 `text-indent`；段间留白等于
  一行高度，和空行分隔的 Markdown 源文件对应。
- **标题**：h1 20pt + 2.5pt 蓝底线，h2 15pt + 1pt 浅蓝底线，h3/h4 逐级缩小，
  颜色 `#17324d` / `#1f3a5f` / `#274b73` / `#33557e`。
- **PDF 书签**：h1–h4 上的 `bookmark-level` / `bookmark-label` 决定大纲层级。
- **引用块**：浅蓝底 `#f4f7fb` + 4pt 蓝左边框 + 3pt 圆角，`page-break-inside: avoid`。
- **表格**：全宽、9.5pt、斑马纹 `#fafbfc`、表头 `#eef3f8`。
- **任务清单**：`ul.task-list` 用 `☐` 伪元素显示方框。
- **弱化段落**：正文里用 `<div class="note">...</div>`（pandoc `fenced_divs`
  支持 `::: note`）套用灰字样式；`.note-title` 是更淡的小标题。
- **纸张**：写死在 `@page` 里。需要 A5/Letter 时改 `size` 和 `margin`，不要指望
  命令行参数。

## 电子书样式要点

- 不写 `@page`、`mm`、`pt` 固定尺寸——阅读器按自己的屏幕排版。
- 字体 Songti SC / Noto Serif CJK SC / Source Han Serif SC，行高 1.7。
- 标题用相对单位（em），h1 1.8em 带 2px 蓝底线，h2 1.4em 带 1px 浅蓝底线。
- 引用块：左侧 3px `#2f6fb2` 竖线，无背景色，避免 Kindle 上反色。
- 表格：`border-collapse: collapse`，表头 `#eef3f8`。
- 电子书默认删掉手写「## 目录」章节，改由 `--level1-toc //h:h2` 等生成导航；
  需要保留时给 `build-azw3.sh` 加 `--keep-toc`。

## 验证样式是否生效

```bash
bash scripts/build-pdf.sh book.md
open dist/book.pdf                 # macOS 预览
python3 - <<'PY'
import pymupdf
doc = pymupdf.open("dist/book.pdf")
print("页数:", doc.page_count, "纸张:", doc[0].rect)
print(doc[0].get_text()[:500])
PY
```

```bash
bash scripts/build-azw3.sh book.md -o dist/book.azw3
ls -lh dist/book.azw3
```

PDF 里如果出现首行缩进，先检查 `assets/pdf-style.html` 是否被改出了
`text-indent`；如果标题字体不对，检查自定义 `<style>` 是否还包含
`PingFang SC`（`build-pdf.sh` 靠这个标记识别要保留的样式）。
