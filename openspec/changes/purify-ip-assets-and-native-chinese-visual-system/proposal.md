## Why

在 AI 视频工坊当前的实现中，小说导入（`novel-import`）与资产库（`series-asset-library`）在提取角色卡、场景库以及世界观预设时，仍然包含大量的英文 Prompt 生成（如 `base_prompt_positive`、`base_prompt_negative`、`facial_prompt`、`default_attire_prompt`、场景 7 视角 `prompt_en`）以及西方 SD/Midjourney 时代的英文风格词（如 `Unreal Engine 5 render, 3D CGI animation, empty room, no humans`）。

这带来了三个核心问题：
1. **翻译失真与文化语义丢失**：国风修仙、古装玄幻等题材中的服饰（如广袖流云道袍、月白深衣）、发髻、法宝及中式建筑场景（如重檐歇山顶、青砖黛瓦），经大模型强制翻译成破碎的英文后往往语义严重失真。
2. **Token 与算力浪费**：在小说导入大纲提取和场景空间解构两个大模型调用环节中，英文 Prompt 的翻译生成占用了约 40% 的 Token，增加了响应延迟与出错概率。
3. **现代模型脱节**：当代国产主流文生图/生视频模型（如 Kling 快手可灵、Jimeng 即梦、Minimax 贝壳、Agnes 等）对原生中文具备极强的深层理解力，反而对英文逗号堆叠词（tag soup）产生排斥或生硬表现。同时，用户在 UI 界面上看到角色卡与场景库中充斥着大段英文提示词，极大地损害了交互体验与可读性。

因此，需要推行“彻底纯中文”（方案 A）的资产纯净化方案，将角色、场景、世界观及视角组装系统全面回归原生中文描述，移除无用的英文字段、英文预设与 UI 输入。

## What Changes

- **小说导入与 IP 主库提取纯净化**：
  - 更新 `AiConstraintEngine.buildNovelMasterExtractionPrompt`，角色提取仅保留 `facial_features_zh`（面部与发型）与 `default_attire_zh`（典型服饰），彻底移除 `facial_prompt`、`attire_prompt`、`prompt_positive`、`prompt_negative` 的英文生成要求。
  - 场景提取仅保留中文名称、基础环境描述与空间特征，彻底移除 `prompt_en` 英文要求。
- **场景空间 7 视角解构纯中文**：
  - 更新 `AiConstraintEngine._promptSceneSpatialDeconstruction`，各视角（俯视全景、正立面、背立面、左侧视、右侧视、特写细节、微距材质）提示词仅输出原生中文空间描述与镜头光影语言，移除 Midjourney/SD 英文提示词及 `{"zh": "...", "en": "..."}` 结构。
- **时代风格预设（VisualEraGenre）中文化**：
  - 清理 `VisualEraGenre.presets` 中的 `costumeAnchor`、`environmentAnchor`、`propMaterialAnchor` 与 `negativeBans`，全面替换为纯正的中式视觉定位词与中文负向排除词（如禁用“现代服饰、牛仔裤、现代电器、塑料感、画面糊化”等），移除英文 tag 堆叠。
- **三视图与场景生图组装适配**：
  - 重构 `CharacterTurnaroundPrompt` 与 `ScenePromptBuilder`：直接基于角色的中文容貌、服饰描述与时代预设组装中文生图提示词，移除对英文 Prompt 的依赖和校验。
- **UI 界面纯净化与输入框精简**：
  - 角色卡编辑（`_CharacterCard`）：移除英文正向/反向提示词、英文容貌/服饰文本框及“翻译成英文”按钮，界面聚焦于角色的中文设定、代表色与三视图。
  - 场景详情与空间视角编辑器（`_SceneEditorSheet`）：移除场景基础英文 Prompt 和 7 个视角的英文提示词编辑框，仅展示与编辑中文空间视角提示词。
  - 世界观 Tab（`_WorldviewTab`）：时代预设与视觉基调展示纯中文定位词与中文排除词。

## Capabilities

### Modified Capabilities
- `ai-video-studio/novel-import`: 移除小说导入长文提取中对角色英文提示词（facial/attire/positive/negative prompt）和场景英文提示词（prompt_en）的提取要求，全面使用原生中文容貌、服饰、环境与空间描写。
- `ai-video-studio/series-asset-library`: 角色资产卡与场景资产库全面采用纯原生中文描述，废弃英文正向/反向 Prompt 字段及翻译流程；时代风格预设（VisualEraGenre）中的服饰、环境、道具锚点与负向排除词全面中文化。

## Impact

- **数据模型**：
  - `lib/tools/ai_video_studio/models/studio_models.dart`:
    - `VisualEraGenre.presets` 预设文本中文化。
    - `SceneDirection` 的提示词读取与生成改为纯中文。
    - `CharacterTurnaroundPrompt` 组装逻辑移除英文要求。
- **大模型 Prompt 模板与校验**：
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`:
    - `buildNovelMasterExtractionPrompt` 约束纯中文结构。
    - `_promptSceneSpatialDeconstruction` 输出纯中文视角描述。
- **UI 视图**：
  - `lib/tools/ai_video_studio/ui/series_page.dart`:
    - 精简角色卡与场景卡中的文本框及多余的英文翻译按钮。
    - 世界观设定中的视觉定位与排除词纯中文渲染。
- **测试用例**：
  - 更新测试套件中对提取 Prompt 与模型输出的断言，确保纯中文测试通过。
- **向后兼容性**：
  - 用户确认当前处于研发测试阶段，旧的测试剧集数据可删除重建，不需要复杂的向后兼容数据迁移脚本。
