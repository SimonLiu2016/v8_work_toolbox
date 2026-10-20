## Context

见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 修复大段并发生成时多任务对 `storyboard.json` 的并发写覆盖 Bug，并自愈恢复已存在磁盘但丢失引用的历史成片。
- 在「任务队列」或云端抽屉中点击「重新取回」后，自动将产物写回剧集数据，并刷新分镜看板展示已生成视频。
- 修复剧本工作台在切换非空剧集时，因无 Key 导致 Flutter 复用旧 `FormFieldState` 的界面假死 Bug。
- 在任务队列中支持一键转到 Agnes 试炼场，全量还原调用现场（提示词、模型、参数、参考图），支持用户就地修改并重发。
- 为 `AssetLibrary` 增加变更通知流，使「收进资产库」能跨页面自动实时响应；优化入库命名与封面。

**Non-Goals:**
- 不重构云端适配器与底层协议（保持 Agnes/SenseAudio 既有契约）。
- 不破坏试炼场现有的普通对话与历史快照留痕机制。

## Decisions

### 1. 采用「最新状态重载 + 串行保存锁（Serialized Atomic Save）」模式
- **方案选择**：
  在 `SegmentVideoGenTask.run` 中，视频生成完成前保持长异步轮询；一旦生成完毕需要写回时，**重新调用 `manager.readEpisode(seriesId, episodeId)`** 读取磁盘最新状态，仅更新本 `segmentId` 对应的项并保存。
  同时在 `StudioProjectManager` 中针对同一集引入异步写入链（`_writeChains[episodeKey]`），确保并发写盘时互斥串行化，彻底消除写覆盖。

### 2. 磁盘成片自愈重连（Self-Healing Auto-Reconnect）机制
- **方案选择**：
  在 `StudioProjectManager.readEpisode` 加载剧集以及分镜看板初始化时，对全部 `segments` 做一次快速的磁盘文件存在性校验：
  若 `segment.clipPath == null`，但 `File('$segmentsDir/${segment.id}.mp4').existsSync()` 且大小有效，自动修复为 `segment.copyWith(clipPath: '${segment.id}.mp4', status: SegmentStatus.done)` 并执行静默回写。
  这样像第一集第 3 大段这类因历史并发被抹掉引用的成片，无需用户重新跑，只要一打开看板就会秒级自愈复原！

### 3. 复用统一的 `writeBack` 回写与分镜看板刷新通知
- **方案选择**：
  将 `VideoTaskRecovery._writeBack` 开放为公共静态/实例方法。在 `_CloudTaskTile._refetch` 成功下载视频后，调用此方法将 `clipPath` 回写入对应的大段或分镜，并调用穿透传入的 `onReloadBoard` 回调，触发分镜看板 `_reload()` 重新渲染。

### 4. 剧本工作台表单元素绑定唯一 `Key`
- **方案选择**：
  在 `ScreenplayPanel` 中：
  - 为整个场景列表赋予 `key: ValueKey(ep.id)`；
  - 为每一个 `_buildSceneCard` 赋予 `key: ValueKey('${ep.id}_${scene.id}')`；
  - 保证切换集数时，Flutter 元素树能够识别出 Widget 节点的变更，彻底销毁上一集的 `FormFieldState` 并重新执行 `initState`，完整呈现新剧集的文本内容。

### 5. 任务调用快照与试炼场草稿桥接（Task-to-Playground Bridge）
- **方案选择**：
  - 在 `VideoTaskLedgerEntry` 中增加 `requestSnapshot`（JSON Map），在 `adapter.generateVideo` 或 `record` 时捕获提交给后端的结构化参数：`channel`, `providerId`, `model`, `prompt`, `durationSec`, `aspectRatio`, `sizeTier`, `mode`, `referencePaths`。
  - 在 `PlaygroundStore` 中增加持久化草稿槽（`setDraft(PlaygroundDraft draft)` 与 `consumeDraft()`）。
  - 在 `_CloudTaskTile` 上添加「试炼场调试」按钮，点击时将该快照存为草稿，并调起试炼场窗口（或直接跳转打开 `PlaygroundPage`）。试炼场在初始化时检查并预载草稿，将提示词、参数和参考图全部自动填充入框。

### 6. `AssetLibrary` 单例提供响应式广播流与语义化命名
- **方案选择**：
  在 `AssetLibrary` 中增加 `final _controller = StreamController<List<StudioAsset>>.broadcast()`，在每次 `_persist()` 或 `addAsset` 完成后广播当前最新列表，`AssetLibraryPage` 监听该流。
  收进资产库时按 `[<剧集名> 第<X>集] 大段 <N> 视频` 规则生成可读名称，并优先复用关键帧/参考图作为封面海报。

## Risks / Trade-offs

- **[并发写入串行化开销]** → 写入操作耗时仅几毫秒，针对同一集串行化开销可忽略。
- **[草稿持久化跨进程传输]** → 通过 `AppPaths` 目录下的 JSON 草稿文件交换数据，无论试炼场是同进程组件还是 `desktop_multi_window` 子窗口均能 100% 稳定读取。
