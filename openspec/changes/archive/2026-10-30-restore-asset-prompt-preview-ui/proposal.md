## Why

在之前的调试过程中，因单文件检出回退操作导致 `series_page.dart` 中原本已实现的“角色、场景、道具生图 Prompt 预览与微调”以及“高级系统提示词覆盖”UI 交互代码意外丢失。用户无法查看组装后的真实 Prompt，也无法编辑修改后发起生成。

本变更旨在将丢失的 UI 交互（Prompt 预览按钮、组件层级拆解与系统提示词持久化覆盖面板）完整精准复原到 `series_page.dart` 中，且严格保持其他功能模块（如 MiMo 配置、道具持久化等）不受任何影响。

## What Changes

- **角色卡 UI 复原**：在三视图生成操作栏恢复“预览 Prompt”入口，调用 `AssetPromptPreviewDialog` 展现分层结构并支持实时微调生图；在形态编辑高级区域恢复系统骨架覆盖。
- **场景库 UI 复原**：全景母图与方位切片视角生成操作区恢复“预览 Prompt”入口，并在面板底部恢复“系统提示词组件与覆盖 (高级)”折叠面板。
- **道具库 UI 复原**：道具编辑操作栏恢复“预览 Prompt”按钮，并在面板底部恢复“系统提示词组件与覆盖 (高级)”折叠面板。
- **保留既有修复**：完整保留 `_PropsTabState` 中的 `didUpdateWidget` 响应式刷新以及 MiMo 等其他并行变更。

## Capabilities

### Modified Capabilities
- `prop-cards`: 明确道具资产卡在 UI 层必须提供生图 Prompt 预览入口与系统资产规范词持久化覆盖卡片。
- `character-turnaround-sheet`: 明确角色三视图生图在 UI 层必须提供 Prompt 预览入口与系统骨架排版约束持久化覆盖卡片。

## Impact

- `lib/tools/ai_video_studio/ui/series_page.dart`: 恢复导入 `asset_prompt_preview_dialog.dart`，补齐角色、场景、道具的 Prompt 预览入口与覆盖卡片。
- 绝不修改任何 Reader、IT Meeting 听力练习相关代码，完全隔离保障 `add-mimo-style-instruction-and-voice-config`。
