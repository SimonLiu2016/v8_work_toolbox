## Why

在「听力练习」模块中，用户当前在词汇表（`VocabularyBrowserDialog`）与精听文稿抽屉（`TranscriptDrawer`）存在两项影响学习效率的关键体验缺失：
1. **词汇表听词链路深且缺乏列表连续听**：单词发音按钮深埋在折叠卡片内，用户无法在词汇列表界面快速点听发音，更无法像单词播放器一样按顺序连续朗读单词列表（纯英文发音磨耳朵与听音辨词）。
2. **精听文稿滚动条静止且重开不居中**：音频播放时虽然当前句有底色高亮，但由于缺乏滚动控制器与定位机制，画面不会跟随滚动，播放超出首屏后高亮行掉出视窗；每次重新打开窗口或抽屉时，文稿均停在最顶部，无法精准将当前正在朗读的句子正中间对齐呈现。

## What Changes

- **词汇表单行即点即听**：在词汇列表每行右侧提供直观的单音发音按钮 `[🔊]`，无需展开折叠卡片即可直接试听该单词发音。
- **词汇列表连续播放器（播表模式）**：
  - 在词汇表顶部提供列表朗读控制栏，包含「顺序播放 / 暂停」、「上一词」、「下一词」、「列表循环开/关」与当前播词进度（如 `5/24`）。
  - 采用纯英文标准发音（选项 A），单词播毕后自动保留停顿缓冲（默认 1.5 秒）并自动步进至下一词。
  - 自动作用于当前筛选视图（全部词汇、重点关注、搜索结果）。
  - 连续播放时，词汇列表自动高亮当前词并平滑滚动保持在视窗可视区域。
- **精听文稿滚动跟随与居中定位**：
  - 将 `TranscriptDrawer` 升级为 `StatefulWidget`，引入 `ScrollController` 并建立每轮对话索引对齐通道。
  - **初次/重新打开强制居中**：在窗口/抽屉初次构建或重新打开时（`addPostFrameCallback`），依据当前正在播放的 `currentTurnIndex`，精准将当前句以 `alignment: 0.5` 滚动至视窗垂直正中央。
  - **播放中平滑跟随**：随着音频播放跨越至新句子，自动平滑滚动对齐。
  - **手动滚动防冲突**：当用户主动向上/向下滚轮翻阅其他段落时，暂停自动强抢视野，并在右下角浮现快捷药丸按钮 `[ ⬇ 回到正在朗读句 ]`；点击后立即平滑居中并恢复跟随。

## Capabilities

### Modified Capabilities

- `it-meeting-listening-tool`: 扩展词汇表发音播放机制（支持单行直接点听与当前列表连续朗读播放器），并完善精听文稿滚动控制器生命周期（初次/重开强制居中与播放平滑跟随）。

## Impact

- **UI 组件**：
  - [`lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart)：新增列表播放控制栏、单行发音按钮、连续播放步进调度器与可视区域滚动。
  - [`lib/tools/it_meeting_listening/ui/transcript_drawer.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/it_meeting_listening/ui/transcript_drawer.dart)：重构为 `StatefulWidget`，挂载 `ScrollController`，实现生命周期居中定位与手动翻阅悬浮按钮。
- **测试**：在 `test/it_meeting_listening/` 新增针对词汇列表连续播放与文稿居中滚动定位的单元/组件测试。
- **依赖与存储**：完全复用已有的本地 TTS 合成与音频播放能力（`VocabularyStudyStore`、`AudioPlayer`），无新增第三方包依赖。
