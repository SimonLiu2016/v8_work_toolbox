## Context

「听力练习 → 词汇表」（`VocabularyBrowserDialog`）当前已支持：
- 全量词频索引 `MeetingVocabularyIndex`（`lib/tools/it_meeting_listening/services/meeting_vocabulary_index.dart`），提供 `postingsFor(word)` 返回该词在全部真实会议中的出处记录（`VocabularyPosting`：`meetingTitle`、`turnIndex`、`slotId`、`timestampMs`、`sentence`）。
- 助学存储 `VocabularyStudyStore`（`lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`），持久化 `focusedWords`（归一化词根集合）、`wordProfiles`（音标/词性/中文释义）、`sentenceTranslations`（例句中文翻译）。
- 已有「送入迷你播放器」按钮（`vocab-send-to-mini-btn`）位于对话框头部，作为并列操作位的既有范式。

所有导出所需数据已存在于上述两个服务中，无新增数据模型、无迁移、无跨模块依赖。

## Goals / Non-Goals

**Goals:**
- 纯逻辑层 `VocabularyMarkdownExporter` 组装 Markdown 字符串，无 UI 依赖、可独立单测。
- UI 层仅做按钮 + 文件保存 + SnackBar 提示，不掺入组装逻辑。
- 导出对现有数据零副作用。

**Non-Goals:**
- 不做 CSV/纯文本/Anki 格式导出（本次仅 Markdown）。
- 不做导出格式选择弹窗或实时预览。
- 不修改重点关注词、助学数据或词汇索引的持久化结构。
- 不涉及迷你播放器、TTS 或任何音频逻辑。

## Decisions

### D1: 导出逻辑放在独立服务类，而不是 UI 内联方法
**选择**：新建 `VocabularyMarkdownExporter`，静态方法接收 `index` + `studyStore`，返回 `String`。
**理由**：Markdown 组装含去重、缺失字段兜底等边界逻辑，独立类便于纯 Dart 单测（`test/it_meeting_listening/vocabulary_markdown_exporter_test.dart`），UI 层只留胶水。
**备选**：内联在 `_VocabularyBrowserDialogState` —— 否决，UI 难测且污染构建方法。

### D2: 例句来源直接使用 `index.postingsFor(word)`
**选择**：对每个重点词调用 `MeetingVocabularyIndex.postingsFor(normalizedWord)`，它已按会议标题、轮次排序，且不看停用词/噪声折叠（重点词天然是真术语）。
**理由**：复用既有排序与访问语义，与界面展开卡片完全一致，避免重建第二套查询逻辑。
**备选**：从 `postings` 全表过滤 —— 否决，重写排序且易与界面不一致。

### D3: 例句去重以「归一化句文本」为键
**选择**：用 `VocabularyStudyStore.normalizeSentenceKey(sentence)`（折叠连续空白、去首尾空格）作为去重键，同一句中词多次出现只保留一条。
**理由**：与助学存储的例句缓存键同一套归一化，保证「界面展示的翻译」和「导出时的翻译」命中同一缓存条目。
**备选**：直接字符串相等 —— 否决，空白差异会造成漏判。

### D4: 缺失助学字段平滑省略
**选择**：音标、词性、中文释义、例句中文翻译均为 `if (非空)` 条件输出；无字段时整行不出现，不写 `null`/占位。
**理由**：满足 spec「缺失字段自然省略」；离线或刚标记时导出不报错、不空转。
**备选**：填 `（未生成）` —— 否决，污染知识库正文。

### D5: 文件保存用 `FilePicker.platform.saveFile`
**选择**：复用 `file_picker`（仓库既有依赖），`fileName: '重点关注词汇_YYYYMMDD_HHmm.md'`，`allowedExtensions: ['md']`，返回 null（取消）时静默返回。
**理由**：与 `novel_export_dialog.dart`、`ai_subtitles_dialog.dart` 的既有保存模式一致，macOS 原生面板体验统一。
**备选**：自绘目录选择弹窗 —— 否决，重复造轮子。

### D6: 按钮命名与定位
**选择**：`OutlinedButton.icon`，key `vocab-export-focused-btn`，位于「送入迷你播放器」右侧，`focusedCount == 0` 时禁用。
**理由**：与既有 `vocab-send-to-mini-btn` 并排，视觉与交互范式一致，测试可锚定。

## Risks / Trade-offs

- [重点词很多时导出文本较大] → Markdown 为纯文本，无 IO 阻塞；组装为同步字符串操作，量级（数百词 × 数句）远小于任何性能阈值。
- [部分例句翻译仍在异步加载中，导出时缺失] → 符合 spec「缺失自然省略」；用户可稍后再导出获取完整翻译。
- [`saveFile` 返回路径为空字符串（某些平台）] → 按 `null` 同样处理为取消，不写文件。
- [导出文件名含中文，某些知识库不支持] → 文件名仅用于本地磁盘保存，不进入文档正文，风险可忽略。

## Migration Plan

无数据迁移。新增导出服务与 UI 按钮，不改任何既有持久化结构。回滚 = 删除新文件 + 撤销按钮改动。

## Open Questions

无。
