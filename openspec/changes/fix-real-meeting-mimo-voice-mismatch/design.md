## Context

真实会议的「说话人与音色」链路是 MiMo 盲区（详见 proposal.md - Why）。生词本链路在 v0.2.0 已接入 MiMo 探测，但真实会议的 UI、说话人解析、烘焙三处仍直接使用 `VoicePool`（StepFun）音色 id，而当前 TTS 槽位绑定 MiMo。由于 `VoicePool` id 集合与 `mimoSupportedVoiceIds` 零交集，`OpenAiTtsEngine.adaptVoiceForProvider(isMimo: true)` 把所有非 MiMo id 静默归一为 `mimo_default`，导致改音色后每个角色都是同一个女声默认音色。

已确认的代码事实：
- `real_meeting_views.dart:_buildSpeakerRow` 与 `it_meeting_listening_page.dart`「我的身份」对话框只列 `VoicePool.all`，不探测 MiMo。
- `speaker_profile_resolver.dart` 散列兜底走 `RoleVoiceMap.voiceFor` → `VoicePool`，产出 StepFun id。
- `real_meeting_baker.dart:154` 直接取 `speaker.voiceId` 传入 `customVoiceId`；`rehearsal_baker.dart:392` 同理（`RehearsalVoices` 硬编码 5 个 StepFun 男声 id）。
- 生词本已有可复用的探测模式：`vocabulary_study_store._resolveDefaultVoiceId` / `_resolveDefaultStyle`、`vocabulary_browser_dialog._buildVoiceAndStyleBar`，两处各写了一遍相同的「遍历 `slotBindings['tts']` → 判定 `isMimo`」逻辑。
- `real_meeting_panel.dart` 无人 import（死代码），不改。

## Goals / Non-Goals

**Goals**
- 真实会议与生词本共用同一套「当前 TTS 槽位 → 音色候选 / 默认音色 / 默认风格指令」的探测结果，消除第三份重复。
- 在 MiMo 下，真实会议的音色下拉、「我的身份」、散列兜底、`MyIdentity.defaultVoiceId`、`RehearsalVoices` 全部产出/展示合法 MiMo 音色 id，且烘焙透传 MiMo 风格指令。
- 非 MiMo 下行为完全不变（仍用 `VoicePool`）。

**Non-Goals**
- 不改 `OpenAiTtsEngine` 的 `adaptVoiceForProvider` 防御逻辑本身（它兜底 `mimo_default` 是合理的最后防线，问题在于上游给了它无法识别的 id）。
- 不改 `real_meeting_panel.dart`（死代码）。
- 不做「按 MiMo 音色重新映射既有已合成音频」——已合成音频保持原音色，只有重新合成后生效（与现有「改音色 → 待重新合成」语义一致）。

## Decisions

### D1: 提炼单一共享 MiMo 探测 helper，不新增依赖

生词本两处重复了「遍历 `AiConfigStore.instance.slotBindings['tts']` 取首个启用供应商 → 用 `OpenAiTtsEngine.isMimoModel` 判定」。新建一个纯查询类型（如 `MimoTtsContext` / `tts_binding_probe.dart`），暴露三件事：

```dart
class TtsBindingProbe {
  static bool isMimo();                    // 当前 TTS 槽位是否绑定 MiMo
  static List<TtsVoiceOption> voiceOptions(); // MiMo → defaultMimoVoices，否则 VoicePool 映射
  static String defaultVoiceId();           // MiMo → 'mimo_default'，否则 VoicePool.zhixingjiejie.id
  static String defaultStyle();             // MiMo → 保守默认风格指令，否则 ''
}
```

**为什么**：三个调用方（生词本、真实会议 UI、说话人解析）都需要同一答案；若各写一遍，将来「MiMo 判定规则变了」要改三处。把判定收敛到 `OpenAiTtsEngine.isMimoModel` 一处调用，其余都是它的投影。

**替代方案考虑**：
- 让 `OpenAiTtsEngine` 暴露「当前绑定」——违背其职责（它是合成引擎，不是配置探测），且会引入对 `AiConfigStore` 的循环依赖。
- 直接在各调用点内联 `isMimoModel`——正是当前生词本的重复做法，不采纳。

### D2: 说话人散列兜底在 MiMo 下从 MiMo 音色池散列，而非吞成默认

