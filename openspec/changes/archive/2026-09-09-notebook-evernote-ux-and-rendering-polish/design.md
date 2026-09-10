## Context

参见 `proposal.md`。现有解析逻辑使用 `html2text` 粗糙转换，忽略了图片标签与代码块属性；同时中间笔记列表只支持单选点选，缺少批量维护机制；UI 采用暗黑模式造成大面积沉闷阅读体验。

## Goals / Non-Goals

**Goals:**
- 在 `scripts/evernote_import.py` 中对 ENML 做正则/DOM 预处理：保护代码块、替换 `<en-todo>` 为 Markdown Checkbox、保留 `<en-media>` 对应图片标记。
- 在 `EvernoteImportService` 中实现完善的 Markdown / RichText ➔ Quill Delta 转换器，支持代码块（`code-block`）、待办事项（`list: checked/unchecked`）、层级标题、行内加粗斜体及原位图片嵌入。
- 在 `NotebookPage` 中实现 `_isBatchMode`，支持 `_selectedNoteIds` 集合管理、全选、反选、批量软删除与废纸篓批量彻底清空。
- 重构中列和右列的色彩系统：中列背景 `#F5F6F8`，卡片 `#FFFFFF`（选中 `#E8F0FE`）；右列编辑器背景 `#FFFFFF`，文字 `#1E293B`，工具栏 `#F8FAFC`。

**Non-Goals:**
- 支持富文本复杂表格单元格实时计算（保持清晰排版展示即可）。

## Decisions

### 1. 代码块与图片的 Delta 映射规范
- 采用 Flutter Quill 标准 Delta 规范：
  - 代码行：`{"insert": "code_line"}, {"insert": "\n", "attributes": {"code-block": true}}`
  - 图片嵌入：`{"insert": {"image": localPath}}, {"insert": "\n"}`
- 附件保存后将生成的绝对路径立即回填至 Delta 标记处，无法原位匹配的补充追加至文末。

### 2. 批量删除与事务安全性
- 在 `NoteStore` 中增加批量删除方法 `batchDeleteNotes(List<String> ids)` 与 `batchPermanentlyDeleteNotes(List<String> ids)`，使用 SQLite 批量事务一次性更新/删除，保障数百篇笔记毫秒级响应。

### 3. 三栏色彩搭配方案
- 左栏（导航栏）：`#1E1E1E`，文字 `#E2E8F0`（专业侧栏质感）。
- 中栏（列表栏）：底色 `#F5F6F8`，分割线 `#E2E8F0`，卡片 `#FFFFFF`，标题 `#0F172A`，时间与摘要 `#64748B`。
- 右栏（编辑栏）：底色 `#FFFFFF`，文字 `#1E293B`，光标与选区 `#2563EB`，代码块背景 `#F1F5F9`。
