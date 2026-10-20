## Context

动机见 proposal.md — Why。行为契约见 specs/。此处只记影响实现方式的现状。

**当前导入链路的实际形状**（`idea_incubator_panel.dart`）：

```
_importNovelFromLibrary() ─┐
_importNovelFile()        ─┴─► _processNovelContent(novelContent)
                                 │
                                 ├─ await _showImportScopeDialog()   ← 弹窗选范围
                                 ├─ Timer.periodic(1s) → _novelImportStatus
                                 ├─ await AiConstraintEngine.extractNovelMaster()        ← 240s
                                 ├─ await AiConstraintEngine.segmentNovelEpisodes()      ← 240s
                                 │     └─ await _manager.importNovelProject()
                                 └─ await _manager.importChapterToEpisode()
```

进度状态是 `_novelImporting` + `_novelImportStatus` 两个实例字段，ticker 是局部 `Timer`。`studio_shell.dart` 的 `_buildStage` 每次 `setState` 都新建 `IdeaIncubatorPanel`（无 key、无 IndexedStack、无 keep-alive），所以切页签 = dispose = 进度归零，但 `await` 链仍在跑。

**既有的可复用设施**（这是本设计成立的前提，不新造）：

| 设施 | 位置 | 提供什么 |
|---|---|---|
| `VideoTaskLedger` | `services/video_task_ledger.dart` | 持久化 JSON、原子写、串行写链、状态机、`record()`/`update()`/`findBy*`、`resetForTesting` |
| `VideoTaskRecovery` | `services/video_task_recovery.dart` | 启动时扫描未完成任务并认领的完整范式 |
| `StudioTaskQueue` | `services/studio_task_queue.dart` | 内存调度 + broadcast stream + `enqueue(cancel)` |
| `AiLogger` / `AiLogDialog` | `services/ai_logger.dart`、`shell/ai_log_dialog.dart` | 全量 AI 调用落盘 + 现成查看器 |
| `_ActiveBadge` | `ui/storyboard_board.dart:962` | 顶栏任务角标的现成样式 |

**关键约束**：

1. **进程死 = 请求断**。全库零 `dart:isolate`、零 headless 模式，HTTP 请求挂在 UI isolate 上。所以"关窗继续跑"成立（`windowShouldClose` → `hideMainWindow()`，进程存活），"退出后继续跑"不成立。
2. **`AiConstraintEngine.run` 无取消通道**。`chatFn` 一旦发出，只能等它超时或返回。
3. **小说元数据已被丢弃**。`NovelSelectionResult` 带 `novel`（id/title）与 `selectedChapterIndices`，但 `_processNovelContent(String)` 只收合并文本。
4. **文本被硬截断**（`ai_constraint_engine.dart:446`，>35000 字只留首 20000 + 尾 15000）。本次不改，但它让"预计耗时"只能按遍数给，不能按字数线性推。

## Goals / Non-Goals

**Goals:**
- 导入任务的生命周期归属从 Widget 挪到服务层，UI 变成纯订阅者。
- 进度可见性与导航解耦：任何页签、关窗重开都能看到。
- 导入任务可追索：谁导入的哪本小说、成功还是中断、失败在哪一遍。
- 进程中断后诚实告知 + 手动重试，绝不自动重提。

**Non-Goals:**
- 不做跨进程后台执行（无 isolate 基础设施，见约束 1）。
- 不做导入取消（约束 2：请求发出后撤不回；第一遍之前的取消留待后续评估）。
- 不改文本截断策略。
- 不把 `StudioTaskQueue` 改成通用队列——它是分镜/片段产物的内存调度器，语义不匹配（见决策 2）。

## Decisions

### 决策 1：新建 `NovelImportTaskService`，不把逻辑塞进 ledger

ledger 是**被动的记录簿**：`record()` / `update()` / `findBy*()`，它不知道任务怎么执行。导入任务需要的是"持有执行体 + 推进阶段 + 广播进度"，这是调度器的职责。

所以分层：

