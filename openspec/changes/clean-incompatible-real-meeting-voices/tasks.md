## 1. 说话人解析器与音色清洗机制

- [x] 1.1 在 `SpeakerProfileResolver` 中引入 `validVoiceIds` 候选池过滤：当 `setting.voiceId` 存在但不在有效音色候选集中时，将其重置为空，自动回退到当前供应商合法的散列音色。
- [x] 1.2 在 `RealMeetingService.resolveSpeakers` 中传入 `TtsBindingProbe.voiceOptions()` 的音色集合，检测是否存在不兼容音色并返回清洗后的设定。
- [x] 1.3 在 `RealMeetingService.resolveSpeakers` 中实现自愈持久化：若检测到清洗发生，自动异步将清洗后的 `MeetingSpeakerSettings` 保存至磁盘。

## 2. 烘焙音色对齐与待更新组（Pending Groups）计算自愈

- [x] 2.1 审查并确保 `RealMeetingBaker.bake` 传给底层合成引擎与记录在 `TurnGroupAudio.voiceId` 中的音色始终为清洗后的有效音色。
- [x] 2.2 确保在强制重新合成（`rebakeGroups`）成功后，`groupAudios` 正确回写更新后的有效 `voiceId` 并持久化到 `audio/<meetingId>.json`。
- [x] 2.3 验证 `pendingGroups` 比对逻辑：在重新合成后，期望音色 `desired` 与 `grp.voiceId` 一致，待更新组数立即归零。

## 3. UI 交互与「我的身份」跨厂商防御

- [x] 3.1 在 `real_meeting_views.dart`（`RealMeetingDetail` / `_SpeakerRow`）中移除跨厂商失效音色的只读“自动项”，仅保留当前供应商的有效音色列表。
- [x] 3.2 在 `RealMeetingStore.loadMyIdentity` 与槽位标记「是我」时，增加双向合法音色校验，防止「我」的角色音色跨厂商滞留。

## 4. 测试与验证

- [x] 4.1 编写/更新单元测试，覆盖跨供应商音色自动清洗、散列兜底、自愈持久化以及待更新归零场景。
- [x] 4.2 运行真实会议相关端到端测试确保所有现有用例全量通过。
- [x] 4.3 按照项目规范执行 `./scripts/deploy_local.sh` 编译部署本地应用并验证生效。
