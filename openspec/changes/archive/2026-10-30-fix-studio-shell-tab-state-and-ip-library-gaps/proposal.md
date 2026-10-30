## Why

短视频工坊存在一批高频可见的体验缺陷：切换导航标签时创意孵化面板的导入进度卡片消失（Widget 被 dispose 导致局部 `_activeImportId` 丢失）；IP 主库三个子库能力不对称（场景库无 AI 生成图，角色卡/道具库生成的图无法点开大图/删除）；工坊未配置模型时顶栏按钮文案误导用户为"演示模式"；以及新增市场热门的"3D 国漫/次世代虚拟剧"制作类型。

## What Changes

- **修复 Studio Shell 标签页状态保活**：`_buildStage` 改为 `IndexedStack`，`IdeaIncubatorPanel` 不再因切换导航而 dispose，`_activeImportId` 等局部状态得以保留，进度卡片切走再回来依然可见
- **场景库新增 AI 生成图**：`_SceneEditorSheet` 接入 `SystemAiImageAdapter`，行为对齐道具库（生成 → 存场景目录 → 可收进资产库）
- **角色卡 / 道具库 / 场景库图片放大查看与单张删除**：三处参考图列表增加点击全屏预览 + 单张删除入口；角色卡三视图在"基准参考图"列表中可见、可预览、可删除
- **新增 `3D国漫/次世代虚拟剧` 制作类型**：`StudioProductionType` 增加 `anime3d` 枚举值，附默认提示词模板风格描述（精致光影、流体特效、东方奇幻美学）
- **修正「未配置模型」顶栏按钮文案**：`_isLocalDemoMode` 为 true 时改为 `⚙ 点击配置 AI 引擎`，消除"演示模式"误导；按钮文案过长时做截断，避免在小窗口中撑出布局

## Capabilities

### New Capabilities

- `ai-video-studio/ip-library-image-management`: IP 主库（角色卡、场景库、道具库）图片生成、全屏预览、单张删除的统一能力规范

### Modified Capabilities

- `ai-video-studio/series-asset-library`: 场景库新增 AI 生成图能力（现有 spec 未覆盖此入口）
- `ai-video-studio/shot-production`: 新增 `anime3d` 制作类型影响分镜生成的默认参数与提示词策略

## Impact

- `lib/tools/ai_video_studio/ui/studio_shell.dart`：`_buildStage` 重构为 `IndexedStack`；顶栏按钮文案
- `lib/tools/ai_video_studio/ui/series_page.dart`：角色卡参考图列表、三视图预览/删除；场景库 AI 生成图；道具库图片预览
- `lib/tools/ai_video_studio/models/studio_models.dart`：`StudioProductionType.anime3d`
- `lib/tools/ai_video_studio/ui/project_list_page.dart`：新建项目类型选择需包含 `anime3d`
