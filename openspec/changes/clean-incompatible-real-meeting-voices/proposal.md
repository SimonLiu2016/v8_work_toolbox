## Why

在「听力练习」模块的「真实会议」功能中，当用户切换底层 TTS 供应商（例如从 StepFun 切换为小米 MiMo，或反之），或文稿包含历史残留配置时，`settings.json` 中常残留原供应商的音色标识（如在 MiMo 环境下残留 StepFun 的 `shenchennanyin`）。
这导致两个严重体验缺陷：
1. **合成后所有角色声音单一**：不兼容的旧音色在传入 TTS 引擎时因校验不通过，被底层 `adaptVoiceForProvider` 全量防御兜底为默认音色（如 `mimo_default`），导致不同说话人被压成同一个人发音。
2. **待更新组数（如 9 组）反复滞留无法清除**：旧音色导致烘焙状态记录的 `grp.voiceId` 与当前期望音色 `desired` 持续失配；即使点击重新合成，若存在非法音色配置或状态未归一化，重新合成后仍反复出现待更新提示。

因此需要实施**方向 C**：在检测到当前 TTS 供应商及其音色池时，自动清理与兼容性迁移真实会议中不合法的说话人音色设置，并在烘焙状态中准确对齐实际生效音色，使真实会议在任何供应商切换后均能保持多角色清晰辨识且待更新状态可正确清零。

## What Changes

- **供应商不兼容音色自动清理与回退**：
  - 在读取与解析说话人设定时（`RealMeetingService.resolveSpeakers` / `RealMeetingStore.loadSettings`），校验 `voiceId` 是否在当前 TTS 槽位音色候选池（`TtsBindingProbe.voiceOptions()`）中。
  - 若已保存的 `voiceId` 为非当前供应商支持的音色，自动清除该无效配置，使其平滑回退到当前供应商的合法散列兜底音色（或在用户修改时重新选择合法音色），并持久化清理后的设定。
- **UI 下拉框与状态同步**：
  - 真实会议详情页（`RealMeetingDetail` / `_SpeakerRow`）中剔除将跨厂商非法音色作为只读“自动”项展示的歧义逻辑，统一呈现当前供应商合法音色；清理后自动通知界面更新。
- **烘焙状态与 Pending 状态机自愈**：
  - 确保重合成时落盘的 `TurnGroupAudio.voiceId` 与清理后的有效音色完全一致。
  - 重新合成完成后，`pendingGroups` 比对逻辑精准识别一致状态，9 组等残留待更新状态在重合成完成后彻底归零。
- **我的身份（MyIdentity）音色一致性兼容**：
  - 同步强化 `loadMyIdentity` 与槽位为「是我」时的音色兼容性检查，防止「我」的音色跨供应商滞留。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 增加真实会议在 TTS 供应商切换或存在跨厂商不兼容音色时的自动清理、散列回退、UI 选项自愈与烘焙状态消除规范。

## Impact

- **Affected Code**:
  - `lib/tools/it_meeting_listening/services/speaker_profile_resolver.dart`
  - `lib/tools/it_meeting_listening/services/real_meeting_service.dart`
  - `lib/tools/it_meeting_listening/services/real_meeting_store.dart`
  - `lib/tools/it_meeting_listening/services/real_meeting_baker.dart`
  - `lib/tools/it_meeting_listening/ui/real_meeting_views.dart`
  - 单元测试与端到端测试（`test/it_meeting_listening/`）
- **Data Compatibility**:
  - `settings/<meetingId>.json` 中非法音色在加载时自动清洗并回写，向下兼容且不破坏原稿及回答数据。
