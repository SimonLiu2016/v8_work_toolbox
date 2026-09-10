## Why

笔记本组件在渲染含超链接或特定格式的笔记（如“Docker常规操作”）时，由于 QuillEditor customStyles 缺少 link / lists 等默认样式实现，在 Release 构建中触发空指针异常并被 Flutter ErrorWidget 替换为全灰色块，导致内容空白且不可点击对焦。同时，笔记标题输入框继承了全局深色主题的灰色背景，与浅色纸质画布冲突；印象笔记导入脚本在处理内嵌代码块和富媒体时存在正则截断及非图片附件混杂问题。

## What Changes

- **修复标题行背景颜色**：在 NoteEditor 标题 TextField 的 InputDecoration 中显式设置 filled: false，移除深灰底色，无缝融入白底纸张。
- **解决编辑器灰屏与不可编辑崩溃**：
  - 改用 DefaultStyles.getInstance(context).merge(...) 替代手写不全的 DefaultStyles，为 link、lists、indent、leading、h4~h6 等提供完整兜底，杜绝 Release 模式下的空指针灰屏崩溃。
  - 在 QuillEditor 区域增加局部错误防御与容错渲染。
- **重构 ENML 代码块与格式解析**：
  - 升级 scripts/evernote_import.py：支持包含内部多层 <div> 的完整代码块提取（修复非贪婪截断 bug）；
  - 兼容单横线 -en-codeblock:true 与双横线 --en-codeblock:true；
  - 识别并提取网页剪藏 / ChatGPT 风格的代码块（如含 bash、Copy code 或等宽字体与深底样式的代码区域）。
- **优化图片原位嵌入与附件类型校验**：
  - 仅将真正符合图片格式（MIME 为 image/* 或扩展名为 .png/.jpg/.jpeg/.gif/.webp/.bmp）的资源作为 BlockEmbed.image 插入；
  - 确保块级图片在 Quill Delta 中独占一行（前后补充 \n 隔离），避免格式冲突；
  - 非图片附件（如 .dat、.plist、.java、.pdf）安全归入附件列表，不强行作为图片嵌入。

## Capabilities

### New Capabilities
- `notebook-tool`: 笔记本渲染容错性与富文本样式完备性规范，以及印象笔记本地数据高质量排版还原引擎。

## Impact

- lib/tools/notebook/ui/note_editor.dart：标题栏背景修正、QuillEditor 样式完备性升级与防御。
- lib/tools/notebook/evernote_import_service.dart：MarkdownToDelta 图片与块级元素严格隔离，附件 MIME 校验过滤。
- scripts/evernote_import.py：ENML 多行代码块解析状态机优化、样式识别范围扩展。
