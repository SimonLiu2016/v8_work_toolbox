## Context

参见 `proposal.md`。目前系统在「听力练习」与「会议录音」中均基于 `audioplayers` 插件进行音频回放，但不同模块对播放速率的封装深度参差不齐：
- `WorkspacePlayerBar` 使用 `ListeningPlayerController.setSpeed`，但硬编码在 4 个档位；
- `VocabularyBrowserDialog` 和 `VocabularyListPlayerController` 依赖 `PronunciationAudioBackend`，该接口缺少倍速定义；
- `ItListeningMiniPlayerApp` 悬浮窗硬编码 `if (!isVocab)` 屏蔽了词汇模式调速；
- `MeetingPlaybackController` 已有 `setPlaybackRate` 方法但档位缺少慢速，且未持久化用户偏好。

## Goals / Non-Goals

**Goals:**
- 提供跨工具一致的标准倍速阶梯（`0.5x, 0.75x, 0.85x, 1.0x, 1.25x, 1.5x, 1.75x, 2.0x`）。
- 打通「听力练习」中词汇浏览（单词发音、例句朗读）、词汇连播磨耳朵以及迷你悬浮窗的全场景调速，支持慢速精听和快速扫视。
- 在「会议录音」中补齐慢速精听选项，并在配置中持久化用户的播放倍速习惯。
- 保持 `PronunciationAudioBackend` 与 `MeetingAudioPlayer` 的设备抽象清晰，单元测试无真机音频依赖。

**Non-Goals:**
- 不改变音频离线 TTS 合成（`OpenAiTtsEngine`）产出音频文件本身的采样率与原始时长，变速均在前端播放器（AVPlayer / AudioPlayer）解码阶段由系统级变速算法（Time-Pitch）即时完成。

## Decisions

### 1. 统一的倍速阶梯定义
定义标准通用阶梯常量：
```dart
const List<double> kUniversalSpeedSteps = [0.5, 0.75, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0];
```
替换各组件内分散硬编码的倍速列表。

### 2. 扩展发音设备接口 `PronunciationAudioBackend`
在 `PronunciationAudioBackend` 接口中加入倍速协议：
```dart
abstract class PronunciationAudioBackend {
  double get playbackRate;
  Future<void> setPlaybackRate(double rate);
  ...
}
```
`AudioplayersPronunciationBackend` 内部维护 `_playbackRate`，并在 `playFile(path)` 后确保 `_player.setPlaybackRate(_playbackRate)` 立即生效。

### 3. `VocabularyListPlayerController` 连播倍速与节奏自适应
- 引入 `double _speed = 1.0` 与 `Future<void> setSpeed(double speed)`。
- 连续磨耳朵单词播放等待超时由原本固定的 4 秒调整为 `(4000 / _speed).ceil()`，停顿缓冲保持 1.5 秒不变，实现不同语速下连贯流畅的听力体验。

### 4. 迷你悬浮窗（Mini Window）跨模式双向通信
- 在 `ItListeningMiniPlayerApp` 中移除 `if (!isVocab)`，统一展示倍速选择器；
- 在 `ListeningHost` 接收 `speed:$v` 指令时，自动分发给当前处于激活状态的控制器：
  - 片段模式：分发给 `_controller.setSpeed(speed)`；
  - 词汇模式：分发给 `_vocabPlayer.setSpeed(speed)`；
- 在下发给悬浮窗的状态载荷中，词汇模式正确附带 `speed: _vocabPlayer.speed`。

### 5. `VocabularyBrowserDialog` 全局倍速胶囊
在对话框工具栏（掌握度与关注度过滤右侧）增加倍速选择胶囊：
- 切换倍速时，更新对话框内部 `_playbackSpeed` 并同步设置给 `_vocabPlayer` 和 `_backend`；
- 用户点击任意单词或例句的小喇叭图标时，直接以该倍速播放，实现全局所见即所得的变速体验。

### 6. 会议录音偏好持久化
- 在 `MeetingRecorderConfig` 中新增 `playbackRate`（默认 `1.0`）；
- 用户在行内播放器切换倍速时，通过 `MeetingRecorderStore.saveConfig` 异步持久化；
- 工具启动初始化时，`MeetingPlaybackController` 默认载入已保存的倍速偏好。

## Risks / Trade-offs

- **[倍速过快或过慢引起音频爆音/破音]** → macOS AVPlayer 原生内置专业级音频时间拉伸算法（Time-Pitch Audio Unit），在 0.5x~2.0x 区间内音调保持极其自然，不存在破音或失真风险。
- **[迷你窗通信延迟]** → 迷你窗与主进程通过轻量本地 MethodChannel 通信，延迟低于 10ms，且有状态回传校验，操作响应平滑。