`SpeakerProfileResolver.resolve` 第 3 步的 `RoleVoiceMap.voiceFor(fallback, '')` 在 MiMo 下必须产出 MiMo 合法 id。方案：散列源从 `VoicePool.all` 切换为「当前音色池」（MiMo → `TtsVoiceOption.defaultMimoVoices` 的 id 列表，否则 `VoicePool.all`）。散列函数本身（`RoleVoiceMap._fallbackFor` 的 `hash % length`）不变，只换候选列表，保证「同一槽位同一音色」的纯函数性质不破。

**为什么换池而非映射**：把 StepFun id 映射到 MiMo id 需要一个 9→9 的对应表，且语义（男/女、F0）在两个命名空间里无法对齐（MiMo 音色没有 F0 实测值）；直接在 MiMo 池内散列更简单，且天然保证「散列结果 ∈ MiMo 支持列表」，无需再经 `adaptVoiceForProvider` 兜底。

**边界**：`MyIdentity.defaultVoiceId = 'boyinnansheng'` 在 MiMo 下不合法。方案是让 `loadMyIdentity`/解析层在 MiMo 下回落到 `mimo_default`（或 MiMo 池首个），而非改常量——常量本身保持 StepFun 语义，供非 MiMo 使用。同样，`RehearsalVoices` 的 5 个男声 id 在 MiMo 下映射到 5 个 MiMo 音色（可用既有 id 的确定性映射，如按固定顺序取 MiMo 池 5 个），确保「全部为男声」的语义在 MiMo 下有近似对应。

### D3: 真实会议烘焙透传 MiMo 风格指令

`RealMeetingBaker._synthesize` 与 `RehearsalBaker._synthesize` 目前构造 `TtsSynthesisConfig(mode: customAi, useSystemAiConfig: true).copyWith(customVoiceId: voice)`，`styleInstruction` 缺省为 `''`。改为在 MiMo 下注入 `styleInstruction: TtsBindingProbe.defaultStyle()`。

**为什么**：MiMo 的语速/情感完全靠 `user` 消息里的自然语言指令表达（`_buildMimoStyleInstruction`），缺省空串意味着合成结果用裸默认——正是用户感知「语气平淡」的一部分。与生词本已实现的行为对齐。

### D4: 真实会议音色 UI 复用探测结果

`real_meeting_views.dart` 的说话人音色下拉与「我的身份」对话框把 `VoicePool.all` 替换为 `TtsBindingProbe.voiceOptions()`；非 MiMo 时映射结果与 `VoicePool.all` 等价（用 `TtsVoiceOption` 包装），行为不变。散列兜底项（`voiceId.isEmpty ? null : voiceId`）与 `inPool` 检查同样改为按「当前池」判断，避免「MiMo 下却显示 StepFun id」。

## Risks / Trade-offs

- **[散列兜底音色变化] → [缓解]**：MiMo 下散列候选从 StepFun 池换成 MiMo 池，已合成但未显式设音色的槽位，重新合成后声音可能变化。缓解：这是本次修复的预期目的（此前它们全被吞成 `mimo_default`），且只影响「未显式设定」的槽位；显式设定的不受影响。
- **[`MyIdentity.defaultVoiceId` 语义分叉] → [缓解]**：常量保持 `boyinnansheng`，仅解析/加载层在 MiMo 下回落 `mimo_default`。缓解：回落点收敛在 `TtsBindingProbe.defaultVoiceId()`，避免散落在多处。
- **[风格指令可能影响听感] → [缓解]**：MiMo 风格指令是保守默认（`自然、清晰、语速适中、略带情感`），与生词本一致；用户可在后续版本按需编辑。若个别用户嫌吵，可回落为空串，但当前目标是「与生词本对齐」。
- **[探测结果依赖 `AiConfigStore` 时序] → [缓解]**：探测是同步读全局单例，须在 UI 构建与烘焙启动时都已加载配置。真实会议 UI 已有 `AiConfigStore` 使用先例（生词本同模式），风险低。

## Migration Plan

无数据迁移。既有已合成音频保持原样；改音色或点「重新合成」后按新逻辑生效。纯行为修复，可回滚为 git revert。

## Open Questions

无（散列兜底在 MiMo 下的「同一槽位同一音色」纯函数性质由 D2 保证，无需额外决策）。