```
NovelImportTaskService（新）          ← 执行体 + 阶段推进 + 进度流
   ├─ AiConstraintEngine              ← 不变
   ├─ StudioProjectManager             ← 不变
   └─ VideoTaskLedger（复用）          ← 只负责记录，不负责执行
```

备选：把导入执行体塞进 `VideoTaskLedger`。否——那会让"记录"和"执行"两个生命周期耦合，而 ledger 的文件头明确写了它是跨工具的账本，不该知道小说导入怎么做。

备选：把导入塞进 `StudioTaskQueue`。否——那个队列的 `shotNumber` 关联键、`completedOutputFor`、按 kind 分组全是分镜/片段语义；导入任务没有镜号，塞进去要么加可空字段要么复用 `segmentKey` 那种哈希技巧，两种都是把不相关的概念拧在一起。而且队列是纯内存的，正好没有我们要的持久化。

### 决策 2：进度用 `ChangeNotifier`，不用 Stream

`StudioTaskQueue` 用 broadcast stream（每帧多次回调，Stream 语义合适）；`ScheduledNewsService` / `UnattendedService` / `WebSearchService` 都是 `ChangeNotifier`。导入任务的状态变化是**秒级、少量、需要同步读**的（顶栏角标和抽屉都要读同一份），`ChangeNotifier` 更直接，且与项目里其他"长任务服务"一致。

UI 侧用 `ListenableBuilder`（`studio_shell.dart` 已在用同一模式监听 `StudioSession`）。

进度数据结构（不落盘的运行时态 + 落盘的终态分离）：

```dart
class NovelImportTask {
  final String localId;          // 与 ledger 条目共用
  final String seriesId;
  final String? novelId;         // 决策 4
  final String novelTitle;
  final bool isFullSeason;
  final ImportPhase phase;       // extracting / segmenting / writing / done / interrupted / failed
  final int attempt;             // 当前第几次尝试
  final DateTime startedAt;
  String? error;
}
```

`phase` 是**阶段枚举，不是百分比**。spec 明确要求"未提供百分比时 MUST NOT 编造"，所以这里根本没有百分比字段——不是留空，是没有。

### 决策 3：持久化落在 ledger，用 `adapterId: 'novel-import'` 区分

ledger 的 `VideoTaskLedgerEntry` 已含 `seriesId` / `episodeId` / `label` / `prompt` / `status` / `error` / `targetPath`，字段够用，不需要改 schema。`adapterId` 是现成的分类维度（`VideoTaskRecovery._buildAdapter` 已经靠 `adapterId.startsWith('agnes')` 分流），加一个 `'novel-import'` 值即可。

**关键**：`VideoTaskRecovery` 的 `_buildAdapter` 遇到非 `agnes` 前缀返回 null 并"保持等待"——这正是我们要的行为（导入任务重启后不该被当成视频任务去轮询），但要**显式**处理而不是依赖 null 分支的偶然正确：

```dart
// VideoTaskRecovery._scanAndResume 里显式跳过
if (entry.adapterId == 'novel-import') continue;
```

否则导入任务会以"云端仍在处理"的姿态永远挂在 pending 里，与 spec「重启后标记为已中断」冲突。

`status` 用现成的 `VideoTaskLedgerStatus`：`polling` → 进行中，`failed` → 失败，新增语义映射（导入没有"云端还在跑"这回事，所以 `cloudProcessing` 不用）：
- 进程退出时仍是 `polling` → 下次启动扫到 → 改成 `failed` + `error: '应用退出导致中断'`？

**这里要停下来想**：`failed` 会误导（不是导入失败，是没导完）。但 ledger 的状态枚举加一个 `interrupted` 会牵动 `isActive`、`prune`、UI 筛选多处。**权衡后选择复用 `failed` 但在 `error` 里写明中断原因**，UI 抽屉对 `adapterId == 'novel-import'` 的条目显示"已中断"而非"失败"——展示层做语义翻译，存储层不加枚举值。代价是存储态不够精确；收益是不动一个已被测试覆盖的状态机。

