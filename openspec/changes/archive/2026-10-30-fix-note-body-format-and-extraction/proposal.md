# Proposal: 纠正笔记正文格式描述与提取契约

## 背景与问题

`notebook-storage` spec 声称「store notes as **Quill Delta JSON**」，`notebook-editor` 的措辞也沿用 Quill 语汇。但自 AppFlowy 编辑器迁移后，**实际存储格式已是 AppFlowy document JSON 对象**（`{"document":{"type":"page","children":[...]}}`），不再是 Quill Delta 数组。字段名仍叫 `deltaJson` 是历史遗留，进一步加深了误导。

spec 的这处不准确有实际代价——本次实现阶段二 RAG 时，因相信 spec 描述而假设正文是 Quill Delta 数组，用了 Quill 专用解析器（`jsonDecode(...) as List`），结果：

```
AppFlowy 格式存库
      │
   ┌──┴──────────────────────┐
   ▼                         ▼
FTS 索引正文              RAG 检索片段
_extractPlainText         MarkdownConverter.deltaToMarkdown
   │                         │
   └── 都抛异常 → catch 静默返回 '' ──┘
              │
              ▼
   正文从未进索引（307 条笔记 content 全空）
   搜索与 RAG 只覆盖标题
```

该 bug 已在 commit `7f98d00` 修复（`AppFlowyCodec.jsonToPlainText` 作为唯一提取入口），并在真实库验证（`统计` 命中 12 条，其中 11 条纯靠正文）。

## 解决方案

**纯文档纠偏 + 契约固化**。代码修复已落地，本变更加固 spec，避免同类假设再次发生：

1. `notebook-storage`：把「Quill Delta JSON」改为「AppFlowy document JSON」，并新增「正文提取契约」要求——所有从笔记正文取文本的路径 MUST 走 `AppFlowyCodec.jsonToPlainText`（其内部兼容 AppFlowy 对象与遗留 Quill 数组），MUST NOT 使用 Quill 专用解析器。
2. `notebook-editor`：把「empty Quill Delta」的措辞澄清为「遗留格式」，明确新笔记存 AppFlowy document JSON、旧 Quill 数组仍需可读。

## 能力（Capabilities）

**变更**
- `notebook-storage` — 存储格式描述纠偏；新增正文提取契约要求。
- `notebook-editor` — 遗留格式措辞澄清。

## 影响范围

- **文档**：`openspec/specs/notebook-storage/spec.md`、`openspec/specs/notebook-editor/spec.md`
- **代码**：无新增（`AppFlowyCodec.jsonToPlainText` 已在 `7f98d00` 落地，唯一提取入口已收敛）
- **不受影响**：存储 schema、编辑器行为、导出路径（`export_service` 本就按首字符分支处理两种格式）

## 非目标

- **不改存储格式**。AppFlowy document JSON 是既定事实，不迁回 Quill。
- **不删除 `MarkdownConverter.deltaToMarkdown`**。它仍服务 markdown 导入路径（`AppFlowyCodec` 内部对 markdown 输入会调用它），只是**不应用于解析已存储的笔记正文**。
- **不改 `export_service`**。它已按 `startsWith('[')` 正确分支。

## 成功判据

1. spec 不再声称存储格式是 Quill Delta。
2. spec 明确正文提取的唯一入口与禁止用法，使"用 Quill 解析器读笔记正文"成为可被 review 捕获的违规。
3. 存在回归测试锁定 AppFlowy 格式可提取正文（已在 `7f98d00` 落地：`test/note_text_extraction_test.dart`）。
