## Why

V8WorkToolbox 目前缺乏笔记管理能力。用户已有 312 条印象笔记（217 条可通过 API 获取，40 个笔记本，63 个标签），需要一个本地优先的笔记工具来替代印象笔记，同时支持将现有笔记完整迁移。

## What Changes

- 新增「笔记本」工具，提供富文本编辑、笔记本/标签管理、全文搜索、多格式导出
- 编辑器基于 `flutter_quill`（Quill Delta JSON 存储），支持代码块语法高亮、表格编辑、Markdown 粘贴自动转换
- 导出支持 Markdown / HTML / PDF / 纯文本四种格式
- 印象笔记导入：Python 子进程通过 Evernote API 获取加密笔记明文，Dart 解析 `.notes` 文件元数据与附件
- 三栏 UI 布局：笔记本树形导航 + 笔记列表 + 编辑器
- SQLite 存储，本地优先，无云同步

## Capabilities

### New Capabilities

- `notebook-storage`: 笔记本与笔记的 SQLite 存储层，含笔记本、笔记、标签、附件的 CRUD 与全文搜索
- `notebook-editor`: 基于 flutter_quill 的富文本编辑器，支持代码块、表格、图片嵌入、Markdown 粘贴转换
- `notebook-export`: 多格式导出管线（Markdown / HTML / PDF / 纯文本）
- `evernote-import`: 印象笔记导入，通过 Evernote API 解密 `.notes` 文件，转换为 Quill Delta 存储

### Modified Capabilities

（无）

## Impact

### 新增文件

- `lib/tools/notebook/` — 笔记本工具目录
  - `models.dart` — 数据模型（Note, Notebook, Tag, Attachment）
  - `note_store.dart` — SQLite 存储层（CRUD + FTS 全文搜索）
  - `export_service.dart` — 多格式导出服务
  - `markdown_converter.dart` — Quill Delta ↔ Markdown 双向转换
  - `ui/notebook_page.dart` — 三栏主页面
  - `ui/note_editor.dart` — flutter_quill 编辑器封装
  - `ui/note_list.dart` — 笔记列表组件
  - `ui/notebook_tree.dart` — 笔记本树形导航
- `scripts/evernote_import.py` — Python 印象笔记导入脚本
- `lib/tools/registry.dart` — 新增 NotebookToolDefinition 注册

### 新增依赖

- `flutter_quill` — 富文本编辑器
- `sqflite` 或 `drift` — SQLite
- `quill_delta_to_html` — Delta → HTML 导出

### Python 依赖（导入脚本）

- `evernote3` — 印象笔记 API SDK
- `html2text` — ENML → Markdown 转换

### 数据存储

- `~/Library/Application Support/V8WorkToolbox/notebook.db` — SQLite 数据库
- `~/Library/Application Support/V8WorkToolbox/notebook_attachments/` — 附件目录

### 印象笔记导入数据源

- Token 来源：macOS 钥匙串 `security find-generic-password -s "Evernote"`
- 有效 Token：`22012340/Evernote-China/smd`（217 条笔记，40 个笔记本，63 个标签）
- `.notes` 文件：`/Users/simon/Desktop/我的笔记.notes`（587.9MB，312 条，含元数据与 625 个明文附件）
