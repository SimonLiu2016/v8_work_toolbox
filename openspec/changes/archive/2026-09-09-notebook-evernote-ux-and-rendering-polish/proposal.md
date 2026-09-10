## Why

在实现印象笔记本地迁移后，用户反馈了影响日常使用体验的 5 项核心问题：
1. 导入后笔记排版格式丢失（标题、加粗、待办等）。
2. 图片未能正确显示在正文中。
3. 代码段没有保留高亮格式。
4. 中间列笔记列表无法全选与批量删除。
5. 界面全黑，缺乏印象笔记经典高质感的“深色侧边栏 + 浅色列表 + 白底正文”三栏视觉层次。
解决这些问题能够让笔记本模块达到真正商用、高效且美观的笔记软件标准。

## What Changes

- **ENML 与富文本排版转换引擎升级**：
  - 在 Python 端智能识别 Evernote 的 `--en-codeblock` 并转为标准 Markdown 代码块；识别 `<en-todo>` 转为待办复选框；保留 `<en-media>` 图片标记与附件对应关系。
  - 在 Dart 端重构 Delta 转换器，支持代码块（`code-block`）、待办项（`list: checked/unchecked`）、多级标题（`header`）、行内样式（加粗、斜体、行内代码）及图片原位嵌入（`BlockEmbed.image`）。
- **中间列表批量管理与全选删除**：
  - 中间列新增“批量选择”与“全选”交互，支持单选/全选笔记后一键批量移入废纸篓（或废纸篓中彻底粉碎）。
- **印象笔记经典轻量配色重塑**：
  - 左侧保留深色 `#1E1E1E` 导航。
  - 中间列切换为浅灰背景 `#F5F6F8` 与白色笔记卡片 `#FFFFFF`。
  - 右侧编辑器切换为纯白纸张底色 `#FFFFFF` 与高对比度深色文字 `#202124`，工具栏切换为精致浅灰风格。

## Capabilities

### New Capabilities
- `notebook-evernote-ux-polish`: 提供完整的代码块与图片富文本排版还原、中间列表批量管理及印象笔记风格浅色主题。

## Impact

- 涉及文件：`scripts/evernote_import.py`、`lib/tools/notebook/evernote_import_service.dart`、`lib/tools/notebook/ui/notebook_page.dart`、`lib/tools/notebook/ui/note_editor.dart`、`lib/tools/notebook/note_store.dart`。
