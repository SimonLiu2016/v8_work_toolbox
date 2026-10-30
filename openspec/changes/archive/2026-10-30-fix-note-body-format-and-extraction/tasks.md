# Tasks: 纠正笔记正文格式描述与提取契约

> 代码修复已在 commit `7f98d00` 落地（`AppFlowyCodec.jsonToPlainText` 唯一入口 +
> FTS 版本 3 重建 + 回归测试）。本变更的**剩余工作**是 spec 纠偏与防复发加固。

## 1. Spec 纠偏

- [x] 1.1 `notebook-storage`：把「Quill Delta JSON」改为「AppFlowy document JSON」，澄清 `deltaJson` 字段名是历史遗留，并声明遗留 Quill 数组仍需可读
- [x] 1.2 `notebook-storage`：新增「Single extraction entry point for note body text」要求（唯一入口 `AppFlowyCodec.jsonToPlainText`，禁止用 Quill 专用解析器读已存正文）
- [x] 1.3 `notebook-editor`：把「empty Quill Delta」澄清为「迁移前的遗留格式」，明确新笔记存 AppFlowy document JSON

## 2. 防复发加固

- [x] 2.1 给 `MarkdownConverter.deltaToMarkdown` 加文档注释，明确它**仅用于 markdown/Quill 输入**（导入路径），不得用于解析已存储的笔记正文，并指向 `AppFlowyCodec.jsonToPlainText`
- [x] 2.2 复核所有从 `note.deltaJson` 取文本的调用点，确认无残留的 Quill-only 解析（已知 `export_service` 已按 `startsWith('[')` 正确分支）
- [x] 2.3 在 `notebook-storage` 或 `notebook-editor` 的测试中保留 AppFlowy 格式正文提取的回归守卫（`test/note_text_extraction_test.dart` 已在 7f98d00 落地）

## 3. 验证

- [x] 3.1 全量回归：`flutter test`，确认无新增失败
- [x] 3.2 手工验证：在真实笔记里搜一个只存在于正文的词（如 `统计`、`logstore`），确认能命中——该验证已在部署时通过（`统计` 命中 12 条，其中 11 条纯靠正文）
