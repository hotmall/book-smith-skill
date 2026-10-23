---
name: book-smith-skill
description: book-smith-skill —— 把 Markdown 排版成 PDF / EPUB / AZW3（Kindle），也把 PDF 反向还原成带图片、表格和目录的干净 Markdown。pandoc 先统一生成单文件 HTML，再分别交给 WeasyPrint（PDF）和 Calibre（电子书）。每次生成 Markdown 后都会先跑 chinese-style-guide 排版检查，再跑 markdownlint --fix 做最后结构整理。Use when the user asks to export Markdown to PDF, build an ebook (epub/azw3/mobi) for Kindle or a reader, apply print/ebook typography, convert a PDF into Markdown, recover images and tables from a PDF, or fix a bad PDF→Markdown conversion. Triggers include 导出 PDF、生成电子书、排版、中文排版、转 Kindle、PDF 转 Markdown、PDF 提取图片/表格.
---

# book-smith-skill

三条命令覆盖「Markdown ⇄ 电子书」全流程。所有产物都先变成 HTML，再转目标格式：

```text
PDF ──pdf2md.py──▶ Markdown ──chinese-style-guide 修正 → markdownlint --fix──▶ 定稿 Markdown
                                                                  │
                                                        pandoc（单文件 HTML，内嵌图片/CSS）
                                                        ├── WeasyPrint ──▶ PDF
                                                        └── Calibre ─────▶ AZW3 / EPUB / MOBI
```

```text
scripts/pdf2md.py       PDF  → Markdown（标题/段落/引文/表格/图片）
scripts/build-pdf.sh    Markdown → HTML → PDF（pandoc + WeasyPrint）
scripts/build-azw3.sh   Markdown → HTML → AZW3/EPUB/MOBI（pandoc + Calibre）
scripts/md-lint.sh      Markdown 收尾：chinese-style-guide → markdownlint --fix
scripts/install.sh      安装本 skill，并同步安装 chinese-style-guide
scripts/doctor.sh       检查依赖
assets/pdf-style.html   打印样式
assets/ebook-style.html 电子书样式
```

## 安装

```bash
bash scripts/install.sh                 # OpenCode：~/.config/opencode/skills
bash scripts/install.sh --target ~/.claude/skills   # Claude Code
```

`install.sh` 会同时安装两个技能：

