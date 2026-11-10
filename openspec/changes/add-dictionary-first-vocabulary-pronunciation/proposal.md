# Change Proposal: add-dictionary-first-vocabulary-pronunciation

## 1. 现状与问题背景
在 IT 职场会议听力训练工具的「词汇表」与「练习/考核」（沉浸学习、盲听测验、闪卡自评、磨耳朵轮播）中，目前单词发音一律调用商用云端 AI TTS 大模型（如 SiliconFlow / OpenAI / MiniMax 等）合成：
1. **发音不准**：AI TTS 大模型针对的是自然语言长句流式生成，面对单个孤立的英文单词（尤其是 IT 专业术语如 `sharding`, `governance`, `idempotency` 等）时，缺少前后文，经常出现怪异升调、重音倒错、吞尾音甚至发音失真。
2. **响应缓慢**：每次点击播放都需要建立云端 HTTP 网络连接并等待大模型音频流返回，冷启动耗时高达 1.5s ~ 3s，导致刷词与盲听测验严重卡顿，体验断层。
3. **浪费 Token 资源**：对常见标准英语单词无差别调用大模型，持续消耗商业 API 额度与网络流量。

## 2. 方案与核心目标
建立**「词典真人原声优先 ➔ macOS 原生离线语音兜底 ➔ 云端 AI TTS 终极保底」**的三级弹性发音链路，并提供美音（US · 默认）与英音（UK）口音支持：
1. **第 1 优先级：权威词典真人原声**
   - 优先通过高可用词典音源（如有道/牛津词典音源）拉取外教真人录制的单词标准发音 MP3；
   - 支持美音（type=2）与英音（type=1），首次拉取后写入本地 `vocab_tts_cache/` 永久离线复用。
2. **第 2 优先级：macOS 本机系统级原生离线发音**
   - 当无网络连接或词典未收录该单词时，无缝切换到本机系统语音（美音调用 `Samantha`，英音调用 `Daniel`）；
   - 完全离线脱网，0 毫秒网络延迟，发音清脆标准，0 Token 消耗。
3. **第 3 优先级：商用 AI 云端大模型 TTS**
   - 当上述离线/词典渠道均无法产出音频时，自动降级回退到现有云端大模型，确保永不哑音。
4. **例句原声维持 AI 角色渲染**
   - 会议长句与原句保留现有大模型说话人音色合成，兼顾原句语境感与单词发音准确度。

## 3. 影响范围
- `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`: 核心发音调度与缓存管理。
- `lib/tools/lookup_panel/services/dictionary_service.dart` / `youdao_service.dart`: 词典音频拉取与口音解析。
- `lib/tools/reader/services/tts_engine.dart`: 本地 macOS 引擎支持指定英文 VoiceId。
- `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`: 词汇表界面发音与口音切换。
- `lib/tools/it_meeting_listening/ui/vocabulary_practice_dialog.dart`: 练习与考核界面的快速发音。
- 测试套件与本地 Release 部署。
