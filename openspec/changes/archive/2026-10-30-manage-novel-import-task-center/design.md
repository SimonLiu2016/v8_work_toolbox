## Context

详见 `proposal.md`。当前短视频工坊运行在 `desktop_multi_window` 独立子窗口中，由于缺乏跨重启的状态水合（Hydration）和关窗保护，用户关闭窗口重开后，正在执行或刚完成的长文本小说导入任务记录全部从内存中消失。

## Goals / Non-Goals

**Goals:**
- **跨窗口启动还原**：`NovelImportTaskService` 在启动时从 `VideoTaskLedger` 自动载入历史记录，重建 `_tasks`，支持完整追索。
- **常驻任务管理中心**：顶栏「导入任务」入口常驻，支持多状态角标与分类筛选抽屉（全部/运行中/已完成/已中断），提供产物跳转与重试。
- **创意孵化面板上下文常驻**：面板常态化感知当前剧集的最新导入任务（运行态、完成态、中断态），消除空白页面困惑。
- **关窗拦截守护**：有正在运行的导入长任务时拦截窗口关闭事件，提供二次确认。

**Non-Goals:**
- 不引入跨主子窗口的复杂 Isolate / IPC 守护进程；任务仍随子窗口生命周期运行，但通过关窗拦截预防强杀，通过断点记录支持中断重试。
- 不修改视频生成任务的既有台账结构与轮询恢复逻辑。

## Decisions

### 1. 基于 VideoTaskLedger 的双向水合（Hydration）
- **选择**：复用既有的 `VideoTaskLedger` 持久化机制，新增 `NovelImportTaskService.hydrateFromLedger()` 方法。
- **原因**：`submit`、`_finish`、`_fail` 已经严格落盘到 `task_ledger.json`，且已具备 `adapterId: 'novel-import'` 的标准格式。复用台账避免新建冗余存储文件，并能平滑兼容老任务数据。
- **状态映射**：
  - `status == completed` 映射为 `ImportPhase.done`；
  - `status == failed` 且包含“应用退出”映射为 `ImportPhase.interrupted`，其它映射为 `ImportPhase.failed`；
  - 启动时仍处于 `status == polling` 的条目自动标记为中断并回写。

### 2. 顶栏常驻「导入任务」入口与抽屉增强
- **选择**：在 `StudioShell` 顶栏将原条件渲染的 `ImportTaskBadge` 改为常驻组件 `NovelTaskCenterButton`。
- **表现**：
  - 无任务在跑：展示常规图标与“任务”文本，可随时点击打开抽屉查看历史；
  - 正在运行：展示微动旋转指示器 + 正在运行数字角标；
  - 最近有中断/失败：展示琥珀色告警小点。
- **抽屉增强**：在 `NovelTaskDrawer` 中增加分类 Tab（全部、运行中、已完成、已中断），每条卡片提供【查看产物】（自动选中剧集并跳 IP 主库/分镜）与【重试】。

### 3. 创意孵化面板（IdeaIncubatorPanel）三态常驻
- **选择**：面板不再因为局部变量为空就回落到空白表单，而是通过 `_activeTaskOrRecent` 寻找当前剧集的最近任务。
- **三态设计**：
  - **运行态（Running）**：展示阶段动画、已耗时、进度说明；
  - **完成态（Done）**：展示“最近导入产物概览”（XX集大纲、XX个角色、XX个场景），提供【查看 IP 主库】快捷按钮和【重新导入】；
  - **中断/失败态（Interrupted/Failed）**：展示醒目警告卡片，注明中断时间与原因，提供【一键重试】按钮。

### 4. 基于 WindowListener 的关窗拦截保护
- **选择**：在 `StudioShellPage` 中接入 `windowManager.addListener`，重写 `onWindowClose()`。
- **机制**：
  - 启动时调用 `windowManager.setPreventClose(true)` 开启拦截；
  - 用户触发关闭时检查 `NovelImportTaskService.instance.runningCount`：
    - 若大于 0，弹出 `AlertDialog` 提醒：“小说解构正在进行中，关闭将中断任务，确定退出吗？”
    - 若无运行任务或用户确认强行关闭，先调用 `windowManager.setPreventClose(false)` 解除拦截，再调用 `windowManager.close()` 精准退出当前子窗口，避免误调 `destroy()` 触发系统级 `NSApp.terminate` 关闭主窗口。

## Risks / Trade-offs

- **[Risk] 关窗拦截导致无法正常退出** → **Mitigation**: 仅在 `runningCount > 0` 时拦截；在确认弹窗中提供明确的「强制关闭」按钮，且无任务时直接放行。
- **[Risk] 大量历史任务导致抽屉卡顿** → **Mitigation**: 水合与展示时限制最近 50 条，并提供「清理已结束任务」按钮。
