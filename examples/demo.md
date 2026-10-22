# book-smith-skill 演示文档

这是一份用来验证排版流水线的演示 Markdown。它包含章节标题、多段正文、引文块、
表格和列表，足以覆盖 PDF 与电子书两种输出的大部分样式。

## 第一章 排版要素

### 正文

中文正文建议一段一行，不要手动换行；排版交给 pandoc 和 WeasyPrint。
段落之间留一个空行即可，不需要首行缩进——PDF 样式会按需要处理间距。

英文段落也支持。Line breaks are handled by the renderer, so keep each
paragraph on a single line in the source.

### 引文

> 白日依山尽，黄河入海流。\
> 欲穷千里目，更上一层楼。

### 表格

| 组件 | 作用 |
| --- | --- |
| pandoc | Markdown 转 HTML / PDF |
| WeasyPrint | HTML 转 PDF |
| Calibre | EPUB / AZW3 / MOBI |

### 列表

1. 先写 Markdown
2. 再选输出格式
3. 最后用阅读器检查目录与封面

- 无序列表第一项
- 无序列表第二项

## 第二章 命令

```bash
# PDF
bash scripts/md2pdf.sh examples/demo.md -o dist/demo.pdf

# 电子书
python3 scripts/md2ebook.py examples/demo.md -o dist/demo.epub

# PDF 还原成 Markdown
python3 scripts/pdf2md.py dist/demo.pdf -o dist/demo.md
```

行内代码 `pdf2md.py` 与加粗 **重点** 都可以正常渲染。

## 附录

正文到此结束，用来确认末尾段落不会被吞掉。
