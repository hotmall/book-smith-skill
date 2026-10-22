---
name: book-smith-skill
description: book-smith-skill —— 把 Markdown 排版成 PDF / EPUB / AZW3（Kindle），也把 PDF 反向还原成带图片、表格和目录的干净 Markdown。通用 pandoc + WeasyPrint + Calibre 流水线，内置中文排版样式（段间留白、引文、页码、书签），中文排版统一按 chinese-style-skill 优化。Use when the user asks to export Markdown to PDF, build an ebook (epub/azw3/mobi) for Kindle or a reader, apply print/ebook typography, convert a PDF into Markdown, recover images and tables from a PDF, or fix a bad PDF→Markdown conversion. Triggers include 导出 PDF、生成电子书、排版、中文排版、转 Kindle、PDF 转 Markdown、PDF 提取图片/表格.
---

# book-smith-skill

三条命令覆盖「Markdown ↔ 电子书」全流程，脚本与样式都在本 skill 目录内，
不依赖具体项目结构。

```text
scripts/pdf2md.py      PDF  → Markdown（自动识别标题/段落/引文/表格/图片）
scripts/md2pdf.sh      Markdown → PDF（pandoc + WeasyPrint）
scripts/md2ebook.py    Markdown → EPUB / AZW3 / MOBI（pandoc + Calibre）
scripts/doctor.sh      检查依赖
assets/*.html         打印样式、电子书样式、HTML 模板
```

安装方式、依赖与更多示例见仓库根目录的 `README.md`。

## 何时使用

- 「把这份 md 导出成 PDF / 电子书」「做成 Kindle 能看的 azw3」
- 「这个 PDF 帮我转成 Markdown」「PDF 里的图片/表格提取出来」
- 已有的 PDF→Markdown 结果一团糟（段落被拆碎、页眉页码混进正文、目录错乱）
- 需要统一的排版产出（同一份 Markdown 同时出 PDF 和电子书）

## 开始之前

```bash
bash scripts/doctor.sh
```

缺依赖时按输出安装。`pdf2md.py` 在缺 `pdfplumber`/`pillow` 且本机有 `uv` 时会
自动用 `uv run --with ...` 临时环境运行，无需手动装。

## 中文排版

中文正文**不用首行缩进**，段落之间用空行分隔（Markdown 里是空行，PDF / 电子书里
由段后间距体现）。生成或改写中文 Markdown、PDF、电子书时，必须自动加载
`chinese-style-skill` 并按它的规则优化排版，不需要用户额外要求：

- 中英文、中文与数字之间补空格；中文标点旁不留空格
- 统一全角/半角标点、弯引号、书名号与括号，`……` 和 `——` 用双字符
- 规范日期、时间、电话号码和千位分隔符
- 只改格式，不改语义、用词和段落结构

`pdf2md.py` 输出后先由 agent 用该 skill 过一遍再交付；PDF / 电子书成品也应符合
同一套规则。若当前环境没有安装 `chinese-style-skill`，按上面的规则人工检查一遍，
并在交付时说明。

## 命令

### 1. PDF → Markdown

```bash
python3 scripts/pdf2md.py book.pdf -o book.md --frontmatter --debug
```

默认行为，通常无需调参：

- 统计正文字号、左右边距，按「缩进 = 新段、顶格 = 续行」合并段落
- 比正文大的字号映射为 h2/h3/h4（h1 留给书名），紧邻的主副标题自动合并
- 深缩进的短行输出为 `>` 引文块；行首列表标记还原为列表；等宽字体行还原为代码块
- 页面上有表格结构时输出 Markdown 表格
- 剔除页码、重复页眉页脚、PDF 自带目录页，再按识别到的标题重新生成「## 目录」
- 图片按位置插入，同图去重；首页大幅图存为 `cover.png|jpg`
- 段落之间用空行分隔，不使用首行缩进；输出前清理中英文字间多余空格
- 生成后自动用 `chinese-style-skill` 统一中文标点、空格和数字格式

常用参数：

| 参数 | 用途 |
| --- | --- |
| `--title` / `--author` / `--frontmatter` | 书名、作者、YAML frontmatter |
| `--no-toc` / `--toc-depth N` | 不生成目录 / 目录层级（默认 2 → h2+h3） |
| `--skip-pages 1-2,5` | 跳过封面、版权页等 |
| `--heading-scale 1.12` | 标题字号阈值；层级识别不出来时调小 |
| `--heading-base 2` | 最大字号对应级别；设 1 可保留原 h1 |
| `--indent-chars 2` / `--quote-indent-chars 4` | 原文首行缩进 / 引文缩进阈值（仅用于识别段落） |
| `--paragraph-gap 1.2` | 段间距阈值；无缩进排版或列表粘连时调整 |
| `--no-images` / `--no-cover` / `--no-tables` | 关闭对应抽取 |
| `--keep-page-numbers` | 保留页眉页脚（排查用） |
| `--debug` | 打印识别到的正文号、边距、标题字号 |

