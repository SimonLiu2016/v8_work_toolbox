## Why

在长篇小说影视化改编短剧的编剧研讨室（`WritersRoomDialog`）中，当前面临两个严重影响短剧工业化落地的缺陷：
1. **集数严重缩水为 15 集**：即便 AI 通读后智能推荐了 80 集且目标集数设为 80 集，大模型受单次 Token 物理天花板及缺乏强硬约束的影响，仅输出了 15 集“代表性大纲”，造成全季剧情断层与严重缩水。
2. **单集时长与全剧时长看板缺失**：分集大纲中缺少单集时长标定（如微短剧黄金标准 90 秒），无法精确估算台词容量与全季总片长；同时 500 万字宏篇长文强塞进 80 集缺乏“季播（Season Scope）”范围标定，缺少明确的第一季起止点与高潮节点。

## What Changes

- **单集时长标定与全剧时长看板（Duration Dashboard）**：
  - 增加单集目标时长控制项（默认 90 秒，支持 60秒快节奏、90秒标准短剧、120秒剧情加长、180秒精细微剧下拉选择）；
  - 篇章控制栏增加全季总片长实时看板（如 `共 80 集 · 单集 90 秒 · 全季总片长约 120 分钟 (2.0 小时)`）；
  - 分集大纲卡片中展示单集目标时长角标（`duration_sec`）与台词容量指导（约 300~450 字）。
- **两级篇章分幕架构（Macro Arcs ➔ Micro Episodes）彻底解决集数缩水**：
  - 升级 `_promptWritersRoomSeasonBeats` 与约束校验，引入两级结构：先划分 4~6 个核心戏剧大篇章/幕（`macro_arcs`，各幕明确包含起止集数范围、核心矛盾对峙与转折），再展开各幕分集；
  - 施加严格的集数断言校验与多幕补齐机制，确保生成的有效分集数量精确匹配目标集数（如 80 集），杜绝大模型偷懒输出 15 集代表性大纲。
- **多季体系与第一季范围标定（Season Franchise）**：
  - 在宏观提炼中增加季播规划元数据（标注当前为【第 1 季】、对应原著推荐章节范围、首季季终大高潮及后续季规划伏笔）。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 增补编剧研讨室单集时长与全季总时长看板、两级篇章分幕大纲架构（彻底解决集数缩减问题）以及多季体系第一季范围标定的规范契约。

## Impact

- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：扩展 `planWritersRoomSeasonBeats` 的 System Prompt、用户 Prompt 及 JSON Schema 校验器，支持 `duration_sec`、`macro_arcs` 与目标集数硬性断言。
- `lib/tools/ai_video_studio/ui/writers_room_dialog.dart`：新增单集时长选择器（默认 90s）、全季总片长看板、按篇章/幕分段展示或完整展现 80 集高能分集大纲，标注单集时长与台词预估。
- `test/`：补充两级篇章大幕解析、80 集严格约束自愈以及单集时长字段校验的测试用例。
