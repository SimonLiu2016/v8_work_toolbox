## 1. 导出服务实现

- [x] 1.1 新建 `lib/tools/it_meeting_listening/services/vocabulary_markdown_exporter.dart`，定义 `VocabularyMarkdownExporter` 类，提供静态方法 `String build({required MeetingVocabularyIndex index, required VocabularyStudyStore studyStore, DateTime? now})`，接收索引与助学存储，返回 Markdown 文本
- [x] 1.2 组装导出头部：`# 听力练习重点关注词汇表` 标题、导出时间、重点词总量、素材来源说明（引用块）
- [x] 1.3 遍历 `studyStore.focusedWords`（归一化词根集合），对每个词：
  - 用 `index.display[word] ?? word` 取展示词形
  - 用 `studyStore.profileFor(word)` 取音标/词性/中文释义，非空才输出对应行
  - 用 `index.postingsFor(word)` 取全部出处例句
- [x] 1.4 例句去重：以 `VocabularyStudyStore.normalizeSentenceKey(p.sentence)` 为键，同句多次出现只保留一条；去重后按原排序（会议标题、轮次）输出编号列表
- [x] 1.5 每条例句输出英文原句，且若 `studyStore.translationForSentence(p.sentence)` 非空，附中文翻译行与会议出处（`meetingTitle`、`turnIndex`、`timestampMs` 格式化）
- [x] 1.6 缺失音标/词性/释义/翻译时自然省略对应行，不输出占位符或 `null`

## 2. UI 集成

- [x] 2.1 在 `vocabulary_browser_dialog.dart` 的头部 Row 中，「送入迷你播放器」按钮右侧新增 `OutlinedButton.icon`（key `vocab-export-focused-btn`，图标 `Icons.save_alt_rounded`，文案「导出重点词汇 (.md)」）
- [x] 2.2 按钮 `onPressed` 在 `focusedCount == 0` 时置 `null`（禁用置灰），非 0 时调用导出流程
- [x] 2.3 实现导出流程：调用 `VocabularyMarkdownExporter.build` 组装文本，调起 `FilePicker.platform.saveFile`（`dialogTitle: '导出重点关注词汇'`、`fileName: '重点关注词汇_YYYYMMDD_HHmm.md'`、`type: FileType.custom`、`allowedExtensions: ['md']`）
- [x] 2.4 `saveFile` 返回 `null` 或空字符串（用户取消）时静默返回，不写文件不报错
- [x] 2.5 返回路径非空时，写入文件（`.md` 内容为 UTF-8），成功后弹绿色 SnackBar 提示「已成功导出 N 个重点词汇至: <path>」
- [x] 2.6 写入或保存异常时，弹红色 SnackBar 提示失败原因，不崩溃

## 3. 测试

- [x] 3.1 新建 `test/it_meeting_listening/vocabulary_markdown_exporter_test.dart`：
  - 有重点词时导出包含元数据、音标、词性、释义、频次与全部去重例句
  - 同一原句重复出现只导出一次
  - 缺失助学字段时自然省略、不输出 `null`/占位符
  - 无重点词时导出为空或仅含头部（按设计决定）
  - 例句翻译缓存命中时附带中文翻译与出处
- [x] 3.2 扩展 `test/it_meeting_listening/real_meeting_ui_test.dart`：
  - 无重点词时「导出重点词汇 (.md)」按钮禁用
  - 标记重点词后按钮可点击
  - 点击导出调起保存面板（mock `FilePicker`），确认后写入文件并弹出成功 SnackBar
  - 取消保存（返回 null）时不写文件、无报错

## 4. 校验

- [x] 4.1 运行 `flutter analyze`，无新增告警
- [x] 4.2 运行 `flutter test test/it_meeting_listening/`，全部通过
