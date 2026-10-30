## Context

本设计针对「听力练习」模块中的两大核心视觉与听感体验缺陷展开：
1. 词汇表（[`VocabularyBrowserDialog`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart)）的单词点听深埋与列表播表缺失；
2. 精听文稿抽屉（[`TranscriptDrawer`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/ui/transcript_drawer.dart)）无滚动状态管理导致的滚动条静止与重开不居中。

详见 `proposal.md` 与 `specs/it-meeting-listening-tool/spec.md`。

## Goals / Non-Goals

**Goals:**
- 在 `VocabularyBrowserDialog` 的每个单词行常驻单发音按钮 `[🔊]`，即点即听。
- 在 `VocabularyBrowserDialog` 顶部提供简洁完备的「列表连续播放器」，支持顺序朗读当前筛选列表的英文单词发音（纯英文磨耳朵，选项 A），单词播毕后自动停顿 1.5 秒并步进下一词，支持循环播放与播放时居中跟随。
- 将 `TranscriptDrawer` 重构为 `StatefulWidget`，挂载 `ScrollController` 与每轮条目的对齐通道，在初次打开、窗口恢复、以及播放切句时精准以 `alignment: 0.5` 将当前朗读句居中呈现。
- 在用户手动滚轮翻阅时提供防争抢机制，并呈现悬浮快捷按钮 `[ ⬇ 回到正在朗读句 ]`。

**Non-Goals:**
- 不改变底层已有的 `VocabularyStudyStore` 与本地 TTS 缓存目录结构（完全复用已验证的 `synthesizeOrGetTtsFile` 与 `ttsCacheKey`）。
- 不在单词连播中插入中文释义语音（专注纯正英文听音辨词）。
- 不改变精听主播放器（`ListeningPlayerController`）与会议音频的烘焙流程。

## Decisions

### Decision 1: 词汇列表连续播放状态机与调度器

在 `_VocabularyBrowserDialogState` 内部封装轻量播放队列状态：
- `bool _isListPlaying = false;`
- `int _listPlayingIndex = -1;`
- `bool _isLooping = false;`
- `Timer? _stepTimer;`

**步进调度链路**：
1. 用户点击「▶ 顺序朗读列表」或点击某行右侧的发音按钮切入连续播放；
2. 调度播放第 `_listPlayingIndex` 个可见词的音频（`_visibleEntries()[index]`）；
3. 列表通过 `Scrollable.ensureVisible(key, alignment: 0.5)` 平滑滚动将该词居中；
4. 等待音频播放结束事件（`player.onPlayerComplete` 或注入的 `audioPlayerFn` 完成）；
5. 触发 1500ms 的 `Timer` 停顿缓冲（给用户耳朵消化记忆时间）；
6. 步进到 `index + 1`；若到达列表末尾且 `_isLooping == true` 则回到 0，否则停止播放并恢复就绪图标。

*替代方案考虑*：全局后台单例 vs 对话框局部状态。
词汇表是作为独立模态窗口打开的强化复习工具，用户关闭词汇表窗口时自动释放 `AudioPlayer` 与 `Timer`，避免后台意外混音，保持组件职责清晰内聚。

### Decision 2: 词汇表单行发音入口与折叠手风琴解耦

在 `_entryTile`（未展开的折叠头 Row 中）：
- 在 `entry.display` 旁边新增一个小巧的 `IconButton` / `InkWell`（图标为 `Icons.volume_up_rounded`）；
- 单击该按钮仅触发该单词的发音播放（与连续播放器联动），**不触发展开/折叠手风琴**，实现扫视列表过程中的高效点听。

### Decision 3: 精听文稿抽屉生命周期对齐与防冲突机制

将 `TranscriptDrawer` 升级为 `StatefulWidget`：
1. **渲染对齐**：使用 `Map<int, GlobalKey> _itemKeys` 记录每个 turn 容器的上下文；
2. **首次/重新打开强制居中**：在 `initState` 与第一帧渲染回调 `addPostFrameCallback` 中，若 `widget.currentTurnIndex >= 0`，立即无动画或快速动画调用 `Scrollable.ensureVisible(key.currentContext!, alignment: 0.5)`，确保抽屉展开的第一瞬间，正在朗读的那句话就在视窗最正中；
3. **播放过渡平滑跟随**：在 `didUpdateWidget` 中，检测到 `oldWidget.currentTurnIndex != widget.currentTurnIndex` 且未处于用户手动滚动干预态时，调用平滑动画（250ms, `Curves.easeInOut`）居中对齐；
4. **手动翻阅防争抢**：
   - 包装 `NotificationListener<UserScrollNotification>`；
   - 一旦监听到用户主动手势滑动（`notification.direction != ScrollDirection.idle`），标记 `_userInteracting = true`；
   - 只要处于交互干预态，音频切换句子时不再强抢滚动视野，而是在右下角浮动呈现 `[ ⬇ 回到正在朗读句 ]` 按钮；
   - 点击该按钮或切换播放条目时，重置 `_userInteracting = false` 并平滑居中。

## Risks / Trade-offs

- **[未挂载子项的滚动定位]**：当文稿非常长时，`ListView.builder` 仅挂载可视区域附近的 Widget，过远的句子其 `GlobalKey.currentContext` 可能为 `null`。
  - *缓解措施*：如果目标句的 Context 为 null，根据平均 item 高度执行一次粗估偏移 `_scrollController.jumpTo(targetIndex * estimatedHeight)`，触发目标项实例化，随后在微任务/下一帧执行精确的 `ensureVisible(alignment: 0.5)`。
- **[TTS 合成初次延迟]**：若某词首次播放需要在线合成，可能存在毫秒级等待。
  - *缓解措施*：播放按钮展示缓冲旋转图标，成功返回后继续，且本地磁盘永久缓存，二次播放零延迟。
