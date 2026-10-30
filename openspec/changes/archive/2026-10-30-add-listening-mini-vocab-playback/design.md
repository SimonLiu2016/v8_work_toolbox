## Context

迷你播放窗（`ItListeningMiniPlayerApp`）是独立 Dart isolate，只能渲染状态 + 发指令；**播放状态必须在主进程**（design D7，见 `it_listening_mini_bridge.dart` 头注释）。因此"迷你窗播词汇"的编排必须住进主进程的 `ListeningHost`，迷你窗侧只复用现有按钮层。

词汇表对话框（`VocabularyBrowserDialog`）已有一套经测试验证的连播编排（`_playWordAtContinuousIndex` / `_playWordTtsAndWait`，见 `add-listening-vocab-player-and-transcript-center-scroll` 变更）。但它与滚动静居中、逐词失败标记（`_failedTtsKeys`）、`_visibleEntries()` 高度耦合，不适合直接搬给迷你窗。

## Goals / Non-Goals

**Goals:**
- 主进程侧提供词汇列表播放编排，迷你窗能进入词汇模式并顺序朗读重点词汇。
- 片段播放与词汇播放互斥（无重叠音频）。
- 词汇表对话框提供「送入迷你播放器」入口，复用已落盘的 TTS 磁盘缓存。

**Non-Goals:**
- 不重构对话框既有的连播逻辑（保持其滚动静居中/失败标记不变）。
- 不改 `VocabularyStudyStore` 的持久化结构（完全复用 `synthesizeOrGetTtsFile` / `ttsCacheKey`）。
- 不引入新依赖；不改片段播放链路（`ListeningPlayerController`）。
- 不在词汇播放中加变速（TTS 固定语速）。

## Decisions

### Decision 1: 主进程新增 `VocabularyListPlayerController`，而不是把编排塞进迷你窗

迷你窗无法持有播放状态（跨 isolate 无共享内存），且窗口随时可能被关闭；词汇播放必须由主进程 `ListeningHost` 持有，与片段 controller 同级。

**备选**：抽公共 controller 让对话框与迷你窗共用 → 需要把滚动静居中/逐词失败标记/`_visibleEntries` 重构成回调注入，牵动 3 个测试文件，爆炸半径大。本需求不值得，放弃。

### Decision 2: 严格复刻对话框已验证的编排，而非重新发明

`VocabularyListPlayerController` 复制 `_playWordTtsAndWait` 的链路：停止 → `synthesizeOrGetTtsFile`（磁盘缓存）→ `playFile` → 等待 `onPlayerComplete`（带 4s 超时兜底）→ 1.5s `Timer` 停顿缓冲 → 步进下一词。复用 `VocabularyStudyStore`（同 `vocab_tts_cache/`，对话框播过的词零合成延迟）与 `PronunciationAudioBackend`（独立 `AudioPlayer`，避免与片段播放器争抢）。循环开关 `_continuousLoop` 语义与对话框一致。

**备选**：直接复用对话框实例 → 对话框是模态、生命周期与迷你窗不同，且无法跨 isolate，放弃。

### Decision 3: 迷你窗状态加字段，按钮层尽量不动

`MiniPlayerState` 加 `mode`（`clip|vocab`）、`wordIndex`、`wordCount`；`clipTitle` 复用为当前词文本、`sceneLabel` 置「词汇」。迷你窗按钮照发 `toggle/previous/next/toggleContinuous/close`；`handleMiniCommand` 按 `mode` 分流到片段 controller 或 vocab controller。`speed` 按钮在 vocab 模式隐藏（不渲染 `_speedButton`）。`_pushStateToMini` 按当前激活模式组装状态。

### Decision 4: 互斥与关闭语义

- 启动词汇播放（`openMiniWindowWithVocab`）→ 先 `controller.pause()`（片段）。
- 从主窗口/热键启动片段播放 → `vocabPlayer.stop()`。在 `ListeningHost` 里对片段 controller 的 `notifyListeners` 监听里检测"片段被激活"来停词汇（或用显式钩子）；实现时选侵入最小的。
- 迷你窗 vocab 模式点 `close` → `vocabPlayer.stop()` 再隐藏（与片段"关闭继续播"不同——词表无其它控制面，留着会成孤儿音频）。

### Decision 5: 发送入口取「重点词汇」显示形态

对话框「送入迷你播放器」按钮读取 `_studyStore.focusedWords`，逐词用 `widget.index.display[word] ?? word` 还原展示形态，过滤空词；`focusedCount == 0` 时禁用并提示。

## Risks / Trade-offs

- **[两个 store 同刻合成同一未缓存词]** → 均写临时文件再 `rename` 到目标，同键幂等；极端竞态可能各自合成一次，磁盘缓存命中后无害。接受。
- **[`_pushStateToMini` 与 vocab 状态耦合]** → 迷你窗未连接时 `pushState` 抛异常被 catch 忽略（现有模式），vocab 模式同样安全。
- **[词汇模式关闭会停播]** → 用户可能误以为"关闭即继续"（片段语义）；迷你窗 vocab 模式在状态里以「词汇」标识区分，且关闭 tooltip 保持"关闭悬浮窗"。接受，属 spec 明确行为。
- **[编排与对话框重复 ~100 行]** → 对话框那条已测试且带专属耦合，刻意不复用；若将来第三处需要，再抽公共。

## Open Questions

无（两个待定项已在探索阶段由用户拍板：词列表取**重点词汇**、入口在**词汇表对话框内**；autoplay 与循环保留均已并入 spec/设计）。
