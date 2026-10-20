## Why

IP 主库当前只有角色卡与场景库两类资产，缺三块：道具无任何承载（剧本里的主要道具既不能定义也不能出图）；角色没有多视角参考图（跨镜头长相一致性只能靠文字 prompt 约束）；资产库没有分类与检索，积累几十张图之后只能靠翻。

同时，用户已实测确认 Agnes 图像模型可用单次生成产出质量合格的角色三视图（正面/侧面/背面同帧），因此这条路线的成本是一次生成，不需要 img2img 派生链路。

## What Changes

### 1. 道具数据模型与 IP 主库页签（原 Change A）

- `StudioSeries` 新增 `props` 列表，`PropCard` 含 id、名称、中文描述、英文 prompt、参考图列表、重要性标记。
- `StudioProjectManager` 增删改查 + 目录结构 `series_library/<series-id>/props/<prop-id>/`。
- IP 主库页签从四个扩为五个：「角色卡 / 场景库 / 道具 / 世界观 / 集数与前情」。
- 道具支持提示词或参考图生成图片，生成结果可收进资产库（复用 `AssetLibrary`）。

### 2. 角色三视图生成（原 Change B）

- 角色卡新增「生成三视图」动作：以角色描述 + 参考图组装提示词，单次生成包含正面/侧面/背面的参考图。
- 生成结果存入角色目录（`characters/<id>/turnaround.png`），角色卡展示缩略图。
- 三视图可作为后续分镜生成的参考图参与（走既有 `referenceImages` 链路）。
- 生成的三视图可收进资产库。

### 3. 资产库分类与检索（原 Change C）

- `StudioAsset` 新增 `category` 字段（枚举：character / scene / prop / frame / clip / other）。
- `StudioAsset` 新增 `tags` 字段（自由文本列表）。
- 资产库页新增分类筛选 + 标签/提示词关键词检索。

### 4. 新建剧集的导入入口

沿用「创意孵化」里已有的入口（从小说库选择 / 导入文本文件），不在「新建剧集」处新增第二个入口。避免同一功能两处进入、后续维护时两边漂移。

## Capabilities

### New Capabilities

- `prop-cards`: 剧本主要道具的定义、存储、生图与资产库复用。
- `character-turnaround-sheet`: 角色多视角参考图的生成、存储、展示与复用。

### Modified Capabilities

- `series-asset-library`: 剧集资产模型扩展道具一类；资产库支持分类与检索。
- `ai-video-studio/shot-production`: 角色卡新增三视图生成入口与产物展示。

## Impact

**代码**
- `lib/tools/ai_video_studio/models/studio_models.dart`：`PropCard`、`StudioSeries.props`、`StudioAsset.category` / `tags`。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`：道具 CRUD 与目录。
- `lib/tools/ai_video_studio/services/asset_library.dart`：分类筛选与检索。
- `lib/tools/ai_video_studio/ui/series_page.dart`：道具页签、三视图入口。
- `lib/tools/ai_video_studio/ui/asset_library_page.dart`：分类与检索 UI。

**数据**
- `storyboard.json` 新增 `props` 字段；缺失时按空列表加载，无需迁移。
- `asset_index.json` 新增 `category` / `tags`；缺失时分别回落 `other` 与空列表，无需迁移。

**测试**
- 道具 CRUD 与序列化；三视图生成的请求体与产物落盘；资产分类筛选与关键词检索。

**非目标**
- 不在「新建剧集」处新增导入入口（沿用创意孵化的既有入口）。
- 不做场景全景图（720° equirectangular）——图像模型无原生宽幅比例支持，需另探路线。
- 不做道具的跨剧共享（道具归属单剧，与角色的 IP 主库定位一致）。
