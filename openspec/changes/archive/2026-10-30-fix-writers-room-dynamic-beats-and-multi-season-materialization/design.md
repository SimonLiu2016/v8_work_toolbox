## Context

当前编剧研讨室（`WritersRoomDialog`）已支持多季路线图（`_seasonsRoadmap`）及多篇章宏观大幕（`_macroArcs`），但此前在将模型返回的核心节拍扩充为目标集数时，采用了机械拉伸复制算法，导致连续数集冲突和钩子 100% 重复；并且定稿同步仅影响当前单部剧集，未能在剧集库衍生出后续各季工程。此外，顶栏排版未做弹性约束，导致按钮溢出。

## Goals / Non-Goals

**Goals:**
- 彻底去除机械插值拉伸复制，让分集大纲由小说真实情节密度与高潮冲突自然推演，每集具备独一无二的冲突与钩子。
- 在定稿同步时，自动将研讨室规划的多季路线图在剧集库中物化新建出对应的衍生季度项目（`StudioSeries`），并通过共享 `ipId` 实现跨季 IP 资产与小说绑定的零成本复用。
- 在剧集库列表（`ProjectListPage`）正面直观显化【第 X 季 · 共 N 集】徽标，并在会话更新时即时刷新分集统计。
- 重构研讨室 Header 布局，左侧标题弹性收缩自适应，右侧关闭按钮绝对锚定，彻底根除溢出问题。

**Non-Goals:**
- 不重构底层文件系统为树状嵌套目录（如 `series/seasons/`），而是基于 `StudioSeries` 现有的 `ipId` 机制实现平级项目间的原生资产共享。

## Decisions

### 1. 动态情节驱动的分集规划（消除克隆与污染）
- **实现方式**：
  - 调整 `AiConstraintEngine.planWritersRoomSeasonBeats` Prompt，指示模型依据原著情节密度与叙事冲突，自然输出紧凑饱满的完整独立分集（建议每季 12~24 集，若用户指定更大集数则在模型端逐集推演真实递进）；
  - 重写 `_SchemaValidators.writersRoomSeasonBeats`：当模型输出集数满足或接近目标时，直接清洗规范化返回；若模型返回集数与目标集数存在差异，保留模型吐出的全部真实独立分集，严禁任何形式的线性复制、节拍克隆或在标题追加 `(节拍 X)`。

### 2. 多季路线图自动物化衍生项目 (Multi-Season Materialization)
- **实现方式**：
  - 在 `WritersRoomDialog._applyBeatsToProject()` 中：
    1. **第 1 季（当前剧集）**：更新剧名为《书名 · 第 1 季 · 季名》，同步第 1 季分集与记忆库，绑定 `novelId` 与 `_masterPlot`；
    2. **后续季度（第 2 季、第 3 季...）**：
       - 遍历 `_seasonsRoadmap` 中索引大于 0 的季度；
       - 通过 `_manager.listSeries()` 检查是否已存在同名或同季度项目（避免重复点击定稿创建多份）；
       - 若不存在，调用 `_manager.createSeries(name: ..., ipId: mainSeries.resolvedIpId, novelId: effectiveNovelId, worldview: _masterPlot)`；
       - 读取缓存或规划的该季分集列表 `_seasonEpisodesCache[seasonIndex]`，批量写入该衍生剧集的分集与 `EpisodeMemory`。
  - **资产共享**：所有衍生剧集的 `ipId` 均指向当前剧集的 `resolvedIpId`，因此在进入剧本工作台与分镜看板时，原生享有同一套角色卡库、面容特征与生图 Prompt 锁。

### 3. 剧集库卡片正面显化分季与集数徽章
- 在 `_SeriesCard` 中：
  - 在 `initState` 与 `didUpdateWidget` 中自动拉取 `_loadEpisodes()`，获取分集真实数量；
  - 在标题行右侧渲染醒目的 `_SeasonEpisodeBadge`：
    - 若剧名中含“第 X 季”，提取并高亮显示（如 `第 1 季 · 16 集`）；
    - 若不含季名，直接显示 `共 N 集`；
  - 展开与折叠状态始终与底层数据保持一致。

### 4. 研讨室顶栏弹性响应布局
- 在 `WritersRoomDialog` 顶部 Header：
  - 标题采用 `Flexible(child: Text(..., overflow: TextOverflow.ellipsis))`；
  - 操作按钮文案精简为：`更换小说`、`同步角色 (N)`、`定稿同步全季`；
  - 最右侧 `IconButton(icon: Icon(Icons.close))` 单独保留在 Row 尾端，且 Row 设置 `mainAxisSize: MainAxisSize.max`，杜绝溢出。

## Risks / Trade-offs

- **[Risk] 重复点击“定稿并同步至剧集库”可能产生重复的第 2 季/第 3 季项目。**
  - **Mitigation**: 在创建衍生季度前，根据 `ipId` 与季度名称（如 `第 2 季`）进行查重匹配，若已存在则直接更新其大纲与分集，而非盲目创建新项目。
- **[Risk] 大模型长篇推演时偶发集数少于用户输入的极大数值（如 80 集）。**
  - **Mitigation**: 优先遵循原著小说的自然叙事密度。以大模型推演出的真实高能分集为准，真实展现真实内容，不再强行复制出几十个相同的伪分集。
