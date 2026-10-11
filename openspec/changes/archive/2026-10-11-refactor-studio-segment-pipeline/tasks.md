## 1. 数据模型与迁移

- [x] 1.1 在 `models/studio_models.dart` 新增 `ShotContinuity`（`worldPosition`、`screenPosition`、`holdingLeft`、`holdingRight`、`lightingState`、`stateChanges`），含 `toJson`/`fromJson`/`copyWith`，必填项仅 `worldPosition`/`holdingLeft`/`holdingRight`
- [x] 1.2 新增 `StudioSegment`（`id`、`targetDurationSec`、`boundaryReason`、`promptZh`、`clipPath`、`status`、`shotNumbers`、`excludedShotNumbers`、`degradedRefCount`）与 `enum SegmentStatus`
- [x] 1.3 `StudioShot` 增加 `segmentId` 与 `continuity`，`toJson`/`fromJson`/`copyWith` 同步，默认值保证旧 JSON 可解析
- [x] 1.4 `StudioEpisode` 增加 `segments` 列表与 `toJson`/`fromJson`/`copyWith` 同步
- [x] 1.5 在 `StudioProjectManager.readEpisode` 实现旧版迁移：无 `segments` 时按分镜顺序每 2–3 镜归组（末组可为 1 镜），`boundaryReason` 写「旧版数据自动分组」，**不产生磁盘写入**
- [x] 1.6 `StudioProjectManager` 增加 `episodeSegmentsDir(seriesId, episodeId)`，并在 `_ensureEpisodeDirs` 中创建 `segments/`
- [x] 1.7 `AppPaths.videoStudioSeriesDir` 目录结构注释与 `test/app_paths_test.dart` 的 `allDirs` 断言同步（如需要新增登记项）

## 2. 提示词组装

- [x] 2.1 `PromptAssembler._JoinResult` 增加 `pinned` 支持：被钉住的段不进入超限丢弃候选，`buildShotPrompt` 行为保持不变
- [x] 2.2 实现 `PromptAssembler.buildSegmentPrompt(SegmentPromptParts)`，段序：质量基线 → 风格 → 目标时长 → 角色锚点（含 `{{ref N}}`）→ 场景锚点 → 逐镜动作/台词 → 运镜 → **连续性绝对状态（钉住）** → 片段级补充说明
- [x] 2.3 `buildSegmentPrompt` 返回 `AssembledPrompt`（复用现有类型），`droppedSegments` 不含连续性段
- [x] 2.4 单元测试：超限时优先丢弃尾部可选项而连续性状态保留；无参考图时角色锚点位不输出 `{{ref N}}`

## 3. AI 约束引擎两段化

- [x] 3.1 更新 `_promptScriptBreakdown`：要求先划片段边界（1–4 镜/段）再拆镜，输出 `segments` 数组（含 `target_duration_sec`、`boundary_reason`、`shot_numbers`）与分镜上的连续性字段；保留现有 8–16 镜、景别/情绪/功能枚举、`action_zh` 30–50 字等硬约束
- [x] 3.2 更新 `_SchemaValidators.scriptBreakdown`：校验 `segments` 覆盖全部分镜且镜号连续不重叠；校验相邻片段末镜/首镜的景别、主体或角度至少一项不同（不满足则重试）；校验 `continuity` 必填项存在
- [x] 3.3 新增时长自洽校验：片段目标时长之和与剧集预估总时长偏差 >20% 时在结果中标注 `durationConflict`，不静默截断
- [x] 3.4 `shotRegenerate` 提示词注入所属片段的 `promptZh` 与该镜的 `continuity`，并在输出契约中禁止 AI 新增桥接动作
- [x] 3.5 更新 `test/ai_constraint_engine_test.dart`：新增片段结构、衔接校验、时长冲突标注、单镜重生成不新增动作的契约测试

## 4. 片段级视频生成

