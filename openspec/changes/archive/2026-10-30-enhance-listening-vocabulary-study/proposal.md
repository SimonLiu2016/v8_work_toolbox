# Change: 听力练习词汇表优化（原句单词高亮、「重点关注」独立管理与 AI/TTS 助学卡片）

## Why
当前「听力练习 → 词汇表」（`VocabularyBrowserDialog`）仅展示词频统计与原句纯文本列表，存在两个明显痛点：
1. **展开原句缺少目标词高亮**：用户在展开某个单词查看其会议出现原句时，原句以普通文本展示，无法一眼定位该单词在句中的位置与变形（如大小写、所有格 `'s`）。
2. **缺少针对不熟悉词汇的重点标记与深度助学能力**：用户遇到不熟悉的词汇时，无法将其标记为「重点关注」并单独筛选复习，也缺少该单词的音标、词性、中文释义、所属原句的中文意思，以及单词/原句的独立发音（可通过 TTS 模型临时合成并缓存）。

## What Changes
1. **展开原句中的当前单词高亮**：
   - 在词汇表展开的每个例句（`VocabularyPosting.sentence`）中，使用与词汇表分词一致的词法扫描规则（`MeetingVocabularyIndex.normalizeWord(token) == entry.word`）定位目标单词及其大小写/所有格变形，并以高亮背景色与加粗主色在 `RichText` 中突出展示。
2. **「⭐ 重点关注」标记与独立筛选视图**：
   - 每个单词行新增「⭐ 重点关注」星标开关，支持一键标记/取消标记不熟悉的词汇。
   - 词汇表顶部新增视图切换标签：`全部词汇 (N)` 与 `⭐ 重点关注 (M)`，方便单独列出并集中学习所有重点关注词汇。
   - 重点关注状态与助学数据独立保存在 `it_meeting_listening` 专属持久化存储（`vocabulary_study_store.json`）中，不与全局「生词本」混用，且在 `MeetingVocabularyStore.rebuild` 重建词表索引时绝不丢失。
3. **单词音标/词性/中文释义与原句中文翻译（方案 A）**：
   - **普通单词展开时**：自动查询内置词典服务（`DictionaryService.lookup`，优先有道词典，未命中时回退 `text` 槽位大模型）获取并缓存该单词的**音标、词性、中文解释**；原句中文翻译支持按需点击生成。
   - **标记为「⭐ 重点关注」时**：后台自动立即生成并缓存该单词的**音标、词性、中文解释**以及其下**所有所属原句的中文意思**（调用 `text` 槽位大模型结合上下文翻译）。
4. **单词发音与所属句子单独发音（TTS 临时生成与本地缓存）**：
   - 每个单词卡片提供 `[🔊 单词发音]` 按钮，每条所属原句提供 `[🔊 句子发音]` 按钮。
   - 点击发音按钮时，实时调用 `tts` 槽位模型（`OpenAiTtsEngine`）临时生成对应单词或单句的语音并立即播放；生成后的音频按内容哈希缓存在本地 `vocab_tts_cache/` 目录中，二次点击零延迟直接播放，并支持长按或重播刷新。

## Impact
- Affected specs:
  - `it-meeting-listening`
- Affected code:
  - `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`（新增：重点关注状态、单词音标/词性/释义、句子中文翻译、TTS 音频缓存管理服务）
  - `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`（升级：原句单词高亮、重点关注星标与筛选 Tab、单词助学头卡、原句翻译与单词/单句 TTS 播放控件）
  - `test/it_meeting_listening/vocabulary_study_test.dart`（新增：分词高亮匹配、重点关注持久化、自动释义/句子翻译触发与 TTS 缓存单元测试及 Widget 测试）
