# book-smith-skill

[English](README.md) | 简体中文

> 一个给 AI agent 用的电子书工坊：**Markdown ⇄ PDF / EPUB / AZW3**。
> 脚本与排版样式移植自 `jpm` 工程，所有输出都先转成 HTML，再交给 WeasyPrint
> 或 Calibre。

`book-smith-skill` 是一个自包含的 skill 包：`SKILL.md` 告诉 agent 什么时候用、
怎么调参，`scripts/` 是可直接运行的通用脚本，`assets/` 是排版样式，
`reference/` 是脏 PDF 调参手册和样式说明。全部在本地运行，不依赖云服务。

## 特性

- **PDF → Markdown**：自动统计正文字号、页边距和标题层级，按原文缩进判断段落
  与引文，还原段落、列表、代码块、表格、图片和目录，剔除页码与重复页眉页脚。
- **Markdown → HTML → PDF**：pandoc 生成单文件 HTML（图片/CSS 内嵌），
  WeasyPrint 出 A4 PDF。A4、PingFang SC、段后留白、页脚页码、h1–h4 书签、
  表格斑马纹，全部来自 `jpm/pdf-style.html`。
- **Markdown → HTML → 电子书**：同一份 HTML 交给 Calibre，输出 EPUB / AZW3 /
  MOBI；自动生成阅读器导航、探测封面、写入书名/作者元数据。样式来自
  `jpm/ebook-style.html`。
- **Markdown 收尾**：每次生成 Markdown 后先跑 `chinese-style-guide` 检查中英文
  空格、全半角标点和数字格式，再跑 `markdownlint --fix` 做最后的结构整理。
