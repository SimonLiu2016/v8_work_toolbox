## Why

用户实测 MiMo 语音合成「不自然」。根因有二：**(1)** MiMo 走 Chat Audio 规范，没有 `speed`/`pitch` 参数，其「快慢/语调/情绪」全部靠 **user message 自然语言风格指令** + 文本内 `(风格标签)` 实现；而当前引擎的 chat-audio 分支只发 `assistant` 消息、`audio:{format,voice}`，**user 消息缺位**，导致永远默认平淡。**(2)** 听力练习/生词本的单词播放默认音色是 `VoicePool.zhixingjiejie`（StepFun 音色 id），绑定 MiMo 时被 `adaptVoiceForProvider(isMimo)` 被动兜底成 `mimo_default`，用户无法选到 MiMo 音色。

## What Changes

- **`TtsSynthesisConfig` 新增 `styleInstruction` 字段**（含 toJson/fromJson/copyWith 持久化）：一段自然语言风格指令（如"自然、清晰、语速适中、略带情感"），作为 MiMo `user` 消息注入。非 MiMo 引擎忽略。
- **`OpenAiTtsEngine` chat-audio 分支（tts_engine.dart:598）**：当 `isMimo && styleInstruction 非空` 时，`messages` 前置一条 `{role:'user', content: styleInstruction}`。同时做 **speed→指令翻译**：MiMo 不认 `speed` 参数，引擎层把 `speed != 1.0` 映射为「语速加快/放慢/很快/很慢」追加进指令，所有消费方自动受益。
- **文档朗读设置弹窗（`_SettingsModalContent`）**：新增「朗读风格」多行文本框（绑定 MiMo 时显示），保存进 `TtsSynthesisConfig.styleInstruction` 并持久化到 `reader_config.json`。现有 `speed` 下拉（0.75~2.0x）沿用，由引擎层翻译。
- **听力练习/生词本音色修正**：`VocabularyStudyStore` 的音色来源从「硬编码 StepFun `zhixingjiejie`」改为可配置；绑定 MiMo 时列出 MiMo 官方 9 音色（`defaultMimoVoices`），否则沿用 `VoicePool`。`synthesizeOrGetTtsFile` 透传 `styleInstruction`。生词本播放区新增音色选择下拉。
- **默认风格指令**：`resolveSmartDefault` / `VocabularyStudyStore` 对 MiMo 设一个保守默认（"自然、清晰、语速适中、略带情感"），避免「什么都不填还是平淡」。

## Capabilities

### New Capabilities
<!-- 无：本改动为既有 capability 的增强，非新 capability。 -->

### Modified Capabilities
- `doc-audio-reader`: 修改「OpenAI Chat Audio Completions and Xiaomi MiMo adaptation」——新增 MiMo 风格指令注入与 speed 翻译场景；新增「TTS 配置持久化」中 styleInstruction 字段场景。
- `it-meeting-listening-tool`: 修改「角色到音色的稳定映射」与「素材烘焙与本地落盘」——生词本/听力练习音色可配置（MiMo 音色支持）、风格指令透传场景。

## Impact

- **代码**：
  - `lib/tools/reader/models/reader_models.dart`（`TtsSynthesisConfig` + 字段 + 序列化）
  - `lib/tools/reader/services/tts_engine.dart`（chat-audio 分支 user 消息注入 + speed 翻译）
  - `lib/tools/reader/services/reader_config_store.dart`（`resolveSmartDefault` MiMo 默认风格）
  - `lib/tools/reader/ui/doc_audio_reader_page.dart`（设置弹窗「朗读风格」输入框 + vocab 音色下拉）
  - `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart`（音色可配置 + 风格透传）
- **测试**：`test/tts_engine_provider_transparency_test.dart`（chat-audio 请求体含 user 风格指令 + speed 翻译）、`test/doc_audio_reader_test.dart`（config 序列化含 styleInstruction）、`test/live_translator_test.dart` 或新增 vocab 音色测试。
- **依赖**：无新增依赖。
- **Non-goals**：
  1. **不接 `mimo-v2.5-tts-voicedesign`**（音色定制需换模型 + user 描述 + 可能 `optimize_text_preview`，工作量显著加大）。
  2. **不接 `mimo-v2.5-tts-voiceclone`**（需上传音频样本 base64 + 10MB 限制）。
  3. **不改 AI 视频工坊**（`studio_sound_design` 用 Edge 引擎，不走 MiMo）。
  4. **不做流式（stream:true）**：MiMo 支持 PCM16 流式，但当前引擎非流式解码 base64，流式是独立改动。
