## Context

参见 `proposal.md`。当前 `CharacterCard` 将角色的面容五官与服装装束混杂在一起，导致子形态（如“白色着装”）在与原角色的基础黑袍提示词合并时产生词义冲突，且全身参考图的黑袍像素通过视觉编码器外溢污染新形态。

## Goals / Non-Goals

**Goals:**
1. 在 `CharacterCard` 与 `CharacterVariation` 中实现容貌体态（Identity & Anatomy）与服饰装束（Attire & Costume）的物理分层存储。
2. 实现子形态三视图生成时的「全量置换装配」：仅继承容貌体态，彻底丢弃默认服饰，并自动在负向词中注入针对原服饰的颜色与形制对冲词。
3. 引入「面部特写锚点（Face Anchor）」机制：基准三视图生成后自动裁切正面免冠头像（`face_anchor.png`），同时支持单独生成 1:1 超清面部特写；子形态参考图仅传递面部特写，阻断深色服饰视觉污染。
4. 升级小说全案解构（`novelMasterExtraction`）与提示词翻译（`promptTranslation`），结构化输出容貌与服饰两组中英文 Prompt。
5. 优化角色卡 UI 呈现双栏输入与智能分流，无缝向前兼容既有工程历史数据。

**Non-Goals:**
- 不在客户端引入复杂的深度学习人脸对齐检测权重（利用确定性的三视图正面构图比例顶部裁切，或直接调用模型生成独立 1:1 特写）。
- 不破坏现有分镜中已引用旧角色三视图的历史成片。

## Decisions

### D1: 领域模型分层与向前兼容（Identity vs Attire Model Separation）
- **方案**：
  在 `CharacterCard` 中新增：
  - `facialFeaturesZh`（容貌体态中文）与 `facialPrompt`（容貌体态英文）
  - `defaultAttireZh`（默认服装中文）与 `defaultAttirePrompt`（默认服装英文）
  - `faceAnchorPath`（面部特写文件相对路径，如 `face_anchor.png`）
  保留 `descriptionZh`、`basePromptPositive`、`basePromptNegative` 作为兼容字段。
  在 `fromJson` 时，若旧数据缺失新字段，则自动回落：`facialPrompt = basePromptPositive`，`defaultAttirePrompt = ''`，保证老剧集 100% 正常读取。
- **替代方案考虑**：
  直接废弃旧字段：会导致所有用户已存角色卡在加载时字段丢失或抛异常，不可取。

### D2: 交互式视窗面部特写截取工具（Interactive Visual Face Cropper）
- **方案**：
  废弃容易产生割裂的独立文生图头像与死板的固定比例裁切，采用“三视图交互式视窗截取”：
  1. **交互体验**：提供类似微信/iOS 头像裁切视窗（`FaceCropDialog`）。中央具有固定 1:1 正方形取景框（如 280×280），用户在框内自由拖拽平移三视图底图、使用鼠标滚轮/缩放滑块缩放底图，所见即所得。
  2. **精确裁切**：点击「保存为面部锚点」，根据视窗相对底图的变换矩阵/坐标，使用 Dart `image.copyCrop` 毫秒级生成 1:1 超清 `face_anchor.png`。
  3. **零随机性与高保真**：直接取自用户满意的三视图正面人脸，100% 保持发型、发饰、眼神、肤色与画风一致，彻底杜绝文生图随机跑偏或女性化倾向。
- **替代方案考虑**：
  保留独立文生图：文生图每次随机抽取陌生人脸，且注入 `bust shot` 会导致身体占比过大、头顶被切，无法保证角色一致性。

### D3: 提示词编译器两段式合并与负向颜色对冲（Two-Stage Prompt Assembly）
- **方案**：
  - 基准三视图：`CharacterTurnaroundPrompt.build` 接收 `facialPrompt` 与 `defaultAttirePrompt` 合体组装为完整出场提示词。
  - 子形态三视图：`CharacterTurnaroundPrompt.buildForVariation` 仅接收 `facialPrompt` 与 `variation.attirePrompt`。默认服饰 `defaultAttirePrompt` 被完全剔除；同时检测形态装束中的颜色（如“白色/white”），自动在负向词中追加相反色系（如 `black clothes, dark robes, cyan outfit`）。
- **替代方案考虑**：
  保留旧合并方式仅靠 LLM 修改：无法保证每一次形态修改都能在本地离线或快速响应，确定性的模板组装更稳定。

### D4: 小说全案解构与 Prompt 翻译结构化升级
- **方案**：
  - 在 `StudioAiTask.novelMasterExtraction` 的 System Prompt 中增加字段要求：
    `facial_features_zh`、`facial_prompt`、`default_attire_zh`、`attire_prompt`。
  - 在 `StudioAiTask.promptTranslation` 中升级为返回两组提示词，并保留兼容的组合 `prompt_positive`。
- **替代方案考虑**：
  保持提取端不变，只在 UI 手工拆分：会使通过小说导入的批量角色继续陷入服饰与五官混杂状态，必须在导入端同步升级。

