## Context

在长篇网文影视化改编中，大模型受单次 Completion Token 上限与注意力限制，规划 80 集时容易偷懒只输出 15 集典型大纲；同时缺乏单集时长（如 90 秒）与全季总片长看板，且缺少季播（第 1 季）范围认知。背景详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 在 `WritersRoomDialog` 增加单集时长选择器（默认 90 秒，支持 60/90/120/180 秒标准档位）与全季总片长看板（分钟/小时）。
- 在分集大纲数据结构及分集卡片中展示 `duration_sec` 及台词字数建议。
- 升级 `StudioAiTask.writersRoomSeasonBeats` 为两级架构（`macro_arcs` ➔ `episodes`），施加严格集数断言；校验层若遇模型偷懒截断，依据篇章大幕进行平滑插值自愈，严格保证输出集数精确等于目标集数。
- 在宏观提取中加入季播元数据（标注当前为【第 1 季】及原著推荐章节范围），构建多季宇宙基石。

**Non-Goals:**
- 本阶段不实装多季切换工作台（Phase 2 实现），当前专注夯实第 1 季的 80~100 集完整铺开与时长体系。

## Decisions

### 1. 两级篇章分幕架构（Macro Arcs ➔ Episodes）
- **数据结构契约**：
  - `season_title`: string（季标题，如《神手夺舍风云》）
  - `season_number`: int（默认 1）
  - `adapted_chapters_range`: string（如“第 1 ~ 80 章”）
  - `macro_arcs`: List of `{"arc_number", "title", "episode_range", "core_conflict", "turning_point"}`
  - `episodes`: List of `{"episode_number", "title", "conflict", "characters", "hook", "duration_sec", "arc_name"}`
- **防缩水自愈算法（Arc-Aware Interpolation）**：
  若 LLM 因物理限制仅吐出部分集数（如 15 集），校验器以 `macro_arcs` 或既有节拍作为骨架，按时间线性插值扩充并补充各幕发展节点，确保数组长度严格达到指定集数（如 80 集），编号 1~80 连续递增，绝不让用户看到缩水列表。

### 2. 单集时长与实时看板设计
- 研讨室篇章控制栏增加单集时长下拉：`[60s, 90s, 120s, 180s]`，默认 90 秒；
- 实时显示全季总片长：$$\text{总时长} = \text{集数} \times \text{单集时长}$$，例如 `80 集 · 单集 90 秒 · 全季约 120 分钟 (2.0 小时)`；
- 单集卡片展示 `⏱️ 90s · 建议台词 350~450 字`，提供准确的容量指引。

## Risks / Trade-offs

- **[Risk]** 当目标集数高达 100 集时，超长分集列表在 UI 渲染性能问题。
  - **Mitigation**：ListView 保持按需虚拟化构建，分集卡片轻量渲染，按大篇章/幕归属分组或折叠展示。
- **[Risk]** 插值自愈生成的中间分集是否会造成内容空泛。
  - **Mitigation**：结合已有 `macro_arcs` 的冲突脉络与原著 `master_plot` 进行幕内节拍推演，保证对抗线连贯递进。
