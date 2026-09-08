## Context

本项目是 macOS 桌面工具箱（Flutter macOS），已有 AI 助手、磁盘瘦身、音频阅读器等工具。新增「笔记本」工具需与现有工具架构对齐：注册到 `ToolRegistry`，使用 `AppTheme` 暗色主题，配置存储于 `SettingsStore`。

用户已有 312 条印象笔记导出（`.notes` 文件），其中 217 条可通过 Evernote API 获取明文（Token 在 macOS 钥匙串中验证有效），40 个笔记本，63 个标签，625 个附件。

## Goals / Non-Goals

**Goals:**
- 本地优先的富文本笔记，数据全部存 SQLite，无云依赖
- Quill Delta JSON 作为编辑器内部格式，支持代码块语法高亮、表格、图片
- Markdown 粘贴自动转 Delta，导出支持 MD / HTML / PDF / TXT
- 印象笔记完整迁移（标题/正文/标签/笔记本/附件/时间戳）
- 三栏 UI（笔记本导航 / 笔记列表 / 编辑器）

**Non-Goals:**
- 不做云同步（本地优先）
- 不做 Web 剪藏
- 不做 OCR 图片文字识别
- 不做多设备同步
- 不做印象笔记 ENML 格式的完整 1:1 兼容（只保证内容+元数据迁移）

## Decisions

### 1. 存储：SQLite（drift）

**选择**: `drift`（原 moor）

**理由**: drift 提供类型安全的 Dart API、编译期 SQL 验证、Migration 支持、全文搜索（FTS5）。相比 `sqflite` 的原始 SQL，drift 在复杂查询和类型安全上更有优势。项目已是大型 Flutter 应用，drift 的代码生成开销可接受。

**替代方案**: sqflite — 更轻量但需要手写 SQL 和手动类型映射，易出错。

**数据库 Schema**:

```sql
-- 笔记本
CREATE TABLE notebooks (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  icon TEXT DEFAULT '📓',
  sort_order INTEGER DEFAULT 0,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 笔记
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  delta_json TEXT NOT NULL,          -- Quill Delta JSON
  notebook_id TEXT REFERENCES notebooks(id),
  is_pinned INTEGER DEFAULT 0,
  is_deleted INTEGER DEFAULT 0,     -- 软删除
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

-- 标签
CREATE TABLE tags (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  color TEXT
);

-- 笔记-标签关联
CREATE TABLE note_tags (
  note_id TEXT REFERENCES notes(id) ON DELETE CASCADE,
  tag_id TEXT REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (note_id, tag_id)
);

-- 附件
CREATE TABLE attachments (
  id TEXT PRIMARY KEY,
  note_id TEXT REFERENCES notes(id) ON DELETE CASCADE,
  filename TEXT,
  mime TEXT,
  local_path TEXT NOT NULL,          -- 相对于 attachments/ 目录
  created_at INTEGER NOT NULL
);

-- 全文搜索（FTS5）
CREATE VIRTUAL TABLE notes_fts USING fts5(
  title, content, note_id UNINDEXED
);
```

### 2. 编辑器：flutter_quill

**选择**: `flutter_quill`

**理由**: Flutter 生态最成熟的富文本编辑器，原生使用 Quill Delta JSON 格式，支持：
- 标题/加粗/斜体/下划线/删除线
- 有序/无序列表
- 代码块（含语言标记）
- 表格（通过 custom embed block）
- 图片嵌入
- 自定义 embed（用于附件）

Delta JSON 是编辑器内部格式，存储在 SQLite 中，不需要额外转换。

**代码块**: flutter_quill 内置 `code-block` 支持，配合 `flutter_highlight` 或 `highlight` 包做语法高亮。

**表格**: flutter_quill 通过 `customEmbedBlock` 或 `quill_table_embed` 包支持表格编辑。

### 3. Markdown 双向转换

**选择**: 自研 `markdown_converter.dart`（~150 行）

**Delta → Markdown**:
- 遍历 Delta ops，按 op 属性映射：`header` → `#`，`bold` → `**`，`code-block` → ` ``` `，`list` → `- ` / `1. `
- 图片 embed → `![alt](path)`，附件 embed → `[📎 filename](path)`
- 表格 embed → Markdown 表格语法

**Markdown → Delta**:
- 解析 Markdown AST（用 `markdown` 包，已有依赖）
- 按节点类型生成 Delta ops
- 用于粘贴导入和 `.md` 文件导入

**理由**: quill_delta_to_html 包只做 HTML 方向，Markdown 双向需要自研。逻辑不复杂（遍历+映射），~150 行。

### 4. 导出管线

```
  Quill Delta (SQLite)
       │
  ┌────┼────┬────────┬──────┐
  ▼    ▼    ▼        ▼
 .md  .html .pdf    .txt

  .md   → markdown_converter.dart (Delta→MD)
  .html → quill_delta_to_html 包
  .pdf  → quill_delta_to_html → HTML → macOS PDFKit (JXA)
  .txt  → 遍历 Delta ops 拼接纯文本
