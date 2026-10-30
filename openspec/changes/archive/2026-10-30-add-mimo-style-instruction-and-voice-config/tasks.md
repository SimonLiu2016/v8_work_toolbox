## 1. 配置模型与持久化

- [x] 1.1 在 `lib/tools/reader/models/reader_models.dart` 的 `TtsSynthesisConfig` 新增 `final String styleInstruction`（默认空串），加入构造函数、`copyWith`、`toJson`/`fromJson`（缺失时默认空串）。
- [x] 1.2 在 `lib/tools/reader/services/reader_config_store.dart` 的 `resolveSmartDefault` 中，对 MiMo 分支设置默认 `styleInstruction = '自然、清晰、语速适中、略带情感'`。

## 2. 引擎层风格指令注入与 speed 翻译

- [x] 2.1 在 `lib/tools/reader/services/tts_engine.dart` 新增私有辅助方法：根据 `config.speed` 生成 MiMo 语速片段（1.0→无；≤1.5→"语速加快"；>1.5→"语速很快"；≥0.75→"语速放慢"；<0.75→"语速很慢"）。
- [x] 2.2 修改 chat-audio 分支（约 598 行）的 `messages` 构造：当 `isMimo && styleInstruction 非空` 时，前置 `{'role':'user','content': styleInstruction}`；若 speed 片段非空则拼接到指令末尾。仅 MiMo 生效，非 MiMo 分支不动。

## 3. 文档朗读设置弹窗

- [x] 3.1 在 `lib/tools/reader/ui/doc_audio_reader_page.dart` 的 `_SettingsModalContent` 新增「朗读风格」多行 `TextEditingController`（`_styleController`），initState 用 `initialConfig.styleInstruction` 初始化，dispose 释放。
- [x] 3.2 在 `_save` 中把 `_styleController.text.trim()` 写入 `copyWith(styleInstruction: ...)`。
- [x] 3.3 在弹窗 UI 中、绑定 MiMo 时显示「朗读风格」输入框（hint 如 '自然、清晰、语速适中、略带情感'；非 MiMo 时隐藏或置灰）。

## 4. 听力练习/生词本音色与风格

- [x] 4.1 在 `lib/tools/it_meeting_listening/services/vocabulary_study_store.dart` 新增 `String? styleInstruction`（构造入参 + 持久化字段），`synthesizeOrGetTtsFile` 的 `TtsSynthesisConfig` 透传。
- [x] 4.2 修改 `synthesizeOrGetTtsFile` 的缓存 key：把 `styleInstruction` 纳入 key 前缀，避免改风格后复用旧缓存。
- [x] 4.3 让 `VocabularyStudyStore` 默认音色支持 MiMo：新增可配置 `defaultVoiceId` 逻辑，绑定 MiMo 时默认为 `mimo_default`，否则沿用 `VoicePool.zhixingjiejie`。
- [x] 4.4 在 `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart` 播放区新增音色下拉：绑定 MiMo 时列 `TtsVoiceOption.defaultMimoVoices`，否则列 `VoicePool.all`；选择后传给 store。

## 5. 测试与验证

- [x] 5.1 在 `test/tts_engine_provider_transparency_test.dart` 新增：MiMo + 有 styleInstruction 时请求体含 `user` 消息且位于 `assistant` 之前；speed 翻译片段正确；speed=1.0 不追加；非 MiMo 忽略。
- [x] 5.2 在 `test/doc_audio_reader_test.dart` 新增：`TtsSynthesisConfig` 序列化 round-trip 含 `styleInstruction`；缺失字段默认空串。
- [x] 5.3 运行 `flutter test test/tts_engine_provider_transparency_test.dart test/doc_audio_reader_test.dart` 验证通过。说明：doc_audio_reader_test.dart 有 2 个红测试（`QwenPreset 常量定义符合官方规范`、`OpenAiTtsEngine 针对千问 Token Plan 与通用 API 进行端点自适应与音色智能更正`）为**既有未提交改动**引入（QwenPreset.ttsModels 已改为 qwen-audio-* 系列、引擎已改为 SpeechSynthesizer 路由，但对应断言未同步），非本次改动引入；我新增的 4 个测试（MiMo 风格注入 ×3 + styleInstruction 序列化 ×1）全部通过。
- [x] 5.4 运行 `flutter analyze lib/tools/reader/models/reader_models.dart lib/tools/reader/services/tts_engine.dart lib/tools/reader/services/reader_config_store.dart lib/tools/reader/ui/doc_audio_reader_page.dart lib/tools/it_meeting_listening/services/vocabulary_study_store.dart lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart` 确认无新增告警。
