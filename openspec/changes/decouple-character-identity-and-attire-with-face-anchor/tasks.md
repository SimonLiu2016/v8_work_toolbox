## 1. 领域模型与数据层重构 (Domain Model & Backward Compatibility)

- [x] 1.1 在 `lib/tools/ai_video_studio/models/studio_models.dart` 中为 `CharacterCard` 新增 `facialFeaturesZh`、`facialPrompt`、`defaultAttireZh`、`defaultAttirePrompt` 与 `faceAnchorPath` 字段，并在 `fromJson` 与 `toJson` 中实现向前兼容回退。
- [x] 1.2 在 `CharacterVariation` 中增加 `attirePrompt` 支持，并保持旧 JSON 序列化向后兼容。
- [x] 1.3 编写单元测试验证 `CharacterCard` 与 `CharacterVariation` 的新旧结构序列化、反序列化与默认值平滑降级。

## 2. 面部特写锚点自动裁切与管理服务 (Face Anchor Extraction & Services)

- [x] 2.1 在 `StudioProjectManager` 中实现三视图面部区域自动裁切 `cropAndSaveFaceAnchor`：从标准正面视图顶部提取免冠头部保存为 `face_anchor.png`。
- [x] 2.2 在 `StudioProjectManager` 中增加独立 1:1 面部特写生成服务：仅使用 `facialPrompt` 生成免受全身服装干扰的超清面部锚点图。
- [x] 2.3 编写单元测试验证面部特写裁切工具逻辑与独立特写文件落盘契约。

## 3. 提示词编译器两阶段置换装配与负向对冲 (Prompt Assembler Two-Stage Assembly & Negative Hedging)

- [x] 3.1 修改 `CharacterTurnaroundPrompt.build`，支持将 `facialPrompt` 与 `defaultAttirePrompt` 结合时代题材与风格锁合体组装为完整出场提示词。
- [x] 3.2 修改 `CharacterTurnaroundPrompt.buildForVariation`，实现全量服饰置换：仅继承 `facialPrompt`，彻底剔除 `defaultAttirePrompt`，并依据形态装束（如白色）自动在负向词中注入深色服饰对冲词（如 `black clothes, dark robes, cyan outfit`）。
- [x] 3.3 扩充 `PromptAssembler.normalizeDeltaWords`，增加常见服装款式与颜色映射（`白色着装`、`白衣`、`白长袍`、`黑袍`、`战铠`等）。
- [x] 3.4 编写单元测试验证基准图合体装配、形态图置换装配与色彩反向对冲。

## 4. 小说解构与 Prompt 翻译双维度升级 (Novel Extraction & Translation Enhancement)

- [x] 4.1 升级 `AiConstraintEngine._promptNovelMasterExtraction` 模板与 JSON Schema，要求输出 `facial_features_zh`、`facial_prompt` 与 `default_attire_zh`、`attire_prompt`。
- [x] 4.2 升级 `AiConstraintEngine.promptTranslation`，支持智能将整段中文外貌描述分流为容貌与服饰两组提示词。
- [x] 4.3 更新 `mergeMasterAssets`，将小说解构出的双维度字段持久化写入 `CharacterCard`。
- [x] 4.4 编写单元测试验证小说解构与翻译提示词的双维度提取结果。

## 5. 界面交互升级与参考图解耦 (UI Interaction & Reference Decoupling)

- [x] 5.1 修改 `_CharacterCard` UI：支持容貌体态与默认服饰双栏展示与编辑，新增一键拆分翻译按钮；在视觉资产区增加「面部特写锚点」卡片展示与独立生成/更换头像入口。
- [x] 5.2 修改 `_generateVariationTurnaround`：生成子形态时，参考图列表仅挂接 `face_anchor.png`（纯脸模），彻底切断全身深色服装的视觉污染。
- [x] 5.3 优化形态编辑面板提示：展示当前绑定的面部锚点信息与置换说明。

## 6. 综合验证与本机部署 (Verification & Local Deployment)

- [x] 6.1 运行所有相关单元测试与静态分析，确保 100% 通过。
- [x] 6.2 执行 `./scripts/deploy_local.sh` 编译 Release、重签名并替换部署至本机 `/Applications/V8WorkToolbox.app`。

## 7. 面部特写交互式裁切工具与生命周期管理 (Face Cropper & Lifecycle Management)

