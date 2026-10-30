## Context

在 `lib/tools/ai_video_studio/ui/series_page.dart` 中，角色三视图生成、场景全景母图与方位切片视图生成、道具图生成曾完整接入 `AssetPromptPreviewDialog` 弹窗。
由于调试回滚意外，`series_page.dart` 回滚到了未包含上述 UI 接入的代码。底层 `AssetPromptPreviewDialog` 组件本身完整无损。

## Goals / Non-Goals

**Goals:**
- 精准复原 `series_page.dart` 中角色、场景、道具的 Prompt 预览入口与高级系统提示词覆盖卡片。
- 保留 `_PropsTabState` 中新增的 `didUpdateWidget` 响应式监听。
- 严格隔离，绝不影响并行变更 `add-mimo-style-instruction-and-voice-config`（涉及朗读与听力练习模块）。

**Non-Goals:**
- 不改变底层生图引擎与提示词拼装核心算法（`PromptAssembler` 与 `CharacterTurnaroundPrompt` 已完整就绪）。

## Decisions

### 1. 完整还原 `AssetPromptPreviewDialog.show` 联动入口
- 角色：恢复 `_previewTurnaroundPrompt(CharacterVariation variation, TurnaroundProportion proportion)`，并在操作栏放置「预览 Prompt」按钮。
- 场景：恢复 `_previewPanoramaPrompt` 和 `_previewDirectionPrompt`，并在全景母图和方位视图操作栏放置「预览 Prompt」按钮。
- 道具：恢复 `_previewPrompt`，并在道具编辑栏放置「预览 Prompt」按钮。
- 各面板底部恢复高级系统提示词组件与覆盖折叠面板。

### 2. 补丁合并策略
- 将此前捕获的完整 UI diff 与当前 `series_page.dart` 结合，同时保留刚刚加入的 `didUpdateWidget` 生命周期监听。
