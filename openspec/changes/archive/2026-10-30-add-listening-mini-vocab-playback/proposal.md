## Why

「听力练习」的词汇表（`VocabularyBrowserDialog`）已经能对单词做连续磨耳朵，但那是**模态对话框**——用户一旦关闭对话框或切到别处，朗读就中断；而**常驻迷你播放窗**（`ItListeningMiniPlayerApp`）只能播会议片段，不能播词汇。两条播放链路互不相通。

现有唯一能"边做别的事边磨耳朵"的入口是迷你窗，它却对词汇表完全封闭。这既浪费了已落盘的 TTS 词汇缓存（`vocab_tts_cache/`，对话框播过的词在磁盘上），也让"用碎片时间听单词"这个核心场景缺一个常驻载体。

## What Changes

- 新增 `VocabularyListPlayerController`（`services/`）：**主进程**侧的词汇列表播放编排，严格复刻对话框已验证的编排（停止 → 播放 → 带 4s 超时等待完成 → 1.5s 停顿缓冲 → 步进下一词，循环可选）。复用 `VocabularyStudyStore.synthesizeOrGetTtsFile`（同一磁盘缓存）与 `PronunciationAudioBackend`（独立 `AudioPlayer`）。
- `ListeningHost` 持有该 controller，暴露 `openMiniWindowWithVocab(List<String> words, {autoplay})` 与词汇模式指令路由；片段播放与词汇播放**互斥**（一方激活先停另一方）。
- `MiniPlayerState` 增加 `mode`（`clip | vocab`）、`wordIndex`、`wordCount`；`clipTitle` 复用为当前词文本，`sceneLabel` 置为「词汇」。
- 迷你窗按钮层**几乎不改**：`toggle/previous/next/toggleContinuous/close` 照发，`handleMiniCommand` 按 `mode` 分流；`speed` 按钮在 vocab 模式隐藏（词汇走 TTS 固定语速）。
- `VocabularyBrowserDialog` 头部新增 `[送入迷你播放器]` 按钮：取 `_studyStore.focusedWords`（用户已选定的**重点词汇**）的显示形态推送；`focusedCount == 0` 时禁用；点击先停对话框自身连播再送入，autoplay。
- 迷你窗在 vocab 模式关闭（`close`）时**停止**词汇播放（与片段"关闭继续播"不同——词表没有其它控制面，留着会成孤儿音频）。

## Capabilities

### New Capabilities

- `it-meeting-listening-tool`: 修改既有能力 `常驻悬浮播放窗`——迷你窗增加词汇播放模式与词汇状态展示；新增词汇表送入迷你播放器的行为。

> 注：不新建 capability 路径——本变更完全是既有 `it-meeting-listening-tool` 能力的扩展，复用同一 spec 路径做 delta。

### Modified Capabilities

- `it-meeting-listening-tool`: `常驻悬浮播放窗` 场景扩展（词汇模式）、新增「词汇表送入迷你播放器」需求。

## Impact

- **新增**：`lib/tools/it_meeting_listening/services/vocabulary_list_player_controller.dart`
- **修改**：
  - `lib/tools/it_meeting_listening/services/listening_host.dart`（持有 vocab 控制器、模式路由、`openMiniWindowWithVocab`、互斥）
  - `lib/tools/it_meeting_listening/ui/it_listening_mini_player.dart`（`MiniPlayerState.mode/wordIndex/wordCount`、vocab 渲染与 speed 隐藏）
  - `lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`（头部发送按钮）
- **测试**：新增 `VocabularyListPlayerController` 单测（注入假后端/假 store）、迷你窗 vocab 渲染 widget 测试、host 路由单测；沿用 `test/it_meeting_listening/` 既有假件。
- **不引入**新依赖（`desktop_multi_window` / `audioplayers` / TTS 引擎均已有）。
