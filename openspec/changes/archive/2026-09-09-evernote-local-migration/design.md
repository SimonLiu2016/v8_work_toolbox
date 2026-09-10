## Context

参见 `proposal.md`。印象笔记在 macOS 上的数据持久化位于容器沙盒目录：
`~/Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com/<UserID>/`
该目录下包含：
1. `localNoteStore/LocalNoteStore.sqlite`：存储 CoreData 元数据（表 `ZENNOTEBOOK`、`ZENNOTE`、`ZENTAG`、`ZENRESOURCE` 等）。
2. `content/<ZLOCALUUID>/content.enml`：存储未经加密的完整 ENML/HTML 笔记正文及附件图片。

## Goals / Non-Goals

**Goals:**
- 在 Python 解析脚本 `scripts/evernote_import.py` 中新增 `detect_local` 与 `import_local` 命令，直接提取本地 SQLite 与明文正文，输出标准化的 JSON 结构供 Flutter 导入。
- 增强 `parse_notes` 命令与 Dart 侧 `importFromNotesFile`：当解析 `.notes` 时，若未提供笔记本名称，自动以文件名（如 `我的笔记`）兜底创建笔记本；若遇到 `base64:aes`，若本地存在客户端数据则根据标题与时间自动抓取对应明文 ENML 并转换。
- 在 Flutter 侧 `EvernoteImportService` 中实现 `detectLocalEvernote()` 与 `importFromLocalClient()`。
- 在 `NotebookPage` 导入弹窗中提供友好选项：“一键从本机印象笔记全量迁移”与“导入 .notes / .enex 文件”。

**Non-Goals:**
- 破解离线环境且无本地客户端安装时的专有 AES 密钥（因官方私有算法未公开且不可破解）。
- 双向同步写回印象笔记（仅支持单向迁移导入）。

## Decisions

### 1. Python 脚本作为底层数据提取器与格式转换器
- **决策**：在 `scripts/evernote_import.py` 中实现对 macOS 本地 SQLite 的查询和 ENML 转 Markdown。
- **理由**：系统已自带 Python 3 及 `sqlite3`、`html2text` 模块，无需在 Flutter 引入复杂的原生 C-binding 或对 macOS 沙盒 CoreData schema 做原生绑定，轻量且稳健。

### 2. 笔记本自动归类策略
- **决策**：对于单文件导入，若 XML 中无 `<notebook>`，自动采用 `p.basenameWithoutExtension(filePath)` 作为所属笔记本；若同名笔记本已存在则复用，否则新建。
- **理由**：符合 Evernote 导出习惯（用户导出一个笔记本，文件名即为笔记本名），保证导入后最左侧笔记本列表条理清晰。

### 3. 本地明文智能补全匹配算法
- **决策**：当导入包含 `base64:aes` 的 `.notes` 文件时，解析脚本自动连接本地 `LocalNoteStore.sqlite`，优先通过 `(ZTITLE = title AND abs(ZDATECREATED - created) < 1000)` 匹配，次选 `ZTITLE = title` 命中，并直接从本地读取对应 `content/<ZLOCALUUID>/content.enml`。
- **理由**：无缝解决加密文件内容丢失，给用户带来极致顺滑的体验。

## Risks / Trade-offs

- **[Risk] 用户机器安装了非标准路径或国际版 Evernote (com.evernote.Evernote)** → **Mitigation**: 自动探测候选路径，同时覆盖 `com.yinxiang.Mac` 与 `com.evernote.Evernote`，并支持账号多目录自动发现最新修改者。
- **[Risk] 大量笔记（数百篇）导入时的 UI 卡顿** → **Mitigation**: 采用批量分段与现有 `ImportProgressCallback`，并在 Dart 侧使用局部事务与平滑刷新。
