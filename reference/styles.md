# 样式定制

## 约定

- `assets/pdf-style.html`、`assets/ebook-style.html` 都是 **HTML 片段**：
  以 `<style>` 开头、`</style>` 结尾，由 pandoc 作为 `header-includes` 注入。
  传 `-s` 时也可以直接给纯 CSS 文件，脚本会自动包一层 `<style>`。
- 模板 `assets/template.html` 是最小 HTML 模板：只输出 `<head>`、可选的标题块
  （仅当传了 `--title`）和正文，不引入 pandoc 默认 CSS。
- 换样式：`md2pdf.sh -s my-style.html`、`md2ebook.py -s my-style.html`；
  或设环境变量 `BOOKSMITH_PDF_STYLE` / `BOOKSMITH_EBOOK_STYLE`。
- 改样式不要动脚本；脚本只负责「结构」，样式负责「外观」。

## PDF 样式要点

```css
@page {
  size: A4;                                  /* 也可用 --paper 覆盖 */
  margin: 18mm 16mm 16mm 16mm;                /* 也可用 --margin 覆盖 */
  @bottom-center {
    content: "第 " counter(page) " 页 / 共 " counter(pages) " 页";
  }
}
```

- **字体**：默认 PingFang SC（无衬线）。改宋体：
  `font-family: "Songti SC", "Noto Serif CJK SC", serif;`
- **段落**：中文正文默认 `text-indent: 0`，靠段后 `margin` 留白；不要用
  `text-indent: 2em` 做首行缩进。
- **PDF 书签**：`h1–h4` 上的 `bookmark-level` 决定大纲层级，删掉就只剩页码。
- **目录页码**：`nav#TOC a::after { content: leader('.') target-counter(attr(href), page); }`
  只对 pandoc `--toc` 生成的目录生效（`nav#TOC`）。Markdown 里手写的目录是普通列表，
  不会有页码。
- **纸张**：`--paper A4` / `--paper "210mm 297mm"` / `--paper Letter`；
  页边距 `--margin "20mm 18mm 20mm 18mm"`。
- **长表格**：默认 `page-break-inside: auto`，跨页正常；`thead` 在 WeasyPrint 会重复表头。
- **弱化段落**：正文里用 `<div class="note">...</div>`（pandoc `fenced_divs` 支持
  `::: note`）可套用灰字样式；`.note-title` 是更淡的小标题。

## 电子书样式要点

- 不要写 `@page`、`mm`、`pt` 固定尺寸——阅读器按自己的屏幕排版。
- 字号用相对单位（`em`），行高 1.6–1.8 之间最稳。
- 避免 `position: fixed`、`float`、`text-indent` 缩进首行；Kobo/Kindle 上表现不可控。
- 标题的 `font-size` 不宜超过 1.8em，否则 Kindle 会截断。
- 电子书不输出目录页码（阅读器自己算），用手写「## 目录」章节只会重复，
  所以 `md2ebook.py` 默认删掉它，改由 `--level1-toc //h:h2` 生成导航。

## 自定义一份样式的最小骨架

```html
<style>
  body { font-family: "Songti SC", serif; font-size: 10.5pt; line-height: 1.75; }
  h1 { font-size: 20pt; bookmark-level: 1; bookmark-label: content(); }
  h2 { font-size: 15pt; bookmark-level: 2; }
  h3 { font-size: 12.5pt; bookmark-level: 3; }
  p { margin: 0 0 1em 0; }
  img { max-width: 100%; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border: 0.5pt solid #ccc; padding: 4pt 6pt; }
</style>
```

只写想覆盖的规则即可，其余会落到浏览器/WeasyPrint 的默认值。

## 验证样式是否生效

```bash
bash scripts/md2pdf.sh doc.md -o dist/doc.pdf --keep-html /tmp/doc.html
open /tmp/doc.html            # 浏览器里看到的效果 ≈ WeasyPrint
pdfinfo dist/doc.pdf | head   # 页数 / 纸张
pdftotext dist/doc.pdf - | head -20
```