- [x] 4.1 `VideoGenRequest` 改造：`inputImage` 改可选、新增 `referenceImages: List<File>` 与 `promptZh`（design 决策 3）
- [x] 4.2 `VideoGenAdapterFactory.create` 增加按片段请求选择适配器的分支，保留 `preferredEngineId` 与系统槽位优先级逻辑
- [x] 4.3 `SenseAudioVideoAdapter` 支持多参考图：`content` 数组多项 image，首张 `role: first_frame`、其余 `reference`；prompt 取 `promptZh`（为空回退 `cameraMove`）
- [x] 4.4 `AgnesVideoAdapter` 降级路径：仅取第一张参考图作为 `first_frame`，记录 `degradedRefCount` 并经 `AiLogger` 输出降级警告
- [x] 4.5 `KenBurnsVideoAdapter` 在 `inputImage == null` 时抛出可读错误（「本地动效需要首帧」），支持更长时长（放宽 `totalFrames` 上限）
- [x] 4.6 实现 `SegmentVideoGenTask implements StudioTaskRunner, CancellableTaskRunner`：提交前检查参考图存在与时长在模型白名单（白名单缺失时拒绝并提示，不 clamp 静默提交）、跳过 `excludedShotNumbers`、写回 `segment.clipPath`
- [x] 4.7 更新 `test/ai_video_studio_adapter_test.dart` 与 `test/ai_video_studio_generation_task_test.dart`：多参考 payload 形状、Agnes 降级、Ken Burns 无首帧报错、片段任务跳过排除镜号

## 5. 任务队列

- [x] 5.1 `StudioTaskKind` 增加 `segment('segment', '片段生成')`
- [x] 5.2 队列面板（`_QueueDrawer`）按 kind 分组展示，片段任务显示目标时长与涉及镜号范围
- [x] 5.3 更新 `test/ai_video_studio_task_queue_test.dart`：片段任务入队/取消/并发共享上限

## 6. 分镜看板「按片段」视图

- [x] 6.1 `storyboard_board.dart` 增加视图切换（按片段 / 按镜头），默认按片段
- [x] 6.2 实现片段分组头部：片段序号、目标时长、`boundaryReason`、片段视频缩略图、片段级生成按钮与「缺参考图」阻止提示
- [x] 6.3 片段内分镜卡片复用现有 `_ShotCard`，单镜覆盖入口保留
- [x] 6.4 片段提示词查看/编辑入口（读写 `segment.promptZh` 的补充说明字段）
- [x] 6.5 「全剧批量拆解」与「批量生成关键帧」按钮在两种视图下均可用且语义不变
- [x] 6.6 更新 `test/ai_video_studio_shell_test.dart`（若断言了看板结构）与新增视图切换的 widget 测试

## 7. 交付链路兼容与回归

- [x] 7.1 `DeliveryPanel` 的 `_readyClips` 与总时长计算：按分镜顺序优先取 `clipPath`，缺失时取所属 `segment.clipPath` 并计入时长
- [x] 7.2 `JianyingExporter` 保持按 `shots` 消费，片段产物按其覆盖的分镜位置插入视频轨
- [x] 7.3 更新 `test/ai_video_studio_ffmpeg_test.dart` 与 `test/ai_video_studio_jianying_test.dart`：混用片段与分镜产物的时间轴
- [x] 7.4 新增 `test/ai_video_studio_segment_test.dart`：旧文件加载不写盘、连续两次保存片段划分不变、迁移分组为 2–3 镜
- [x] 7.5 全量回归：`flutter test` 中所有 `ai_video_studio_*` 用例通过；`flutter analyze --no-fatal-infos` 无新增 error/warning
- [x] 7.6 手工验证一个片段化改造前创建的旧剧集：打开后分组稳定、已有媒体路径不变、合成产物与改造前一致

## 8. 文档与收尾

- [x] 8.1 在 `docs/ai-video-studio/` 补充片段化生产单元与连续性台账的说明（目录结构、字段含义、与分镜级生成的关系）
- [x] 8.2 遵循 GEMINI.md 工程规则执行 `./scripts/deploy_local.sh` 并确认部署实例正常运行
