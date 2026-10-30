## Why

在 AI 视频工作室（AI Video Studio）的长视频/短剧生产管线中，下游的分镜看板（Storyboard）、Prompt 编译器与视频生成模型已完整支持道具资产（`PropCard`、`StudioShot.propIds` 与 `<Picture N>` 多图参考）。然而上游的原著小说解析流程存在严重的道具断层：
1. **编剧研讨室缺失关键道具提取**：通读全书主线仅提取了角色、关系与大纲，漏掉了贯穿全剧的核心信物、金手指、本命法宝与武器等关键道具（Key Props），研讨室界面亦无道具展示与同步至 IP 主库的入口；
2. **剧本工作台缺失微观节拍道具提取**：单章小说改编及大纲转分场剧本时，`DramaScene` 与 `DramaBeat` 数据结构均无道具字段，原著涉及的动作道具（如淬毒短刃、茶盏、密函）被淹没在非结构化的动作描写中，导致一键转分镜时镜头道具 `propIds` 与手持状态（`holdingLeft` / `holdingRight`）全部留空，用户被迫逐镜手动重新绑定。

现在推进此项工作，可打通从“原著解析”到“编剧研讨室关键道具沉淀”，再到“剧本工作台微动作节拍道具绑定”，最终无缝流入“分镜看板与生图生成”的端到端资产闭环。

## What Changes

- **编剧研讨室增加关键道具宏观抽取与同步**：
  - 在 `extractWritersRoomMaster` 与提示词中增加 `key_props` 结构化输出（包含名称、类别、核心戏剧功能、外观材质 Prompt 特征）；
  - `WritersRoomDialog` 新增「关键道具」面板展示提炼的资产，并提供「一键同步道具到 IP 主库」功能，批量沉淀为 `PropCard(isKeyProp: true)`；
  - 全季分集大纲规划（`episodes`）中结构化标注该集登场的关键道具列表。
- **剧本工作台节拍模型与提取升级**：
  - 扩展 `DramaBeat` 数据结构，增加 `props`（出场/使用道具名称列表）、`holdingItem`（手持道具）及 `holdingHand`（持握手 `right`/`left`/`both`）；
  - 单章改编（`adaptNovelDramaChapter`）与大纲转分场（`screenplayGeneration`）在 Prompt 中注入 IP 主库已有道具列表，引导 AI 优先复用已知道具并结构化输出节拍道具及人物手持动作；
  - `ScreenplayPanel` 节拍卡片展示道具标签，已匹配 IP 主库道具显示关联状态，未入库即时道具支持一键快速收录为项目道具卡；
  - 升级 `extractDramaBeatsToShots` 转换逻辑，生成分镜时自动匹配并填充 `StudioShot.propIds` 以及 `ShotContinuity.holdingRight` / `holdingLeft`。

## Capabilities

### Modified Capabilities
- `prop-cards`: 规范道具资产卡与编剧研讨室、剧本工作台的原著解析提取集成，支持关键道具由研讨室一键沉淀以及即时道具由工作台快捷收录。
- `ai-video-studio/script-workshop`: 规范剧本工作台分场文学剧本与节拍对道具的承载，支持节拍级道具标注、手持状态记录以及一键转分镜时的道具属性自动继承与连续性映射。
- `ai-video-studio/novel-import`: 规范小说单章导入与编剧研讨室原著主线解析中的道具结构化提取，消除原著解构时道具信息遗失。

## Impact

- **数据模型**：`DramaBeat` 扩展支持 `props`、`holdingItem`、`holdingHand` 字段及序列化反序列化。
- **AI 提示词与约束引擎**：`ai_constraint_engine.dart` 中升级 `_promptWritersRoomMasterExtract`、`_promptWritersRoomSeasonBeats`、`_promptNovelDramaChapterAdaptation` 与 `_promptScreenplayGeneration`。
- **UI 界面**：`writers_room_dialog.dart` 增加关键道具 Tab、卡片展示与同步按钮；`screenplay_panel.dart` 增加节拍道具 Chip 渲染与一键收录交互。
- **分镜转换与生产**：`extractDramaBeatsToShots` 自动完成节拍道具向 `StudioShot.propIds` 与 `ShotContinuity` 的映射填充。