- `book-smith-skill`
- [`chinese-style-guide`](https://github.com/RightCapitalHQ/chinese-style-guide)
  （从该仓库的 `.claude/skills/chinese-style-guide` 复制）

装完新开一个会话，或刷新技能列表。只想手动安装时，把两个仓库分别放进同一个
skills 目录，目录名保持 `book-smith-skill` / `chinese-style-guide`。

开始之前跑一次：

```bash
bash scripts/doctor.sh
```

## Markdown 收尾（必须）

**每次生成或改写 Markdown 之后**，先跑：

```bash
bash scripts/md-lint.sh book.md
```

它会按固定顺序做两件事：

1. 先调用 `chinese-style-guide` 的 `check_format.py`，检查中英文空格、全半角标点、
   数字与日期格式；
2. 再跑 `markdownlint --fix`，按中文排版修正后的文本做最后的结构整理
   （空行、标题包围空行、分隔线等），然后跑一次 `markdownlint` 确认没有残留。

这个顺序是有意的：中文排版修正可能改变行结构，所以 **markdownlint 必须放在
chinese-style-guide 之后**，作为最后一道结构检查。中文检查只报告不自动改；
拿到报告后加载 `chinese-style-guide` skill，按它的规则逐条修正，然后重跑
`md-lint.sh`。只改格式，不改语义、用词和段落结构。**收尾没通过，不要进入 PDF /
电子书导出。**

`pdf2md.py` 默认已自动执行这一步；想跳过用 `--no-lint`。

## 1. PDF → Markdown

```bash
python3 scripts/pdf2md.py book.pdf -o book.md --debug
```

默认行为：

- 统计正文字号、左右边距，按「缩进 = 新段、顶格 = 续行」合并段落
- 比正文大的字号映射为 h2/h3/h4（h1 留给书名），紧邻的主副标题用空格合并
- 缩进达到 `--quote-indent-chars`（默认 4 字）的行输出为 `>` 引文块，
  诗词行之间用 `\` 硬换行
- 行首列表标记还原为列表；等宽字体行还原为代码块
- 页面上有表格结构时输出 Markdown 表格
- 剔除页码、重复页眉页脚、PDF 自带目录页，再按识别到的标题重新生成「## 目录」
- 图片按位置插入，同图去重；首页大幅图存为 `cover.*`
- 段落之间用空行分隔，不使用首行缩进
- 生成后自动跑 `md-lint.sh`（先 chinese-style-guide，后 markdownlint）

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
| `--no-lint` | 生成后不做 markdownlint / 中文检查 |
| `--debug` | 打印识别到的正文号、边距、标题字号 |

导出 PDF / 电子书时**不要带 YAML frontmatter**：书名用 `# 书名`，作者在电子书
命令里用 `-a` 传。`--frontmatter` 只用于需要元数据的其它工具。

脏数据（扫描件、双栏、竖排、无缩进排版）先读 `reference/pdf2md-tuning.md`。

## 2. Markdown → PDF

```bash
bash scripts/build-pdf.sh book.md
```

- 输出固定为 `dist/<md 文件名>.pdf`
- 样式固定为 `assets/pdf-style.html`（内置打印样式）：A4、
  PingFang SC 10.5pt、1.75 行高、段后留白、蓝灰色章节标题、浅蓝引用块、
  页脚「第 N 页 / 共 M 页」、h1–h4 PDF 书签、表格斑马纹
- 流程：pandoc 生成单文件 HTML（`--embed-resources`，图片/CSS 全内嵌）→
  移除 pandoc 默认模板样式 → WeasyPrint 出 PDF
- 中文正文不首行缩进，段落之间靠样式里的段后 `margin` 留白
- 改字体、纸张、配色只改 `assets/pdf-style.html`，不要改脚本

## 3. Markdown → 电子书

```bash
bash scripts/build-azw3.sh book.md -a 作者          # 默认 dist/book.azw3
bash scripts/build-azw3.sh book.md -o dist/book.epub
```

- 同一份 HTML 交给 Calibre，按 `-o` 扩展名输出 `azw3` / `epub` / `mobi`
- 样式固定为 `assets/ebook-style.html`（内置电子书样式）：
  宋体正文、深蓝标题、蓝线引用块、表格边框
- 书名取 Markdown 首个 `#` 标题，也可用 `-t` 指定；`-a` 写作者元数据
- 默认删掉手写的「## 目录」章节，改由阅读器导航（`--keep-toc` 可保留）
- 导航层级：h2 → 一级、h3 → 二级、h4 → 三级
- 封面优先找 `<md 名>.assets/cover.png|jpg|jpeg`
- 首次运行会在 skill 目录建 `.venv-azw3` 并安装 `ebook-converter-lib`
  （需要 Python 3.11+）

## 推荐工作流

1. `pdf2md.py` 抽取 → 看 `--debug` 和抽样段落 → 必要时调参重跑
2. `md-lint.sh` 收尾，按 `chinese-style-guide` 修正剩余排版问题
3. `build-pdf.sh` 出 PDF；需要电子书再跑 `build-azw3.sh`，两者共用同一份 Markdown
4. 校验：命令退出码为 0、文件存在且体积合理；抽查首尾段落、目录条目、图片数量

## 约定

- 标题层级：`#` 书名，`##` 章，`###` 节，`####` 小节；PDF 书签和电子书导航都按这个约定
- 中文段落：不首行缩进，段落之间空一行；留白由样式控制，不用 `text-indent`
- 中文排版：以 `chinese-style-guide` 的规则为准（中英文空格、标点、数字格式）
- 图片目录：`<输出名>.assets/`，封面固定叫 `cover.*`
- 图片写法：`![alt](<path>)`，路径含空格也不会坏
- 产物：默认放 `dist/`
- 样式与脚本：沿用内置实现，不自行发明新的排版规则

## 排障

| 现象 | 处理 |
| --- | --- |
| 标题没被识别 | 调小 `--heading-scale`；确认该行字号确实大于正文 |
| 诗词/引文变成正文 | 调小 `--quote-indent-chars`（要大于 `--indent-chars`） |
| 段落被拆成多段 | 调大 `--indent-chars`；或用 `--quote-indent-chars` 区分引文 |
| 段落粘成一大段 | 调小 `--indent-chars`；无缩进排版靠段间距判断 |
| 页码混进正文 | 页码不在页面上下 10% 区域时，`--keep-page-numbers` 反向排查后手工清理 |
| 目录重复 | 先确认 PDF 自带目录页是否被自动丢弃；仍重复时用 `--skip-pages` 跳过目录页，或 `--no-toc` 后手工补 |
| 图片缺失 | 检查 PDF 是否为矢量图形/扫描图；扫描件需先 OCR（本 skill 不含 OCR） |
| `weasyprint: command not found` | `pip install weasyprint`；macOS 还需 `brew install pango` |
| pandoc 提示 `translations for zh` | 无害警告，可忽略 |
| 电子书没封面 | 确认 `<md 名>.assets/cover.png` / `cover.jpg` |
| 中文检查提示未安装 | `bash scripts/install.sh` 同步安装 `chinese-style-guide` |
| markdown lint 还有问题 | 按行号修正后重跑 `md-lint.sh`；不要直接跳过 |

更细的参数取舍、脏 PDF 处理顺序见 `reference/pdf2md-tuning.md`，
样式说明见 `reference/styles.md`。
