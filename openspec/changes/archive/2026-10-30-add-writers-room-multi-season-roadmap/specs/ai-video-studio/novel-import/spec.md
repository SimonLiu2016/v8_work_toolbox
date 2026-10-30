## ADDED Requirements

### Requirement: 全书全景多季宇宙路线图提取与自愈校验

系统 SHALL 在长文影视化提取管线中支持多季宇宙路线图（`seasons_roadmap`）输出。在通读小说全本后，大模型 SHALL 输出覆盖整部小说的季播方案列表，包含季序号 `season_number`、季标题 `season_title`、原著章节跨度 `adapted_chapters_range`、推荐集数 `recommended_episode_count`、核心主题 `season_theme`、本季主要反派或对立面 `core_antagonist` 及季终大高潮 `season_climax`。
若模型输出缺少 `seasons_roadmap` 或格式残缺，系统校验器自愈引擎 SHALL 自动将当前单季分析兜底封装为包含【第 1 季】的有效路线图，确保 downstream UI 与逻辑永不崩溃。

#### Scenario: 成功提取长篇小说多季路线图
- **WHEN** 用户在编剧研讨室载入一部数百万字的长篇小说并触发主线与改编分析
- **THEN** 系统解析出包含 3 季或更多季度的 `seasons_roadmap` 数组，每季均有明确的原著章节区间、推荐集数（如 80 集）与季终高潮

#### Scenario: 提取输出缺少多季路线图时自动兜底自愈
- **WHEN** 大模型返回的 JSON 数据未包含 `seasons_roadmap` 或该字段为空
- **THEN** 校验器自愈引擎自动将提取出的主线与第一季元数据构造成包含第 1 季的兜底 `seasons_roadmap` 并返回

### Requirement: 编剧研讨室季播工作台切换与独立规划

编剧研讨室（`WritersRoomDialog`）SHALL 提供直观的季播切换控制器（Season Switcher）与多季路线图看板。用户 SHALL 能够点击查看全书多季蓝图，并能在不同季度之间自由切换。切换季度后，控制栏与工作区 SHALL 同步更新为目标季的标题、原著章节范围、推荐集数及季终高潮，并支持为所选季独立生成或重新规划包含大幕（Macro Arcs）的完整分集大纲。

#### Scenario: 用户在研讨室中切换至其他季度
- **WHEN** 用户在编剧研讨室控制栏中点击切换至【第 2 季】
- **THEN** 界面当前规划季名与原著范围更新为第 2 季，并自动加载或提示规划第 2 季的分集大纲

#### Scenario: 选中特定季后定稿同步至剧集大纲
- **WHEN** 用户选中特定季度（例如第 2 季）并点击“定稿并同步至剧集大纲”
- **THEN** 系统以该季特定的标题（如《xxx·第2季》）将该季的大纲与角色信息同步保存至剧集工程
