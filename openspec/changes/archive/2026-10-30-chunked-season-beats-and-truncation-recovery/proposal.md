## Why

在“编剧研讨室”中，当用户基于长篇小说规划全季大纲（通常目标规模为 60 ~ 120 集，如 60 集）时，系统提示词要求大模型一次性推演并输出全量分集条目。由于每集包含篇章、标题、核心冲突、出场角色、断章留钩与时长等 7 项结构化字段，单集消耗约 140~160 Tokens。单次全量生成累积输出在第 26~30 集处必然耗尽主流模型（如 Agnes-cn/agnes-2.5-flash）的 4096 Tokens 物理输出上限（`finish_reason: "length"`），导致返回的 JSON 字符串被腰斩截断。解析引擎由于缺少闭合括号而解析失败，重试机制又将上一次 4000 Token 截断残片注入导致后续重试再次截断，最终引发持续报错崩溃（`ConstraintParseError`）。

为了既彻底消除 4096 Token 物理截断崩溃，又确保每一集都是根据原著自然推演的高品质独立剧情（坚决不搞假机械克隆），必须将全季规划重构为两阶段按宏观大幕分段规划，并在底层提供截断自动闭合容错与自愈能力。

## What Changes

- **分集大纲规划抗截断两阶段重构 (AiConstraintEngine)**：
  - **阶段一（宏观大幕规划）**：先推演全季 3~6 个宏观篇章大幕（`macro_arcs`，覆盖集数范围、核心对抗与转折爆点，仅需约 500 Tokens，100% 极速稳定）；
  - **阶段二（篇章内分批细化）**：针对大集数（目标集数 > 20 集），按大幕范围（或每批 12~16 集）分批推演具体独立分集（每批约 1800~2200 Tokens，永远处于 4096 安全线内），最后无缝汇总；对于小集数（≤ 20 集）保持单次高能直接生成。
- **JSON 数组截断安全自愈容错 (parseJsonLoose)**：
  - 增强松散 JSON 解析器对末尾非正常截断的容错自愈能力。当大模型意外由于输出 Token 超限被截断在 `episodes` 数组中途时，自动丢弃最后一个不完整对象并安全补齐 `]}`，将前面已成功生成的完整分集抢救出栈，杜绝语法抛错崩溃。
- **研讨室分批进度与阶段状态显化 (WritersRoomDialog)**：
  - 在大纲推演时展示细分进度（如“正在规划全季宏观大幕...” -> “正在推演第 1 幕 (1~15 集)...” -> “正在推演第 2 幕 (16~30 集)...”），赋予用户清晰的流式掌控感与确定性。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 增加编剧研讨室大集数规划的两阶段按大幕分批推演规范与 JSON 截断容错自愈要求，保证 60~120 集规模下剧情独立且零截断失败。

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 重构 `planWritersRoomSeasonBeats` 为两阶段大幕分批管线，增强 `parseJsonLoose` 数组截断安全闭合算法；
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`: 支持分阶段进度状态反馈；
- `test/writers_room_materialization_and_dynamic_beats_test.dart` / `test/ai_constraint_engine_test.dart`: 补充大集数分段推演与截断自愈单元测试。
