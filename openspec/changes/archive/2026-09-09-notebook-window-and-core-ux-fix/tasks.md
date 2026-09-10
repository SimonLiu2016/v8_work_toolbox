## 1. 原生窗口居中与沉浸式无标题栏

- [x] 1.1 在 `MainFlutterWindow.swift` 的子窗口创建回调中设置尺寸 1200x750 (min 960x640) 并调用 `window.center()`
- [x] 1.2 在 `MainFlutterWindow.swift` 的子窗口创建回调中开启沉浸式透明标题栏、隐藏标题条、fullSizeContentView 与 isMovableByWindowBackground

## 2. 导入路径加固与全局常驻入口

- [x] 2.1 在 `EvernoteImportService` 中实现脚本路径多重探测（Bundle Resources、工作目录、项目根路径）
- [x] 2.2 在 `NotebookPage` 左侧导航栏底部新增常驻「📥 导入印象笔记」与「📄 导入 Markdown」按钮，确保无笔记时立即可用

## 3. 仿印象笔记核心交互补全

- [x] 3.1 在 `QuillSimpleToolbarConfig` 中启用 `showListCheck: true` 支持交互式待办清单
- [x] 3.2 在 `NoteEditor` 顶部新增元数据栏：置顶图钉切换、笔记本归属切换下拉、标签 Chips 展示与快捷添加
- [x] 3.3 在 `NotebookPage` 左侧导航栏新增「废纸篓」分组，支持展示已软删除笔记，并在详情页提供「恢复」与「彻底粉碎」
- [x] 3.4 在笔记本列表项增加更多操作支持笔记本重命名

## 4. 自动保存与防抖优化

- [x] 4.1 为 `_titleCtrl` 增加 `onChanged` 防抖自动保存，并在失去焦点时静默落盘
- [x] 4.2 优化 `NoteEditor` 自动保存完成后的回调通知，采用轻量静默刷新替代整屏转菊花 `isLoading = true`

## 5. 构建与回归验证

- [x] 5.1 运行 `flutter analyze --no-fatal-infos` 保证 0 错误
- [x] 5.2 运行现有回归测试套件验证功能完好
- [x] 5.3 构建发布 Release 版本并启动验证居中显示、无标题栏沉浸样式与核心交互
