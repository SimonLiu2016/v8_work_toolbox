## 1. 助学存储与服务层（`VocabularyStudyStore`）
- [x] 1.1 创建 `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`，定义 `VocabularyWordProfile` 模型与 `VocabularyStudyStore` 持久化服务（管理 `focusedWords`、`wordProfiles`、`sentenceTranslations` 及 `vocab_tts_cache/` 目录，使用原子读写与依赖注入以便测试）
- [x] 1.2 实现 `ensureWordProfile(String word)`：优先查询本地缓存，未命中时调用 `DictionaryService.lookup` 提取音标、词性与中文释义，仍未命中时回退 `SlotTextGenerator`（`text` 槽位）生成并落盘
- [x] 1.3 实现 `ensureSentenceTranslations(String word, List<String> sentences)`：针对未缓存的原句调用 `SlotTextGenerator` 生成中文句意并落盘
- [x] 1.4 实现 `synthesizeOrGetTtsFile(String text)`：按文本哈希检查 `vocab_tts_cache/<hash>.mp3`，未命中时调用 `OpenAiTtsEngine`（`tts` 槽位）临时合成音频并缓存到本地文件

## 2. 词汇表对话框（`VocabularyBrowserDialog`）交互升级
- [x] 2.1 实现原句目标词高亮组件：使用与 `MeetingVocabularyIndex` 一致的分词与 `normalizeWord` 规则扫描 `VocabularyPosting.sentence`，在 `RichText` 中高亮当前单词（含大小写及 `'s` 所有格变形）
- [x] 2.2 新增「⭐ 重点关注」星标按钮与顶部 `[全部词汇 (N)]` / `[⭐ 重点关注 (M)]` 筛选切换栏，支持将重点关注的单词单独列出
- [x] 2.3 升级单词展开区域：顶部展示单词助学头卡（音标、词性、中文解释、`[🔊 单词发音]` 按钮）；普通单词展开时自动触发 `ensureWordProfile`，标记「重点关注」时后台自动触发 `ensureWordProfile` + `ensureSentenceTranslations`
- [x] 2.4 升级每条所属原句项：展示高亮英文原句、中文句意（已缓存时直接展示，未缓存时提供一键生成按钮）、`[🔊 句子发音]` 独立按钮与 `[↗ 跳到原会议]` 按钮

## 3. 测试、静态检查与本机应用部署
- [x] 3.1 编写 `test/it_meeting_listening/vocabulary_study_test.dart`，覆盖：原句单词高亮匹配（含大小写与 `'s` 变形）、重点关注持久化与独立筛选、方案 A 分级触发生成（展开自动查释义、重点关注自动补全句意）、TTS 临时合成与缓存命中测试
- [x] 3.2 运行 `flutter analyze lib/tools/it_meeting_listening` 与 `flutter test` 确保零静态警告且全部测试通过
- [x] 3.3 执行 `./scripts/deploy_local.sh` 重新构建 Release 并替换本机 `/Applications/V8WorkToolbox.app`
