## Why

对于数百万字的长篇网络文学，单部短剧（80~100 集，每集 90 秒）通常仅能承载原著前几十至一百章的内容（例如凡人流的主角初出茅庐与凡躯破局）。原著后续广袤的世界观展开、境界跨越、宗门战争与更高阶宿敌，若缺乏全局多季规划，往往造成剧情烂尾、设定断层或无法长线持续产出。

为了支持影视短剧工业级 IP 的全案长线孵化，AI 编剧研讨室需要具备**“全书多季宇宙（Multi-Season Franchise Architecture）”**的顶层架构能力：大模型在通读原著全文后，一次性梳理出贯穿全书的多季播路线图（第 1 季、第 2 季、第 3 季……至全书终局），并在编剧研讨室中提供季播切换控制台，允许制片人与编剧逐季独立审阅、打磨大纲并投产。

## What Changes

- **全书多季宇宙路线图提取契约（Multi-Season Roadmap Extraction）**：
  - 在 `extractWritersRoomMaster` 中增强提炼输出，在保留核心主线与人物资产的同时，增加 `seasons_roadmap` 契约列表：
    - `season_number`：季序号（1, 2, 3...）；
    - `season_title`：本季剧名（如“神手风云”、“宗门秘境”、“乱星海风暴”）；
    - `adapted_chapters_range`：对应原著章节跨度（如“第 1 ~ 80 章”）；
    - `recommended_episode_count`：本季推荐集数（如 80 集、100 集）；
    - `season_theme`：本季核心叙事主题与阶段目标；
    - `core_antagonist`：本季核心对立势力/主要反派；
    - `season_climax`：本季终极大高潮。
- **编剧研讨室多季切换工作台（Season Switcher Workbench）**：
  - 在 `WritersRoomDialog` 控制栏新增**「季选择器/切换条」**，直观展示全书规划的所有季度徽章（包含季序号、季名与章节跨度）；
  - 支持用户在各季之间自由点击切换；切换选中季后，工作台自动加载该季对应的推荐集数、原著章节范围、季终大高潮及该季专属的两级篇章分幕大纲（Macro Arcs ➔ Episodes）；
  - 支持针对当前选中的季重新单独触发 AI 分集规划或通过对话协商局部调整。
- **全书多季宇宙路线图看板（Multi-Season Roadmap Board）**：
  - 在研讨室左侧面板增加可折叠展开的“🗺️ 全书多季宇宙蓝图看板”，以时间线/卡片流直观展示从第 1 季到全书终局的宏观演进图景。
- **多季分别定稿与同步剧集机制**：
  - “定稿并同步至剧集大纲”支持依据当前选中季的标题与分集（如《xxx·第2季：宗门秘境》），精准同步到当前剧集或对应季工程中，共享全局角色库与资产库。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 增补长篇小说全景多季宇宙路线图（Multi-Season Roadmap）提取契约、编剧研讨室多季切换工作台与逐季独立分集大纲规划规范。

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：扩展 `extractWritersRoomMaster` 的 System Prompt、User Prompt、JSON Schema 与校验器自愈逻辑，支持 `seasons_roadmap` 多季数组解析；在 `planWritersRoomSeasonBeats` 中支持接收指定季的元数据进行针对性规划。
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`：增加多季状态管理（`_seasonsRoadmap`、`_currentSeasonIndex`）、季切换 Tab 栏、多季路线图卡片展示，以及切换季时的分集大纲重新规划/缓存机制。
- `test/`：补充全书多季路线图提取、缺省兜底自愈与季切换状态联动的测试用例。
