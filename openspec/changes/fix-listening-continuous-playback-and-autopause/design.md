# Design: 修复听力练习连续播放失效与句间停顿隐式残留问题

## 1. 架构与控制流设计

### 1.1 `ListeningPlayerController` 生命周期重置
在 `lib/tools/it_meeting_listening/services/listening_player_controller.dart` 中：
- `play(ListeningClip clip, ...)`：
  - 检查是否切换了不同的素材 `_currentClip?.id != clip.id`，或无论何时执行重新点播新的片段时，重置：
    ```dart
    _autoPause = false;
    _lastAutoPausedTurnIndex = null;
    ```
  - 对外提供清晰的 `setAutoPause(bool value)` 与 `isAutoPause` getter。

### 1.2 `WorkspacePlayerBar` 控制栏交互优化
在 `lib/tools/it_meeting_listening/ui/workspace_player_bar.dart` 中：
- **区分列表连播与句间停顿**：
  - 列表连播按钮文案从“连续播放（场景内循环）”改为更准确清晰的提示：“自动连播下一条（列表循环）”，图标保持或优化提示 Tooltip。
  - 无论 `isMeeting` 与否，若 `player.isAutoPause` 为 `true`，在控制栏中央或右侧显著呈现状态指示胶囊：
    `[⏸ 句间停顿跟读中 | 点击恢复连播]`
  - 用户轻点该胶囊即可执行 `player.setAutoPause(false)`，如果当前正处于暂停状态，可一并调用 `player.resume()`，立刻恢复整篇连续收听。
  - 在会议模式下的“跟读停顿”按钮保持同步状态与交互。

## 2. 交互一致性与容错
- 当用户进入公开素材库（`isMeeting == false`）或普通播放时，默认绝不会因为前一次练习残留 `_autoPause` 而产生困惑的单句卡顿。
- 用户可以随时明确知晓：
  1. “我是在一句一句停顿跟读吗？”（是的话，控制栏有醒目胶囊提示，且能一键关掉）
  2. “当前这篇放完后，会自动切下一篇吗？”（由“自动连播下一条（列表循环）”控制）
