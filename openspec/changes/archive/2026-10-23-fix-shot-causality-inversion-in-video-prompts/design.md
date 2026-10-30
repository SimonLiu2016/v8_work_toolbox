## Context

动机见 proposal.md 的 Why；行为契约见本次 change 的四份 spec delta。这里只记录实现层面的关键约束。

当前三条生成路径的提示词组装入口与缺口：

| 路径 | 入口 | 现状 |
|---|---|---|
| 分镜级 | `PromptAssembler.buildVideoGenPrompt`（prompt_assembler.dart:922） | 台词段落在最前，动作段落无先后标注 |
| 片段级 | `PromptAssembler.buildSegmentPrompt`（prompt_assembler.dart:1466） | 正则把 `dialogue` 从 `actionZh` 剥离，整段无对白 |
| AI 重写 | `AiConstraintEngine._promptVideoPromptRewrite`（ai_constraint_engine.dart:1927） | 四条铁律，无因果时序约束 |

已有但未消费的资产：`StudioShot.dialogueEstimatedSec`（studio_models.dart:2842）、`DirectorDecisions.temporalEvolution`、`PromptAssembler.extractSpeakerName`、`SegmentShotParts.dialogue`（prompt_assembler.dart:2681）。

时间区间格式的既有正确实现：`SeedanceTaskCompiler.compileSegment`（prompt_assembler.dart:2742），输出 `[0.0s - 3.0s] 镜号 N`，但生成链路无调用方。

音轨侧：`_concatAudio` 的 `targetDurations` 参数（ffmpeg_composer.dart:663）从未被调用方传入。

## Goals / Non-Goals

**Goals:**

- 让三条路径都输出带显式秒数区间的动作—台词序列，格式统一。
- 复用 `temporalEvolution` 与 `dialogueEstimatedSec`，不新增数据字段。
- 在不改 `StudioShot` / `DirectorDecisions` 序列化结构的前提下完成全部改动。
- 让 C11 能在提交云端生成前拦截因果倒置。

**Non-Goals:**

- 不新增 `StudioShot` 字段，不改 `storyboard.json` 结构，不做数据迁移。
- 不改 TTS 引擎、不改 `cleanDialogueForSpeech` / `extractSpeakerName` 的既有契约。
- 不改造 `SeedanceTaskCompiler` 本体，也不把它接到生成链路（它的输出面向手动复制场景，与生成链路对提示词密度的要求不同）。
- 不解决"视频模型仍然不遵守时序"——那是模型能力问题，本设计只保证输入正确。

## Decisions

### 1. 时间区间语法的唯一来源：抽出一个共享编译器，而非复制 SeedanceTaskCompiler

把 `[0.0s - 3.0s]` 的区间计算抽成 `PromptAssembler` 内的静态工具，分镜级与片段级都调它。

**为什么不直接复用 `SeedanceTaskCompiler.compileSegment`**：它输出的是完整执行稿（画风、主体定义、Handoff），生成链路只需要区间序列这一片段。整篇复用会把 Handoff 段也塞进提示词，而单镜生成拿不到片段上下文。

**为什么不各写一份**：两份格式漂移后，用户从「复制 Seedance 执行稿」和「实际生成用的提示词」里看到不同格式，会以为有一个是错的。

### 2. 分镜级：新增独立的【因果时间轴】段，而不是把时间戳塞进现有段落

`buildVideoGenPrompt` 保持现有 7 段结构，只做两件事：
- 段落顺序调整：`【画面微动作】` 与 `【动作攻防拆解】` 前移到 `正向对白约束` 之前；
- 追加第 8 段 `【因果时间轴】`，内容形如 `0.0s 姜七夜拱手一拜 → 1.5s 转身牵驴向门口 → 2.8s 老王跳脚并喝骂（台词）`。

**为什么不把时间戳直接写进 `【画面微动作】`**：`actionZh` 是用户可编辑字段，也是 C02 对白保真、C05 地标衔接等规则的匹配源。污染它会让所有基于 `actionZh` 的规则匹配失效。时间轴必须是**派生段**，不落盘、不影响 `actionZh`。

**为什么不只调段落顺序不加时间轴**：顺序只解决"提示词里谁在前"，不解决"模型在同一段里把两个主体的动作演成同时发生"。秒数标注是唯一能约束同镜内相位的手段。

### 3. 时间轴的秒数分配策略

```
输入：durationSec、actionZh、temporalEvolution、dialogueEstimatedSec

情况 A：有 temporalEvolution
  → 尝试从中解析显式秒数（如"前1.5秒…后1.5秒…"）
  → 解析成功：按解析结果分段
  → 解析失败：按默认次序分配，但在时间轴中保留 temporalEvolution 原文作为相位说明

情况 B：无 temporalEvolution
  → 台词时段 = dialogueEstimatedSec（无标注时按 durationSec × 0.4 兜底）
  → 台词时段贴在本镜末尾：[durationSec - est, durationSec]
  → 动作时段 = [0, durationSec - est]
```

**为什么台词默认贴末尾**：用户的例子（老王骂完，姜七夜才走）说明模型倾向把台词放前面。把台词默认钉在时间轴尾部，是与该倾向对冲的最简策略；`temporalEvolution` 存在时以它为准。

**为什么用 `dialogueEstimatedSec` 而不是 `audioDurationMs`**：`audioDurationMs` 要等 TTS 合成后才有，而视频生成先于配音发生。预估秒数是生成时唯一可得的台词时长信号。

