## Why

当前「笔记本」独立窗口打开时停留在屏幕左下角，且保留了原生灰色标题栏，视觉上与主窗口沉浸式透明标题栏严重不一致。同时，笔记本功能虽然设计了 SQLite 存储模型，但 UI 上将核心导入入口隐藏在已选笔记内部导致全新状态下无法导入，且缺失待办清单 Checkbox、置顶、废纸篓、标签归属管理以及平滑自动保存等仿印象笔记的核心功能。需要通过本提案进行窗口级与体验级的全面修复。

## What Changes

- **原生窗口沉浸化与屏幕居中**：在 macOS 原生层配置子窗口尺寸（1200x750）、调用 `center()` 居中显示，并开启全尺寸透明沉浸式内容视图（消除原生灰色标题栏），与主窗口风格保持完全统一。
- **全局常驻导入入口**：将「导入印象笔记（.notes / API）」和「导入 Markdown」移至左侧导航栏常驻操作区，彻底解决新用户因无笔记而无法找到导入入口的问题。
- **Release 打包脚本路径与资源自适应**：在 `EvernoteImportService` 中实现打包路径感知与 fallback 探测，确保生产发布版本正常调用解析脚本。
- **补齐印象笔记核心交互功能**：
  - 工具栏开启 **待办清单（Checkbox）** 支持（`showListCheck: true`）。
  - 编辑器顶部支持 **笔记本归属选择**、**标签添加/移除**、**置顶 Pin 切换**。
  - 左侧栏增加 **废纸篓（Trash）** 分组，支持查看软删除笔记并提供一键恢复或彻底粉碎。
  - 笔记本列表项支持 **重命名** 操作。
- **静默后台自动保存防抖**：
  - 标题输入框增加 `onChanged` 防抖自动保存，不再依赖按回车键。
  - 保存后采用局部更新或静默刷新，消除中栏笔记列表频繁弹出 loading 转圈菊花的闪烁问题。

## Capabilities

### New Capabilities
- `notebook-window`: 笔记本子窗口的居中定位、自适应初始尺寸与 macOS 原生沉浸式无标题栏渲染。
- `notebook-evernote-ux`: 仿印象笔记的核心体验（全局常驻导入、待办清单、置顶、废纸篓管理、标签关联与静默自动保存）。

### Modified Capabilities
（无）

## Impact

- `macos/Runner/MainFlutterWindow.swift`: 在子窗口创建回调中配置窗口居中与沉浸式样式。
- `lib/tools/notebook/ui/notebook_page.dart`: 左侧栏新增废纸篓与导入按钮，中栏与编辑区交互重构。
- `lib/tools/notebook/ui/note_editor.dart`: 工具栏增加待办清单，顶部增加元数据操作栏，标题防抖保存。
- `lib/tools/notebook/evernote_import_service.dart`: 脚本路径自适应探测。