```

PDF 使用 macOS 原生 PDFKit（通过 JXA 脚本调用），项目中 `document_parser.dart:451` 已有此模式。不需要引入额外 PDF 依赖。

### 5. 印象笔记导入：Python 子进程

**选择**: `scripts/evernote_import.py` + Dart `Process.run`

**理由**:
- Evernote API 是 Thrift 二进制协议，Dart 无官方 SDK
- Python evernote3 SDK 仅 ~80 行核心代码
- Python 脚本输出 JSON，Dart 读取后写入 SQLite
- 脚本可独立测试，不侵入 Dart 代码

**脚本接口**:

```bash
# 列出所有笔记元数据
python3 evernote_import.py list --token TOKEN > notes_meta.json

# 获取单条笔记内容（ENML → Markdown）
python3 evernote_import.py fetch --token TOKEN --guid GUID > note_content.json

# 批量导出全部笔记
python3 evernote_import.py export_all --token TOKEN --output notes_export.json
```

**输出格式**:
```json
{
  "notes": [
    {
      "title": "...",
      "markdown": "...",
      "tags": ["tag1", "tag2"],
      "notebook": "笔记本名",
      "created": "20240101T120000Z",
      "updated": "20240102T120000Z",
      "resources": [
        {"hash": "abc123", "mime": "image/png", "base64": "..."}
      ]
    }
  ]
}
```

**Token 获取**: 通过 macOS `security` CLI 从钥匙串读取，两个 Token 都尝试（54282628 和 22012340），取有笔记的那个。

**.notes 文件辅助**: Dart 用 `xml` 包解析 `.notes` 文件获取：
- 标题、标签、创建/更新时间（明文，不加密）
- 附件 base64 数据（明文，不加密）
- 正文内容标记为加密，由 Python 脚本通过 API 补充

### 6. UI 三栏布局

```
┌──────────────┬──────────────────┬───────────────────────────┐
│  左栏 (200px) │  中栏 (280px)     │  右栏 (flex)              │
│               │                   │                           │
│  📓 笔记本     │  搜索框           │  标题 (可编辑)             │
│  ├─ 📁 工作    │  ─────────────    │  ─────────────────────    │
│  ├─ 📁 学习    │  笔记A  09-01     │                           │
│  ├─ 📁 个人    │  笔记B  08-28     │  flutter_quill 编辑器     │
│  │             │  笔记C  08-15     │                           │
│  ─────────── │                   │  [代码块] [表格] [图片]    │
│  🏷 标签       │  ─────────────    │                           │
│  ├─ #Java     │  共 N 条笔记       │  ─────────────────────    │
│  ├─ #AI       │                   │  导出: [MD] [HTML] [PDF]  │
│  ├─ #SQL      │                   │  创建: 2024-01-01         │
│               │                   │  标签: [Java] [AI]        │
└──────────────┴──────────────────┴───────────────────────────┘
```

- 左栏：笔记本树形（可展开/折叠），标签列表，点击筛选笔记
- 中栏：笔记列表（标题+摘要+日期），搜索框，排序
- 右栏：编辑器（flutter_quill），标题编辑，导出按钮，元数据

### 7. 工具注册

新增 `NotebookToolDefinition` 到 `lib/tools/registry.dart`：

```dart
class NotebookToolDefinition extends ToolDefinition {
  @override String get id => 'notebook';
  @override String get title => '笔记本';
  @override String get subtitle => '富文本笔记管理与印象笔记导入';
  @override IconData get icon => Icons.note_alt_outlined;
  @override ToolCategory get category => ToolCategory.system;
  @override Widget buildPage(BuildContext context) => const NotebookPage();
}
```

## Risks / Trade-offs

**[Evernote API Token 过期]** → Token 可能随时间失效。导入是一次性操作，建议用户导入后验证完整性。脚本在 Token 失效时给出明确错误提示。

**[217 vs 312 条笔记差异]** → API 返回 217 条，.notes 文件有 312 条。差异的 95 条可能是已删除或在另一个账号。导入时以 API 为准（有正文），.notes 中有但 API 中没有的笔记只导入元数据（标题+标签+时间），正文标记为"加密内容，无法获取"。

**[PDF 导出依赖 PDFKit]** → 使用 JXA 调用 macOS 原生 PDFKit，仅 macOS 可用。项目本身已是 macOS 专用，不构成额外约束。

**[flutter_quill 版本兼容]** → flutter_quill 对 Flutter SDK 版本有要求。需验证与项目当前 Flutter 3.9+ 的兼容性。
