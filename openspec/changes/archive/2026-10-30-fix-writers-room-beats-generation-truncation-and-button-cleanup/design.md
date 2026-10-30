## Context

见 proposal.md 与 spec.md。在当前《编辑研讨室》（WritersRoomDialog）中，导入小说后默认/测算的目标集数常为 60~100 集（默认 80 集）。
目前调用 `AiConstraintEngine.planWritersRoomSeasonBeats` 时，系统在用户提示词与系统提示词中同时要求 AI“必须输出严格等于 80 集且包含所有 7 字段的详细 JSON，严禁偷懒截断”。这导致单次输出 Token 远超主流模型（DeepSeek、GPT-4o、Qwen）单次 4096 的上限，导致输出截断、JSON 不合法并触发 `ConstraintParseError`。
同时，捕获异常后界面仅依靠底部 SnackBar 提示，空状态没有任何错误呈现，加之小节标题与规格栏均有“重新规划本季大纲”同名按钮，造成交互混乱与静默失效。

## Goals / Non-Goals

**Goals:**
- 消除小节标题栏冗余的“重新规划”按钮，保持控制栏到列表的自上而下单向心智模型。
- 解决 60~120 集等长篇大集数规划时必现的 LLM 单次输出 Token 截断崩溃问题，确保大模型单次在 4096 Tokens 限制内安全完成合法 JSON 输出。
- 完善空状态错误可视化：在空状态卡片中就地呈现异常原因与【立即重试】按钮，彻底消除静默失败假象。

**Non-Goals:**
- 不重写分镜与片段制作阶段的逻辑（仅作用于编辑研讨室宏观大纲规划层）。
- 不破坏现有小集数（12、24 集）的原生直接生成支持。

## Decisions

### 1. 按钮层级重构与清理
- **方案选择**：彻底移除 `🎬 全季分集规划与断章钩子` 小节标题右侧的 `TextButton.icon('重新规划本季大纲')`。
- **保留项**：
  1. 规格栏（Row 2）右侧常驻的 `ElevatedButton.icon('重新规划本季大纲')`，明确作为参数驱动的主操作；
  2. 列表空状态卡片中的大尺寸居中引导按钮 `[🎬 立即规划第 X 季分集大纲 (共 Y 集)]`。
- **替代方案考虑**：曾考虑在小节标题保留一个仅有图标的小刷新按钮，但在紧邻上一行已有主按钮的情况下仍显多余，且容易引起到底刷新哪个部分的歧义。彻底移除能实现视觉与语义的完全纯净。

### 2. 长篇大纲生成策略：节拍骨架生成 + 篇章感知平滑扩充
- **根因分析**：
  80 集 × 7 个字段（标题、篇章、40字冲突、30字钩子、角色数组等）≈ 8,000~12,000 Tokens，任何商业 LLM 的单次 completion output 均无法承载。
- **解决方案**：
  - 更新 `_promptWritersRoomSeasonBeats` 与 `AiConstraintEngine.planWritersRoomSeasonBeats`：
    当 `episodeCount > 24` 时，引导模型输出 4~6 大宏观大幕（`macro_arcs`）以及覆盖全季关键节点的 **12~16 集高能冲突节拍骨架**；
  - `_SchemaValidators.writersRoomSeasonBeats` 已经内置了按篇章弧光分布的映射平滑插值机制（`((targetIdx - 1) * (rawEps.length - 1) / (targetEpisodeCount - 1)).round()`），会自动扩充为与 `targetEpisodeCount` 完全一致的 80 集完整分集列表。
  - 容错保底：在 `_SchemaValidators.writersRoomSeasonBeats` 中，若模型返回了 `macro_arcs` 且即使模型漏填 `episodes`，也自动根据 `macro_arcs` 补齐 80 集合格节拍，不再返回 `null` 抛出异常，提供双重韧性保险。

### 3. 空状态就地错误反馈机制
- 在 `_WritersRoomDialogState` 中引入 `String? _beatsPlanError` 状态变量；
- 执行 `_planSeasonBeats()` 时：
  - 开始前清空 `_beatsPlanError = null`；
  - 成功时更新缓存并保持 `_beatsPlanError = null`；
  - `catch (e)` 捕获异常后，将友好的错误诊断信息记录入 `_beatsPlanError`；
- `_buildEmptyBeatsCard()` 重构：
  - 若 `_beatsPlanError != null`，显示警示状态样式容器，展示错误摘要（如模型超时、服务异常等），并将主按钮文字切换为 `[重新尝试规划第 X 季大纲]`；
  - 避免仅靠 SnackBar 容易被弹窗层遮盖或 4 秒后消失的问题。

## Risks / Trade-offs

- **[Risk]** 插值生成的 80 集中间过渡集可能会有节拍标题后缀（如 `(节拍 X)`）。
  - **Mitigation**: 插值算法结合 `macro_arcs` 动态推断每个过渡集所属篇章的大幕冲突与危机，并保留用户后续通过右侧“AI 编剧研讨窗口”逐集精修微调的能力。
- **[Risk]** 用户若设定了较小的集数（如 12、24 集）。
  - **Mitigation**: Prompt 中设置阈值：若集数 $\le 24$，模型依然直接全量生成每个单集；仅当集数 $> 24$ 时启用节拍骨架策略，两全其美。
