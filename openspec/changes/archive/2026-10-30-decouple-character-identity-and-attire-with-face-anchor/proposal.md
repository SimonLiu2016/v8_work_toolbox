## Why

当前角色资产卡将容貌五官与服装装束混杂在单一的 `descriptionZh` 与 `basePromptPositive` 中，导致在新增子形态（如“白色着装”）时，系统仅在原有黑袍词尾部追加新词，同时传递包含全身黑袍的参考底图，造成严重的正向服饰冲突与视觉底图串色污染。通过在领域模型层将“容貌体态（Identity）”与“服饰装束（Attire）”解耦，并引入“面部特写锚点（Face Anchor）”，从根本上实现换装形态的纯净置换与五官高保真传承。

## What Changes

- **模型解耦与向前兼容 (CharacterCard & Variation Refactor)**:
  - 在 `CharacterCard` 中拆分容貌字段（`facialFeaturesZh`, `facialPrompt`）与默认服饰字段（`defaultAttireZh`, `defaultAttirePrompt`），保留 `descriptionZh` 与 `basePromptPositive` 作为兼容属性，确保现有工程平滑加载。
  - 新增 `faceAnchorPath`（面部特写锚点图相对路径）。
  - 在 `CharacterVariation` 中强化独立装束定义（`attirePrompt` / `positiveDelta`），支持在置换形态时彻底剥离默认服饰。
- **提示词组装器两段式合并与负向颜色对冲 (PromptAssembler Two-Stage Assembly)**:
  - 基准三视图：合体组装 `facialPrompt + defaultAttirePrompt`。
  - 子形态三视图：置换组装 `facialPrompt + variation.attirePrompt`，彻底剥离基准服装，并在负向词中自动对冲基准服饰颜色与特征（如白衣时自动抑制 `black clothes, dark robes`）。
- **面部特写锚点（Face Anchor）双轨支持与高精度交互式裁剪 (Avatar Extraction & Cropper Precision)**:
  - 交互式视窗裁剪：基于 `FaceCropDialog` 提供 1:1 取景框平移缩放工具。通过设置 `InteractiveViewer(constrained: false)` 与 `toScene` 原生取点，消除视窗紧约束对源图的尺寸压制，保证裁剪像素坐标 100% 精确对齐原图真实像素，彻底解决误截取顶端低像素背景的问题。
  - 防覆盖与删除生命周期：三视图重新生成时弹窗确认是否覆盖面部锚点；卡片支持一键物理删除与缓存失效（`PaintingBinding.instance.imageCache.evict`）。
  - 子形态参考图绑定：生成形态三视图时，`refImages` 仅挂接 `face_anchor.png`（纯脸模），通过 Agnes 图生图协议编码为 Data URI Base64 传递，从物理视觉上彻底隔绝全身深色服装的特征泄露。
- **三视图纯白背景加固与提示词环境词清洗 (Turnaround Pure White Background Protection)**:
  - 提示词首置纯白底强约束词（`isolated on solid pure white background, clean white studio backdrop, completely blank empty background`），并将白底优先级提至最高。
  - 清理提示词内 `consistent lighting and background` 等易被扩散模型误解为“生成环境背景”的诱导词。
  - 在生成三视图时清洗全局 `styleTokens` 中的场景词（如 `dark realism`, `cinematic lighting` 等），避免剧集电影感光影污染三视图白底。
  - 基准三视图生成时阻断历史参考图传递，确保纯文本生图，杜绝旧背景图的构图保留污染。
- **小说全案解构与提示词翻译结构化升级 (Novel Extraction & Translation Enhancement)**:
  - 升级 `StudioAiTask.novelMasterExtraction`，在角色提炼中结构化输出 `facial_features_zh` / `facial_prompt` 与 `default_attire_zh` / `attire_prompt`。
  - 升级 `StudioAiTask.promptTranslation`，支持将整段中文外貌描述智能分流为容貌与服饰两组 Prompt。
- **UI 交互增强 (Series Page Character & Variation Editor)**:
  - 角色卡编辑区呈现「容貌与体态」和「默认服饰」双栏输入及一键智能拆分翻译按钮。
  - 视觉资产区增加独立展示与管理「面部特写锚点」卡片。
  - 形态编辑面板明确标注继承纯净面容，并展示绑定的面部特写。

## Capabilities

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 角色卡支持容貌体态与服饰装束解耦存储、面部特写锚点管理，并在子形态装配时全量置换服装与对冲颜色。
- `ai-video-studio/novel-import`: 小说全案导入支持将角色提炼细化为容貌体态与默认出场服饰的双维度结构化解析。

## Impact

- **数据模型**: `CharacterCard` 与 `CharacterVariation` 扩展新字段并保持 JSON 序列化向后兼容。
- **编译器与引擎**: `PromptAssembler`、`CharacterTurnaroundPrompt` 与 `AiConstraintEngine`（小说解构与翻译模板）。
- **界面层**: `lib/tools/ai_video_studio/ui/series_page.dart` 中的 `_CharacterCard`、`_CharactersTab` 与 `_VariationEditor`。
- **测试套件**: 需新增模型序列化、提示词两段式合并、小说双维度解构、面部特写路由等单元测试。
