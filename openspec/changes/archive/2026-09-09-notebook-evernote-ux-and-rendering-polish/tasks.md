## 1. 排版转换与图片原位嵌入引擎升级

- [x] 1.1 在 `scripts/evernote_import.py` 中升级 `convert_enml_to_markdown`：预处理 `--en-codeblock`、`<en-todo>` 及 `<en-media>` 占位标记
- [x] 1.2 在 `lib/tools/notebook/evernote_import_service.dart` 中实现完整的 Delta 转换器，支持代码块（`code-block`）、待办项（`list: checked/unchecked`）、层级标题与行内加粗斜体
- [x] 1.3 在 `evernote_import_service.dart` 中实现正文图片路径回填与原位 `BlockEmbed.image` 嵌入

## 2. 批量选择与批量删除功能实现

- [x] 2.1 在 `lib/tools/notebook/note_store.dart` 中增加 `batchDeleteNotes` 和 `batchPermanentlyDeleteNotes` 批量事务处理接口
- [x] 2.2 在 `lib/tools/notebook/ui/notebook_page.dart` 中增加批量管理模式状态、多选集合、全选/取消全选按钮与批量删除交互对话框

## 3. 印象笔记经典浅色三栏界面重塑

- [x] 3.1 改造中间列表栏视觉：背景使用 `#F5F6F8`，卡片使用白底 `#FFFFFF`，文字深色易读，增加优雅分割线与选中高亮态
- [x] 3.2 改造右侧编辑器：正文区域改为 `#FFFFFF` 白底纸质背景，标题与正文采用深灰/墨黑字体，工具栏与元数据条采用高质感浅灰
- [x] 3.3 调优代码块在浅色主题下的渲染样式（浅灰背景 `#F1F5F9`，深色等宽代码）

## 4. 验证与发布

- [x] 4.1 运行测试套件与代码静态分析 `flutter analyze --no-fatal-infos`
- [x] 4.2 验证导入包含代码段和图片的笔记排版正常、全选批量删除交互正常
- [x] 4.3 构建 macOS Release 版本并重启验证
