## Why

文档语音朗读功能存在两个体验缺口：(1) 打开文档后无法清空/关闭当前文档——`AudioReaderController` 只有 `loadDocument`/`stop`/`play`，无 `clearDocument`，UI 也无对应按钮，文档一旦载入只能靠导入新文档覆盖；(2) 调整 TTS 音色配置后无法用新配置重新生成已打开文档的语音——`TtsCoordinator.updateConfig` 只改 `_config` 字段不清缓存，且缓存键 `(docId, chunkIndex)` 不含配置指纹，旧音色合成的音频被 `isChunkCached` 当作命中直接复用，用户换音色后听到的仍是旧音色。

## What Changes

- **清空当前文档能力**：`AudioReaderController` 新增 `clearDocument()`（停止播放 + 清空 `_document` + 可选清该 doc 缓存）；UI AppBar 在"导出 MP3"旁新增"关闭文档"按钮（仅文档已载入时可用），关闭后回到空状态引导卡片。
- **改 TTS 配置后重新生成**：`TtsCoordinator.updateConfig` 区分**合成相关字段**（mode/voice/音色/provider/model）与**播放相关字段**（语速/音量）——仅合成相关字段变更时，若当前有已打开文档，弹显式确认对话框"音色变更将清空当前文档缓存并重新合成，是否继续？"，用户确认后 `clearDocCache(currentDocId)` + 重新预合成；语速/音量变更不清缓存（它们是播放器侧实时调节，不经过合成）。显式确认而非隐式清空，因为 customAi 模式合成是付费 AI 调用，用户应知道"改音色 = 重新花钱合成"。
- **缓存键不变**：仍为 `(docId, chunkIndex)`——本变更走"显式清缓存 + 重合成"路径，不引入配置指纹到缓存键（避免多套音色共存导致磁盘占用翻倍）。清缓存后旧音色音频消失，切回旧音色需再清一次重合成，这是可接受的代价。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `doc-audio-reader`: 新增"清空当前文档"与"TTS 配置变更后重新合成"行为需求；修改"TTS configuration persistence"需求，补充配置变更后的缓存失效与重新合成语义。

## Impact

- **代码**：`lib/tools/reader/services/audio_reader_controller.dart`（`clearDocument`）；`lib/tools/reader/services/tts_coordinator.dart`（`updateConfig` 区分字段 + `clearDocCache` 调用）；`lib/tools/reader/ui/doc_audio_reader_page.dart`（AppBar 关闭文档按钮 + 配置变更确认对话框）。
- **行为兼容**：正常播放/缓存命中路径零变化；仅新增清空能力与配置变更后的显式重合成。无 BREAKING。
- **安全**：customAi 模式合成付费，显式确认防误触发；清缓存仅作用于当前文档目录，不影响其他文档。
