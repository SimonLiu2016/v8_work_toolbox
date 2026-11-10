## Why

用户在 IT 会议听力练习（`ItMeetingListeningPage`）中使用「词汇表」（`VocabularyBrowserDialog`）学习技术词汇时，经常将核心术语标记为「⭐ 重点关注」。当前这些重点词仅能在应用内对话框或迷你磨耳朵窗口中播放学习，无法导出至外部知识库（如 Obsidian、Notion、Logseq）或本地笔记进行离线复习。更重要的是，听力练习的核心价值在于**语境（Context）**，用户需要将重点词连同其在真实会议中出现的英文原句、中文翻译、音标释义及会议出处全量导出为易读且结构化的 Markdown 文本。

## What Changes

- **新增 Markdown 导出服务 (`VocabularyMarkdownExporter`)**：
  - 纯逻辑层提取重点关注单词列表，组装包含导出元数据、单词（展示词形）、音标、词性、中文释义、全语料频次的 Markdown 文本；
  - 自动聚合该词在真实会议中的所有所属出处原句（`VocabularyPosting.sentence`），去除同句重复词导致的冗余例句；
  - 附带每条例句对应的中文翻译（如有）以及会议材料名称、发言轮次与时间戳；
  - 对缺失音标、释义或例句翻译的词汇提供平滑兜底，确保全量导出不中断。
- **扩展词汇表对话框交互 (`VocabularyBrowserDialog`)**：
  - 在对话框右上角新增「导出重点词汇 (.md)」操作按钮（与「送入迷你播放器」并列）；
  - 状态与重点关注词汇数量联动（无重点词时禁用并提示“先标记重点词汇”）；
  - 点击调起系统原生文件保存面板（`FilePicker.platform.saveFile`），预设默认文件名（如 `重点关注词汇_YYYYMMDD_HHmm.md`）；
  - 保存成功后给出 SnackBar 成功提示与路径反馈。

## Capabilities

### New Capabilities
<!-- 无新增顶级 capability -->

### Modified Capabilities
- `it-meeting-listening`: 扩展词汇表交互与数据导出规范，新增重点关注词汇及其所属会议原句、中文翻译全量导出为本地 Markdown 文件的需求与用例。

## Impact

- **代码影响**：
  - 新建 `lib/tools/it_meeting_listening/services/vocabulary_markdown_exporter.dart`
  - 修改 `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`
  - 新建测试 `test/it_meeting_listening/vocabulary_markdown_exporter_test.dart`
  - 扩展测试 `test/it_meeting_listening/real_meeting_ui_test.dart`
- **依赖与系统**：复用现有的 `file_picker` 依赖，无新增第三方包，无破坏性 API 变更。
