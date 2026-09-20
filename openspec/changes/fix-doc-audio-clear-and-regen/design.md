## Context

当前状态（动机见 proposal.md）：

- **控制器无 clearDocument**：`AudioReaderController`(`audio_reader_controller.dart`) 有 `loadDocument`/`stop`/`play`/`pause`/`jumpToChunk` 等，但无方法清空 `_document`。一旦 `loadDocument` 了，`_document` 永远非 null。
- **UI 无关闭按钮**：AppBar actions 当前为「导入文档 / 网页链接 / 导出 MP3 / AI 日志 / TTS 设置」（`doc_audio_reader_page.dart:316-344`），无"关闭文档"。
- **缓存键不含配置**：`AudioCacheManager` 按 `(docId, chunkIndex)` 定位（`audio_cache_manager.dart:45-69`），`isChunkCached` 只看这两个维度。`findExistingChunkFile` 找到旧文件即命中。
- **updateConfig 不失效缓存**：`TtsCoordinator.updateConfig`（`tts_coordinator.dart:20-23`）只 `_config = newConfig; notifyListeners()`，`ensureChunkSynthesized` 仍走 `isChunkCached` 命中旧音色音频。
- **已有 clearDocCache 能力**：`AudioCacheManager.clearDocCache(docId)`（`:124-130`）已存在，直接复用。
- **customAi 合成付费**：TTS 模式含 Edge-TTS（免费）与 customAi（付费 API 调用），清缓存重合成在 customAi 下有费用——显式确认是安全选择。

## Goals / Non-Goals

**Goals:**

- 用户能清空/关闭当前文档，回到空状态。
- 用户改 TTS 音色后能用新配置重新生成当前文档语音，听到实际效果。
- 合成相关字段 vs 播放相关字段的区分清晰，语速音量变更不误清缓存。
- customAi 模式下清缓存重合成经用户显式确认，不偷偷花钱。

**Non-Goals:**

- 不改缓存键架构（不引入 configHash 到路径/查找）——走"显式清缓存"路径，避免多套音色共存导致磁盘占用翻倍。
- 不做"切回旧音色也能复用旧缓存"——清了就没了，切回需再清一次重合成，这是可接受代价。
- 不改 TTS 合成引擎本身、不改 MP3 导出流程。

## Decisions

### D1: clearDocument 放 controller，UI AppBar 加按钮

```
  AudioReaderController.clearDocument({bool clearCache = false})
  ════════════════════════════════════════════════════
  await stop()
  if clearCache && _document != null:
    await coordinator.cacheManager.clearDocCache(_document!.id)
  _document = null
  _currentChunkIndex = 0
  notifyListeners()
```

UI：AppBar 在"导出 MP3"后加 `IconButton(Icons.close_rounded, tooltip: '关闭文档')`，`onPressed: doc != null ? () => _closeDocument() : null`。`_closeDocument` 先弹轻确认（"关闭当前文档？[同时清空缓存] / [仅关闭] / 取消"），默认"仅关闭"。

**为什么放 AppBar**：和现有"导入文档/网页链接/导出 MP3"并列，动作一致性高，用户直觉能找到。

### D2: updateConfig 区分合成字段 vs 播放字段

```
  TtsSynthesisConfig 字段分类
  ════════════════════════════════════════════════════
  合成相关（变更需清缓存重合成）：
    mode, voiceId, providerId, model, speedInConfig*
  
  播放相关（变更不清缓存，播放器实时调）：
    playbackSpeed, volume
```

注：`speedInConfig` 若存在需谨慎——当前 `setSpeed` 调 `_player.setPlaybackRate`（播放器侧），不经过合成。需确认 config 里有没有"合成语速"字段（有些 TTS 引擎支持合成时指定语速）。若 config 里同时有合成语速和播放语速，合成语速归"合成相关"。

`updateConfig(newConfig)`:
```
  oldConfig = _config
  _config = newConfig
  if currentDoc != null && synthesisFieldsChanged(oldConfig, newConfig):
    弹确认对话框（见 D3）
  notifyListeners()
```

`synthesisFieldsChanged` 对比 mode/voiceId/providerId/model（+ 合成语速若有）。

### D3: 显式确认对话框（customAi 付费安全）

```
  确认对话框
  ════════════════════════════════════════════════════
  标题: "音色配置已变更"
  正文: "新配置将与当前文档已有音频不同。是否清空当前文档缓存并重新合成？
        （customAi 模式为付费 AI 调用）"
  按钮: [取消] [仅保存配置] [清空并重新合成]
```

- **取消**：不应用配置变更（恢复旧 config）
- **仅保存配置**：应用新 config + 持久化，但不清缓存（下次播放仍用旧音频，直到手动清或换文档后重新打开）
- **清空并重新合成**：`clearDocCache(currentDocId)` + 应用新 config + 重新预合成第一段

**为什么三选一而非二选一**：用户可能只想"先存下新音色偏好，下次新文档再用"——不想为当前已合成的文档付费重做。"仅保存配置"满足这个场景。

### D4: 重新合成只预取第一段，不全量

清缓存后不立即全量重合成整篇文档（可能几十段、customAi 费用高），只重新合成当前播放段（或第一段），后续按现有 `ensureAhead` 预取机制增量推进。用户点播放即触发当前段重合成。

### D5: clearDocument 与 clearDocCache 复用现有 AudioCacheManager

不新建缓存清理逻辑——`AudioCacheManager.clearDocCache(docId)` 已存在且按 docId 精准清理，直接复用。`TtsCoordinator` 需暴露 `cacheManager` 或新增 `clearDocCache` 转发方法。

## Risks / Trade-offs

- [清缓存后切回旧音色需重合成] → 可接受：用户显式选择清缓存，且 customAi 费用提示在前；Edge-TTS 免费模式下重合成无成本。
- [updateConfig 字段分类错误——误把合成语速当播放语速，或反之] → D2 明确分类 + 实现时对照 TtsSynthesisConfig 字段定义审查；若 config 无合成语速字段则更简单。
- [用户选"仅保存配置"后困惑为何听到的还是旧音色] → 确认对话框正文明确说明"仅保存不清缓存，当前文档仍用旧音频"；且下次新文档会用新配置。
- [并发：清缓存时有 inFlight 合成任务] → `clearDocCache` 前先 `_inFlightTasks.clear()`（coordinator 已有此字段），避免清完又被旧任务写回。
- [关闭文档时未停播放导致后台继续合成] → `clearDocument` 先 `stop()` 再清 `_document`，`ensureChunkSynthesized` 首行检查 `_document == null` 提前返回。

## Migration Plan

- 纯新增能力，无数据迁移。已缓存音频原样保留；用户首次使用"关闭文档"或"改配置重合成"即激活新路径。
- 回滚 = revert 代码，无状态残留。
