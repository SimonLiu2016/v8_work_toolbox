## Why

在 AI 短视频工坊（AI Video Studio）落地后，创作者在实际制作连续短剧时面临多处流程断层与体验阻碍：创意孵化后无法查看完整内容或基于已有剧集扩写、剧集库缺乏分集展开管理且切换剧集时标题卡死、场景卡无法编辑且与分镜脱节、风格词与 TTS 音色输入方式不友好、集数与前情回顾缺少编辑闭环，以及分镜看板无法清晰切换集数、生成产物（关键帧/视频）黑盒无预览播放与导出手段。

本次变更旨在修复这些核心交互断点，梳理出直观流畅的连续短剧创作工作流，完善资产与分集的管理能力，并打通分镜音视频产物的可视化与播放闭环。

## What Changes

- **TopBar 响应式修复与分集指示**：将顶部状态栏纳入会话监听范围，彻底修复切换剧集时标题与类型徽章不刷新的问题，并清晰呈现当前活跃分集。
- **剧集与分集双层管理体系**：
  - 剧集库卡片支持展开查看当前剧集下全部子集（第 1..N 集）列表，提供快捷新建分集按钮。
  - 分镜看板顶部常驻分集切换导航条，支持一键在各集分镜看板之间无缝切换与新建下一集。
- **双模式创意孵化工坊**：
  - 支持「全剧主线孵化」（从模糊概念提炼主线钩子、反转与节奏）与「单集剧情扩写」（基于已有世界观与上一集前情钩子续写下一集）。
  - 创意方案持久化保存，界面高亮已采纳方向，支持侧边抽屉随时查看与编辑修改完整内容。
- **IP 主库基建与关联深化**：
  - 场景库支持展开编辑中文描述、AI 一键生成英文 Prompt、上传垫图参考图；分镜卡片显式提供场景选择下拉框并自动注入生图 Prompt。
  - 世界观提供常用影视风格词快捷预设 Chip 标签点选。
  - 默认 TTS 音色优先接入系统全局 `AiConfigStore` 配置的音色与供应商，并提供下拉选择与试听播放。
  - 提供多集前情回顾时间线列表，支持各集剧情摘要与下集钩子的 AI 自动提炼与手动编辑保存。
- **分镜看板产物可见与播放闭环**：
  - 明确提示当前图像与视频生成引擎模式（商业 API vs 本地免费占位演示模式），消除卡死疑惑。
  - 分镜缩略图智能区分关键帧图片与已生成视频（叠加居中播放图标与时长角标）。
  - 缩略图点击支持高清大图全屏弹窗与视频内置播放器循环播放。
  - 提供分镜产物的「另存为」、「在 Finder 中定位」与重新生成操作。

## Capabilities

### New Capabilities
- `ai-video-studio`: 短视频工坊工作台整体体验、响应式顶部栏、引擎状态指示与分集导航。
- `ai-video-studio/idea-incubator`: 双模式创意孵化（全剧主线 vs 单集扩写）、创意卡片持久化与抽屉式编辑。
- `ai-video-studio/series-asset-library`: 连续剧资产库管理（分集树、场景卡全功能编辑与分镜关联、风格预设、系统 AI 音色优先绑定、多集前情记忆）。
- `ai-video-studio/shot-production`: 分镜可视化看板（分集切换条、缩略图大图与视频播放闭环、素材导出定位）。

### Modified Capabilities
<!-- 本次变更对现有其它模块规格无破坏性修改 -->

## Impact

- **UI 层**：
  - `lib/tools/ai_video_studio/ui/studio_shell.dart`：重构顶部栏监听，增加分集感知。
  - `lib/tools/ai_video_studio/ui/project_list_page.dart`：增加分集折叠展开面板与快捷建集。
  - `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：支持模式切换、已有剧集上下文读取、创意抽屉。
  - `lib/tools/ai_video_studio/ui/series_page.dart`：场景编辑抽屉、风格词标签库、系统音色选择器、多集前情时间线。
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`：增加分集切换导航条、缩略图点击预览播放弹窗、Finder 定位与导出。
- **服务与数据模型层**：
  - `lib/tools/ai_video_studio/models/studio_models.dart`：丰富场景卡与创意存储模型。
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`：创意孵化 Prompt 支持注入上下文。
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`：支持场景详情读写与创意方案归档。
  - `lib/services/ai_config_store.dart` & `lib/tools/reader/services/tts_engine.dart`：音色列表获取与试听桥接。
