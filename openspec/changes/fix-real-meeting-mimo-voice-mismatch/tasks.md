## 1. 共享 MiMo 探测 helper

- [x] 1.1 新建 `lib/tools/it_meeting_listening/services/tts_binding_probe.dart`，提供 `TtsBindingProbe`：同步遍历 `AiConfigStore.instance.slotBindings['tts']` 取首个启用供应商，用 `OpenAiTtsEngine.isMimoModel` 判定是否 MiMo
- [x] 1.2 在 `TtsBindingProbe` 中暴露 `voiceOptions()`（MiMo → `TtsVoiceOption.defaultMimoVoices`，否则 `VoicePool.all` 映射为 `TtsVoiceOption`）、`defaultVoiceId()`（MiMo → `mimo_default`，否则 `VoicePool.zhixingjiejie.id`）、`defaultStyle()`（MiMo → 保守默认风格指令，否则 `''`）
- [x] 1.3 生词本 `vocabulary_study_store._resolveDefaultVoiceId` / `_resolveDefaultStyle` 改为调用 `TtsBindingProbe`，删除重复内联探测
- [x] 1.4 生词本 `vocabulary_browser_dialog._buildVoiceAndStyleBar` 改为调用 `TtsBindingProbe`，删除重复内联探测

## 2. 真实会议音色解析与默认值适配 MiMo

- [x] 2.1 `SpeakerProfileResolver.resolve` 散列兜底改用「当前音色池」（MiMo → `TtsVoiceOption.defaultMimoVoices` 的 id 列表，否则 `VoicePool.all`），保持同一槽位同一音色的纯函数性质
- [x] 2.2 `MyIdentity.defaultVoiceId` 保持 `boyinnansheng`；在 `loadMyIdentity` 解析层于 MiMo 下回落到 `TtsBindingProbe.defaultVoiceId()`，非 MiMo 行为不变
- [x] 2.3 `RehearsalVoices` 在 MiMo 下将 5 个男声 id 确定性映射到 5 个 MiMo 音色，保持「全部为男声」语义的近似对应；非 MiMo 行为不变
- [x] 2.4 `real_meeting_service.resolveSpeakers` 传入 MiMo 判定结果，确保散列兜底与默认值走同一探测

## 3. 真实会议音色 UI 适配 MiMo

- [x] 3.1 `real_meeting_views.dart` 说话人音色下拉：候选从 `VoicePool.all` 替换为 `TtsBindingProbe.voiceOptions()`，`inPool`/兜底项检查按当前池判断
- [x] 3.2 `it_meeting_listening_page.dart`「我的身份」对话框：音色候选替换为 `TtsBindingProbe.voiceOptions()`，初始值回落到 `TtsBindingProbe.defaultVoiceId()`
- [x] 3.3 确认非 MiMo 下音色候选与行为与现状完全等价（回归点）

## 4. 烘焙透传 MiMo 风格指令

- [x] 4.1 `RealMeetingBaker._synthesize`：MiMo 下在 `TtsSynthesisConfig` 注入 `styleInstruction: TtsBindingProbe.defaultStyle()`
- [x] 4.2 `RehearsalBaker._synthesize`：MiMo 下同样注入 `styleInstruction`
- [x] 4.3 确认 MiMo 下所选 MiMo 音色直接发往合成请求、不被 `adaptVoiceForProvider` 替换为 `mimo_default`（透传验证）

## 5. 自动化测试与验证

- [x] 5.1 单元测试：MiMo 下 `SpeakerProfileResolver` 散列兜底产出 MiMo 合法音色且不同槽位高概率不同
- [x] 5.2 单元测试：MiMo 下 `TtsBindingProbe.defaultVoiceId()` 为 `mimo_default`，非 MiMo 下为 `VoicePool.zhixingjiejie.id`
- [x] 5.3 单元测试：MiMo 下 `RealMeetingBaker`/`RehearsalBaker` 注入 `styleInstruction`，且所选 MiMo 音色透传不被替换
- [x] 5.4 集成/手动验证：TTS 槽位绑定 MiMo，真实会议「说话人与音色」改音色 → 点「重新合成」→ 各角色声音对应所选 MiMo 音色且不再全部相同
