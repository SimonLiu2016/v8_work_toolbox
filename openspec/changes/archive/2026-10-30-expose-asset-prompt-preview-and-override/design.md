## Context

在短视频工坊（`ai_video_studio`）中，角色三视图（Turnaround）、场景（360°全景母图与方位切片视角）以及道具（单品资产图）的生图流程分别依赖 `CharacterTurnaroundPrompt`、`ScenePromptBuilder` 以及 `PropPromptBuilder` 进行提示词组装。
当前流水线中，系统隐式叠加了大量底层约束（如空镜底板锁、时代环境锚点 `environmentAnchor`、全景透视约束 `panoHead/panoTail`、去塑料守卫等）。由于这些组件在 UI 上对用户不可见且不可控，当生成非现实空间（如"意识空间/识海"、"星空虚空"）时，系统硬编码注入的"古建亭台楼阁"、"architectural vista"等词汇会强制污染生图意图，造成模型生成建筑物等偏离预期的结果。

## Goals / Non-Goals

**Goals:**
- **短周期（即时预览与一次性编辑）**：
  - 打造通用的生图提示词预览/编辑弹窗 `AssetPromptPreviewDialog`，支持显示最终拼装的正向/负向 Prompt、词数统计、组件拆解高亮。
  - 在场景（全景母图生成、方位视角生成）、角色（形态三视图生成）、道具（道具图生成）界面的生成按钮旁提供"预览/编辑 Prompt"操作入口。
  - 用户可直接在弹窗中修改正向/负向 Prompt，点击"以此 Prompt 生成"后提交生图。
- **长周期（持久化结构性覆盖）**：
  - 在资产卡数据模型中增加系统提示词覆盖字段：
    - `SceneCard`：`systemPromptOverride`（方位视角环境前导词覆盖）、`panoramaSystemPromptOverride`（全景母图头尾透视约束覆盖）。
    - `CharacterVariation`：`systemPromptOverride`（三视图骨架/排版约束覆盖）。
    - `PropCard`：`systemPromptOverride`（道具单品规范覆盖）。
  - 在 `ScenePromptBuilder`、`CharacterTurnaroundPrompt`、`PropPromptBuilder` 中优先读取并采用覆盖值。
  - 在资产卡编辑界面中加入可折叠的"系统提示词组件"配置区，展示当前生效的系统层并支持编辑保存覆盖值。

**Non-Goals:**
- 不在此变更中改造分镜关键帧（Storyboard Keyframe）或镜头生视频（Video Generation）的提示词组装逻辑（严格限定在角色、场景、道具三大素材资产生成环节）。
- 不破坏现有配置与资产卡 JSON 兼容性（缺省时自动使用出厂默认值）。

## Decisions

### 1. 通用预览弹窗 `AssetPromptPreviewDialog` 设计
- **形态**：居中对话框，宽度适配桌面端（680px）。
- **内容区**：
  1. 提示词组件概览条：展示当前注入的各层（[系统规范锁]、[时代环境锚]、[风格锁]、[用户描述]），让用户一目了然提示词构成。
  2. 正向 Prompt（可编辑多行文本框，带字数统计与一键复制）。
  3. 负向 Prompt（可编辑多行文本框）。
- **交互动作**：
  - "还原为默认组装"：丢弃临时修改，重新由 Builder 计算最新拼装文本。
  - "以此 Prompt 生成"：关闭弹窗并以当次编辑的内容作为参数执行生图调用。

### 2. 数据模型字段扩展与 JSON 兼容
- **`SceneCard`**：
  - 增加 `String? systemPromptOverride;`
  - 增加 `String? panoramaSystemPromptOverride;`
  - 在 `copyWith`、`toJson`、`fromJson` 中增加对应字段（为空时不序列化或反序列化为 null）。
- **`CharacterVariation`**：
  - 增加 `String? systemPromptOverride;`
- **`PropCard`**：
  - 增加 `String? systemPromptOverride;`

### 3. Builder 方法签名与覆盖逻辑
- **`ScenePromptBuilder.buildPanoramaPrompt`**：
  - 增加可选参数 `String? panoramaSystemPromptOverride`。
  - 若传入且非空，替换 `panoHead` 与 `panoTail` 拼接逻辑，允许针对意识空间/非建筑空间完全自定义头尾锚点。
- **`ScenePromptBuilder.buildPositivePrompt`**：
  - 沿用已有或扩展 `sceneEnvironmentOverride` 参数，优先采用 `scene.systemPromptOverride`。
- **`PropPromptBuilder.buildPositivePrompt`**：
  - 增加可选参数 `String? systemPromptOverride`，优先于 `propAssetRequirement`。
- **`CharacterTurnaroundPrompt.buildForVariation`**：
  - 增加可选参数 `String? systemPromptOverride`，优先替换默认的 `_viewLayoutRequirement` 与 `_identityRequirement`。

### 4. UI 侧交互集成
- 在 `series_page.dart` 中：
  - 场景全景工作区：在"生成 360° 全景母图"按钮旁增加预览图标按钮；在方位视角编辑行增加预览图标按钮；在场景详情下方增加可折叠的"系统提示词组件"面板。
  - 角色形态编辑区：在"生成三视图"按钮旁增加预览入口；在形态高级配置中增加系统骨架词覆盖面板。
  - 道具编辑区：在"生成道具图"按钮旁增加预览图标按钮；在道具详情下方增加资产规范词覆盖面板。

## Risks / Trade-offs

- **风险 1：用户在预览弹窗中过度精简导致模型丧失风格约束**
  - **对策**：弹窗提供"还原为默认组装"按钮，且一次性修改不覆盖资产卡长期配置，随时可安全复原。
- **风险 2：历史资产卡 JSON 反序列化异常**
  - **对策**：所有新增字段均设为 optional，`fromJson` 中使用安全类型转换 `json['systemPromptOverride'] as String?`，老数据平滑向上兼容。
