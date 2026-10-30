## 1. 时代风格预设与提示词组装中文化 (Studio Models)

- [x] 1.1 更新 `VisualEraGenre.presets` 中的 5 大时代预设（`xianxia`, `historical_costume`, `republican_era`, `urban_modern`, `futuristic_scifi`），将 `costumeAnchor`、`environmentAnchor`、`propMaterialAnchor` 与 `negativeBans` 替换为地道、精准的原生中文描述，彻底去除英文标签堆砌
- [x] 1.2 重构 `CharacterTurnaroundPrompt` 与 `ScenePromptBuilder`，直接基于中文容貌特征（`facial_features_zh`）、服饰（`default_attire_zh`）、场景空间描述与时代预设组装原生中文生图提示词，并在验证方法中移除对英文 Prompt 的必填依赖

## 2. 大模型长文提取与空间解构纯中文化 (AiConstraintEngine)

- [x] 2.1 重写 `AiConstraintEngine.buildNovelMasterExtractionPrompt`：在角色卡 JSON 规范中移除 `facial_prompt`、`attire_prompt`、`prompt_positive`、`prompt_negative`，场景中移除 `prompt_en`，引导大模型输出具象且富有画面感的原生中文面貌与服饰描写
- [x] 2.2 重写 `AiConstraintEngine._promptSceneSpatialDeconstruction`：移除 SD/Midjourney 英文 tags 要求与 `{"zh": "...", "en": "..."}` 结构，使大模型直接输出 7 个机位的纯中文空间光影构图描述，并适配相应的解析器

## 3. UI 界面纯净化与输入框精简 (Series Page)

- [x] 3.1 精简 `_CharacterCard`：移除正向英文提示词、负向英文提示词、英文容貌与服饰输入框，移除“翻译成英文”按钮，优化角色卡布局与三视图生成交互
- [x] 3.2 精简 `_SceneEditorSheet`：移除基础英文提示词输入框，在 7 个空间视角折叠面板中仅保留中文视角描写输入与生成，移除英文提示词文本框
- [x] 3.3 优化 `_WorldviewTab`：将时代预设的服饰、环境、道具材质锚点及负向排除项纯中文直观渲染

## 4. 自动化测试与工程部署验证 (Verification & Deployment)

- [x] 4.1 审查并更新 `test/` 目录下受影响的测试用例，确保断言适配纯中文结构且所有单元测试全部通过
- [x] 4.2 执行 `flutter analyze` 确保工程无任何静态检查错误
- [x] 4.3 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并在本机替换部署 `/Applications/V8WorkToolbox.app`
