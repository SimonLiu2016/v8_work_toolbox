## Why

在分镜（Storyboard）制作与图生视频流水线中，分镜不仅需要关联角色与场景，往往还需要绑定关键道具（如信物、武器、法宝、坐骑等）。然而当前系统存在三大缺陷：
1. **分镜道具完全缺失**：`StudioShot` 数据结构未声明 `propIds`，分镜看板未加载项目道具库，出场资产面板无任何“添加道具”入口，导致道具资产无法进入分镜上下文；
2. **角色添加缺乏选择交互**：现有“添加角色”按钮硬编码为直接添加未绑定列表的第一个角色（`available.first.id`），无法供用户自由勾选或按需选择指定角色；
3. **资产参考图单选限制**：`ShotAssetBinding` 仅支持单张 `materialPath` 字符串与单选下拉框，无法为单一角色或单一道具同时绑定多张参考图（如正面全身 + 特写细节），限制了大模型对复杂资产的还原精度。

现在推进此项工作，可打通从 IP 资产库道具到分镜资产面板、再到提示词 `<Picture N>` 与多参考图视频生成模型的完整闭环。

## What Changes

- **分镜数据模型扩充**：在 `StudioShot` 中新增 `propIds: List<String>` 字段，支持序列化/反序列化及分镜复制。
- **资产绑定多图扩展**：扩展 `ShotAssetBinding`，支持存储多张素材路径（`materialPaths: List<String>`），并保持向后兼容原有单图属性 `materialPath`。
- **分镜看板道具与角色交互升级**：
  - 看板数据层加载项目的道具库列表（`_manager.listProps(seriesId)`）；
  - 出场资产面板新增“添加道具”入口与“道具资产行”（显示道具名称、分工与素材图选择器）；
  - 改造“添加角色”与“添加道具”交互，点击弹出选择菜单/列表，支持用户自由选择任意可用实体加入分镜；
  - 资产行支持为单个角色或道具绑定多张参考图，并在面板右上角实时汇总出场总参考图数与模型上限提醒。
- **素材解析与提示词编译联动**：
  - `AssetMaterialEnumerator` 新增 `forProp` 枚举器，扫描并列出道具目录下存在的候选图；
  - `AssetBindingResolver` 支持解析 `propIds` 及其多图绑定，统一编排生成有序的 `<Picture N>` 列表（角色 ➔ 道具 ➔ 场景）；
  - `PromptAssembler` 在【素材指代】段中输出道具标签（如 `<Picture 3> = 杀生剑（道具）`），并在分镜正向提示词中注入出场道具特征与交互动作。

## Capabilities

### Modified Capabilities
- `ai-video-studio/shot-production`: 分镜出场资产支持绑定道具（`propIds`），支持多角色与多道具选择交互，支持单资产绑定多张参考图进入视频生成请求。
- `storyboard-visual-composition`: 提示词组装引擎支持将出场道具及其多张参考图编译为 `<Picture N>` 素材指代与正向道具视觉约束。
- `prop-cards`: 道具卡资产接入分镜生产与资产绑定链路，支持在分镜卡中反查与被引用。

## Impact

- **数据层**：`StudioShot` 新增 `propIds` 字段；`ShotAssetBinding` 升级支持 `materialPaths`（兼容旧版数据）。
- **看板 UI**：`storyboard_board.dart` 的 `_ShotAssetPanel` 与 `_AssetRow` 重构支持道具与多图。
- **编译器与生成服务**：`prompt_assembler.dart`、`studio_generation_tasks.dart` 适配道具参考图与多图数组。
- **向后兼容性**：所有现有剧集与分镜 JSON 均无缝兼容，缺失 `propIds` 或使用旧 `material_path` 的分镜自动补齐默认值。
