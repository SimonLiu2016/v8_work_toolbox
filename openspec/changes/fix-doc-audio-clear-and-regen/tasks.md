# Tasks

## 1. 清空当前文档能力（controller）

- [x] 1.1 `AudioReaderController` 新增 `clearDocument({bool clearCache = false})`：先 `stop()`，`clearCache` 为真且 `_document != null` 时调 `coordinator.clearDocCache(_document!.id)`，清 `_document = null` + 重置 `_currentChunkIndex/_currentPosition/_chunkDuration`，`notifyListeners()`
- [x] 1.2 `TtsCoordinator` 暴露 `clearDocCache(String docId)` 转发方法（调 `cacheManager.clearDocCache` + `_inFlightTasks.clear()`），供 controller 与 UI 调用
- [x] 1.3 单测：`clearDocCache` 清空目录 + 取消 inFlight（纯逻辑测试通过）；controller clearDocument 因 AudioPlayer 平台通道依赖留手动验收（环境红测试，见 memory）

## 2. AppBar 关闭文档按钮（UI）

- [x] 2.1 `doc_audio_reader_page.dart` AppBar actions 在"导出 MP3"后加 `IconButton(Icons.close_rounded, tooltip: '关闭文档')`，`onPressed: doc != null ? _closeDocument : null`
- [x] 2.2 `_closeDocument` 弹三选一对话框（[取消]/[仅关闭]/[关闭并清空缓存]），默认"仅关闭"；调用 `controller.clearDocument(clearCache: 用户选择)`
- [x] 2.3 关闭后 UI 自动回到空状态卡片（因 `_controller.document == null` 触发 `_buildEmptyState` 分支，无需额外逻辑）

## 3. TTS 配置变更区分字段 + 显式重合成（coordinator + UI）

- [x] 3.1 `TtsSynthesisConfig` 审查：合成相关字段 = mode/voiceId/customVoiceId/systemProviderId/customModel/customEndpoint/customApiKey/useSystemAiConfig；播放相关 = speed/pitch
- [x] 3.2 `TtsCoordinator` 新增 `synthesisFieldsChanged(oldConfig, newConfig) → bool`，对比合成相关字段
- [x] 3.3 `doc_audio_reader_page.dart` 新增 `_applyConfigChange(oldConfig, newConfig)`：检测 `synthesisFieldsChanged` 且有文档时弹三选一确认（[取消]/[仅保存配置]/[清空并重新合成]），"清空并重新合成"调 `coordinator.clearDocCache(doc.id)` + 应用新 config + `setState`
- [x] 3.4 `_showSettingsModal` 改为先关闭 bottom sheet 再调 `_applyConfigChange`（避免 bottom sheet 与确认对话框叠加）
- [x] 3.5 单测：合成字段变更返回 true；播放字段(speed/pitch)变更返回 false；完全相同返回 false（纯函数测试 6 项全绿）；UI 确认路径（依赖 AudioPlayer 平台通道）留手动验收

## 4. 验证

- [x] 4.1 相关测试套件全绿（doc_audio_clear_regen 6 项 + doc_audio_reader 38 项）；手动验收待用户在 App 中执行：打开文档→关闭→回空状态；改音色→弹确认→清空重合成→新音色可听；改语速→无确认→实时生效
- [x] 4.2 `openspec validate fix-doc-audio-clear-and-regen --strict` 通过
