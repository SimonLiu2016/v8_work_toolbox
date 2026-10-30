## Why

短视频工坊的角色、场景、道具生成图像时，系统会在用户填写的 Prompt 之外隐式叠加大量系统级约束词（空镜锁、时代环境锚点、全景投影约束、风格锁等），用户完全无法感知这些注入层，导致无法诊断和修正生成结果（例如：场景描述为"意识空间"却因系统注入的"古建亭台楼阁"时代锚点而总是生成带有现实建筑的图片）。需要同时推进短期透明化（生成前可预览并一次性编辑完整 Prompt）与长期结构性覆盖（资产卡持久化保存各系统提示词组件的覆盖值）。

## What Changes

- **短期：生成前 Prompt 预览与编辑**：在角色三视图生成、场景（方位视角/全景母图）生成、道具图生成的界面，增加"预览最终 Prompt"按钮，展示组装完成的正向与负向完整 Prompt，并允许用户直接编辑后再提交生成请求。
- **长期：资产卡持久化系统提示词组件覆盖**：
  - `SceneCard` 新增可选字段：`systemPromptOverride`（场景方位视角生图的系统前导词覆盖）与 `panoramaSystemPromptOverride`（全景母图生图的系统前导词覆盖）。
  - `CharacterCard` / `CharacterVariation` 新增可选字段：`systemPromptOverride`（三视图生图的系统骨架词覆盖）。
  - `PropCard` 新增可选字段：`systemPromptOverride`（道具图生图的系统资产规范词覆盖）。
  - 以上覆盖字段在对应的 `PromptBuilder` 中被优先采用（覆盖时替换对应的系统默认常量；为空时回退到系统默认）。
  - 资产卡编辑界面增加可展开的"系统提示词组件"区域，按层（前导锁、环境锚、风格锁、用户词）可视化展示各组件实际值，并允许用户对系统层进行文字覆盖并持久保存。

## Capabilities

### New Capabilities
<!-- 无独立新能力 -->

### Modified Capabilities
- `ai-video-studio/scene-360-panorama-projection`: 场景 360° 全景母图与方位视角生成新增系统提示词组件覆盖字段支持与生成前 Prompt 预览/编辑能力。
- `character-turnaround-sheet`: 角色三视图生成新增系统提示词组件覆盖字段支持与生成前 Prompt 预览/编辑能力。
- `prop-cards`: 道具图生成新增系统提示词组件覆盖字段支持与生成前 Prompt 预览/编辑能力。

## Impact

- **Affected code**:
  - `lib/tools/ai_video_studio/models/studio_models.dart`：`SceneCard`、`CharacterCard`/`CharacterVariation`、`PropCard` 新增覆盖字段，含 `toJson`/`fromJson` 兼容处理。
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`：`ScenePromptBuilder`、`PropPromptBuilder`、`CharacterTurnaroundPrompt` 各 `build*` 方法接收并优先使用覆盖字段。
  - `lib/tools/ai_video_studio/ui/series_page.dart`：场景编辑弹窗（方位视角 & 全景生成按钮侧）、角色形态三视图生成界面、道具编辑弹窗各增加预览/编辑 Prompt 的交互入口与系统提示词组件面板。
- **APIs/Dependencies**: 无外部依赖变更，全部为本地数据模型与 UI 扩展，向下兼容既有 JSON 配置。