### 4. 片段级：保留对白，改为「区间 + 动作/对白」交替序列

`buildSegmentPrompt` 的第 5 段（纯视觉画面动作整合）改造为：

```
[0.0s - 4.0s] 镜号 1（中景）：
  动作：姜七夜拱手随意一拜
[4.0s - 7.0s] 镜号 2（中景）：
  动作：姜七夜转身牵驴向衙门口走去
  对白（2.0s）：老王：你！你站住！反了你了！
[7.0s - 12.0s] 镜号 3（近景）：
  动作：老王在背后跳脚
```

不再执行 `RegExp(r'(dialogue|台词|对白)\s*[:：].*')` 剥离。对白单独成行、带时长标注，与动作行区分——这让模型能区分"这是要演的动作"和"这是要配的话"。

**为什么不沿用既有 `SegmentShotParts.dialogue` 字段直接拼**：该字段已存在但从未被读取（proposal 已述），直接读取即可，无需新增字段。改造点只在第 5 段的组装逻辑。

**片段级要不要闭口守卫**：要。既有分镜级提示词的 `全员闭口守卫` 措辞在片段级不存在，而片段级一旦含对白，模型可能尝试画面内开口。需在片段提示词中注入同等强度的闭口声明，并为它写测试锁定。

### 5. C11 因果倒置检测的判定逻辑

```
触发条件（全部满足才报）：
  1. 分镜 dialogue 非空，且发声类型为对白（非内心独白/旁白）
  2. extractSpeakerName(dialogue) 解析出的说话人 ≠ actionZh 中首个出现的角色名
  3. temporalEvolution 为空
     —— 即用户/AI 既没把反应拆到独立分镜，也没声明相位

严重级：WARNING（不阻断生成）
```

**为什么是 WARNING 不是 BLOCKING**：判定 2 依赖"actionZh 中首个出现的角色名"这一启发式，误报率不为零。误报若阻断生成，用户会被卡住。WARNING 让用户在花额度前看到风险，同时保留覆盖权。

**为什么条件 3 用 `temporalEvolution` 判空**：它是本设计选定的相位声明载体。有声明说明作者已知悉先后；无声明 + 说话人不匹配 = 大概率倒置。

### 6. 音轨：`targetDurations` 接上，用 `apad` + `atrim` 而非 `adelay`

```
每段台词：apad → atrim=<该镜 durationSec>
```

**为什么不用 `adelay` + 静音拼接**：`adelay` 需要为每段手算绝对偏移，段数变化时偏移全部重算；`apad`+`atrim` 让每段自包含到目标长度，concat demuxer 自然累加，与 SRT 的游标模型（`cursorMs += holdMs`）一致。

**为什么改 `_concatAudio` 而不是新增函数**：`targetDurations` 参数本就存在，注释已写明该用滤镜实现（ffmpeg_composer.dart:665-670），只是两个调用点没传。补上即可，不新增 API。

**concat demuxer 的局限**：demuxer 不做重采样，长度归一必须在滤镜层完成，因此需从 `-f concat` + 流拷贝改为 `filter_complex` 逐段 `apad`/`atrim` 再 `concatn`。失败时保留既有的"退回第一段"回退路径。

## Risks / Trade-offs

- **[Risk] 分镜级段落顺序变化会破坏断言旧顺序的测试** → **[Mitigation]** 先跑基线确认既有失败项（已知 `test/ai_video_studio_cinematic_director_test.dart` 的 `心声独白` 断言在改动前已红，与本次无关），再逐个更新受影响断言，不借机改无关测试。
- **[Risk] 片段级提示词从无对白变为含对白，模型可能画面内开口** → **[Mitigation]** 注入与分镜级等强度的闭口守卫措辞，并新增测试断言该措辞存在。
- **[Risk] `temporalEvolution` 是自由文本，解析秒数失败率高** → **[Mitigation]** 解析失败时回落到默认次序分配并保留原文作为相位说明，不因解析失败而省略时间轴段。
- **[Risk] `dialogueEstimatedSec` 对无标注台词按 `durationSec` 钳制估算，可能与真实 TTS 时长偏差大** → **[Mitigation]** 时间轴只用于约束视频模型的相位，真实音轨仍由 `audioDurationMs` 驱动；两者不一致时以音轨为准，不反向改时间轴。
- **[Risk] `StudioPresetStore` 自定义 `video_prompt_rewrite` 模板会绕过新增的第 5 条铁律** → **[Mitigation]** 自定义模板追加在默认约束之后时仍会带入第 5 条；仅在完全替换时失效，此时依赖 C11 兜底。
- **[Risk] `_concatAudio` 改用滤镜后长剧集音频拼接变慢** → **[Mitigation]** 单集分镜数 ≤ 16，滤镜图规模很小；先实测一集合成耗时再决定是否需要分段优化。

## Migration Plan

纯增量改动，无数据迁移：
1. 先落 L2 提示词层（分镜级重排 + 时间轴 + 片段级时序序列），跑既有测试并更新受影响断言。
2. 落 L1 拆镜模板约束与 L3 的 C11，补对应测试。
3. 最后落 L4 音轨 `targetDurations`，实测一集合成的时间轴对齐。

回滚策略：每层独立可回滚。L2/L3 是提示词与规则层，回滚不影响已生成产物；L4 涉及 FFmpeg 滤镜，回滚即恢复不传 `targetDurations` 的原行为。
