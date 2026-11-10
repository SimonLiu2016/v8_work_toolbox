## Context

当前听力练习的精听抽屉 [`TranscriptDrawer`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/ui/transcript_drawer.dart) 采用纯文本平铺展示，[`ListeningPlayerController`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/services/listening_player_controller.dart) 仅支持整篇或场景级别的连续播放，缺乏对单句/意群维度的精细控制与复盘沉淀。长难句听力训练需要高效的“意群视觉拆解、即时跟读循环、以及难句归档复盘”技术支撑。

## Goals / Non-Goals

**Goals:**
- 在纯本地端完成高响应、零延迟的意群断句切分与连读弱读规则识别。
- 在播放控制器中引入单句无缝 A-B 循环（Turn Looping）、句间自动停顿（Auto-Pause）与 0.8x/1.0x 极速切替能力。
- 在精听抽屉中提供“意群排版”、“盲听遮罩”与“单句循环”无干扰交互。
- 建立长难句复盘本（Sentence Vault），实现难句摘录、标签管理与卡片流复盘。

**Non-Goals:**
- 不引入重型 NLP 外部模型或云端语法分析，所有断句切分与连读规则均基于轻量本地规则与正则库。
- 不替换底层音频解码器，完全复用既有的 `AudioPlayerListeningAdapter`。

## Decisions

### 1. 本地启发式意群切分器 (Local Sense Group Chunker)
- **决策**：在 [`transcript_parser.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/services/transcript_parser.dart) 中实现纯本地的 `SenseGroupChunker`，根据标点符号（逗号、破折号）、从句连接词（`that`, `which`, `because`, `when`, `if`, `as`, `so`）、从属短语（`in this case`, `moving forward`）将长句拆为多行 Chunk，并在每个 Chunk 尾部生成停顿指示符（`//`）。
- **备选方案**：调用 LLM 在线切分。缺点是网络耗时高、无法在文稿滚动时即时计算，且存在 token 费用；本地规则具有毫秒级零延迟与 100% 离线确定性。

### 2. 高频连读与弱读词法标注 (Liaison & Weak Form Marker)
- **决策**：内置连读规则引擎（辅音结尾 + 元音开头，如 `辅+元`，以及 IT 常见高频搭配如 `check out`, `kind of`, `sort of`, `branch off`, `push request`），结合常见弱读介词/冠词列表（`to`, `of`, `for`, `at`, `and`, `a`, `the`），在富文本渲染时生成连读弧线下划线与浅灰字体。

### 3. 播放器单句循环与极速变速状态机 (Turn Looping & Fast Speed Toggle)
- **决策**：
  - 在 `ListeningPlayerController` 中增加 `int? loopingTurnIndex`。在 `onPositionChanged` 回调中，若当前播放毫秒超过当前 turn 的 `endMs`，立即调用 `seek(turn.startMs)`，实现单句无缝死循环。
  - 增加 `toggleQuickSpeed()` 方法，在 `1.0x` 和预设慢速（默认 `0.8x`）之间瞬时无锁切换，不重载音频。

### 4. 长难句复盘本独立持久化 (SentenceVaultStore)
- **决策**：新建 `SentenceVaultStore`，在 `AppPaths.itMeetingListeningDir` 下维护 `sentence_vault.json`。数据模型 `VaultSentence` 记录会议 ID、轮次序号、发言人、文本、时间戳、所属音频路径、用户标签（`consecutive_clauses` / `liaison_blindspot` / `high_wpm`）及复习状态（已掌握/待复习）。复用已有的 JSON 原子写与自愈机制。

## Risks / Trade-offs

- **[启发式断句可能存在偶发不完全符合语法的分块]** → 保持原文可一键切换为原样纯文本排版（标准模式），用户可自由切替；标点与从句连词规则能覆盖 85% 以上的长句场景。
- **[单句循环 seek 导致的边界微杂音]** → 基于既有的 turn 起止时间戳，如果与前后话轮有微小重叠，增加 30ms 的边界缓冲，避免首尾削波。
