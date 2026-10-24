## Context

动机与行为契约见 proposal.md 与三份 spec delta。这里只记实现层面的关键约束。

### 现状：三个字段的语义混用与 UI 缺位

```
shot.mood（画面氛围）
  ├─ 本意：驱动 BGM 匹配与运镜推荐
  ├─ 实际：buildVideoGenPrompt 直接把它当台词语气 → 「语气：温馨」配怒斥台词
  └─ UI：7 处引用、0 个输入控件（全是 _Tag 只读展示）

directorDecisions.temporalEvolution（本镜内时间相位）
  ├─ 本意：供因果时间轴切分
  ├─ 实际：解析不出秒数时被原样塞进 prompt 当「相位说明」
  └─ UI：_DirectorDecisionsPanel 的 _buildDecisionRow 只读

台词语气
  ├─ 数据本来就在 dialogue 里：AI 拆镜 prompt 要求「（压低声音，咬牙）」
  └─ 实际：从未被解析，反而用 mood 顶替
```

### 关键观察：语气数据已经存在，只是没被读

`ai_constraint_engine.dart:1309` 拆镜模板第 7 条明确要求 dialogue「在需要时加入情绪语气提示（例如"（压低声音，咬牙）你找死！（预估2秒）"）」。所以台词文本里本就带语气，`cleanDialogueForSpeech` 还特意剥离过它——只是剥下来就扔了，没传给提示词编译。

这意味着「语气从台词解析」几乎零成本：把 `cleanDialogueForSpeech` 已经识别出的括号内容接过来即可。

## Goals / Non-Goals

**Goals:**

- 语气只来自台词本身，解析不到就留白——不错好过没有。
- `mood` 回归画面氛围本职，且用户能改。
- `temporalEvolution` 只在能干活时进 prompt，且用户能改。
- 场景指涉矛盾在花钱前被拦住。

**Non-Goals:**

- 不改 `cleanDialogueForSpeech` 的既有契约（TTS 依赖它剥离干净文本）。
- 不新增 `dialogueTone` 字段——数据已在台词里，加字段是重复。
- 不改 `seconds` 字段类型（字符串是 Agnes 文档约定，现有测试锁定）。
- 不处理「动作幅度太大导致人脸漂移」这类模型能力问题。

## Decisions

### 1. 语气解析：复用 cleanDialogueForSpeech 的括号识别，不新写正则

`cleanDialogueForSpeech` 已经用 `RegExp(r'[（\(][^）\)]*秒[）\)]')` 干过同类活。新增一个 `extractDialogueTone(String dialogue)`：

```
输入：「（压低声音，咬牙）你找死！（预估2秒）」
  ↓ 剥掉预估注记 → 「（压低声音，咬牙）你找死！」
  ↓ 取首个括号内容且不含「秒/预估」→ 「压低声音，咬牙」
  ↓ 过滤纯动作提示（如「起身」「怒」）→ 保留
输出：「压低声音，咬牙」
```

**为什么不直接取所有括号内容**：台词里可能有非语气的括号（场景提示、动作提示）。限定「首个括号 + 不含秒数注记 + 长度 ≤ 12 字」能把误收率压到可接受，且解析不到就留白，误收的代价也有限。

**为什么留白而不是回落 mood**：回落 mood 就是现在的 bug 本身。语气是可选修饰，没有它 prompt 照样成立。

### 2. temporalEvolution：从「原样保留」改为「静默丢弃」

```
现在（prompt_assembler.dart:1397）：
  if (temporal.isNotEmpty) {
    return '$timeline。相位说明：$temporal';   ← 解析不出也塞进去
  }

改成：
  if (phaseSplit != null) {
    // 只在解析出秒数时，把它作为人类可读的相位说明附加
    return '$timeline。相位：$phaseSplit秒前为动作相位';
  }
  return timeline;   // 解析不出 → 什么都不加
```

**这是上一轮 change 我埋的雷**。当时想的是「别丢信息」，但忽略了一个事实：`temporalEvolution` 是 AI 自由文本，绝大多数不含可解析秒数，于是绝大多数分镜都被塞了一句「相位说明：动作处于启动及推进相位」。模型不读，人看冗余。

现在 UI 要把这个字段开放编辑（见决策 4），用户填了可解析的秒数就能驱动时间轴——那才是它该有的用法。

### 3. `<Picture N>` 从时间段末尾改到主体名之后

