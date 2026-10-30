## Why

在 AI 漫剧工作台日常创作中，用户反馈在分镜看板执行“清空分镜”或删除分镜后，前往剧本工作台点击“一键转换为5D分镜看板”，发现分镜文字内容一模一样，且之前已生成的视频片段全部“死而复生”重新关联挂载在分镜卡片上，导致用户产生“删除和清空操作无效”的严重认知困惑。

根本原因在于：
1. 剧本面板的“一键转换为5D分镜看板”实际上仅是本地静态规则转换，并未调用大模型 AI 进行重拆，造成分镜文本无变化；
2. 底层 `StudioProjectManager._healEpisodeMediaIfNeeded` 存在盲目自愈机制，单纯依赖固定文件名 `shot_${number}.mp4` 检索磁盘，在新分镜生成时强行将旧视频资产绑回；
3. 清空与重拆操作缺少针对历史媒体文件的归档或清理选项。

## What Changes

- **改造“清空分镜”与“重新拆镜”流程**：在清空本集分镜和从剧本重拆时，支持用户选择归档/重命名旧媒体文件（`clips/` 与 `frames/`），防止历史废弃视频被新分镜错位挂载。
- **阻断盲目自愈重连（切断幽灵重连）**：优化 `_healEpisodeMediaIfNeeded` 逻辑，禁止仅凭 `shot.number` 强行绑定物理文件；增加分镜内容/指纹校验或重拆标记，只有指纹一致的分镜才允许安全自愈。
- **解耦剧本工作台操作文案与心智模型**：
  - 将剧本工作台的【一键转换为5D分镜看板】更名为【同步剧本节拍至分镜（本地）】，明确标注为本地规则转换；
  - 剧本工作台与分镜看板均提供显式的【AI 重新拆分分镜】操作通道，调用 `scriptBreakdown5D` 大模型服务，消除用户的心智混淆。

## Capabilities

### Modified Capabilities
- `ai-video-studio/shot-production`: 规范分镜清空与重新拆解生命周期，增加媒体资产归档隔离机制，杜绝幽灵视频自愈错位。
- `ai-video-studio/script-workshop`: 明确剧本节拍本地映射与 AI 大模型五维拆解的操作边界与文案反馈。

## Impact

- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 优化媒体自愈逻辑与分镜媒体归档清理方法。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 升级“清空分镜”与“从剧本重拆”的弹窗交互与归档动作。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart`: 统一同步按钮文案与 AI 拆镜引导。
