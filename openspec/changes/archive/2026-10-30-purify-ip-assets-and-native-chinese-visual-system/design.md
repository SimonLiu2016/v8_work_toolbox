## Context

当前短剧制作中，角色资产卡、场景库以及世界观时代预设系统设计初期受到早期 Stable Diffusion / Midjourney 的影响，残留了大量英文正反向提示词、英文翻译生成阶段以及英文预设词。详见 `proposal.md`。

现代面向中文影视与微短剧制作的先进生成引擎（包括 Kling、Jimeng、Minimax、Agnes 等）对中文原生语义与长句有极其优秀的理解能力，直接输入原生中文不仅语义精确，而且排除了英文翻译的语义折损，更减少了小说拆解大纲时近 40% 的 Token 开销与延迟。

## Goals / Non-Goals

**Goals:**
- **提取端彻底中文化**：在 `AiConstraintEngine` 的小说主库提取和场景空间 7 视角解构中，全部去除英文 Prompt 字段提取，仅输出地道、高表现力的中文容貌、服饰、空间格局和构图描述。
- **预设系统纯正中文化**：重构 `VisualEraGenre.presets` 中的服饰锚点、环境锚点、道具材质锚点及负向排除词，全面采用纯中文视觉语言。
- **生图组装适配**：`CharacterTurnaroundPrompt` 与 `ScenePromptBuilder` 改为直接由角色与场景的中文特征词、时代预设中文锚点拼接组装高质量生图提示词。
- **UI 纯净化**：精简 `series_page.dart` 中的角色卡、场景卡与世界观设置，彻底移除英文 Prompt 输入框和翻译按钮。

**Non-Goals:**
- 不对旧测试剧集数据编写复杂的向下兼容迁移逻辑（用户确认测试数据随时可清空并重新导入）。
- 不破坏 `series_profile.json`、角色卡与场景卡的底层文件系统层级结构。

## Decisions

### 1. 角色资产卡数据模型简化
- **决策**：在角色卡模型与存储中，以 `facial_features_zh` 与 `default_attire_zh` 作为核心容貌外貌描述；原有字段 `facial_prompt`、`default_attire_prompt`、`base_prompt_positive`、`base_prompt_negative` 变为可选或默认留空/废弃。
- **替代方案考虑**：保留英文并由后台自动静默翻译。放弃原因：翻译增加无谓的 LLM 调用成本与延迟，且目前生成的英文 tag 质量低劣，无实际价值。

### 2. 场景空间 7 视角解构直接输出纯中文单键值对
- **决策**：`AiConstraintEngine._promptSceneSpatialDeconstruction` 要求 LLM 直接输出 `{"birds_eye_view": "中文空间描述...", ...}`，而非旧版的 `{"zh": "...", "en": "..."}`。在 `SceneDirection` 解析时兼容字符串直接作为提示词。
- **替代方案考虑**：保留双语字典。放弃原因：下游所有生图与展示均不需要英文，保留双语字典导致结构繁琐且浪费模型 Token。

### 3. VisualEraGenre 时代预设重置为高质量中式视觉词
- **决策**：5 大时代预设（`xianxia` 仙侠修真、`historical_costume` 古装历史、`republican_era` 民国年代、`urban_modern` 都市现代、`futuristic_scifi` 未来科幻）重写为纯中文结构：
  - `costumeAnchor`: 时代特定衣冠服饰、材质、发饰描写。
  - `environmentAnchor`: 时代特定地理、建筑、光影环境。
  - `propMaterialAnchor`: 时代特定器皿、道具与质感。
  - `negativeBans`: 时代严厉排除项（如仙侠禁用现代元素、塑料感等）。

### 4. UI 界面精简交互
- **决策**：
  - `_CharacterCard`: 移除英文文本框，仅展示与编辑角色的中文五官发型和服饰设定。
  - `_SceneEditorSheet`: 移除每个视角的“英文提示词 (Prompt EN)”输入框，仅保留“视角画面描述 (中文)”输入框与一键生成。
  - `_WorldviewTab`: 渲染时代预设的中文锚点及中文排除标签。

## Risks / Trade-offs

- **[风险] 既有单元测试可能断言了英文 Prompt 字段的存在**
  - **缓解策略**：同步审查并更新 `test/` 下涉及 `AiConstraintEngine`、`CharacterTurnaroundPrompt` 以及小说导入的测试用例，将期望断言调整为原生中文。
- **[风险] 某些纯海外仅支持英文的生图模型适配问题**
  - **缓解策略**：当前主力视频与图像引擎已全面转向 Kling / Jimeng / Agnes / Minimax 等支持原生中文的现代引擎；未来若有纯海外引擎需求，应由该引擎的驱动层在网络出站前做即时翻译适配，而不污染 IP 主库这一核心业务层。
