# book-smith-skill

> 一个给 AI agent 用的电子书工坊：**Markdown ⇄ PDF / EPUB / AZW3**。
> 从一句话到成书，内置中文版式识别与打印样式。

`book-smith-skill` 是一个自包含的 skill 包：`SKILL.md` 告诉 agent 什么时候用、
怎么调参，`scripts/` 是可直接运行的通用脚本，`assets/` 是可替换的排版样式，
`reference/` 是脏 PDF 调参手册和样式定制指南。全部在本地运行，不依赖云服务。

## 特性

- **PDF → Markdown**：自动统计正文字号、页边距和标题层级，识别首行缩进与引文，
  还原段落、列表、代码块、表格、图片和目录，剔除页码与重复页眉页脚。
- **Markdown → PDF**：pandoc + WeasyPrint，A4/Letter 可换，页脚页码、PDF 书签、
  目录页码、表格斑马纹、引用块样式开箱可用。
- **Markdown → 电子书**：EPUB / AZW3 / MOBI / DOCX，自动生成阅读器导航、
  探测封面、写入书名/作者/系列元数据。
- **中文优先**：中英混排拼接、中文标点整理、对齐造成的字间空格清理、
  中文字体栈都已处理。
- **省事**：`doctor.sh` 一键体检；`pdf2md.py` 缺依赖且本机有 `uv` 时会自动
  拉临时环境运行；电子书引擎缺失时自动建缓存虚拟环境。
- **可替换排版**：样式是独立 HTML/CSS 文件，不动脚本即可换字体、纸张、配色。

## 安装

把仓库地址交给 agent，让它装成技能即可，不需要自己敲命令：

```text
帮我安装这个 skill：<repo-url>
```

agent 会把它放进当前客户端的技能目录（OpenCode 全局为
`~/.config/opencode/skills/book-smith-skill`，Claude Code 为
`~/.claude/skills/book-smith-skill`），并保持目录名与 `SKILL.md` 中的
`name: book-smith-skill` 一致。新开一个会话，在技能列表里看到它就算装好了。
只想给某个项目用，就让 agent 装到项目的 `.opencode/skills/` 下。

依赖同样交给 agent：第一次使用时会自动运行 `bash scripts/doctor.sh`，缺什么
装什么。需要的组件是 pandoc、WeasyPrint、Python（pdfplumber / pillow），以及
Calibre 的 `ebook-convert` 或 Python 3.11+。Linux 上需要中文字体（Noto CJK）
和 pango，Windows 建议在 WSL 里使用。

## 用法

装好之后直接用自然语言提需求，agent 会按 `SKILL.md` 选择脚本、参数和样式，
并在出错时自动排查。下面是可以直接照说的例子。

### PDF → Markdown

> 帮我把 `~/Downloads/某书.pdf` 转成 Markdown，保留图片、表格和目录。

agent 会统计正文字号和页边距、按缩进分段落与引文、还原列表和代码块、剔除页码
与重复页眉页脚、重建目录，并把图片抽到 `<文件名>.assets/`，首页大图存成封面。
如果是扫描件、双栏或竖排，它会先说明限制，再按 `reference/pdf2md-tuning.md`
调参重跑。

### Markdown → PDF

> 把 `book.md` 导出成 A4 的 PDF，带页码和目录。

默认会套用内置中文打印样式：首行缩进、章节色带、引用块、页脚页码、PDF 书签和
表格斑马纹。想换字体、纸张或配色，直接说「换成 Letter / 宋体 / 双栏目录」，
或者提供自己的 CSS 文件。

### Markdown → 电子书

> 把 `book.md` 做成 Kindle 能看的 azw3，书名《……》，作者是……。

支持 EPUB、AZW3、MOBI、DOCX；agent 会自动生成阅读器导航、探测封面、写入书名/
作者/系列元数据，并按 `<文件名>.assets/cover.*` 找封面。

### 组合流程

