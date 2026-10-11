# 片段化生产单元与连续性台账

本文记录 AI 短视频工坊的「片段（Segment）」生产单元与「连续性台账」两套结构：
它们为什么存在、字段含义、以及与分镜级生成的关系。对应变更
`refactor-studio-segment-pipeline`。

## 1. 为什么要有「片段」

改造前一集的生产单元是「镜」：8–16 个分镜各生成一张关键帧、各生成一段 3–5 秒
视频，最后拼起来。这带来三个互相叠加的问题：

```
改造前（一镜一段）                改造后（一片段一段）
──────────────                   ─────────────
大纲 → 16 张关键帧               大纲 → 片段边界
     → 16 段视频                       ↓
     → 拼接（无连续性契约）        每片段一次视频生成
                                       ↓
                                  拼接（有台账约束）
```

- **成本**：16 次云端视频调用，而一次片段生成只要 4–5 次。
- **连续性**：各自独立生成的 3 秒片段之间没有任何契约，拼接后必然是 PPT 感。
- **叙事**：分镜表一旦因为时长或叙事需要合并镜头，就得推翻重来。

片段是「连续叙事节拍的最小可生成单元」，含 1–4 个分镜。它是 `drama` 类型的
视频生成单元；`anime` / `narration` 仍可按分镜生成本地 Ken Burns，但允许整段
合并成一次生成以减少 FFmpeg 调用。

## 2. 目录结构

```
AppSupportDir/video_studio/series_library/<series-id>/episodes/<ep-id>/
├── storyboard.json      # 唯一事实来源：shots + segments
├── audio/               # 台词音频 + SRT
├── frames/              # 分镜级关键帧
├── clips/               # 分镜级视频产物
├── segments/            # 片段级视频产物   ← 新增
└── exports/             # 成片、封面、剪映草稿
```

`clips/` 与 `segments/` 分开是因为两者的消费方式不同：分镜级产物按镜头进时间轴，
片段级产物按片段进时间轴（见 `jianying-draft-format.md` 的视频轨规则）。

## 3. `StudioSegment` 字段

| 字段 | 含义 |
|---|---|
| `id` | `seg-<n>`，n 从 1 起 |
| `targetDurationSec` | 目标时长。AI 划边界时给出，用户可改 |
| `boundaryReason` | 边界判定理由。迁移生成的片段写死「旧版数据自动分组」 |
| `promptNote` | 片段级补充说明，追加在组装提示词末尾 |
| `clipPath` | 已生成片段视频的文件名（相对 `segments/`） |
| `status` | `pending` / `generating` / `done` / `failed` |
| `shotNumbers` | 参与的镜号，按分镜顺序 |
| `excludedShotNumbers` | 被单镜覆盖而移出本次生成的镜号 |
| `degradedRefCount` | 参考图被降级的数量。0 表示未降级 |

**`segments` 只存元数据与指向，不复制分镜。** `shotNumbers` 按顺序指向
`episode.shots`，这样 `shots` 保持唯一事实来源，声音设计、SRT、FFmpeg 合成、
剪映导出四处消费方都不需要改。

### 降级为什么必须可见

`degradedRefCount > 0` 表示「用户传了 N 张参考图，模型只用了 1 张」。当前只有
`SenseAudioVideoAdapter` 原生支持多参考（`content` 数组多项 image）；`Agnes` 与
`Kling` 只取第一张。降级数量落盘并在看板上提示，否则用户会以为人物一致性约束
生效了——而实际上模型只看到一张脸。

## 4. `ShotContinuity` 字段

| 字段 | 能否由 AI 推导 |
|---|---|
| `worldPosition` | 可（相对固定地标的绝对位置） |
| `screenPosition` | 可（当前机位下的画面关系） |
| `holdingLeft` | **不可**，只能来自原文 |
| `holdingRight` | **不可**，只能来自原文 |
| `lightingState` | 可 |
| `stateChanges` | **不可**，只能来自原文或用户编辑 |

后三项是必填项——缺一个就意味着 AI 在替用户编剧情。spec「禁止 AI 自行桥接」
要求：原文给出初始状态时直接使用，不得补充"道具如何被拿到手里"之类的前史。

台账被 `PromptAssembler.buildSegmentPrompt` 拼进片段提示词，且**钉住不参与超限
丢弃**——默认策略是「超限从尾部丢」，而台账段正好拼在尾部。丢风格词只是画面少
点味道，丢持物状态会直接产生穿帮。

## 5. 旧版数据迁移

`storyboard.json` 没有 `segments` 字段时，`StudioProjectManager.readEpisode` 自动
补齐分组：

- 按分镜顺序每 3 镜归组；剩 4 镜时拆 2+2（末组只含 1 镜没有「片段」的意义）
- `boundaryReason` 写「旧版数据自动分组」，让用户能区分 AI 划的与系统补的
- **纯函数，不落盘**——读取路径不该有写副作用，失败会污染用户数据，也让
  「打开即修改」难以解释。结果保留到下一次 `saveEpisode` 自然写回
- 幂等由「`segments` 非空即跳过」保证

## 6. 两种视图

分镜看板提供「按片段」与「按镜头」两种视图，默认按片段：

- **按片段**：`_SegmentGroupCard` 为可折叠分组，组头展示目标时长、边界理由、
  片段视频状态与生成按钮；组内复用 `_ShotCard`
- **按镜头**：改造前的平铺形态，一行一张分镜卡

两种视图共享同一个 `_buildShotCard`，所以同一分镜在两种视图里长得一模一样、
行为也一模一样。

## 7. 交付链路如何混用两种产物

合成与剪映导出按分镜顺序消费，优先级为：

1. 分镜级产物 `shot.clipPath`（用户单独出的那一镜）
2. 片段级产物 `segment.clipPath`（覆盖该片段的全部镜头）

时长计入规则不同：

- 分镜级产物按该镜的建议时长
- 片段级产物按「片段目标时长 ÷ 覆盖镜头数」摊分

摊分而不是按整段累加，是因为片段是一次生成的整体，剪回时间轴时必须按镜头摊，
否则 N 镜的片段会按整段时长累加，成片时长虚高 N 倍。