- **一键安装**：`scripts/install.sh` 安装本 skill 时，会同步安装
  [`chinese-style-guide`](https://github.com/RightCapitalHQ/chinese-style-guide)。
- **省事**：`doctor.sh` 一键体检；`pdf2md.py` 缺依赖且本机有 `uv` 时会自动
  拉临时环境运行；电子书引擎缺失时自动建 `.venv-azw3`。

## 安装

把仓库地址交给 agent，让它装成技能即可。安装本 skill 时**同时安装**
[`chinese-style-guide`](https://github.com/RightCapitalHQ/chinese-style-guide)，
最省事的方式是运行仓库里的安装脚本：

```bash
# OpenCode（默认 ~/.config/opencode/skills）
bash scripts/install.sh

# Claude Code
bash scripts/install.sh --target ~/.claude/skills
```

脚本会同时安装：

```text
<SKILLS_DIR>/
├── book-smith-skill/
└── chinese-style-guide/      来自 RightCapitalHQ/chinese-style-guide
```

装好后新开一个会话（或刷新技能列表），在技能列表里看到
`book-smith-skill` 和 `chinese-style-guide` 就算成功。

依赖交给 agent：第一次使用会运行 `bash scripts/doctor.sh`，缺什么装什么。
需要的组件是 pandoc、WeasyPrint、Python（pdfplumber / pillow）、markdownlint，
以及 Python 3.11+（电子书脚本会自动安装 `ebook-converter-lib`，底层是 Calibre
引擎）。Linux 上需要中文字体（Noto CJK）和 pango，Windows 建议在 WSL 里使用。

## 流程

```text
PDF ──pdf2md.py──▶ Markdown ──chinese-style-guide 修正 → markdownlint --fix──▶ 定稿 Markdown
                                                                  │
                                                        pandoc（单文件 HTML）
                                                        ├── WeasyPrint ──▶ PDF
                                                        └── Calibre ─────▶ AZW3 / EPUB
```

### 1. PDF → Markdown

> 帮我把 `~/Downloads/某书.pdf` 转成 Markdown，保留图片、表格和目录。

```bash
python3 scripts/pdf2md.py book.pdf -o book.md --debug
```

agent 会统计正文字号和页边距、按缩进分段落与引文、还原列表和代码块、剔除页码
与重复页眉页脚、重建目录，并把图片抽到 `<文件名>.assets/`，首页大图存成封面。
段落之间用空行分隔，不做首行缩进；生成后会自动跑 `md-lint.sh`，用 markdownlint
修结构、用 `chinese-style-guide` 检查中文排版。

### 2. Markdown → PDF

> 把 `book.md` 导出成 PDF，带页码。

```bash
bash scripts/build-pdf.sh book.md
```

输出 `dist/book.pdf`。默认套用 `jpm/pdf-style.html`：A4、PingFang SC 正文、
段后留白、蓝灰章节标题、浅蓝引用块、页脚「第 N 页 / 共 M 页」、PDF 书签和
表格斑马纹。中文正文不首行缩进。

### 3. Markdown → 电子书

> 把 `book.md` 做成 Kindle 能看的 azw3，作者是……。

```bash
bash scripts/build-azw3.sh book.md -a 作者
bash scripts/build-azw3.sh book.md -o dist/book.epub
```

同一份 HTML 可按扩展名输出 EPUB / AZW3 / MOBI，自动生成阅读器导航、探测
`<文件名>.assets/cover.*` 封面，并写入书名/作者元数据。

### 4. Markdown 收尾

```bash
bash scripts/md-lint.sh book.md
```

`md-lint.sh` 的执行顺序是：

1. 先跑 `chinese-style-guide` 的 `check_format.py`，检查中文排版；
2. 按报告修正后重跑；
3. 最后跑 `markdownlint --fix` 和 `markdownlint`，在最终文本上做结构检查。

中文检查只报告不自动改；按报告修正、重跑通过后再导出 PDF / 电子书。
`pdf2md.py` 默认会自动执行这一步。

### 组合流程

> 把这个 PDF 重排成 PDF 和电子书。

agent 的典型做法是：`pdf2md.py` 转 Markdown → 抽样校对并调参 → `md-lint.sh`
收尾并按 `chinese-style-guide` 修正 → 用同一份 Markdown 分别跑 `build-pdf.sh`
和 `build-azw3.sh` → 检查文件、目录条目和图片数量。

## 约定

- 标题层级：`#` 书名，`##` 章，`###` 节，`####` 小节
- 中文段落：不首行缩进，段间空行；留白由样式控制，不用 `text-indent`
- 中文排版：统一按 `chinese-style-guide` 的规则检查
- 图片目录：`<输出名>.assets/`，封面固定叫 `cover.*`
- 图片写法：`![alt](<path>)`
- 产物：默认放 `dist/`
- 样式：只改 `assets/pdf-style.html` / `assets/ebook-style.html`，不改脚本里的
  排版规则

## 样式来源

`assets/pdf-style.html` 与 `assets/ebook-style.html` 分别是
`jpm/pdf-style.html`、`jpm/ebook-style.html` 的原样移植：

- PDF：A4，页边距 `18mm 16mm 16mm 16mm`，PingFang SC 10.5pt / 1.75 行高，
  段后 `1.75em`，h1–h4 书签，页脚页码，引用块 `#f4f7fb` + 4pt 蓝边，表格斑马纹，
  `.note` 灰字弱化段落，任务清单方框。
- 电子书：Songti SC 正文 1.7 行高，深蓝标题带下边框，引用块左侧 3px 蓝线，
  表格边框与表头底色；不含 `@page` 等打印专用规则。

`build-pdf.sh` 和 `build-azw3.sh` 的核心命令、pandoc 参数、HTML 中间产物处理
也照搬 `jpm/build-pdf.sh`、`jpm/build-azw3.sh`。样式细节见 `reference/styles.md`。

## 目录结构

```text
.
├── SKILL.md                 技能说明（agent 入口）
├── README.md                英文 README（默认显示）
├── README.zh-CN.md          本文件
├── assets/
│   ├── pdf-style.html       打印样式（jpm 移植）
│   └── ebook-style.html     电子书样式（jpm 移植）
├── scripts/
│   ├── pdf2md.py            PDF → Markdown
│   ├── build-pdf.sh         Markdown → HTML → PDF
│   ├── build-azw3.sh        Markdown → HTML → EPUB/AZW3/MOBI
│   ├── md-lint.sh           chinese-style-guide → markdownlint 收尾
│   ├── install.sh           安装本 skill + chinese-style-guide
│   └── doctor.sh            依赖体检
├── reference/
│   ├── pdf2md-tuning.md     脏 PDF 调参手册
│   └── styles.md            样式说明
└── examples/demo.md         可直接跑通的演示文档
```

## 已知限制

- 双栏/多栏、竖排 PDF 不做栏检测，建议先裁切或改用 `pdftotext -layout`
- 扫描件需要先 OCR（如 `ocrmypdf`），本仓库不含 OCR
- 标题层级只按字号判断，全部同字号的文档识别不出标题
- 跨页表格按页抽取，不自动合并
- 页脚脚注会按阅读顺序留在正文里
- chinese-style-guide 的检查器只覆盖空格、标点、数字等可机检规则，语义和用词
  仍需 agent 按该 skill 的说明复核

## 常见问题

| 现象 | 处理 |
| --- | --- |
| `weasyprint: command not found` | 让 agent 补装 WeasyPrint（macOS 还需要 pango） |
| PDF 里中文变方框 | 换字体（`font-family`），或安装思源/Noto CJK |
| 正文出现首行缩进 | 去掉自定义样式里的 `text-indent` |
| pandoc 提示 `translations for zh` | 无害警告，忽略 |
| 电子书转换第一次很慢 | 正在建 `.venv-azw3` 装 `ebook-converter-lib`，之后复用 |
| 电子书没有目录 | 确认正文有 `##` 及更高级标题 |
| PDF 转出来段落粘连 / 被拆碎 | 让 agent 按 `reference/pdf2md-tuning.md` 调段落间距与缩进阈值 |
| 目录出现两份 | 不要重复生成目录，或跳过 PDF 自带的目录页 |
| 封面没被识别 | 直接指定封面图；默认只认首页占比够大的图片 |
| 中文检查提示未安装 | `bash scripts/install.sh` |
| markdown lint 还有问题 | 按行号修正后重跑 `md-lint.sh` |

## 说明

- 命令输出里的 `[booksmith]` 前缀、`BOOKSMITH_*` 环境变量是工具内部标识，
  与技能名 `book-smith-skill` 对应同一套脚本。
- 已在 macOS（pandoc 3.9 / WeasyPrint 68 / Calibre 引擎）上验证：
  Markdown→PDF→Markdown 往返、中文缩进分段、引文块、列表、代码块、表格、
  目录重建、封面识别，EPUB/AZW3 的元数据、导航、封面。
