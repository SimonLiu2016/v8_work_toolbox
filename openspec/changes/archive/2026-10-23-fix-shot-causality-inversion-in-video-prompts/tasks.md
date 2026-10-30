## 1. 时间区间共享编译器

- [x] 1.1 在 `PromptAssembler` 中新增静态时间区间工具，输入分镜时长列表，输出 `0.0s-4.0s` 形式的区间序列（首镜从 0.0 起算，末镜结束时刻等于总时长）
- [x] 1.2 为 1.1 编写单测：3 个分镜时长 4.0/3.0/5.0 产出 `0.0s-4.0s`、`4.0s-7.0s`、`7.0s-12.0s`，末镜结束时刻等于 12.0

## 2. 分镜级提示词：段落重排与【因果时间轴】段（L2）

- [x] 2.1 调整 `buildVideoGenPrompt` 段落顺序：`【画面微动作】` 与 `【动作攻防拆解】` 前移到 `正向对白约束` 之前，对白段落后移
- [x] 2.2 在 `buildVideoGenPrompt` 中新增第 8 段 `【因果时间轴】`：按 design 决策 3 的策略分配秒数——有 `temporalEvolution` 时尝试解析显式秒数并保留原文作相位说明，无时按「动作在前、台词贴末尾」分配，台词时长取 `dialogueEstimatedSec`（无标注时按 `durationSec × 0.4` 兜底）
- [x] 2.3 内心独白（`isInnerVoice` / `voiceType == innerVoice`）不参与动作因果排序，时间轴中标注为与画面并行的画外心声
- [x] 2.4 确认 `actionZh` 未被时间戳污染（时间轴为派生段，不写回 `actionZh`），并确认 C02 对白保真、C05 地标衔接等基于 `actionZh` 的规则匹配不受影响
- [x] 2.5 编写单测：老王反应台词 + 姜七夜离去动作的 5 秒分镜，断言提示词中动作段落在对白段落之前，且时间轴中老王跳脚与台词时刻晚于姜七夜拱手/转身/牵驴区间
- [x] 2.6 编写单测：`temporalEvolution` 为空且台词无预估标注时仍产出时间轴段，台词排在本镜动作之后
- [x] 2.7 编写单测：内心独白分镜的时间轴不把独白排在动作之前，且标注为画外心声

## 3. 片段级提示词：保留对白并输出时序序列（L2）

- [x] 3.1 改造 `buildSegmentPrompt` 第 5 段：移除 `RegExp(r'(dialogue|台词|对白)\s*[:：].*')` 剥离逻辑，改为读取 `SegmentShotParts.dialogue` 输出「区间 + 动作行 + 对白行」结构，对白行带秒数标注
- [x] 3.2 区间起点由前序分镜时长累加得出，复用 1.1 的工具；首镜从 0.0 起算
- [x] 3.3 在片段提示词中注入与分镜级等强度的全员闭口守卫措辞，防止含对白后模型画面内开口
- [x] 3.4 编写单测：3 分镜片段（4.0/3.0/5.0 秒，第 2 镜含台词）产出三个区间，第 2 镜区间内同时含动作与台词，且台词未被剥离
- [x] 3.5 编写单测：第 1 镜甲角色动作、第 2 镜乙角色台词时，乙台词所在区间起始秒数大于甲动作所在区间起始秒数
- [x] 3.6 编写单测：片段提示词含全员闭口守卫措辞

## 4. AI 视频提示词重写补第 5 条铁律（L2）

- [x] 4.1 在 `_promptVideoPromptRewrite` 的四大铁律后新增「因果时序唯一性」：反应性台词必须晚于其触发动作，重写不得将台词前移；同一镜内不同主体的动作不得合并为同时发生
- [x] 4.2 确认 `StudioPresetStore` 自定义模板路径下该约束仍生效；完全替换时记录其依赖 C11 兜底
- [x] 4.3 编写单测：断言默认模板含「因果时序」相关约束文案

## 5. 拆镜模板新增反应独立成镜约束（L1）

- [x] 5.1 在 `_promptScriptBreakdown5D` 增加约束：某角色台词为另一角色动作的反应时优先拆到独立分镜；同镜共处时必须在 `temporalEvolution` 声明触发相位早于反应相位
- [x] 5.2 确认该约束不破坏既有「剧情保真锁」——拆分不得改变剧情事件的内容、归属或顺序
- [x] 5.3 编写单测：断言 5D 模板含反应独立成镜约束文案，且剧情保真锁文案仍存在

## 6. 质检 C11 因果倒置规则（L3）

- [x] 6.1 在 `DirectorValidationEngine` 新增 C11 规则，判定条件按 design 决策 5：对白非空且非内心独白/旁白 + `extractSpeakerName` 说话人 ≠ `actionZh` 中首个出现的角色名 + `temporalEvolution` 为空，严重级 WARNING
- [x] 6.2 规则 message 说明因果倒置风险，suggestion 提示拆分反应镜头或补充相位声明
- [x] 6.3 编写单测：老王说话 + 姜七夜动作 + 无 `temporalEvolution` 的分镜报 C11 WARNING
- [x] 6.4 编写单测：同分镜但 `temporalEvolution` 非空时不报 C11
- [x] 6.5 编写单测：内心独白分镜不触发 C11
- [x] 6.6 确认新增规则不影响既有 C01~C10 的既有断言与 10 分制评分基线

## 7. 台词音频按分镜游标落位（L4）

- [x] 7.1 修改 `_concatAudio`：传入 `targetDurations` 时改用 `filter_complex` 逐段 `apad` + `atrim` 归一化到目标时长后 `concatn`，不再依赖 concat demuxer 流拷贝
- [x] 7.2 保留「滤镜拼接失败时退回第一段」的回退路径，并清理临时 list 文件
- [x] 7.3 `ComposeRequest` 增加分镜目标时长序列字段，`delivery_panel._compose` 按 `episode.shots` 顺序填入（与 `_timelineClips` 同一套展开规则）
- [x] 7.4 `compose` 与 `_mixAudio` 两个调用点均传入 `targetDurations`
- [x] 7.5 编写单测：传入 `targetDurations` 后生成的 FFmpeg 参数含 `apad` 与 `atrim`
- [x] 7.6 实测一集（含 3 段以上台词）合成耗时与音画对齐，确认字幕/音频/画面三方游标一致

## 8. 回归与文档

- [x] 8.1 跑 `test/dialogue_tts_speaker_and_character_drift_test.dart`、`test/ai_video_studio_cinematic_director_test.dart`、`test/shot_production_modes_and_cinematic_quality_test.dart`，更新受段落顺序影响的断言
- [x] 8.2 确认 `test/ai_video_studio_cinematic_director_test.dart` 中改动前已失败的红测试 `心声独白` 保持原状，不借机修改
- [x] 8.3 跑全量 `flutter test`，确认无新增失败
- [x] 8.4 归档前 `openspec validate fix-shot-causality-inversion-in-video-prompts --strict` 通过
