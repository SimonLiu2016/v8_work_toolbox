## Why

在听力练习中，进阶瓶颈往往“不是单词听不懂，而是句子一长，信息堆叠在一起，大脑工作记忆跟不上、记不住、拆解不过来”。当前听力练习仅提供整句线性播放与纯文本展示，容易使用户退化为“逐词心译”或“眼睛看懂代替耳朵听懂”。必须重塑听力认知训练形态，提供从“盲听抓主干”到“意群切片分析”再到“影子跟读与难句复盘”的完整训练闭环。

## What Changes

- **意群分块排版与停顿标记 (Sense Group Chunking & Pause Badges)**：在精听文稿中，长句按语法意群（主干从句、介词短语等）结构化换行排版，并显式标注自然呼吸停顿点（`//`），彻底改变整块密集文本的视觉压迫。
- **高频连读与弱读视觉指示 (Connected Speech Notation)**：识别常见连读（如辅音接元音 `branch‿off`）并以弧线连接；弱读功能词（如 `to`, `of`, `and`）视觉轻化呈现，打破“认识单词但连读后认不出”的听觉盲区。
- **影子跟读专用控制 (Shadowing Controls: Turn Loop & Instant Speed Toggle)**：
  - **单句 / 轮次 A-B 死循环**：长句跟不上时一键单句循环回放，无需反复拖动进度条；
  - **0.8x / 1.0x 极速切换**：一键或快捷键（如 `Tab`）在慢速与原速间瞬间切替，先听清连读发音细节，再原速感受语音流；
  - **句间自动停顿（Auto-Pause）**：支持播完单句自动暂停留白，给大脑消化与复述时间。
- **盲听遮罩模式 (Blind Listen Masking)**：精听抽屉支持一键文本遮罩模式，强制屏蔽视觉代偿，强化纯听觉“抓主干（Who + Action + Core Info）”能力。
- **长难句复盘本 (Sentence Vault)**：
  - 话轮右侧新增“⭐ 摘录为难句”，支持标记难点原因（连读盲区、从句过长、语速过快）；
  - 在生词本旁提供「难句闪卡库」，支持集中慢放抽查、句式节奏熟悉与掌握度管理。

## Capabilities

### Modified Capabilities
- `it-meeting-listening-tool`: 增加意群断句排版、连读弱读图谱指示、单句循环影子跟读交互、盲听主干遮罩、以及长难句复盘本管理能力。

## Impact

- **Affected Code**:
  - `lib/tools/it_meeting_listening/services/transcript_parser.dart` (意群断句与连读规则分析)
  - `lib/tools/it_meeting_listening/services/term_highlighter.dart` & `term_widgets` (意群块与连读弧线渲染)
  - `lib/tools/it_meeting_listening/services/listening_player_controller.dart` (单句循环 A-B Loop、句间自动暂停、0.8x/1.0x 极速切替)
  - `lib/tools/it_meeting_listening/ui/workspace_player_bar.dart` & `transcript_drawer.dart` (盲听遮罩开关、单句循环按钮、难句摘录入口、意群视图切换)
  - `lib/tools/it_meeting_listening/services/sentence_vault_store.dart` (新服务：难句持久化与掌握度追踪)
  - `lib/tools/it_meeting_listening/ui/sentence_vault_dialog.dart` (难句闪卡复盘界面)
- **Dependencies & APIs**: 纯前端视觉与播放控制器交互增强，不引入新的第三方重型依赖。
