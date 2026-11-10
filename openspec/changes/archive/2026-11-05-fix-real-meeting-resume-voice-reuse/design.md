## Context

真实会议的分组烘焙在 `RealMeetingBaker.bake`（`lib/tools/it_meeting_listening/services/real_meeting_baker.dart:113`）里有一个续跑优化：以旧 bake state 为底，逐组检查 `turns/<meetingId>/gN.mp3` 是否存在且上次未失败，命中则 `continue` 跳过合成。这个优化在「音色从未变过」的场景下是对的，但它判断「能不能复用」时只看两个信号——文件存在、上次未标记失败——**不看这组音频当初是用哪个音色念的**。

音色解析链路（`resolveSpeakers` → `sanitizeVoices` → `SpeakerProfileResolver.resolveAll`）在 2026-11-05 的 `clean-incompatible-real-meeting-voices` 之后已经是正确的：清洗跨厂商脏音色、MiMo 下把散列兜底收进官方音色池、合成请求携带正确 `voiceId`。实测日志（2026-11-05 13:58–14:12，会议 `rm_45006ed0a3df8b35`「10-29 项目周例会」）证明请求端确实交错了 `Dean` / `白桦` / `Milo` 等多个音色。

问题出在请求端之后：129 组里约 110 组的逐组音频是历史遗留（2026-11-02 StepFun 时期、2026-11-04 深夜音色被吞成 `mimo_default` 的失败烘焙、更早未记录音色的组）。「重新合成」入口调用的是 `bake()` 而非 `rebakeGroups()`，`forceGroups` 恒为空集，于是这些组全部命中续跑分支被复用，旧音频原样拼进整篇 mp3。同时 `pendingGroups`（`real_meeting_service.dart:328`）按「期望音色 ≠ 落盘音色」检出 9 组待更新，用户点重新合成时这 9 组又被续跑跳过，落盘音色不变，待更新计数纹丝不动——形成死循环。

约束：
- `TurnGroupAudio.voiceId` 字段已存在且会持久化，无需改数据模型。
- bake state 中 `voiceId` 可能为空串（旧版本未记录），必须与「音色不匹配」区分处理，但两者都应触发重烘。
- 合成成本高（MiMo 单组 5–50 秒），不能让每次烘焙都全量重做。

## Goals / Non-Goals

**Goals:**
- 让续跑复用的前提包含音色一致性，使「重新合成」能真正替换掉音色不对的历史音频。
- 把「落盘无音色记录」纳入不一致判定，让可追溯性缺口一并自愈。
- 保证一次「重新合成」跑完后 `pendingGroups` 归零，不引入新的死循环。
- 保持音频文件已存在且音色正确时的增量续跑能力（调度、失败重试都不退化）。

**Non-Goals:**
- 不改音色解析、清洗、散列兜底、`adaptVoiceForProvider` 这整条链路——它已被验证是对的。
- 不改 bake state / 逐组音频的落盘格式。
- 不引入并发合成或加速策略；首次全量重烘的耗时是接受的一次性代价。
- 不动公开素材片段（`ClipBaker`）与排练会议（`RehearsalBaker`）的续跑逻辑。

## Decisions

### Decision 1: 复用条件增加「落盘音色 == 期望音色」

**方案**：在 `bake()` 的复用分支里，把条件从

```dart
if (!forced && resume && !previousFailed.contains(i) && await file.exists() && await file.length() > 0)
```

扩展为额外要求 `previousGroups[i].voiceId == voice`（`voice` 已在循环里算出：`speaker?.voiceId` 或 `defaultVoice`）。

空 `voiceId` 天然不等于任何非空期望音色，因此历史无记录组自动落入重烘分支，无需额外特判——这与「音色不匹配」共用同一条件，语义统一：**复用的前提是复用得对**。

