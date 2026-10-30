## Context

在长篇网文改编短剧流程中，当前已经具备单季 80 集的两级篇章大幕（Macro Arcs）规划与防缩水机制。然而，百万字小说往往包含 3~8 个明显的阶段性大篇章（如凡躯破局、宗门试炼、出海争霸、跨界大战等）。

为了支持真正的长线 IP 全案孵化，本方案在 `AiConstraintEngine` 与 `WritersRoomDialog` 中构建全书多季宇宙路线图（Multi-Season Roadmap）提取、本地多季状态缓存与季播快速切换工作台。

## Goals / Non-Goals

**Goals:**
- **全书多季路线图契约**：在 `AiConstraintEngine.extractWritersRoomMaster` 中输出 `seasons_roadmap`，包含 3~6 个季度的核心元数据（季号、标题、原著章节跨度、推荐集数、核心主题、主要反派、季终大高潮）；
- **校验自愈容错**：在 `_SchemaValidators.writersRoomMasterExtract` 中增加对 `seasons_roadmap` 的健壮自愈兜底，当 LLM 遗漏该字段时自动根据当前单季信息封装第 1 季路线图，保障 downstream 零异常；
- **研讨室季播切换器（Season Switcher）**：在 `WritersRoomDialog` 篇章控制栏增加横向滑动的季度选择器 Chips，展示各季序号、季名与原著区间，支持一键切换活跃季；
- **多季大纲独立缓存与即时切换**：采用本地按季缓存机制（`_seasonEpisodesCache` 与 `_seasonMacroArcsCache`），切换季度时无损保留各季已规划的分集大纲，未规划时提供一键规划触发；
- **全书多季宇宙可视化看板**：在主界面展示全书多季路线图卡片流，直观呈现全书影视化全景；
- **指定季定稿同步**：支持将当前选中季的大纲精准同步至剧集工程。

**Non-Goals:**
- 一次性并发请求大模型生成全部季度（如 5 季 × 80 集 = 400 集）的微观分集（极易遭遇并发上限、Token 溢出与算力浪费；本设计采用“全书全景宏观路线图一次性提炼，各季微观分集按需点击独立生成/缓存”的最佳工业实践）。

## Decisions

### 1. 契约增强与自愈机制
在 `AiConstraintEngine.extractWritersRoomMaster` 输出中注入：
```json
{
  "seasons_roadmap": [
    {
      "season_number": 1,
      "season_title": "神手风云",
      "adapted_chapters_range": "第 1 ~ 80 章",
      "recommended_episode_count": 80,
      "season_theme": "凡躯踏入仙途，暗藏造化神瓶，生死逆袭杀墨夺舍",
      "core_antagonist": "墨大夫 (余子童)",
      "season_climax": "神手谷密室夺舍决死反杀，得筑基残卷破空离谷"
    },
    ...
  ]
}
```
若大模型未产出 `seasons_roadmap`，自愈器提取现有的 `season_number`、`season_title`、`adapted_chapters_range`、`season_climax` 构筑默认第 1 季对象，并在列表为空时自动注入。

### 2. 研讨室多季工作台状态与缓存设计
在 `_WritersRoomDialogState` 中引入：
- `List<Map<String, dynamic>> _seasonsRoadmap = []`：当前小说的全景季播路线图；
- `int _selectedSeasonIndex = 0`：当前正在检视与规划的季度索引；
- `Map<int, List<Map<String, dynamic>>> _seasonEpisodesCache = {}`：各季已规划分集大纲缓存；
- `Map<int, List<Map<String, dynamic>>> _seasonMacroArcsCache = {}`：各季已规划大幕缓存；
- 当切换 `_selectedSeasonIndex` 时，自动取出对应季的元数据，若该季已生成大纲直接命中缓存渲染；若未生成，自动调用 `_planSeasonBeats()` 进行规划并写入缓存。

### 3. `planWritersRoomSeasonBeats` 支持季上下文注入
在 `planWritersRoomSeasonBeats` 中支持传入当前选中季的 `seasonNumber`、`seasonTitle`、`adaptedChaptersRange`、`seasonTheme`、`seasonClimax`，使大模型明确当前正在规划哪一季的 80 集高能分集，从而与原著对应章节与高潮精准对齐。

## Risks / Trade-offs

- **[Risk]** 通读长篇小说提取全书多季路线图时，大模型可能忽略原著后半部剧情。
  - **Mitigation**: 在 System Prompt 中强调“必须根据小说全局篇幅与世界观阶梯，规划覆盖全书完结的完整多季蓝图（建议 3~6 季）”，并要求注明各季对应的原著章节跨度。
- **[Risk]** 频繁切换季可能导致用户误以为之前季的大纲丢失。
  - **Mitigation**: 研讨室内部维护 `_seasonEpisodesCache`，季间切换时立即读写缓存，实现丝滑秒切并保留所有编辑与规划历史。
