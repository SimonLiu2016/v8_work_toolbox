## Why

真实会议的「说话人与音色」界面只认识 StepFun 角色音色池（`VoicePool`，9 个 id），而当前 TTS 槽位绑定的是小米 MiMo。MiMo 的音色命名空间（`mimo_default` / 冰糖 / 茉莉 / 苏打 / 白桦 / Mia / Chloe / Milo / Dean）与 `VoicePool` 的 id 集合**零交集**，于是任何在界面上选择的音色，到 `OpenAiTtsEngine.synthesize` 里都被 `adaptVoiceForProvider(isMimo: true)` 静默吞成 `mimo_default`——一个女性默认音色。结果：改音色、点「重新合成」后，每个角色都播放小米默认女声，与界面选择完全脱节，且无任何报错。生词本链路在 v0.2.0 已经接入 MiMo 探测与音色候选切换，真实会议链路是遗漏的同类回归。

## What Changes

- **共享 MiMo 探测 helper**：把生词本里重复的「探测当前 TTS 槽位 → 判定是否 MiMo」逻辑（`vocabulary_study_store._resolveDefaultVoiceId` / `vocabulary_browser_dialog._buildVoiceAndStyleBar`）提炼为单一共享源，供真实会议链路复用，消除第三份重复。
- **真实会议「说话人与音色」UI 适配 MiMo**：音色下拉与「我的身份」对话框在 TTS 槽位绑定 MiMo 时列出 MiMo 官方预置音色（`TtsVoiceOption.defaultMimoVoices`），非 MiMo 时维持 `VoicePool`；不再显示必然被吞掉的 StepFun id。
- **真实会议音色解析与默认值适配 MiMo**：`SpeakerProfileResolver` 的散列兜底、`MyIdentity.defaultVoiceId`、`RehearsalVoices` 在 MiMo 下产出合法 MiMo 音色 id，否则散列/默认值照样被 `adaptVoiceForProvider` 吞成 `mimo_default`，整场同一声音。
- **真实会议烘焙透传 MiMo 风格指令**：`RealMeetingBaker` 与 `RehearsalBaker` 在 MiMo 下透传默认风格指令（自然语言语速/情感），与生词本一致，使合成结果有可感知的语气而非裸默认。

## Capabilities

### New Capabilities
（无新增 capability，真实会议属于既有 `it-meeting-listening-tool` 能力域。）

### Modified Capabilities
- `it-meeting-listening-tool`: 「角色到音色的稳定映射」需求扩展到真实会议：音色候选、默认值、散列兜底与烘焙在 MiMo 下必须产出合法 MiMo 音色并被直接透传，不得回退到 `mimo_default`。

## Impact

- **Affected Code**:
  - `lib/tools/it_meeting_listening/ui/real_meeting_views.dart`（说话人音色下拉 + 「我的身份」对话框的 MiMo 候选）
  - `lib/tools/it_meeting_listening/ui/it_meeting_listening_page.dart`（「我的身份」对话框音色候选）
  - `lib/tools/it_meeting_listening/services/speaker_profile_resolver.dart`（散列兜底适配 MiMo）
  - `lib/tools/it_meeting_listening/services/real_meeting_baker.dart` & `rehearsal_baker.dart`（MiMo 风格指令透传）
  - `lib/tools/it_meeting_listening/models/real_meeting_models.dart`（`MyIdentity.defaultVoiceId` 适配）
  - 新增共享 MiMo 探测 helper（从 `vocabulary_study_store.dart` / `vocabulary_browser_dialog.dart` 提炼）
- **Dependencies & APIs**: 无新增第三方依赖。复用既有 `OpenAiTtsEngine.isMimoModel`、`TtsVoiceOption.defaultMimoVoices`、`mimoSupportedVoiceIds`、`AiConfigStore.slotBindings`。
- **Out of scope**: `real_meeting_panel.dart` 是无人 import 的死代码，不改。
