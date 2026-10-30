## Why

分镜看板生成的视频出现反逻辑时序：一镜之内「姜七夜拱手一拜，转身牵驴走出衙门」与「老王在背后跳脚喝骂」本应动作先、反应后，实际生成却变成老王先说台词、姜七夜再演动作。

根因不在视频模型，而在我们把一段有因果的剧本压成了无时序的平铺文本：三条生成路径中，分镜级提示词把台词放在动作之前且不标注先后；片段级提示词主动用正则把对白从动作描述里剥掉，整段提示词一句台词都没有，动作之间只用「，」平接；唯一写对了时间区间语法的 `SeedanceTaskCompiler` 没有任何生成调用方。同时，AI 拆镜已经产出的 `temporalEvolution`（本镜内时间相位）与可从台词解析的 `dialogueEstimatedSec`（台词落点秒数）从未进入任何提示词，质检引擎 C01~C10 也没有一条校验因果先后。合成侧 `_concatAudio` 的 `targetDurations` 参数从未被传入，音频轨整体前移，进一步放大错位。

## What Changes

- **分镜级视频提示词段落重排**：`buildVideoGenPrompt` 将「画面微动作」与「攻防因果」段落前移到「正向对白约束」之前，使因果链在执行顺序上优先于台词；动作段落显式标注本镜内的先后顺序。
- **新增【因果时间轴】段**：`buildVideoGenPrompt` 依据 `directorDecisions.temporalEvolution`、`dialogueEstimatedSec`（或台词标注的预估秒数）与 `durationSec` 编译一段显式时间区间文本，形如 `0.0s 姜七夜拱手一拜 → 1.5s 转身牵驴向门口 → 2.8s 老王在背后跳脚喝骂（台词）`。这是本次改动的核心。
- **片段级提示词保留对白并改为时序序列**：`buildSegmentPrompt` 停止从 `actionZh` 中剥离 `dialogue`，改为按分镜顺序输出带 `[起始s - 结束s]` 时间区间的「动作 + 对白」交替序列；区间起点由前序分镜时长累加得出。沿用 `SeedanceTaskCompiler` 已有的时间区间语法，而非新造格式。
- **AI 视频提示词重写补第 5 条铁律**：`_promptVideoPromptRewrite` 增加「因果时序唯一性」约束——反应性台词 SHALL 出现在触发动作之后，重写时不得将台词前移至其触发动作之前；同时禁止把同一镜内的多个主体的动作合并为同时发生。
- **质检新增 C11 因果倒置规则**：当分镜台词的说话人（`extractSpeakerName` 解析）不是本镜首个动作的执行者，且本镜既无 `temporalEvolution` 时序标注、也未把该反应台词拆至独立分镜时，`DirectorValidationEngine` 报 WARNING，提示用户拆分反应镜头或补充时序标注。此规则在消耗生成额度前拦截。
- **台词音频按分镜游标落位**：`compose` 与 `_mixAudio` 向 `_concatAudio` 传入 `targetDurations`，使每段台词音频 `apad` + `atrim` 到对应分镜时长，修复音频/字幕/画面三方错位这一放大倒置的次生问题。
- **拆镜模板新增反应独立成镜约束**：`_promptScriptBreakdown5D` 增加规则——当某角色的台词是对另一角色动作的反应时，该台词 SHALL 优先分配到独立分镜；确需同镜共处时 SHALL 在 `temporalEvolution` 中显式声明先后相位。这是治本项，从源头减少单镜双主体因果。

## Capabilities

### New Capabilities

- `ai-video-studio/shot-causality-ordering`: 定义单镜与片段内动作—台词因果时序的编译契约，包括【因果时间轴】段的构成规则、时间区间语法的唯一格式、以及反应性台词的成镜约束。

### Modified Capabilities

- `ai-video-studio/shot-production`: 分镜级视频生成提示词的段落顺序与内容要求发生变化（动作因果链前置、台词后置、新增时间轴段）；新增分镜级提示词的因果时序要求场景。
- `ai-video-studio/segment-production`: 「片段提示词组装」要求发生变化——片段提示词 SHALL 保留对白并输出带时间区间的动作/对白交替序列，而非剥离对白后平接动作。
- `ai-video-studio/script-workshop`: 「结构化分镜拆解」新增反应独立成镜约束，拆镜结果的 `temporalEvolution` 从可选说明升级为因果时序的强制承载字段（仅在同镜含反应台词时强制）。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/prompt_assembler.dart` — `buildVideoGenPrompt` 段落重排与新增【因果时间轴】段；`buildSegmentPrompt` 时序序列化；`SegmentShotParts.dialogue` 由未消费字段转为输入。
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` — `_promptVideoPromptRewrite` 新增第 5 条铁律；`_promptScriptBreakdown5D` 新增反应独立成镜约束。
- `lib/tools/ai_video_studio/services/director_validation_engine.dart` — 新增 C11 规则。
- `lib/tools/ai_video_studio/services/ffmpeg_composer.dart` — `compose` / `_mixAudio` 向 `_concatAudio` 传 `targetDurations` 并实现 `apad`+`atrim`。
- `lib/tools/ai_video_studio/ui/delivery_panel.dart` — `_compose` 需向 `ComposeRequest` 提供分镜时长序列。

**依赖的既有资产**
- `StudioShot.dialogueEstimatedSec` 与 `DirectorDecisions.temporalEvolution` 由「已生产未消费」转入生成链路；`temporalEvolution` 进入提示词后可被 `StudioPresetStore` 的自定义模板覆盖，需确认自定义路径不被绕过。

**风险**
- 分镜级提示词段落顺序变化会影响断言旧顺序的测试（已知 `test/ai_video_studio_cinematic_director_test.dart` 有一条已在改动前失败的红测试 `心声独白`，与本次无关但同文件）。
- 片段提示词从「无对白」变为「含对白」，视频模型可能开始尝试画面内开口。需在片段提示词中保留既有的闭口守卫措辞，并新增测试锁定。
- `_concatAudio` 改用滤镜后，concat demuxer 的失败回退路径（退回第一段）需保持可用。
