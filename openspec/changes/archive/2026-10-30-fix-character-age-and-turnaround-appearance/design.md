## Context

在 `ai-video-studio` 中，角色资产卡管理（`series_page.dart`）与提示词组装引擎（`prompt_assembler.dart`、`ai_constraint_engine.dart`）共同控制角色三视图的生成。
当前实现存在三处结构性缺陷导致少年/无须角色被生成为长胡子中年人：
1. `CharacterTurnaroundProportion.standard` 将标准成人比例写死为 `tall and slender figure, mature adult anatomy`，破坏了少年与富态身材；
2. 扩散模型（如 FLUX.1）对古装汉服男角色具有强烈的“蓄须美髯”先验，且 Flux 不支持 Negative Prompt，使得负向词中的“长胡子/beard”完全无效；
3. 形态差异词直接以中文字符拼接进英文提示词，且形态生成时强行锁死已有胡子的旧三视图作为图生图底图。

详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- **比例锚点中立化**：将标准比例（standard）修改为解剖结构中立的描述，移除强制的“成熟成年人”与“修长挺拔”，支持少年与富态。
- **正向年龄与无须防御守卫（Positive Clean-Shaven Guard）**：在 Prompt 编译器中实现规则化面部守卫。当检测到少年/幼年/青年/无须或负向排斥胡须时，自动在正向提示词中植入 `clean-shaven, completely hairless face, smooth bare chin, youthful teen boy`，彻底攻克 Flux 不支持负向提示词的顽疾。
- **差异词中英规范化与正向对立转换**：当用户在差异词中填入中文时，自动进行中英映射；对负向填写的排他词（如“长胡子”），在正向中自动补充对应的排他正向词（如 `clean-shaven face`）。
- **形态三视图底图解耦**：在形态三视图生成面板增加「继承基准脸模」切换开关，支持从纯文字提示词重新生成干净三视图，打破错误面模的克隆死锁。

**Non-Goals:**
- 不替换底层生图模型引擎，继续保持与 FLUX.1、SDXL、SenseAudio、Agnes 等所有引擎的兼容。
- 不破坏现有 `CharacterCard` 与 `CharacterVariation` 的数据存储格式，保证历史工程透明兼容。

## Decisions

### 1. 修改 `CharacterTurnaroundProportion.standard` 锚点
- **决策**：
  将 `positiveAnchor` 由：
  `'standard human proportions, 7-head tall proportion, tall and slender figure, mature adult anatomy, realistic body structure, full body head to toe'`
  改为：
  `'standard human proportions, 7-head tall proportion, natural human anatomy, well-proportioned figure, realistic body structure, full body head to toe'`
- **理由**：移除 `tall and slender figure`（避免与胖、富态对抗）与 `mature adult anatomy`（避免与少年、青年对抗），保留 7 头身和自然解剖体态。
- **备选方案**：新增一个专门的 `teenager` 比例。但由于现有 UI 与集数分镜中仅有标准与 Q 版双轨，在中立化标准比例上通过角色 Prompt 自主定义年龄与胖瘦最为平滑。

### 2. 在 `CharacterTurnaroundPrompt.build` 中加入面容与胡须正向防御守卫
- **决策**：
  在 `CharacterTurnaroundPrompt` 中新增静态方法或守卫：
  检测中文描述、正向 Prompt、差异词或负向词：
  - 若命中少年特征（如 `少年`、`小弟`、`青年`、`男孩`、`书童`、`幼年`、`teen`、`youth`、`boy`）或命中负向排胡须（如 `长胡子`、`胡子`、`beard`、`mustache`、`facial hair`）：
  - 自动向 Positive Prompt 追加正向锁：
    `clean-shaven, completely hairless face, smooth bare skin and chin, youthful appearance, no facial hair`。
- **理由**：
  这是唯一能同时解决 **Flux 负向词失效** 与 **古装汉服蓄须偏置** 的根本解法。任何基于 Negative Prompt 的修补在 Flux 下都是空谈，必须在 Positive 中用强正向词占据面部生成注意力。

### 3. 增强 `AiConstraintEngine._promptPromptTranslation` 提示词模板
- **决策**：
  在 LLM 翻译模板中明确要求：
  - 当中文描述指出角色为少年、儿童、青年或未蓄须者时，`prompt_positive` 必须显式输出 `clean-shaven, smooth hairless face, youthful [age] teenager`，严禁泛化为 `1man` 或商铺掌柜等容易带出胡子的词汇；
  - `prompt_negative` 必须同步补齐 `beard, mustache, goatee, stubble, wrinkles, elderly, mature adult face`。
- **理由**：源头保证用户在角色卡点击“生成 Prompt”时输出高质量的、包含无须特征的英文 Prompt。

### 4. 差异词处理与形态参考图解耦
- **决策**：
  - 在 `PromptAssembler.mergeVariation` 中，增加对纯中文差异词的常见关键词对齐（如 `少年` → `youthful teenager, clean-shaven`，`长胡子` → 负向注入 `beard, mustache` 且正向补充 `clean-shaven`）；
  - 在 `_generateVariationTurnaround` 中添加布尔控制 `inheritBaseFace`（默认为 true）。若用户取消勾选，则 `refImages` 留空且提示词不注入 `faceIdentityTokens`，纯依照形态 Prompt 生成全新三视图。
- **理由**：赋予用户彻底摆脱“前一张图画错了胡子，后面形态全被带偏”的能力。

## Risks / Trade-offs

- **[Risk]** 自动注入 `clean-shaven` 是否会导致本就想设计长胡子角色的设定被误伤？
  → **Mitigation**：仅在命中“少年/年轻/幼/童”或明确在负向排除胡须时触发；若描述中含有“美髯、长须、胡茬、胡子、beard”等蓄须词汇，则绝不触发排胡须守卫。
- **[Risk]** 取消形态继承底图可能导致不同形态间五官差异略微变大。
  → **Mitigation**：仅在用户主动取消继承（如底图生成明显错误时）才切断参考图，常态下仍默认保留脸模继承。
