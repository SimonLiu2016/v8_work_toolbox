## Why

在之前的变更执行中，由于调试弹窗顶部安全边距与按钮溢出时误执行了对 `series_page.dart` 的单文件检出回滚操作，导致已在模型层（`studio_models.dart`）和算法层（`prompt_assembler.dart`）完整支持的“提示词预览与系统提示词覆盖”功能在 UI 交互层意外丢失。用户无法在“IP主库”的道具、场景以及角色编辑中预览组装后的完整 Prompt，也无法展开系统提示词组件卡片进行自定义覆盖。

本变更旨在将丢失的 UI 交互（Prompt 预览按钮、组件层级拆解与系统提示词持久化覆盖面板）完整精准复原到 `series_page.dart` 中。

## What Changes

1. **场景库 UI 复原**：
   - 全景母图生成操作区恢复“预览 Prompt”入口，调用 `AssetPromptPreviewDialog`。
   - 方位切片视角生成操作区恢复“预览 Prompt”入口。
   - 场景编辑面板底部恢复“系统提示词组件与覆盖 (高级)”可折叠配置卡片，支持修改与持久化 `systemPromptOverride`（空镜底板规范词覆盖）和 `panoramaSystemPromptOverride`（全景母图透视规范词覆盖）。
2. **道具库 UI 复原**：
   - 道具编辑操作栏在“生成道具图”旁恢复“预览 Prompt”按钮。
   - 道具编辑面板底部恢复“系统提示词组件与覆盖 (高级)”可折叠配置卡片，支持修改与持久化 `systemPromptOverride`（单品资产规范词覆盖）。
3. **角色形态 UI 复原**：
   - 角色三视图生成操作区恢复“预览 Prompt”按钮。
   - 角色形态高级配置区恢复系统骨架与排版约束覆盖卡片。

## Capabilities

### New Capabilities
<!-- 无新增能力 -->

### Modified Capabilities
- `ai-video-studio/scene-360-panorama-projection`: 明确场景全景母图与方位视角生图在 UI 层必须提供 Prompt 预览入口与系统提示词持久化覆盖卡片。
- `prop-cards`: 明确道具资产卡在 UI 层必须提供生图 Prompt 预览入口与系统资产规范词持久化覆盖卡片。
- `character-turnaround-sheet`: 明确角色三视图生图在 UI 层必须提供 Prompt 预览入口与系统骨架排版约束持久化覆盖卡片。

## Impact

- `lib/tools/ai_video_studio/ui/series_page.dart`: 恢复导入 `asset_prompt_preview_dialog.dart`，补齐场景、道具、角色的预览方法、状态字段与覆盖面板。
- 不影响底层数据模型序列化与 Prompt 组装逻辑（相关逻辑此前已就绪）。
