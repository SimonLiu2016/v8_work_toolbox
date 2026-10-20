## Why

在 AI 短视频工坊中，用户创建“少年 / 幼年 / 青年”男性角色（如“天人居白胖少年”）时，生成的角色三视图频发性出现浓密胡须、中年甚至老翁模样。尽管用户在形态“正向差异词”填写“少年”、在“负向差异词”填写“长胡子”，生成结果依然无法摆脱胡须与苍老特征。

根本原因在于：
1. 系统在标准比例三视图提示词中全局无差别硬编码注入了 `tall and slender figure, mature adult anatomy`（成熟成年人解剖结构、高挑纤细），从底层直接覆盖了少年的幼态与富态；
2. 古装汉服与酒楼商铺先验极易被扩散模型联想为“美髯长者/蓄须掌柜”；
3. 工坊默认的 Flux 模型底层无 Negative Prompt 机制，负向词中的“长胡子”被完全忽略，必须在 Positive Prompt 中以“clean-shaven, hairless face”显式排斥；
4. 形态差异词为纯中文时未做自动翻译，直接硬拼进英文提示词导致语义失效；
5. 形态三视图生成时强制将旧的有胡子三视图作为参考图底图并声明“保持一致五官特征”，导致胡须被死锁继承。

为保证角色设计与剧本设定的严密一致性，必须在资产库提示词编译与三视图生成链路上彻底根治面容年龄与胡须先验污染。

## What Changes

- **解耦并中立化体态比例正向锚点**：移除 `CharacterTurnaroundProportion.standard` 中硬编码的 `mature adult anatomy` 与 `tall and slender figure`，改为年龄中立的解剖结构描述 `natural human proportions, well-proportioned anatomy`，防止成年修长先验压制少年与富态。
- **引入角色年龄面容防御机制（Age & Clean-Shaven Facial Guard）**：
  - 在 `PromptAssembler` 与 `AiConstraintEngine.promptTranslation` 中建立显式年龄与胡须规则：当检测到角色中文描述或正向词包含“少年、小弟、男孩、青年、书童、幼年、干净、无须”等少年/青少年关键词时，强制在英文 Positive Prompt 中追加 `youthful teen boy, clean-shaven, completely hairless face, smooth bare chin, young teenage appearance`。
  - 为 Flux / SD 等扩散引擎在正向提示词中彻底阻断古装蓄须先验。
- **差异词自动中译英与规范化**：
  - 在形态差异词保存与装配时，自动检测中文并规范化翻译为英文短语（如“少年”→ `youthful teenager, clean-shaven boy`，“长胡子”在负向中译为 `beard, mustache, facial hair, goatee`，若引擎为 Flux 则同步将对立词 `clean-shaven` 注入正向）。
- **形态三视图参考图解耦与底图重置机制**：
  - 在形态三视图生成时，增加「是否继承基础脸模」选项（默认开启，但当基础图生成错误时可主动关闭）；
  - 允许纯凭文字提示词重新生成形态三视图，阻断旧错误三视图的面部克隆死锁。

## Capabilities

### New Capabilities
（无新建独立 Capability，沿用连续剧资产体系）

### Modified Capabilities
- `ai-video-studio/series-asset-library`: 强化角色资产卡 Prompt 翻译与三视图装配规范，新增年龄与无须正向防御、体态与年龄解耦、差异词规范化及形态参考图解耦。

## Impact

- **Affected Code**:
  - `lib/tools/ai_video_studio/models/studio_models.dart`: 修改 `CharacterTurnaroundProportion.standard` 锚点词。
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`: 在 `CharacterTurnaroundPrompt` 与 `PromptAssembler.mergeVariation` 中增加年龄面容感知注入与中英文差异词适配。
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`: 增强 `_promptPromptTranslation` 的年龄与胡须硬约束。
  - `lib/tools/ai_video_studio/ui/series_page.dart`: 形态版本面板支持无底图纯文生图与差异词翻译优化。
- **API & Protocol**: 无破坏性 API 变更，向后兼容现有角色卡数据。
