## Context

MiMo 的 TTS 走 Chat Audio 规范，`OpenAiTtsEngine` 的 chat-audio 分支（`tts_engine.dart:598`）只发 `assistant` 消息 + `audio:{format,voice}`。MiMo 文档确认其**没有** `speed`/`pitch` 数值参数——快慢/语调/情绪全部通过 **user message 自然语言指令**（路径 A）与文本内 `(风格标签)`（路径 B）表达。当前 user 消息缺位 → 永远默认平淡。

听力练习/生词本：`VocabularyStudyStore` 默认音色是 `VoicePool.zhixingjiejie`（StepFun 音色 id），绑定 MiMo 时被 `adaptVoiceForProvider(isMimo)` 被动兜底成 `mimo_default`，用户无法选中 MiMo 音色。详见 proposal.md - Why。

## Goals / Non-Goals

**Goals:**
- 为 MiMo 合成注入可配置的自然语言风格指令（user message），使语速/语调/情绪可感知调节。
- 引擎层把既有 `speed` 字段翻译成指令片段，所有 MiMo 消费方自动受益，无需各自翻译。
- 文档朗读设置弹窗提供「朗读风格」输入框，持久化到 `reader_config.json`。
- 听力练习/生词本音色可配置：绑定 MiMo 时列出 MiMo 官方 9 音色，不再被动回退；风格指令透传。

**Non-Goals:**
- 不接 `mimo-v2.5-tts-voicedesign`（音色定制，需换模型 + user 描述 + `optimize_text_preview`）。
- 不接 `mimo-v2.5-tts-voiceclone`（音频样本 base64 + 10MB 限制）。
- 不改 AI 视频工坊（`studio_sound_design` 用 Edge 引擎，不走 MiMo）。
- 不做流式 `stream:true`（PCM16 SSE，独立改动）。

## Decisions

**D1: 风格指令用 `TtsSynthesisConfig.styleInstruction` 字段承载，而非新增专用类型。**
所有消费方（文档朗读/听力练习/生词本）都已构造 `TtsSynthesisConfig`；加一个字段即可让引擎统一读取，避免为每个消费方引入各自的「风格」概念。非 MiMo 引擎忽略该字段。

**D2: speed→指令翻译放在引擎层（`OpenAiTtsEngine`），而非各消费方。**
MiMo 不认 `speed` 参数；若让每个 UI 各自翻译，会重复且易漂移。引擎层统一映射：
`speed == 1.0` → 不追加；`1.0 < speed <= 1.5` → 「语速加快」；`speed > 1.5` → 「语速很快」；`0.75 <= speed < 1.0` → 「语速放慢」；`speed < 0.75` → 「语速很慢」。附加到 styleInstruction 之后。

**D3: 音色选择修正只落在生词本/听力练习侧。**
`VocabularyStudyStore` 加一个可配置音色来源；`vocabulary_browser_dialog.dart` 播放区加音色下拉。绑定 MiMo 时用 `TtsVoiceOption.defaultMimoVoices`（9 个），否则沿用 `VoicePool`。默认音色在 MiMo 下为 `mimo_default`。

**D4: 保守默认风格指令。**
MiMo 下 `resolveSmartDefault` / `VocabularyStudyStore` 默认 `styleInstruction = '自然、清晰、语速适中、略带情感'`，避免开箱即平淡。用户可在设置里改。

## Risks / Trade-offs

- **[指令被文本内标签覆盖]** → MiMo 同时支持 user 指令与文本内 `(标签)`；文本内标签优先级更高（文档未明说，但为叠加语义）。文档朗读若正文含标签，二者会叠加，属预期行为，非 bug。
- **[指令措辞不生效]** → 风格指令是自然语言，同一措辞效果因文本而异；无法保证精确。用保守默认 + 可编辑缓解。
- **[speed 语义在非 MiMo 下不变]** → 翻译只发生在 MiMo chat-audio 分支；OpenAI speech / Qwen DashScope 仍走各自的 `speed`/无参数路径，不受影响。
- **[生词本缓存不失效]** → `synthesizeOrGetTtsFile` 以文本为 key 缓存；改风格指令后旧缓存仍复用。需在指令变化时清缓存或把指令纳入 key（决定：纳入 key 前缀，简单可靠）。

## Migration Plan

纯新增字段与 UI，无数据迁移。旧 `reader_config.json` 无 `styleInstruction` 字段 → `fromJson` 默认空串，行为不变（不注入 user 消息）。回滚即移除字段与 UI。

## Open Questions

无。
