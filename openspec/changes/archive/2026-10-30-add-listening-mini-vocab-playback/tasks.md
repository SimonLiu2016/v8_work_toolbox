## 1. 词汇列表播放编排（主进程）

- [x] 1.1 新增 `VocabularyListPlayerController`（`lib/tools/it_meeting_listening/services/vocabulary_list_player_controller.dart`）：持词列表、当前下标、循环开关与播放/暂停/步进状态；构造注入 `VocabularyStudyStore`、`PronunciationAudioBackend` 与可选的 `defaultVoiceId`。
- [x] 1.2 实现编排链路：`setWords(List<String>)` → 停止 → `synthesizeOrGetTtsFile`（磁盘缓存）→ `playFile` → 等待 `onPlayerComplete`（4s 超时兜底）→ 1.5s `Timer` 停顿缓冲 → 步进下一词（循环可选）；逐词失败以状态位上报（`failedKeys`），成功清除。
- [x] 1.3 暴露 `start({autoplay})`、`toggle`、`previous`、`next`、`stop`、`setLoop` 与只读快照（`currentWord`、`wordIndex`、`wordCount`、`isPlaying`、`isLooping`、`words`、`failedWords`）；实现 `ChangeNotifier`。

## 2. ListeningHost 集成与互斥

- [x] 2.1 `ListeningHost` 持有 `VocabularyListPlayerController`（惰性创建，默认复用 `VocabularyStudyStore` 默认基目录与 `AudioplayersPronunciationBackend`），暴露 `openMiniWindowWithVocab(List<String> words, {autoplay})` 与 `deactivateVocabPlayback()`。
- [x] 2.2 `handleMiniCommand` 增加按激活模式的分流：vocab 模式下 `toggle/previous/next/toggleContinuous` 路由到 vocab controller；`close` 先 `vocabPlayer.stop()` 再隐藏；`speed:` 在 vocab 模式忽略。
- [x] 2.3 互斥接线：`openMiniWindowWithVocab` 先暂停片段 controller；片段播放启动时停 vocab controller（在 host 内监听片段 controller 的激活，或经 `_pushStateToMini` 检测——选侵入最小的实现，保证无重叠音频）。
- [x] 2.4 `_pushStateToMini` 按当前激活模式组装状态：vocab 模式推 `mode=vocab`、`clipTitle=当前词`、`sceneLabel='词汇'`、`wordIndex/wordCount`、`playing/continuous=循环`；clip 模式推现有字段且 `mode=clip`。

## 3. 迷你窗词汇模式渲染

- [x] 3.1 `MiniPlayerState` 增加 `mode`（`clip|vocab`，默认 `clip`）、`wordIndex`、`wordCount`，`fromMap/toMap` 同步。
- [x] 3.2 迷你窗 `build` 按 `mode` 切换：vocab 模式下隐藏 `_speedButton`、`clipTitle` 显示当前词、时间文本改为 `n/N` 词序；控件按钮复用现有 `_iconButton`。
- [x] 3.3 vocab 模式关闭（`close` 按钮）先发 `close` 指令（host 侧停 vocab 播放）再 `windowManager.hide()`——与片段"关闭继续播"区分。

## 4. 词汇表送入迷你播放器

- [x] 4.1 `VocabularyBrowserDialog` 头部加「送入迷你播放器」按钮（`ValueKey('vocab-send-to-mini-btn')`）：读 `_studyStore.focusedWords` → `widget.index.display[word] ?? word` 还原展示形态 → 过滤空词；`focusedCount == 0` 时禁用并提示「先标记重点词汇」。
- [x] 4.2 点击先 `_stopContinuousPlayback()`（停对话框自身连播）再 `ListeningHost.instance.openMiniWindowWithVocab(words, autoplay: true)`；失败时经 `AiLogger.logError` 落日志并提示。

## 5. 验证与本地部署

- [x] 5.1 新增 `VocabularyListPlayerController` 单测（`test/it_meeting_listening/vocabulary_list_player_test.dart`）：注入假 `PronunciationAudioBackend` 与假 `VocabularyStudyStore`（或真实 store + 临时目录），覆盖顺序步进、循环、失败上报、停止/上一词/下一词、4s 超时兜底。
- [x] 5.2 新增迷你窗 vocab 渲染 widget 测试：`mode=vocab` 时显示当前词与 `n/N`、隐藏变速控件、`close` 指令发出且窗口 `hide`。
- [x] 5.3 新增 host 路由单测（复用既有 `mini_player_widget_test.dart` 假件）：vocab 模式指令分流、`openMiniWindowWithVocab` 互斥（片段先暂停）、关闭停播。
- [x] 5.4 运行 `flutter analyze` 确保目标代码零错误、零警告。
- [x] 5.5 运行 `openspec validate add-listening-mini-vocab-playback --strict` 确保规范严格合规。
- [x] 5.6 执行 `./scripts/deploy_local.sh` 重新构建并替换本机 `/Applications/V8WorkToolbox.app`。
