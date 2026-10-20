## MODIFIED Requirements

### Requirement: 角色资产卡与形态版本化

系统 SHALL 在 IP 主库中为每个常驻角色维护一张角色资产卡，包含：角色名称、容貌体态（`facialFeaturesZh` 与 `facialPrompt`）、默认出场装束（`defaultAttireZh` 与 `defaultAttirePrompt`）、基础兼容 Prompt（`descriptionZh`、`basePromptPositive`、`basePromptNegative`）、面部特写锚点图（`faceAnchorPath`）、基准参考图列表、绑定的 TTS 音色标识符。

系统 SHALL 支持为同一角色创建多个命名形态（State Variation），每个形态 SHALL 存储独立的形态装束差异词（`attirePrompt` / `positiveDelta`）。

在生成基准三视图后，系统 SHALL 支持用户通过交互式视窗裁剪工具（支持拖拽平移与缩放）从正面视图中精确截取 1:1 免冠面部特写保存为面部特写锚点（`face_anchor.png`），或手动上传/指定锚点图；裁剪组件 SHALL 将底图声明为无约束（`constrained: false`）并采用 `toScene` 原生取点，杜绝视窗压缩形变，确保 100% 精确映射原图像素并产出超清 512x512 头像；系统 SHALL 支持用户随时删除/清除已保存的面部特写锚点；在重新生成三视图时，系统 SHALL 提示用户是否从新三视图重新截取面部特写，绝不可静默强制覆盖。

在生成三视图（基准三视图或形态三视图）时，提示词编译器 SHALL 强化纯白底约束：必须将纯白底声明（`isolated on solid pure white background, clean white studio backdrop, completely blank empty background`）置于提示词开头，严禁包含 `consistent lighting and background` 等场景诱导词，并自动对全局 `styleTokens` 进行场景词清洗以剔除环境与暗调光影词；生成基准三视图时，系统 SHALL 强制阻断参考图传递（`referenceImages: []`），确保以纯文本生图模式执行。

在生成子形态三视图时，系统 SHALL 将容貌词与该形态装束词置换组装，全量剔除默认装束词，并在负向提示词中自动对冲默认装束的颜色与特征；当开启面容继承时，参考图列表 SHALL 仅挂接面部特写锚点图（`face_anchor.png`）；生图引擎适配器 SHALL 将参考图读取编码为标准 Data URI Base64 并传递至 `extra_body.image` 数组，物理阻断基准全身服装对新形态的视觉色彩污染并确保图生图模型准确识别脸模。

系统 SHALL 在分镜生产阶段自动将当前激活形态的完整 Prompt 组装到生图请求中。

#### Scenario: 自然语言角色描述转换为标准 Prompt

- **WHEN** 用户以中文自然语言描述角色外貌并点击"生成 Prompt"
- **THEN** 系统 SHALL 调用 AI 智能将描述分流拆解为容貌体态与默认装束两组英文 Prompt，并合成全量正反向 Prompt 供用户确认与微调

#### Scenario: 容貌与装束双维度提示词组装与纯白底三视图生成

- **WHEN** 用户触发生成角色的基准三视图
- **THEN** 系统 SHALL 将 `facialPrompt` 与 `defaultAttirePrompt` 结合时代题材与清洗后的风格锁合体组装为前置纯白底的提示词，以纯文本生图模式成功生成全身纯白底基准三视图，并引导用户进行交互式面部特写截取

#### Scenario: 交互式视窗精确截取与删除面部特写锚点

- **WHEN** 用户在拥有三视图的角色卡上点击“从三视图截取面部”或点击面部锚点卡片上的删除按钮
- **THEN** 系统 SHALL 支持在交互弹窗中以原图真实像素映射平移缩放底图并精确截取保存 1:1 `face_anchor.png`，且立即刷新内存图片缓存；或在确认后物理删除该文件并清空卡片引用

#### Scenario: 子形态生成时全量置换服饰并传递 Base64 面部锚点

- **WHEN** 用户为具有深色默认装束的角色新建形态（如“白色着装”）并触发生成形态三视图
- **THEN** 系统 SHALL 仅继承该角色的 `facialPrompt` 并融入新形态的白色装束词，全量剔除默认深色装束词，在负向词中自动注入深色服饰对冲词，且将 `face_anchor.png` 编码为 Data URI Base64 装入 `extra_body.image`，产出纯净白袍且面容一致的三视图

#### Scenario: 切换角色形态触发分镜 Prompt 重组

- **WHEN** 用户在单集制作区将某角色的激活形态从"默认"切换为"白色着装"
- **THEN** 系统 SHALL 将该集所有包含该角色的待生成分镜的 Prompt 自动重组为包含新形态装束的 Prompt，已生成的历史分镜不受影响

