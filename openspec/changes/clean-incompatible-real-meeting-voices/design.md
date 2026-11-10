## Context

在真实会议的架构中，说话人音色经历四层流转：
```
UI 选择 / 历史文件 (settings/<id>.json)
  ↓
RealMeetingService.resolveSpeakers & SpeakerProfileResolver.resolveAll
  ↓
RealMeetingBaker.bake (逐组送入 TtsEngine.synthesize)
  ↓
烘焙状态落盘 (audio/<id>.json - TurnGroupAudio.voiceId) & pendingGroups 对比
```
目前 `TtsBindingProbe.voiceOptions()` 能够感知当前 TTS 槽位是 MiMo 还是 StepFun/OpenAI 并输出对应有效音色。然而，`SpeakerSetting.voiceId` 是一个纯字符串，一旦用户在 StepFun 下配置了 `shenchennanyin`，随后系统 TTS 槽位切换为 MiMo，该旧音色仍保存在磁盘 JSON 中。在 `SpeakerProfileResolver.resolve` 中直接取用了 `setting.voiceId`，既未校验其是否属于当前供应商，也未清除它。最终底层 `adaptVoiceForProvider` 强制将其降级为 `mimo_default`，引发“所有角色声音单一”；同时因为磁盘 `voiceId` 与期望状态脱节，引发“待更新 9 组反复出现且无法消除”。

详见 `proposal.md` 与 `specs/it-meeting-listening-tool/spec.md`。

## Goals / Non-Goals

**Goals:**
- 提供跨供应商的音色有效性检测与自动清洗：当加载真实会议时，自动识别并清理不属于当前 TTS 供应商的失效 `voiceId`，平滑回退为当前供应商下的散列兜底音色，并自动持久化清洗结果。
- 保证重新合成后待更新组数（Pending Groups）彻底归零：落盘的 `TurnGroupAudio.voiceId` 与当前有效期望音色严格对齐。
- UI 不再误导性展示跨厂商失效的“自动项”，确保用户在下拉菜单中始终看到并选择当前供应商真正支持的音色。
- 「我的身份」（MyIdentity）支持跨厂商双向校验，防止「我」的角色音色在切换供应商后失效。

**Non-Goals:**
- 不改变底层各个 AI 厂商 TTS 引擎（如 MiMo / Qwen / StepFun）的调用协议。
- 不影响真实会议原稿文件（`meetings/<id>.json`）及转写文本。

## Decisions

### Decision 1: 在 `SpeakerProfileResolver` 引入有效音色集合校验（Valid Voice Pool Sanitization）
- **方案**：
  在 `SpeakerProfileResolver.resolve` 与 `resolveAll` 中，接收 `validVoiceIds: Set<String>?`（取自 `TtsBindingProbe.voiceOptions().map((v) => v.id).toSet()`）。
  - 若 `setting.voiceId` 非空且不在 `validVoiceIds` 中，判定为**不兼容的跨供应商历史残留**，将其视为未配置（空字符串），从而进入统一的散列兜底逻辑。
  - 散列兜底保证为当前供应商的合法音色池，不同说话人大概率分配不同音色，立刻恢复“听声辨人”能力。
- **替代方案考虑**：
  - *替代案 A：在底层 TtsEngine 做跨厂商音色模糊映射（例如把 StepFun 的男声映射成 MiMo 的男声）*。
    - 缺点：各厂商音色风格、语言、音高差异巨大，映射规则脆弱且随着模型迭代容易再次失效；直接重置为散列兜底能保证干净统一。

### Decision 2: `RealMeetingService.resolveSpeakers` 触发自愈回写持久化
- **方案**：
  在 `RealMeetingService.resolveSpeakers(meeting)` 读取 `settings` 时，如果检测到有任何槽位的 `voiceId` 属于非法跨厂商音色：
  1. 生成清洗后的 `cleanedSettings`（将非法音色槽位重置为合法值或清除其旧 `voiceId`）；
  2. 异步调用 `store.saveSettings(meeting.id, cleanedSettings)` 自动纠正磁盘文件；
  3. 这样后续无论在 UI 渲染、`pendingGroups` 判定还是 `bake` 合成中，读取到的均是纯净的合法设定，杜绝脏数据反复引发不一致。

### Decision 3: UI 消除伪“自动项”，与当前供应商音色池严格闭合
- **方案**：
  在 `real_meeting_views.dart`（`_SpeakerRow`）中：
  - 只有当 `voiceId` 为空时，下拉框展示散列兜底音色；
  - 移除 `if (!inPool && voiceId.isNotEmpty) DropdownMenuItem(value: voiceId, child: Text('$voiceId（自动）'))` 这类保留脏数据的兼容逻辑；
  - 由于经过 Decision 1/2 清洗后，`resolved.voiceId` 必然落在当前 `voiceOptions` 内，下拉框将自然显示对应的合法项。

### Decision 4: 烘焙状态与 Pending Groups 一致性保证
- **方案**：
  - 在 `RealMeetingBaker.bake` 中合成成功时，写入 `groupAudios[i]` 的 `voiceId` 必须是已清洗校验的 `speaker.voiceId`；
  - 在 `RealMeetingBaker.rebuildAudio` 中派生 Clip 与 `MeetingBakeState` 时，保留该有效 `voiceId`；
  - `pendingGroups` 比较 `desired = speakers[slotId]?.voiceId` 与 `grp.voiceId` 时，由于两端都使用统一的清洗后有效音色，重新合成后 `desired == grp.voiceId` 必定成立，待更新组数立即归零。

## Risks / Trade-offs

- **[Risk] 用户在旧供应商下精心挑选的特定音色在切换供应商后被重置**
  → **Mitigation**: 这是必然且合理的折衷。因为 StepFun 的 `shenchennanyin` 在 MiMo 下根本不存在，强行保留只会导致被 TTS 降级为默认女声。重置后散列兜底会按性别分配 MiMo 音色，且用户随时可以在下拉框中重新为该角色挑选 MiMo 音色。
- **[Risk] 首次加载带有脏数据的会议时触发额外一次文件写（自愈回写）**
  → **Mitigation**: 使用已有的原子写机制 `_writeAtomic`，开销微秒级，且写完后持久化生效，下次打开即为干净数据。
