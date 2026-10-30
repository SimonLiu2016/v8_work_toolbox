## Context
「听力练习」模块的会议词汇表（`VocabularyBrowserDialog`）基于 `MeetingVocabularyIndex` 索引所有真实会议逐字稿中的单词及其出现原句（`VocabularyPosting`）。当前展开单词仅以纯文本展示原句，且 `MeetingVocabularyStore.rebuild` 每次都会从头覆盖 `meeting_vocabulary_index.json`。
为了支持：
1. 展开原句中目标单词高亮；
2. 单词标记「⭐ 重点关注」并可单独列出（在「听力练习 → 词汇表」内部独立展示与管理）；
3. 提供单词音标、词性、中文解释、所属句子的中文意思；
4. 提供单词发音与所属句子的单独发音（点击时调用 TTS 模型临时合成并本地缓存）；

需要设计一套与 `MeetingVocabularyStore.rebuild` 解耦的持久化助学存储与服务层。

## Goals / Non-Goals
- **Goals**:
  - 精确高亮原句中与当前词条匹配的词段（兼容大小写与 `'s` 所有格变形）。
  - 提供「⭐ 重点关注」标记与顶部 `全部词汇` / `⭐ 重点关注` 独立视图切换，数据独立保存在 `it_meeting_listening` 目录下。
  - 实现方案 A 的分级生成策略：普通单词展开时自动获取音标/词性/中文释义（句意按需点击生成）；标记「重点关注」时后台自动补全音标/词性/中文释义及所有所属原句的中文意思。
  - 实现按需实时调用 `OpenAiTtsEngine`（`tts` 槽位）合成单词发音与原句单独发音，并按文本 SHA-1/哈希缓存在本地目录中。
- **Non-Goals**:
  - 不向左侧全局「生词本（VocabBook）」写入数据，保持听力练习词汇表内部独立闭环管理。
  - 不在标记重点关注时预先批量合成 TTS 音频，避免并发打爆 TTS 接口配额。

## Decisions

### 1. 原句目标词高亮算法（Token-aware Highlighting）
- 使用与 `MeetingVocabularyIndex.extractSentencesAndTokens` 相同的词法正则 `RegExp(r"[A-Za-z][A-Za-z0-9'\-]*")` 扫描 `VocabularyPosting.sentence`。
- 对每个匹配的 `RegExpMatch`，计算 `MeetingVocabularyIndex.normalizeWord(match.group(0)!) == entry.word`。
- 若相等，则在 `RichText` 中将该区间渲染为高亮 `TextSpan`（带圆角背景色或主色半透明底色 + 加粗主色文字），未匹配区间保持默认样式，从而原样保留原句的大小写与标点。

### 2. 独立持久化存储：`VocabularyStudyStore`
- 存储路径：`<AppSupport>/it_meeting_listening/vocabulary_study_store.json`，音频缓存目录：`<AppSupport>/it_meeting_listening/vocab_tts_cache/`。
- 数据结构：
  - `focusedWords`: `Set<String>`（保存已标记「⭐ 重点关注」的归一化单词 key）。
  - `wordProfiles`: `Map<String, VocabularyWordProfile>`，包含：
    - `word`: `String`
    - `phonetic`: `String?`（如 `/ˈɡʌvənəns/`）
    - `partOfSpeech`: `String?`（如 `n. / v.`）
    - `definitionZh`: `String?`（中文解释）
    - `updatedAt`: `String`
  - `sentenceTranslations`: `Map<String, String>`（Key 为原句文本归一化空白后的字符串或 hash，Value 为中文句意）。
- 采用同步/原子文件读写保存 JSON 元数据（与 `RealMeetingStore` / `RehearsalStore` 一致），保证 `MeetingVocabularyStore.rebuild` 重建索引时完全不影响 `VocabularyStudyStore` 中的重点关注标记与助学缓存，且在 Widget 测试（`FakeAsync`）下不阻塞。

### 3. 单词释义与原句翻译生成流水线
- **单词音标/词性/中文释义（`ensureWordProfile(String word)`）**：
  1. 先查 `VocabularyStudyStore` 本地缓存；若已有非空释义则直接返回。
  2. 调用内置 `DictionaryService.lookup(word)`（有道词典 API）：提取 `phonetic`、聚合各词性及中文释义写入缓存并返回。
  3. 若词典未命中或未返回中文释义（例如技术专有词/缩写），回退调用 `SlotTextGenerator`（`AiService.instance.chat(slot: 'text')`）请求 JSON 格式的 `{phonetic, partOfSpeech, definitionZh}`，写入缓存并返回。
- **所属原句中文翻译（`ensureSentenceTranslations(String word, List<String> sentences)`）**：
  1. 过滤出尚未缓存在 `sentenceTranslations` 中的原句列表。
  2. 调用 `SlotTextGenerator` 一次性批量翻译该单词下的未缓存原句，写入 `VocabularyStudyStore` 并通知 UI 刷新。
- **触发时机**：
  - 展开任意单词时：自动调用 `ensureWordProfile(word)`。
  - 点击「⭐ 重点关注」开启时：自动调用 `ensureWordProfile(word)` + `ensureSentenceTranslations(word, sentences)`。
  - 普通单词展开卡片中，若某条原句尚无缓存翻译，显示轻量的 `[译]` 按钮，点击后单独生成该句翻译。

### 4. TTS 临时合成与缓存播放（`playTtsText(String text)`）
- 计算 `text.trim()` 的确定性哈希（如 FNV-1a / SHA-1 hex）作为文件名 `vocab_tts_cache/<hash>.mp3`。
- 若文件已存在且大小 > 0，直接使用 `AudioPlayer` 播放本地文件。
- 若文件不存在，调用注入的 TTS 合成回调（默认使用 `OpenAiTtsEngine` 读取 `SettingsStore` 的 `tts` 槽位配置合成音频字节），写入 `vocab_tts_cache/<hash>.mp3` 后立即播放。
- 播放状态在对话框内统一管理（同一时刻仅播放一个单词或句子发音，对应的 `🔊` 按钮展示加载中 spinner 或播放中动画）。