遇到脏数据（扫描件、双栏、竖排、无缩进排版）先读
`reference/pdf2md-tuning.md`，再决定调哪个参数，不要盲目改脚本。

### 2. Markdown → PDF

```bash
bash scripts/md2pdf.sh book.md -o dist/book.pdf
bash scripts/md2pdf.sh book.md --paper A4 --margin "20mm 18mm" --toc
```

- 默认样式 `assets/pdf-style.html`：PingFang SC 正文、章节色带、引用块、
  页脚「第 N 页 / 共 M 页」、PDF 书签（h1–h4）、表格斑马纹
- `-s 自定义样式` 换样式（HTML 片段或纯 CSS 文件均可，脚本会自动包 `<style>`），`BOOKSMITH_PDF_STYLE` 可设默认
- `--title` 只在需要额外标题块时传；Markdown 里已有 `# 书名` 时不要重复传
- Markdown 里已有「## 目录」时不要加 `--toc`，否则出现两份目录
- `--keep-html out.html` 保留中间产物，便于排查排版问题

### 3. Markdown → 电子书

```bash
python3 scripts/md2ebook.py book.md -o dist/book.epub        # EPUB
python3 scripts/md2ebook.py book.md                          # 默认 dist/book.azw3
python3 scripts/md2ebook.py book.md -f azw3 -a 作者 --cover cover.jpg
```

- 格式由 `-o` 扩展名或 `-f` 决定：`epub` / `azw3` / `mobi` / `docx`
- 自动删掉手写的「## 目录」章节，改由阅读器导航（`--keep-toc` 可保留）
- 导航层级 `--toc-depth 3` 对应 h2/h3/h4
- 封面优先 `--cover`，否则找 `<md 名>.assets/cover.*`
- 转换引擎优先用 Calibre 的 `ebook-convert`；没有则在
  `~/.cache/booksmith/venv-ebook` 建虚拟环境装 `ebook-converter-lib`（需 Python 3.11+）
- 其它 Calibre 选项用 `--arg` 透传，例如 `--arg=--publisher=某社`

## 推荐工作流

1. **PDF 重排**：`pdf2md.py` → 检查 `--debug` 输出与抽样段落 → 调参重跑 →
   用 `chinese-style-skill` 优化中文排版 → `md2pdf.sh` 出新 PDF / `md2ebook.py` 出电子书
2. **一次源文件，多端产出**：`doc.md` 同时跑 `md2pdf.sh` 和 `md2ebook.py`，
   两份产物共用同一套标题层级（h1 书名、h2 章、h3 节）
3. **校验**：确认命令退出码为 0、输出文件存在且体积合理；抽查首尾段落、
   目录条目数、图片数量；PDF 可用 `pdftotext`/`pdfinfo` 复核页数与文字。

## 约定

- 标题层级：`#` 书名，`##` 章，`###` 节，`####` 小节；两种输出都按这个约定生成导航
- 中文段落：不首行缩进，段落之间空一行；段间留白由样式控制，不用 `text-indent`
- 中文排版：以 `chinese-style-skill` 的规则为准（中英文空格、标点、数字格式）
- 图片目录：`<输出名>.assets/`，封面固定叫 `cover.*`，脚本会清理旧的 `image*/cover.*`
- 链接：图片一律写成 `![alt](<path>)`，路径含空格也不会坏
- 样式改动只改 `assets/*.html`，不要改脚本里的排版规则

## 排障

| 现象 | 处理 |
| --- | --- |
| 标题没被识别 | 调小 `--heading-scale`；确认该行字号确实大于正文 |
| 段落被拆成多段 | 调大 `--indent-chars`；或用 `--quote-indent-chars` 区分引文 |
| 段落粘成一大段 | 调小 `--indent-chars`；无缩进排版靠段间距判断，`--heading-depth` 不影响 |
| 页码混进正文 | 页码不在页面上下 10% 区域时，`--keep-page-numbers` 反向排查后手工清理 |
| 目录重复 | PDF 自带目录未被删掉 → 用 `--no-toc` 生成后再手工补，或 `--skip-pages` 跳过目录页 |
| 图片缺失 | 检查 PDF 是否为矢量图形/扫描图；扫描件需先 OCR（本 skill 不含 OCR） |
| `weasyprint: command not found` | `pip install weasyprint`；macOS 还需 `brew install pango` |
| pandoc 提示 `translations for zh` | 无害警告，可忽略 |
| 电子书没封面 | 确认 `<md 名>.assets/cover.png` / `cover.jpg`，或传 `--cover` |

更细的参数取舍、脏 PDF 处理顺序见 `reference/pdf2md-tuning.md`，
样式定制（字体、纸张、页码、书签、`.note` 弱化段落）见 `reference/styles.md`。
