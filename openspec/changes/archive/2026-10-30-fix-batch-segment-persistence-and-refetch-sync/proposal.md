## Why

用户在分镜看板、剧本工作台与任务队列操作中发现了以下核心链路断裂与体验问题：
1. **并发快照覆盖导致大段成片展示丢失**：分镜看板中，第一集的第 3 大段之前已成功生成，但随后第 4 大段生成完成写回时，因任务启动时抓取了旧内存快照，覆盖抹除了第 3 大段在 `storyboard.json` 中的 `clip_path`；重新取回时也未写回剧集。
2. **剧本工作台切换集数假死**：剧本工作台中第 1 集与第 2 集均有剧本时，下拉切换集数后，因 Flutter `TextFormField` 缺乏唯一键 `Key` 导致复用了旧的 `FormFieldState`，输入框内容不切换。
3. **任务队列无法直达试炼场调试**：任务队列中每次 AI 调用均消耗了额度与长等待，但生成效果不佳或需要微调时，无法一键将完整的调用参数（提示词、参考图、画幅、时长、模型）导入 Agnes 试炼场进行编辑与重试。
4. **资产库缺少响应式事件与呈现脱节**：资产入库时缺乏响应式变更通知，且默认处于「图片」页签，造成“收进资产库有提示但看不见”的感知偏差。

## What Changes

- **原子化重载写回与磁盘成片自愈重连（Self-Healing）**：
  - 重构 `SegmentVideoGenTask`，写回前重新从磁盘读取最新 `episode` 并序列化保存，杜绝并发竞争覆盖。
  - 在分镜看板初始化及数据加载时增加成片自愈比对：若 `clipPath == null` 但磁盘对应位置（`segments/seg-X.mp4`）真实存在有效视频，自动重连并修复元数据。
- **重新取回全链路剧集同步与看板刷新**：
  - 改造 `refetchCompleted` 与 `_CloudTaskTile._refetch`，取回视频后自动调用 `_writeBack` 写回 `storyboard.json`。
  - 将分镜看板重载通知（`onPersisted` / `onReload`）穿透至任务抽屉，取回成功后即时刷新分镜卡片。
- **剧本工作台集数切换响应式重绘修复**：
  - 为 `ScreenplayPanel` 中的场次列表与表单输入控件绑定基于剧集与场次的唯一 `Key`，使集数下拉切换时自动销毁并重建表单状态。
- **任务队列一键直达 Agnes 试炼场调试与重发**：
  - 在 `VideoTaskLedgerEntry` 中持久化记录完整的调用参数快照（`requestSnapshot`：提示词、参考图路径、时长、画幅比例、模型等）。
  - 在任务抽屉卡片上提供「在试炼场调试」按钮，一键调起 Agnes 试炼场并自动预载全部参数与参考素材，支持用户就地修改并重发请求。
- **资产库响应式广播与入库体验增强**：
  - 在 `AssetLibrary` 中引入变更流通知（`Stream<List<StudioAsset>>`），`AssetLibraryPage` 监听此流实时自动刷新。
  - 优化大段/分镜入库时的语义化命名（如 `[剧集名-第X集] 大段 2 视频`），并在没有封面时抽取关键帧/参考图海报避免纯黑卡片。

## Capabilities

### New Capabilities
<!-- 无需新增顶层能力目录，均在现有能力规范下扩展与修复 -->

### Modified Capabilities
- `ai-video-studio/segment-production`: 增加并发大段批量生成时的最新状态原子重载回写规范，以及基于本地磁盘既有成片的自愈对齐（Self-Healing）规范。
- `async-video-task-ledger`: 规范「重新取回（refetch）」行为在完成本地文件拉取后必须强制同步写回剧集；增加完整调用快照与一键导出到调试工具的规范。
- `ai-video-studio/script-workshop`: 规范剧本工作台在多集之间切换时表单界面的即时响应与状态重建，杜绝跨集残留。
- `agnes-playground`: 增加接收外部任务调用快照（Draft Prefill）并自动填充提示词、参数与参考图进行单次调试重发的规范。
- `studio-asset-library`: 增加资产库变更通知事件流规范，以及分镜/大段入库时的可读命名与海报抓取规范。

## Impact

- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`: 优化大段生成原子重载保存逻辑。
- `lib/tools/ai_video_studio/services/studio_project_manager.dart`: 增加读剧集时的自愈检查与序列化写链。
- `lib/tools/ai_video_studio/services/video_gen_adapter.dart` & `video_task_recovery.dart`: 强化 `refetchCompleted` 回写。
- `lib/tools/ai_video_studio/services/video_task_ledger.dart`: 扩充 `requestSnapshot` 保存与解析。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 增加试炼场直达按钮、穿透重载回调。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart`: 修复场次表单 Key 绑定。
- `lib/tools/agnes_playground/ui/playground_page.dart`: 支持草稿参数（Draft Prefill）接收与预填。
- `lib/tools/ai_video_studio/services/asset_library.dart` & `ui/asset_library_page.dart`: 实现事件广播流与响应式刷新。