> 把这个 PDF 重排成 PDF 和电子书。

agent 的典型做法是：先转成 Markdown 并抽样校对 → 必要时调参重跑 → 用同一份
Markdown 分别产出 PDF 和电子书 → 检查文件是否存在、目录条目和图片数量是否正常。

## 约定

- 标题层级：`#` 书名，`##` 章，`###` 节，`####` 小节；两种输出都按这个层级生成导航
- 图片目录：`<输出名>.assets/`，封面固定叫 `cover.*`
- 图片写法：`![alt](<path>)`，路径含空格也不会坏
- 产物：默认放 `dist/`，已在 `.gitignore` 里排除

## 样式定制

`assets/pdf-style.html` 与 `assets/ebook-style.html` 是 HTML 片段（`<style>…</style>`），
想用自己的样式，把 CSS 文件交给 agent 让它替换即可，纯 CSS 也能用。常用改法：

- 字体：改 `font-family`，宋体用 `"Songti SC", "Noto Serif CJK SC", serif`
- 纸张与页边距：直接告诉 agent 要 A4/Letter 和具体边距，不要写死在样式里
- PDF 书签：`h1–h4` 上的 `bookmark-level`
- 目录页码：`nav#TOC a::after { content: leader('.') target-counter(attr(href), page); }`

细节见 `reference/styles.md`。

## 目录结构

```text
.
├── SKILL.md                 技能说明（agent 入口）
├── README.md                本文件
├── assets/
│   ├── pdf-style.html       打印样式
│   ├── ebook-style.html     电子书样式
│   └── template.html        最小 HTML 模板
├── scripts/
│   ├── pdf2md.py            PDF → Markdown
│   ├── md2pdf.sh            Markdown → PDF
│   ├── md2ebook.py          Markdown → EPUB/AZW3/MOBI/DOCX
│   └── doctor.sh            依赖体检
├── reference/
│   ├── pdf2md-tuning.md     脏 PDF 调参手册
│   └── styles.md            样式定制指南
└── examples/demo.md         可直接跑通的演示文档
```

## 已知限制

- 双栏/多栏、竖排 PDF 不做栏检测，建议先裁切或改用 `pdftotext -layout`
- 扫描件需要先 OCR（如 `ocrmypdf`），本仓库不含 OCR
- 标题层级只按字号判断，全部同字号的文档识别不出标题
- 跨页表格按页抽取，不自动合并
- 页脚脚注会按阅读顺序留在正文里

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `weasyprint: command not found` | 让 agent 补装 WeasyPrint（macOS 还需要 pango） |
| PDF 里中文变方框 | 换字体（`font-family`），或安装思源/Noto CJK |
| pandoc 提示 `translations for zh` / `Abstract has no translation` | 无害警告，忽略 |
| 电子书转换第一次很慢 | 正在建 venv 装 `ebook-converter-lib`，之后复用 |
| 电子书没有目录 | 让 agent 确认正文有 `##` 及更高级标题，或调整导航深度 |
| PDF 转出来段落粘连 / 被拆碎 | 让 agent 按 `reference/pdf2md-tuning.md` 调段落间距与缩进阈值 |
| 目录出现两份 | 告诉 agent 不要重复生成目录，或跳过 PDF 自带的目录页 |
| 封面没被识别 | 直接指定封面图；默认只认首页占比够大的图片 |

## 说明

- 命令输出里的 `[booksmith]` 前缀、`BOOKSMITH_*` 环境变量和 `~/.cache/booksmith`
  缓存目录是工具内部品牌名（Booksmith），与技能名 `book-smith-skill` 对应同一套脚本。
- 已在 macOS（pandoc 3.9 / WeasyPrint 68 / Calibre 引擎）上验证：
  Markdown→PDF→Markdown 往返、中文缩进分段、引文块、列表、代码块、表格、目录重建、封面识别，
  EPUB/AZW3 的元数据、导航、封面，以及纯 CSS 自定义样式。