### D5: 面部特写生命周期闭环与安全更新机制（Face Anchor Lifecycle & Safe Replacement）
- **方案**：
  1. **支持一键删除**：面部特写卡片右上角增加删除按钮（`✕`）。点击确认后调用 `deleteFaceAnchor` 物理删除 `face_anchor.png` 并清空 `faceAnchorPath`，使角色可平滑退回“未设置”状态。
  2. **三视图更新后的防呆引导**：
     - 当角色尚未设置面部锚点时，生成三视图完成后自动弹出截取视窗，引导一键截取；
     - 当角色已拥有面部锚点时，重新生成三视图完成后弹出询问对话框：“检测到新的三视图已生成，当前面部特写为旧版，是否重新截取？”，由用户选择立即截取或保留原状，绝不静默覆盖。

### D6: Agnes 图像模型图生图协议与参数规整（Agnes Reference Image & Img2Img Contract）
- **方案**：
  在 `SystemAiImageAdapter.generate` 中：
  1. 识别 `isAgnes` 模型时，读取 `request.referenceImages`（若开启脸模继承则为 `face_anchor.png`），将图像文件编码为标准 Data URI Base64 格式（`data:image/png;base64,...`）；
  2. 将图片数组装入 `extra_body.image` 字段，并将 `extra_body.response_format` 设为 `"url"`；
  3. 按照 Agnes 规范注入规整后的输出尺寸 `size: "2K"` 与宽高比 `ratio: "9:16"`（1:1 时为 `"1K"`, `"1:1"`）；
  4. 彻底激活 Agnes 服务端的 `images/i2i` 图生图路由，确保形态三视图精准继承脸模。

### D7: Flutter 图像缓存（ImageCache）多维失效机制
- **方案**：
  在图片写入、替换或删除后：
  1. 调用 `PaintingBinding.instance.imageCache.evict(FileImage(file))` 清除引擎级位图解码缓存；
  2. 在缩略图 Widget 树上注入带文件最后修改时间戳的 `ValueKey('${file.path}_${file.lastModifiedSync().millisecondsSinceEpoch}')`，确保 UI 缩略图与大图弹窗时刻同步更新。

### D8: FaceCropDialog 视窗无约束渲染与 toScene 像素映射架构
- **问题根因**：
  `InteractiveViewer` 默认 `constrained: true` 将内部 `SizedBox(width: 1080, height: 1920)` 强制压制为 `420x420` 视窗大小，导致底图变形且逆变换矩形落入 `[0~420]` 坐标区间，映射到源图上只能切出头顶上方空白处的 100px 局部微缩背景并被放大为马赛克。
- **架构方案**：
  1. 为 `InteractiveViewer` 显式设置 `constrained: false` 与 `boundaryMargin: const EdgeInsets.all(double.infinity)`，保证底图按原始宽高真实比例参与几何变换与手势交互；
  2. 废弃手工逆矩阵转换，统一采用 Flutter 原生 `_transformController.toScene(viewportBoxTopLeft)` 与 `toScene(viewportBoxBottomRight)`，毫秒级获取源图 `[0..image.width, 0..image.height]` 真实像素点；
  3. 执行 `img.copyCrop` 截取选区并平滑重采样到 512x512 超清头像输出。

### D9: 三视图纯白背景加固与提示词环境词清洗机制
- **问题根因**：
  1. `CharacterTurnaroundPrompt` 包含 `consistent lighting and background` 诱导词，现代生图大模型读到 `background` 会强制绘制背景；
  2. 剧集全局 `styleTokens` 包含了电影级场景光影词（如 `dark realism`, `cinematic film still`），排在末尾的白底词被严重冲淡；
  3. 基准三视图生成时若角色卡已有旧参考图，传入后激活了 Agnes 图生图模式，忠实保留了旧图中的环境背景。
- **架构方案**：
  1. **纯白底前置强约束**：在提示词最开头注入 `isolated on solid pure white background, clean white studio backdrop, completely blank empty background`，极大提升白底注意力权重；
  2. **诱导词清除**：将 `consistent lighting and background` 重构为 `uniform neutral studio lighting, solid white background`；
  3. **环境词清洗器 (`cleanTurnaroundStyleTokens`)**：在三视图生成时，自动从 `styleTokens` 中清洗掉 `cinematic`, `dark realism`, `lighting`, `atmosphere`, `dungeon`, `scene`, `background`, `environment` 等场景环境词，仅保留纯艺术画风词；
  4. **基准图参考图阻断**：在 `_generateTurnaround` 中强制传递 `referenceImages: []`，保证基准三视图恒以纯文本生图模式产出纯净白底。

## Risks / Trade-offs

- **[Risk] 旧版三视图裁切坐标与不同模型输出的偏差**
  → **Mitigation**: 引入交互式可视裁切框，用户可随意平移和缩放取景，完美避开头顶发冠被削或切入肩膀的问题。
- **[Risk] 大分辨率三视图转换为 Base64 增加请求体大小**
  → **Mitigation**: 裁切后的 1:1 `face_anchor.png` 尺寸适中（通常数百 KB），编码为 Base64 耗时在 10ms 以内，完全不影响传输性能。


## Migration Plan

- 新增字段均为可选并附带老字段回落逻辑，不需要数据库迁移。
- 变更完成后运行单元测试验证，并执行 `./scripts/deploy_local.sh` 编译部署。
