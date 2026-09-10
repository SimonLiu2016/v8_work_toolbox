## Context

See `proposal.md` - Why.
`V8WorkToolbox` 是基于 macOS Flutter 的工作台应用，主窗口使用 `MainFlutterWindow.swift` 配置了沉浸式透明标题栏与全尺寸内容视图。笔记本工具通过 `desktop_multi_window` 创建独立子窗口。当前子窗口由于原生创建配置缺失，处于左下角且带灰色原生标题栏。同时，前端 `NotebookPage` 缺少关键交互（置顶、废纸篓、标签、待办清单、全局导入入口）。

## Goals / Non-Goals

**Goals:**
- 子窗口在原生创建回调中设置尺寸 1200x750，居中显示，并应用与主窗口一致的无标题栏透明沉浸式样式。
- 将导入入口迁移到左侧导航栏常驻区域，新用户零笔记时依然立即可用。
- 修复 `EvernoteImportService` 在 macOS 打包状态下的 Python 脚本寻址逻辑，提供项目路径与 Bundle 路径双重 fallback。
- 完善仿印象笔记核心交互：富文本待办 Checkbox、置顶 Pin、废纸篓 Trash、笔记归属与标签管理。
- 优化自动保存：标题与正文防抖保存，采用局部静默刷新，杜绝中间列表频繁转菊花。

**Non-Goals:**
- 不引入云同步或远程账号注册。
- 不修改底层 SQLite 表结构（现有 schema 已完整支持 `is_pinned`、`is_deleted`、`tags`、`attachments`）。

## Decisions

### 1. 原生层统一沉浸式与居中调度
- **选择**：在 `MainFlutterWindow.swift` 的 `FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in ... }` 中直接配置 `controller.view.window`。
- **配置项**：
  - `window.minSize = NSSize(width: 960, height: 640)`
  - `window.setFrame(NSRect(..., 1200, 750), display: true)`
  - `window.center()`
  - `window.titlebarAppearsTransparent = true`
  - `window.titleVisibility = .hidden`
  - `window.styleMask.insert(.fullSizeContentView)`
  - `window.isMovableByWindowBackground = true`
- **替代方案**：使用 Dart 层的 `window_manager` 或 `desktop_multi_window` channel 控制。由于子窗口生命周期在原生展示前更早完成布局，在 Swift 创建回调中直接修改最平滑且无闪烁。

### 2. 导航栏常驻操作与废纸篓设计
- **选择**：在左侧导航栏底部放置常驻工具栏（包含「导入印象笔记 .notes / API」、「导入 Markdown」）；在导航栏顶部列表增加「📝 全部笔记」与「🗑 废纸篓 (Trash)」。
- **逻辑**：点击废纸篓时，查询 `is_deleted = true` 的笔记，笔记详情页显示「恢复」和「彻底粉碎」按钮。

### 3. 仿印象笔记详情页头部设计
- **选择**：在笔记详情页标题栏上方增加紧凑的信息栏：
  - 笔记本选择器（点击下拉选择或移动到其他笔记本）
  - 标签 Chips（可快捷添加已有标签或输入新标签）
  - 置顶图钉图标（点击即时切换 `isPinned` 并更新排序）
  - 软删除按钮（移入废纸篓）

### 4. 自动保存与中栏刷新解耦
- **选择**：`NoteEditor` 的标题和正文采用各自的防抖定时器（800ms）。自动保存成功后，只更新本地缓存的数据模型，不触发带 `isLoading = true` 的全局刷新，仅通知列表轻量重绘元数据。

### 5. 导入脚本路径解析优化
- **选择**：`EvernoteImportService` 依次探测：
  1. `Platform.resolvedExecutable` 同级或 `../Resources/scripts/evernote_import.py`
  2. 当前工作目录 `scripts/evernote_import.py`
  3. 源码工程基准路径 `/Users/simon/ClaudeWorkspace/V8WorkToolbox/scripts/evernote_import.py`

## Risks / Trade-offs

- **[macOS 窗口拖拽干扰输入]** → 设置 `isMovableByWindowBackground = true` 时，如果在背景空白处点击拖拽可移动窗口，但文本框与编辑器内部点击应正常获取焦点。Flutter 控件会拦截自身事件，已在主窗口得到验证。
- **[大体积 .notes 解析耗时]** → 本地 `我的笔记.notes` 约 588MB，使用进度弹窗与后台 Process 异步处理，并通过进度回调持续刷新 UI 提示。