**为什么优于把「重新合成」改走 `rebakeGroups(pendingGroups)`**：
- `pendingGroups` 对 `grp.voiceId.isEmpty` 显式 `continue`（见 `real_meeting_service.dart:336`），因此无记录的 11 组永远不会被它检出；改走 forceGroups 仍会漏掉这批。
- 走 `rebakeGroups` 只覆盖「当前检出的待更新组」，而未来任何「落盘音色过期但状态库未标识」的情况仍会复发。把不变量放在复用条件上，是根治而非逐案打补丁。
- 改动面最小：一个布尔条件，不动调用方、不动 pending 计算。

**替代方案 B（未采用）**：在 `bake()` 里加一个 `requireVoiceMatch: bool` 开关，由调用方按入口选择。缺点是多一个配置维度、默认值容易在将来被误设；当前只有一个语义正确的行为，不需要开关。

### Decision 2: 复用失败时的落盘与失败标记语义不变

**方案**：重烘走的是既有 `forced` 之外的普通路径——目标文件直接写、失败时写静音占位并 `failed: true`、`voiceId` 记录为本次 `voice`。这与既有行为一致，只是现在「音色不一致」也会进入这个路径。

**注意点**：普通（非 forced）重烘失败会**覆盖**旧音频为静音占位（`_audio.writeSilence`）。对音色不一致的组来说这是可接受的——旧音频本来就是错音色、复用没有价值；但需在测试里明确断言这一点，避免有人误以为「旧的好音频被静音覆盖」是回退。

**替代方案（未采用）**：让音色不一致的组改走 `forced` 语义（写临时文件、失败保留旧音频）。缺点是要额外维护一份 forced 集合的派生，且会让「重新合成」部分成功时出现新旧音色混杂的状态，更难解释。当前选择「要么新音色、要么明确失败」，与 `pendingGroups` 的期望状态判定一致。

### Decision 3: 待更新计数无需改动

**方案**：`pendingGroups` 保持现状。修复后，重烘成功即写回期望音色，`desired == grp.voiceId` 成立，待更新自然归零。空记录组仍不作为待更新展示（「不知道当时用的什么，不等于用错了」这条既有设计理由依然成立），但它们在下次烘焙时会被 Decision 1 顺带修好，不会长期滞留。

## Risks / Trade-offs

- **[Risk] 首次「重新合成」触发大规模重烘，耗时 1–2 小时且消耗 TTS 配额**
  → **Mitigation**: 这是清除历史残留的一次性成本。任务里要求 UI 进度与取消（`shouldCancel`）可用；`bake()` 已有组间取消能力，无需新增。文档与任务里明确标注该代价，避免用户误以为卡死。

- **[Risk] 重烘失败的组被静音占位覆盖，用户失去「至少还能听」的旧音频**
  → **Mitigation**: 只影响音色本就不对的组；`failed: true` 会在 UI 上显式暴露，用户可再次重试。若未来需要保留旧音频，可另开变更把「音色不一致」并入 forced 语义。

- **[Risk] 大量组同时进入重烘后，中途取消导致新旧音色混拼**
  → **Mitigation**: 取消后 `pendingGroups` 会准确报出剩余不一致的组（因为它们的落盘音色仍是旧的），用户再次点重新合成即可继续；不会出现「取消了但显示已全部完成」。

- **[Trade-off] 复用条件变严，正常的增量续跑也会多一次 `voiceId` 比较**
  → 该比较是纯内存字符串比较，成本可忽略。

## Migration Plan

无需数据迁移。部署后：
1. 打开带历史残留的真实会议 → 待更新数（若之前被 `pendingGroups` 挡住则为 0，但音频仍不对）→ 点「重新合成」。
2. 首轮会重烘所有音色不一致或无记录的组；期间可取消，已完成的组保留新音色。
3. 完成后整篇音频按说话人差异化朗读，待更新归零；此后再烘焙恢复增量续跑。

回滚：回退该条件即可，bake state 与音频文件格式均未变，新旧版本可互操作。
