## Context

当前笔记应用中间列采用 `ListView.builder` 渲染笔记卡片，卡片仅绑定左键选择事件（`onTap`），缺乏次级按键（右键）响应。应用导出服务 `ExportService._exportToPdf` 使用 `package:pdf` 默认 Type 1 字体，不支持中文字形。

## Goals / Non-Goals

**Goals:**
- 在中间列笔记卡片上实现完整的 13 项右键上下文操作菜单，所有菜单项具备明确功能落地。
- 利用 `desktop_multi_window` 实现单篇笔记在独立桌面窗口中打开编辑。
- 建立全屏/沉浸式大字号笔记演示视窗。
- 支持将笔记中内嵌图片及外部附件一键批量另存至本地文件夹。
- 实现无需外部网络的本地 CJK 字体加载流水线，保证 PDF 导出中文显示 100% 保真。

**Non-Goals:**
- 不引入外部云端或第三方服务器中转（保持 100% 本地离线隐私安全）。
- 不更改底层 SQLite / Drift 核心表结构（复用已有的 `isPinned`、`Attachments` 等字段）。

## Decisions

### 决策 1：右键菜单触发与定位机制
- **选择**：使用 `GestureDetector(onSecondaryTapDown: (details) => _showNoteContextMenu(context, details.globalPosition, note))` 精准捕获鼠标指针全局屏幕坐标，通过 `showMenu<String>` 弹出原生风格的 Material/Cupertino 浮动菜单。
- **备选方案**：使用全局右键监听。弃用原因：卡片级别触发更加精准，且能直接捕获当前指向的具体 `Note` 实体。

### 决策 2：独立子窗口（在新窗口中打开笔记）参数协议
- **选择**：扩展 `main.dart` 中的子窗口路由，支持 `note:<noteId>` 参数协议：
  ```dart
  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    final noteId = subWindowArgument.substring(5);
    ...
    runApp(_SingleNoteWindowApp(noteId: noteId));
  }
  ```
- **备选方案**：在现有窗口内做拆分视图（Split View）。弃用原因：用户明确要求“在新窗口中打开笔记”，多窗口更符合 macOS 生产力工作流。

### 决策 3：PDF 导出 CJK 字体优先本地离线加载
- **选择**：在 macOS 上优先尝试加载系统自带的 `/System/Library/Fonts/Supplemental/Arial Unicode.ttf`（支持完整 CJK 字符集，读取时间约 30ms），若不存在或异常则回退至 `PdfGoogleFonts.notoSansSC`。
- **缓存机制**：在 `ExportService` 中维护单例 `pw.Font? _cachedCjkFont`，首次加载后常驻内存，后续多次导出无需重复读盘。
- **全局样式注入**：通过 `pw.Document(theme: pw.ThemeData.withFont(base: cjkFont, bold: cjkBoldFont))` 统一生效至 Header、Paragraph、Bullet 与 Text。

### 决策 4：“创建任务”与“快捷方式”语义落地
- **创建任务**：在当前笔记的 Delta 结尾无缝插入一条带待办属性的 Checkbox 项（`"- [ ] 新任务"`）并自动落盘，实现笔记内轻量待办管理。
- **添加/移除快捷方式**：映射至 `note.isPinned` 属性。已置顶的笔记显示“从快捷方式中移除”，未置顶显示“添加笔记到快捷方式”，操作后自动刷新列表排序与图钉指示。

## Risks / Trade-offs

- **[大字体文件加载内存占用]** → `Arial Unicode.ttf` 约为 22MB，采用静态单例按需惰性加载，仅在首次执行 PDF 导出时读入内存，不影响冷启动性能。
- **[子窗口独立进程数据同步]** → 由于 `drift_sqflite` 底层使用统一的 SQLite 数据库文件，单篇笔记子窗口中保存修改后，通过 SQLite 文件持久化，主窗口在获得焦点或定时刷新时能够自动感知最新内容。
