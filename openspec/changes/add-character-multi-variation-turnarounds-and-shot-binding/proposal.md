## Why

在小说推文与动漫连续剧制作中，角色绝非单张三视图所能涵盖：角色在不同剧情阶段会有年龄时期的变化（如少年期、成年期、老年期），在不同场景下会更换服装装备（如日常道袍、隐匿夜行衣、玄铁重战甲、战损撕裂、Q版纸人化身）。目前角色卡仅支持一张全局三视图，导致分镜需要特定装束或年龄时，Prompt 描述与参考底图发生严重冲突，造成脸模失真或换装失效。

本提案通过将角色形态（`CharacterVariation`）升级为持有专属三视图的视觉资产实体，并在生成形态三视图时自动注入默认脸模底图实现“脸模一致性传承”，同时在分镜脚本中支持单镜直接绑定具体形态与动态路由三视图参考图，实现多形态、多装束、多年龄段角色的工业级视觉连续性。

## What Changes

- **形态专属三视图与模型扩展**：在 `CharacterVariation` 中增加 `turnaroundPath` 与 `referenceImages` 字段，支持形态独立生成与落盘（如 `turnaround_${variation.id}.png`）。
- **脸模特征一致性继承（Face Identity Inheritance）**：在为子形态（如战甲、少年期、夜行衣）生成三视图时，系统自动将基准 `turnaround.png`（或默认参考图）作为参考图输入生图引擎，确保换装或年龄变迁时五官骨骼与风格不走样。
- **形态卡片 UI 独立生成与管理**：在角色卡形态列表中，每个形态提供独立的三视图展示、比例选择（标准 / Q版）生成、入资产库与删除功能。
- **分镜脚本镜头级形态绑定（Shot Variation Binding）**：`StudioShot` 增加 `characterVariations: Map<String, String>`，分镜卡（`_ShotCard`）提供角色与具体形态联动选择器，允许用户明确指定某镜头中角色处于哪一服装或年龄形态。
- **关键帧任务动态底图路由（Turnaround Image Routing）**：生图任务优先读取分镜绑定形态的专属三视图作为生图参考底图，未生成时平滑回退至角色默认三视图。

## Capabilities

### New Capabilities
<!-- 无需新增顶层 capability 目录，复用现有架构 -->

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 角色资产卡扩展支持形态专属三视图落盘、脸模参考图自动继承与独立资产入库。
- `ai-video-studio/shot-production`: 分镜模型与分镜卡 UI 支持镜头级绑定角色具体形态，关键帧任务按指定形态动态路由三视图参考图。

## Impact

- **数据模型**：`lib/tools/ai_video_studio/models/studio_models.dart`（`CharacterVariation` 增加 `turnaroundPath`、`referenceImages`；`StudioShot` 增加 `characterVariations` 并保持旧版 JSON 向后兼容）。
- **服务与生图任务**：
  - `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`（`ImageGenTask._referenceImages` 识别形态三视图）。
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`（支持形态三视图提示词组装）。
- **UI 界面**：
  - `lib/tools/ai_video_studio/ui/series_page.dart`（形态列表增设形态三视图生成器与脸模底图继承逻辑）。
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`（分镜卡增加角色与形态联动选择器）。