- [x] 7.1 实现 `FaceCropDialog` 交互式视窗裁剪组件：支持居中 1:1 方形取景框、三视图底图拖拽平移与滚轮缩放，并实时计算像素映射与精确裁切。
- [x] 7.2 在 `StudioProjectManager` 中实现 `deleteFaceAnchor` 与 `cropFaceAnchorFromRect`：支持一键物理删除与视窗矩形精确裁切保存，并清除卡片 `faceAnchorPath`。
- [x] 7.3 在 `_CharacterCard` UI 中增加面部特写删除按钮（`✕`）与「从三视图截取面部」入口，替换失效的文生图特写按钮。
- [x] 7.4 优化三视图生成回调：未设置锚点时引导弹窗截取；已设置锚点时弹出是否重新截取确认框，废弃原有的静默死板覆盖。
- [x] 7.5 在图片保存与删除后引入多维缓存失效机制（`PaintingBinding.instance.imageCache.evict` + `ValueKey` 时间戳），解决缩略图与大图不同步问题。

## 8. Agnes 图像图生图协议与参数规整 (Agnes Reference Image & Img2Img Contract)

- [x] 8.1 在 `SystemAiImageAdapter.generate` 中实现 Agnes 协议图生图传参：将 `request.referenceImages` 读取并编码为 `data:image/png;base64,...`，注入 `extra_body.image` 数组。
- [x] 8.2 在 `SystemAiImageAdapter.generate` 中规整 Agnes 尺寸参数：注入 `size: "2K"` 与 `ratio: "9:16"`（1:1 时为 `"1K"`, `"1:1"`），并将 `extra_body.response_format` 设为 `"url"`。
- [x] 8.3 编写单元测试验证 Agnes 图生图 Payload 组装、Base64 Data URI 编码与尺寸吸附。
- [x] 8.4 运行所有单元测试确保 100% 通过，并执行 `./scripts/deploy_local.sh` 编译部署。

## 9. 面部特写裁剪视窗约束与像素映射重构 (Face Cropper Coordinate & Resolution Fix)

- [x] 9.1 修改 `FaceCropDialog`：为 `InteractiveViewer` 设置 `constrained: false` 与 `boundaryMargin: const EdgeInsets.all(double.infinity)`，确保源图按真实分辨率尺寸参与布局。
- [x] 9.2 重构 `_initSmartAlignment` 与 `_onConfirm`：统一采用 `_transformController.toScene` 毫秒级直接计算取景框在源图上的真实像素选区，消除视窗压制形变并输出 512x512 超清头像。
- [x] 9.3 编写单元测试验证 `FaceCropDialog` 坐标转换逻辑与无损高分辨率裁剪。

## 10. 三视图纯白背景加固与提示词环境词清洗 (Turnaround Pure White Background & Prompt Sanitization)

- [x] 10.1 修改 `CharacterTurnaroundPrompt`：清除 `consistent lighting and background` 诱导词，并在提示词开头注入强力纯白背景声明（`isolated on solid pure white background, clean white studio backdrop, completely blank empty background`）。
- [x] 10.2 实现 `CharacterTurnaroundPrompt.cleanTurnaroundStyleTokens`：过滤全局风格锁中的 `cinematic`, `dark realism`, `lighting`, `atmosphere`, `scene`, `background` 等场景词，仅保留纯艺术画风词。
- [x] 10.3 修改 `_generateTurnaround`：生成基准三视图时严格传递 `referenceImages: []`，阻断历史图片或旧背景作为参考图污染。
- [x] 10.4 编写单元测试验证三视图纯白背景前置约束与风格词清洗效果。

## 12. 三视图 16:9 横屏画幅升级与对齐适配 (Turnaround 16:9 Landscape Aspect Ratio & Smart Alignment)

- [x] 12.1 在 `series_page.dart` 中将基准与形态三视图生图请求统一置为 `width: 1920, height: 1080`（Agnes 2K 16:9 舒展构图）。
- [x] 12.2 在 `StudioProjectManager.cropAndSaveFaceAnchor` 中适配横屏与竖屏自适应坐标。
- [x] 12.3 在 `FaceCropDialog._initSmartAlignment` 中增加横屏 16:9 智能头部自动吸附（X 约 17%，Y 约 20%）。

## 13. 头像截取全原生无损高清保真与本机部署 (Native Resolution Crop & Local Deployment)

- [x] 13.1 在 `FaceCropDialog._onConfirm` 中移除 512x512 强制缩放，直接返回 100% 原生无损裁剪图。
- [x] 13.2 编写与更新单元测试验证横屏尺寸参数传递与原生高清分辨率裁切保真。
- [x] 13.3 运行全部单元测试确保 100% 通过，并执行 `./scripts/deploy_local.sh` 编译 Release、重签名并替换部署至本机 `/Applications/V8WorkToolbox.app`。