```
现在：0.0s-2.4s 姜七夜拱手随意一拜，转身牵驴走出衙门，老王在背后跳脚。（<Picture 1>）
改成：0.0s-2.4s 姜七夜（<Picture 1>）拱手一拜，转身牵驴走出衙门；老王（<Picture 2>）在背后跳脚
```

时间区间只标时刻，图片编号紧贴主体。这样读起来是「谁（用哪张图）做什么」，而不是「做了什么（用这张图）」。

片段级同样处理：动作行内每个角色名后跟编号。

### 4. 两个 UI 入口的落点

**情绪下拉** —— 放在分镜卡现有的控件行（场景/时长/模式那一排），与「时长」并列：

```
Row: [场景▾] [情绪▾] [时长▾] [模式▾] [画幅▾]
```

值取 `ShotMood.values`，写入 `shot.copyWith(mood: id)`。**注意**：`mood` 同时驱动 `MoodTokens.of()`（生图光线词）和 `BgmMatcher`，所以改它会同时影响关键帧光线与 BGM 推荐——这是对的，用户改情绪本就该三者一致。

**时间演变编辑** —— `_DirectorDecisionsPanel` 的 `_buildDecisionRow` 只读文本改为可编辑 `TextField`：

```
现在：_buildDecisionRow(context, '时间演变', d.temporalEvolution)  ← 纯展示
改成：_buildDecisionEditor(context, '时间演变', d.temporalEvolution, onChanged)
```

onChanged 走 `shot.copyWith(directorDecisions: d.copyWith(temporalEvolution: v))`。面板已有 `onChanged` 通道（其他字段如果可编辑的话），需要确认；若没有，加一个。

**一个权衡**：`_DirectorDecisionsPanel` 有 6 个字段，全部开放编辑会让面板变得很长。我倾向**只开放「时间演变」**（因为它直接影响时间轴、且当前完全不可改），其余保持只读——它们要么已由其他面板覆盖（光影/机位在运镜面板），要么是 AI 内部推导（美学质感）。如果你要全开放，说一声。

### 5. C12 场景指涉冲突：用名词包含判定，不用 NLP

```
判定：actionZh 中含「衙门」而 scene.name 是「巡城司大牢」且不含「衙门」→ 冲突
```

做法很土但有效：从 `actionZh` 里抽取「场景类名词」（衙门/大牢/牢房/街道/客栈/书房…一个 30 词的枚举表），若抽到的名词既不在 `scene.name` 也不在 `scene.descriptionZh` 里，报 WARNING。

**为什么不用语义相似度**：那要引模型或词向量，成本与不确定性都过高。一个 30 词枚举表能覆盖 90% 的真实案例，误报的代价也只是用户多点一下「忽略」。

**为什么是 WARNING**：存在合法情况——「走出衙门」可能是指「从大牢被提出去衙门口」，跨场景动作在连续叙事里成立。拦住但允许继续。

### 6. 片段级也吃这三项改动

`buildSegmentPrompt` 的语气、时间轴编号位置、场景图声明要和 `buildVideoGenPrompt` 保持一致，否则同一份数据在两条路径上产出不同 prompt。片段级没有 per-shot 的 mood/tone 输入，取该片段**首个有台词的分镜**的解析结果。

## Risks / Trade-offs

- **[Risk] 语气留白后 prompt 变短，可能损失模型的情绪引导** → **[Mitigation]** 只在解析不到语气时留白；AI 拆镜模板本就要求写语气提示，正常流程下大部分分镜有语气可解析。
- **[Risk] 情绪下拉改了 mood 会同时改动关键帧光线词与 BGM** → **[Mitigation]** 这是刻意的一致性——但要在 UI 上提示用户「情绪同时影响画面光线与配乐」，避免改了之后困惑关键帧为何也变了。
- **[Risk] temporalEvolution 开放编辑后，用户可能填入更长的无效文本** → **[Mitigation]** 输入框加 placeholder 提示「例：前2.0秒拱手，后3.0秒转身」，且不可解析文本本来就不会进 prompt，最坏情况是回到默认次序。
- **[Risk] C12 的 30 词枚举表覆盖不全，漏报** → **[Mitigation]** 漏报的后果是回到现状（不拦），不比现在差；误报允许用户忽略。

## Migration Plan

无数据迁移。`mood` 与 `temporalEvolution` 都是既有字段，改动只涉及读取方式与 UI 入口。已生成的分镜不受影响；重新生成时使用新逻辑。

回滚策略：语气解析与时间轴改动都是纯函数内的条件分支，回滚即恢复旧分支；两个 UI 控件是新增，删除不影响数据。
