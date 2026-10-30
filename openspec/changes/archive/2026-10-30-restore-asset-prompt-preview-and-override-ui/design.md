## Context

在之前的变更中，因调试弹窗顶部安全边距与按钮溢出时误执行了对 `series_page.dart` 的还原命令（`git checkout lib/tools/ai_video_studio/ui/series_page.dart`），导致本已开发完毕的生图提示词预览及系统覆盖面板在 UI 层丢失。
底层数据模型（`studio_models.dart`）与组装算法（`prompt_assembler.dart`）以及通用对话框（`asset_prompt_preview_dialog.dart`）均完整保留，因此本次设计直接针对 `series_page.dart` 将这三处丢失的 UI 入口与控制器绑定精准复原。

## Goals / Non-Goals

**Goals:**
- 在 `series_page.dart` 中恢复引入 `asset_prompt_preview_dialog.dart`。
- 在 `_SceneEditorSheetState` 中：
  - 恢复 `_systemPromptOverride` 和 `_panoramaSystemPromptOverride` 两个控制器与保存/释放逻辑。
  - 恢复 `_previewPanoramaPrompt` 和 `_previewDirectionPrompt` 两个预览方法，弹出 `AssetPromptPreviewDialog` 并支持以预览修改后的 Prompt 触发真实生图。
  - 在全景母核操作栏和方位视角按钮栏恢复“预览 Prompt”按钮。
  - 在底部恢复 `_buildSystemPromptOverrideCard` 高级折叠面板。
- 在 `_PropEditorSheetState` 中：
  - 恢复 `_systemPromptOverride` 控制器与保存/释放逻辑。
  - 恢复 `_previewPrompt` 方法，弹出 `AssetPromptPreviewDialog`。
  - 在操作栏的“生成道具图”旁恢复“预览 Prompt”按钮。
  - 在底部恢复 `_buildSystemPromptOverrideCard` 高级折叠面板。
- 在 `_CharacterCardState` / 形态编辑中：
  - 恢复三视图生成的 Prompt 预览入口与形态骨架覆盖逻辑。

**Non-Goals:**
- 不变动既有数据模型定义或数据库/JSON 文件结构（已向下兼容且未损坏）。
- 不破坏已经修好的顶部安全避让（`useSafeArea: true`、`SafeArea`）和操作栏防溢出（`Wrap`）。

## Detailed Design

### 1. 场景编辑弹窗恢复
- **预览方法**：`_previewPanoramaPrompt` 与 `_previewDirectionPrompt(SceneDirection dir)`。
  - 组装 `PromptComponentLayer`（包含系统空镜锁、全景投影规范、时代环境锚点、风格负向词、用户描述等不同色彩标签）。
  - 调用 `AssetPromptPreviewDialog.show(...)`，若用户点击“以此 Prompt 生成”，直接调用内部实际适配器发起 `adapter.generate` 并将结果回填到当前场景方位/全景路径。
- **高级折叠面板**：`_buildSystemPromptOverrideCard()` 采用 `ExpansionTile`，内含 `systemPromptOverride` 和 `panoramaSystemPromptOverride` 两个 TextField。

### 2. 道具编辑弹窗恢复
- **预览方法**：`_previewPrompt`。
  - 组装单品资产规范、时代材质风格、正向描述、负向守卫四层组件。
  - 弹出 `AssetPromptPreviewDialog`，支持以此 Prompt 直接生成道具图并落入道具资产目录。
- **操作栏按钮**：在 Wrap 布局中排列 `[添加参考图] [从资产库选择] [尺寸档位] [预览 Prompt] [生成道具图]`。
- **高级折叠面板**：包含单品资产规范前导词输入框。

### 3. 角色三视图恢复
- 在三视图生成行加入预览入口，将角色外貌、形态、服装与标准三视图排版骨架清晰分层展现。
