## 1. 数据层 (SQLite 存储)

- [ ] 1.1 添加 `drift` 和 `sqlite3_flutter_libs` 依赖，配置代码生成
- [ ] 1.2 定义数据库 Schema（notebooks, notes, tags, note_tags, attachments, notes_fts），实现 Migration
- [ ] 1.3 实现 `NoteStore`：笔记 CRUD（create/read/update/soft-delete/restore）、笔记本 CRUD、标签 CRUD、附件管理
- [ ] 1.4 实现 FTS5 全文搜索：索引同步、搜索查询、结果排序
- [ ] 1.5 编写数据层单元测试

## 2. 编辑器集成

- [ ] 2.1 添加 `flutter_quill` 依赖，验证与 Flutter 3.9+ 兼容性
- [ ] 2.2 实现 `NoteEditor` 组件：flutter_quill 封装、工具栏（标题/加粗/列表/代码块/表格/图片）、自动保存
- [ ] 2.3 实现代码块语法高亮（集成 `highlight` 包）
- [ ] 2.4 实现表格编辑支持（quill_table_embed 或自定义 embed block）
- [ ] 2.5 实现图片/文件插入：选择文件 → 保存到 attachments/ → 插入 embed

## 3. Markdown 双向转换

- [ ] 3.1 实现 `DeltaToMarkdown`：遍历 Delta ops，按属性映射为 Markdown 语法（标题/强调/列表/代码块/表格/图片/附件）
- [ ] 3.2 实现 `MarkdownToDelta`：用 `markdown` 包解析 Markdown AST，生成 Delta ops
- [ ] 3.3 实现 Markdown 粘贴检测：监听剪贴板，识别 Markdown 内容并自动转换
- [ ] 3.4 编写双向转换单元测试（覆盖标题/加粗/列表/代码块/表格/图片）

## 4. 导出管线

- [ ] 4.1 实现 `ExportService`：统一导出入口，支持 Markdown / HTML / PDF / 纯文本
- [ ] 4.2 Markdown 导出：调用 `DeltaToMarkdown`，弹出保存对话框
- [ ] 4.3 HTML 导出：使用 `quill_delta_to_html` 包生成带 CSS 的独立 HTML
- [ ] 4.4 PDF 导出：HTML → macOS PDFKit (JXA)，参考 `document_parser.dart` 已有模式
- [ ] 4.5 纯文本导出：遍历 Delta ops 拼接纯文本

## 5. UI 三栏布局

- [ ] 5.1 实现 `NotebookPage` 三栏布局：左栏笔记本导航 (200px)、中栏笔记列表 (280px)、右栏编辑器 (flex)
- [ ] 5.2 实现 `NotebookTree`：笔记本树形列表、标签筛选、新建/重命名/删除笔记本
- [ ] 5.3 实现 `NoteList`：笔记列表（标题+摘要+日期）、搜索框、排序、筛选
- [ ] 5.4 实现 `NoteEditor` 页面集成：标题编辑、编辑器、导出按钮、元数据展示
- [ ] 5.5 实现工具注册：`NotebookToolDefinition` 添加到 `registry.dart`

## 6. 印象笔记导入

- [ ] 6.1 编写 `scripts/evernote_import.py`：钥匙串 Token 读取、Evernote API 连接、笔记列表获取、单条内容获取、ENML→Markdown 转换、批量导出 JSON
- [ ] 6.2 实现 Dart 导入服务：`Process.run` 调用 Python 脚本、读取 JSON 输出、写入 SQLite
- [ ] 6.3 实现 `.notes` 文件解析：XML 解析元数据（标题/标签/时间）、附件 base64 提取
- [ ] 6.4 实现导入 UI：导入按钮、进度条、错误摘要、导入完成后刷新笔记列表
- [ ] 6.5 处理差异：API 有但 .notes 没有的 / .notes 有但 API 没有的（正文标记为"加密内容无法获取"）

## 7. 集成验证

- [ ] 7.1 运行 `flutter analyze --no-fatal-infos`，确认 0 错误
- [ ] 7.2 编写编辑器集成测试：创建笔记、编辑、保存、搜索、导出
- [ ] 7.3 手动验证印象笔记导入：执行完整导入，检查 217 条笔记的标题/正文/标签/笔记本/附件是否正确迁移
- [ ] 7.4 手动验证导出：分别导出 MD/HTML/PDF/TXT，确认格式正确
