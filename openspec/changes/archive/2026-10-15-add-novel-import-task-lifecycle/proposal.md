## Why

小说全案导入是工坊里最长的任务：两遍 AI 调用，每遍 240s 超时、最多 3 次尝试，最坏 24 分钟。但这条链路写在 `IdeaIncubatorPanel` 的 State 里，进度只有 `_novelImporting` / `_novelImportStatus` 两个局部字段。工坊的页签切换是**新建 Widget**（`studio_shell.dart` 的 `_buildStage` 不传 key、无 IndexedStack、无 keep-alive），切走即 dispose——用户看到的"小说全案深度解构中"消失，而 AI 调用还在后台跑，没有任何地方记录它、也没有任何地方能再看到它。关窗更隐蔽：`AppDelegate.windowShouldClose` 走 `hideMainWindow()`，进程没退，任务继续跑但界面全无。用户既不知道后台是否在解构，也不知道进度，更无法在重启后找回。

这不是新需求——导入长文本必须可观察，这在最初的探索里就提出过（"导入时创建分析任务"），只是从未落成 spec，也从未实现。

## What Changes

### 1. 导入任务从 Widget 状态提升为服务级任务

新增 `NovelImportTaskService`：导入提交后由服务持有执行体与进度流，UI 只订阅。切页签、关窗（进程存活）都不影响任务继续，也都能再看到进度。

任务进度**如实反映**：阶段文案（Pass 1/2、写入中）、已耗时秒数、当前尝试次数。供应商未给出进度时 MUST NOT 编造百分比——与 `async-video-task-ledger` 对视频任务的既有要求一致。

### 2. 不随导航消失的任务入口

工坊顶栏新增常驻任务指示（复用分镜看板 `_ActiveBadge` 的做法），点开是任务抽屉：列出进行中的导入任务、阶段、已耗时，以及最近的完成/失败记录。任何页签下都可观察，不必回到创意孵化。

### 3. 导入任务的持久化与重启语义

导入任务登记进**现有** `VideoTaskLedger`（复用其持久化、原子写与状态机，不新建第二套存储），使「这部小说被导入过哪几次」可追索。重启时的处理：

- 运行中的任务 → 标记为**已中断**，明确告知，提供重试入口。
- **MUST NOT 自动重新提交**——自动重提等于二次计费，比不恢复更糟。这与视频任务"重启后继续轮询但不重新创建"是同一条边界：视频的云端任务还活着所以能续，导入的 HTTP 请求已经断了所以不能续。

### 4. 导入元数据保留

`NovelSelectionResult` 已携带小说 id 与标题，当前 `_processNovelContent` 只取 `combinedText` 把元数据全扔了。补上：任务记录与台账条目带来源小说标识，使"这是从哪本小说导入的"可回溯。

### 5. 开始前告知工作量

导入范围弹窗已有"文本统计：共约 N 字 / M 行"。补上**预计耗时提示**（两遍重调用、每遍最长 4 分钟、可重试），让用户在点"开始导入"前就知道这是分钟级任务，而不是转圈后以为卡死。

### 6. 工坊内的 AI 调用日志入口

`AiLogger` 已记录全部 AI 请求/响应/错误，`AiLogDialog` 已在 AI 配置页、文档朗读、磁盘瘦身三处开放，唯独工坊没有入口——而工坊是调用密度最高的地方。补上，使导入失败时用户能自己看到供应商回了什么。

## Capabilities

### New Capabilities

- `novel-import-task-lifecycle`: 小说导入作为长任务的提交、进度可见性、持久化追索、重启中断语义与重试契约。

### Modified Capabilities

- `ai-video-studio/novel-import`: 既有导入 requirement 补"导入过程 SHALL 作为可观察、可追索的长任务"——原 requirement 只描述了导入成功后的产物，对导入过程本身无任何约束，这正是进度丢失没有违反任何 spec 的原因。

## Impact

**新增代码**
- `lib/tools/ai_video_studio/services/novel_import_task_service.dart`：任务服务（提交、进度流、持久化、重启恢复）。
- `lib/tools/ai_video_studio/ui/novel_task_drawer.dart`：任务抽屉与顶栏指示。

**改动代码**
- `lib/tools/ai_video_studio/ui/idea_incubator_panel.dart`：`_processNovelContent` 改为委托服务，删掉局部状态与局部 ticker；导入范围弹窗补预计耗时提示。
- `lib/tools/ai_video_studio/ui/studio_shell.dart`：顶栏挂任务指示；`_bootstrap` 里调用恢复扫描（与 `VideoTaskRecovery.startOnce()` 同侧）。
- `lib/tools/ai_video_studio/services/video_task_ledger.dart`：新增 `novel-import` 适配器标识（复用现有 schema，不加供应商专属列）。
- `lib/tools/ai_video_studio/ui/novel_selector_dialog.dart`：结果已带元数据，无需改动；仅确认 `NovelSelectionResult` 被完整透传。
- `lib/tools/ai_video_studio/ui/studio_settings_dialog.dart`：补 AI 日志入口。

**数据**
- 复用 `video_task_ledger/tasks.json`，新增 `adapterId: 'novel-import'` 的条目。无新文件、无迁移。

**测试**
- 任务服务：提交、进度流、切"UI"不中断、持久化跨重启、重启后标记中断且不自动重提、元数据保留。
- UI：任务抽屉显示进行中任务与阶段。

**非目标**
- 不做跨进程后台执行（无 isolate / headless 基础设施，进程死则请求断）。本次只做"进程存活时可观察 + 进程死亡可追索 + 可手动重试"。
- 不改小说文本的截断策略（`ai_constraint_engine.dart` 的 35000 字硬截断是另一个问题，单独提）。
- 不做导入任务的取消（HTTP 请求已发出则撤不回；未发出的第一遍之前可以取消，这个留到实现时评估性价比）。