### 决策 4：保留小说元数据，扩 `_processNovelContent` 的签名

改成接收 `NovelSelectionResult`（文件导入路径构造一个等价的、`novelId` 为 null 的结果）。这样：

- 任务记录能带 `novelId` + `novelTitle`（spec「记录带来源小说标识」）。
- 单章导入时 `selectedChapterIndices` 可用于 label（"第 3-7 章"）。
- 文件导入的 `novelId` 为 null 是合法的——spec 只要求"从小说库选择时"带标识。

### 决策 5：顶栏指示 + 抽屉，复用 `_ActiveBadge` 样式

放在 `studio_shell.dart` 的 `_buildTopBar`，"刷新"按钮左侧。点击开 `showModalBottomSheet`（与 `_QueueDrawer` 同形态）。抽屉列：进行中任务（阶段 + 已耗时 + 尝试次数）+ 最近终态任务（成功/失败/中断 + 时间 + 原因）。

关窗重开后的恢复：`_bootstrap` 里在 `VideoTaskRecovery.instance.startOnce()` 之后调用 `NovelImportTaskService.instance.recoverInterrupted()`，把 `polling` 态的 novel-import 条目标记为中断。**只改状态，不重新执行**（spec「MUST NOT 自动重新提交」）。

### 决策 6：AI 日志入口加在工坊设置弹窗

`AiLogDialog` 是现成的，工坊设置弹窗加一个入口即可。放在引擎配置区附近——用户在这里切模型，导入失败时最自然来此找原因。

## Risks / Trade-offs

- **[复用 `failed` 表示中断，存储态不精确]** → UI 层按 `adapterId` 翻译展示语义；ledger 的状态机不动。若将来第三个消费者也需要"中断"语义，再提升为枚举值（那时改是一处，现在改是牵动 `isActive`/`prune`/三处 UI 筛选 + 既有测试）。
- **[进程退出即请求断，用户仍可能白等]** → 这是基础设施上限，不是本次能解的。缓解：① 开始前告知工作量（决策：弹窗补提示）；② 失败/中断记录可查 + 手动重试；③ spec 明确"关窗可继续"这条真实可用的路径，让用户知道关窗比退出安全。
- **[预计耗时无法按字数精确推]** → 文本被硬截断（约束 4），且模型速度不可知。只给"两遍 × 每遍最长 4 分钟 × 最多 3 次尝试"的构成说明，不给具体分钟数承诺——给一个达不到的预估比不给更糟。
- **[`_processNovelContent` 改签名会牵动两个调用点]** → 只有 `_importNovelFromLibrary` 与 `_importNovelFile` 两处，且都不接收其他参数。改动面小，但有测试覆盖不到的风险（面板无 widget 测试），靠 analyze + 实机验证兜住。
- **[导入任务与视频任务共用台账，条目混在一起]** → `adapterId` 分流；台账的 `allEntries()` 消费者（分镜看板 `_CloudTaskSection`）需要过滤掉 novel-import 条目，否则看板的"云端任务"区会出现小说导入。**这是本次改动最容易漏的一处**，tasks 里单列。

## Migration Plan

无数据迁移。实施顺序：

1. 服务层：`NovelImportTaskService`（阶段推进 + 进度流 + ledger 记录 + 恢复标记）。
2. 台账分流：`VideoTaskRecovery` 显式跳过 novel-import；`_CloudTaskSection` 过滤。
3. UI：`idea_incubator_panel` 改为委托服务 + 元数据透传 + 弹窗补耗时提示。
4. UI：`studio_shell` 顶栏指示 + 抽屉 + `_bootstrap` 调恢复。
5. AI 日志入口。
6. 测试与部署。

回滚：服务层是新增文件，UI 改动集中在两个文件；单独回滚任一层不会让既有导入链路不可用（退回"进度只在面板里"的旧行为）。

**验证要点**：切页签进度不消失；关窗重开任务仍在；重启后被标记为中断且不自动重提；分镜看板的云端任务区不出现小说导入条目；旧 `tasks.json`（无 novel-import 条目）加载正常。
