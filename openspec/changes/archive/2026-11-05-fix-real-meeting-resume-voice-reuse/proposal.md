## Why

在真实会议（如「10-29 项目周例会」）中，用户已为各说话人配置了合法 MiMo 音色，且解析链路（清洗、散列兜底、合成请求）已发出正确的多音色请求，但点击「重新合成」后整篇音频仍呈现单一的 `mimo_default` 女声，且「待更新 N 组」反复出现、无法通过重新合成清除。

根因在 `RealMeetingBaker.bake` 的**续跑复用条件**：只要逐组音频文件存在且上次未标记失败，就直接复用旧音频、跳过合成——复用判断完全不看该组落盘的 `voiceId` 是否等于当前期望音色。历史残留的旧音频（11-04 音色被吞成 `mimo_default` 的失败烘焙、11-02 的 StepFun 音色、更早的未记录音色组）因此全部被原样保留拼进整篇 mp3。同时「重新合成」入口走的是 `bake()`（`forceGroups` 恒为空），永远不会走 `rebakeGroups` 的强制重烘路径，导致 `pendingGroups` 检出的待更新组在重新合成中被 `continue` 跳过，形成「进度跑完、待更新纹丝不动」的死循环。

## What Changes

- **续跑复用增加音色一致性条件**：`RealMeetingBaker.bake` 的复用判断在原有「文件存在且上次未失败」之上，新增「该组落盘的 `voiceId` 与本次解析出的期望音色一致」——不一致的组不再复用旧音频，而是按当前期望音色重新合成。
- **历史无记录组一并自愈**：落盘 `voiceId` 为空的组（旧版本 bake 未记录音色）视为不一致，同样触发重烘，消除「音色分配可追溯」的盲区。
- **待更新归零闭环**：重烘成功后落盘的 `TurnGroupAudio.voiceId` 即为期望音色，`pendingGroups` 比对通过，待更新计数在重新合成完成后彻底归零。

## Capabilities

### Modified Capabilities

- `it-meeting-listening-tool`: 真实会议烘焙的续跑复用 SHALL 以「落盘音色与当前期望音色一致」为前提；音色不一致（含空记录）的组 SHALL 重新合成，使「重新合成」一次跑完后待更新组数归零、整篇音频呈现各说话人配置的差异化音色。

## Impact

- **Affected Code**:
  - `lib/tools/it_meeting_listening/services/real_meeting_baker.dart`（`bake` 的复用条件）
  - 单元测试（`test/it_meeting_listening/real_meeting_baker_test.dart` 等）
- **Data Compatibility**:
  - `audio/<meetingId>.json`（bake state）格式不变；首次以新逻辑重烘后，历史残留的非法/空 `voiceId` 被合法音色覆盖。
  - **一次性代价**：带历史残留的会议（如 129 组中约 110 组旧音频）首次「重新合成」会重烘大部分组，按 MiMo 单组 5–50 秒耗时，整场约需 1–2 小时；此后恢复增量续跑。
