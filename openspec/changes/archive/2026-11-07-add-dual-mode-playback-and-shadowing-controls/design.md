# Design: 听力练习解耦双维度控制（篇级三态循环模式与全场景句级跟读停顿）

## 1. 模型与枚举定义
在 `lib/tools/it_meeting_listening/models/listening_models.dart` 中新增：
```dart
enum ListeningLoopMode {
  orderOnce('order-once', '单篇播放', '播完即止，不自动切下一首'),
  listLoop('list-loop', '列表连播', '播完自动切下一篇素材'),
  singleLoop('single-loop', '单篇循环', '播完后反复重听当前篇');

  final String id;
  final String label;
  final String description;

  const ListeningLoopMode(this.id, this.label, this.description);
}
```

## 2. 控制器状态与行为 (`ListeningPlayerController`)
- 新增 `ListeningLoopMode _loopMode = ListeningLoopMode.orderOnce;`
- 提供 `ListeningLoopMode get loopMode => _loopMode;`
- 提供 `void setLoopMode(ListeningLoopMode mode)` 与 `ListeningLoopMode cycleLoopMode()`：
  ```dart
  ListeningLoopMode cycleLoopMode() {
    switch (_loopMode) {
      case ListeningLoopMode.orderOnce:
        _loopMode = ListeningLoopMode.listLoop;
        break;
      case ListeningLoopMode.listLoop:
        _loopMode = ListeningLoopMode.singleLoop;
        break;
      case ListeningLoopMode.singleLoop:
        _loopMode = ListeningLoopMode.orderOnce;
        break;
    }
    notifyListeners();
    return _loopMode;
  }
  ```
- 兼容保留 `bool get isContinuous => _loopMode == ListeningLoopMode.listLoop;`
- 在 `_onComplete()` 中：
  ```dart
  if (_loopMode == ListeningLoopMode.singleLoop && _clip != null) {
    await seek(0);
    await resume();
  } else if (_loopMode == ListeningLoopMode.listLoop && _queue.isNotEmpty) {
    await next(filePathFor: defaultFilePathFor);
  } else {
    _state = ListeningPlaybackState.stopped;
    notifyListeners();
  }
  ```
- 在 `setAutoPause(bool)` 中，明确支持全场景切换，并在切换素材时如果未特别锁定，保持安全状态。

## 3. UI 呈现 (`WorkspacePlayerBar`)
- **篇级流转三态按钮**：
  - `ListeningLoopMode.orderOnce`:
    - 图标：`Icons.arrow_right_alt_rounded`（单向箭头）
    - 颜色：`textSecondary`
    - Tooltip: `播放模式：单篇播放（播完即止，不自动切下一首）`
  - `ListeningLoopMode.listLoop`:
    - 图标：`Icons.repeat_rounded`（列表循环）
    - 颜色：`accent`
    - Tooltip: `播放模式：列表连播（播完自动切下一篇）`
  - `ListeningLoopMode.singleLoop`:
    - 图标：`Icons.repeat_one_rounded`（单曲循环）
    - 颜色：`accent`
    - Tooltip: `播放模式：单篇循环（反复重听当前篇）`
  - 点击时调用 `player.cycleLoopMode()`，并通过传入的回调或内部机制提示 Toast。

- **句级跟读模式开关（胶囊）**：
  - 当 `player.isAutoPause == false`：
    - 渲染轻量线框胶囊：`[💬 畅听]`
    - Tooltip: `当前为整篇畅听，点击开启逐句停顿（影子跟读留白）`
    - 点击调用 `player.setAutoPause(true)`
  - 当 `player.isAutoPause == true`：
    - 渲染醒目橙色高亮胶囊：`[⏸ 逐句跟读]`
    - Tooltip: `当前开启了逐句跟读停顿，每句播完自动暂停留白。点击恢复整篇畅听`
    - 点击调用 `player.setAutoPause(false)` 并自动 resume
  - 单句 A-B 循环指示器 `[🔂 第 X 句循环 ✕]` 保持独立存在，优先级高于通用自动停顿。
