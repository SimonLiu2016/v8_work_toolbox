## 1. 基础模型与体态比例中立化 (Model & Proportion Anchor Refactor)

- [x] 1.1 修改 `lib/tools/ai_video_studio/models/studio_models.dart` 中的 `CharacterTurnaroundProportion.standard` 锚点：将 `tall and slender figure, mature adult anatomy` 改为年龄与体型中立的 `natural human anatomy, well-proportioned figure`，防止成年修长先验压制“白胖富态”与“少年”。
- [x] 1.2 编写单元测试验证 `CharacterTurnaroundProportion.standard` 序列化与新锚点词。

## 2. 提示词编译器年龄与无须防御守卫 (Prompt Assembler Age & Clean-Shaven Guard)

- [x] 2.1 在 `lib/tools/ai_video_studio/services/prompt_assembler.dart` 的 `CharacterTurnaroundPrompt` 中新增面容与胡须感知防御逻辑：当检测到角色中文描述、正向词、差异词或负向词命中少年/青年/儿童/无须特征（或排斥胡须）时，在 Positive Prompt 中自动注入 `clean-shaven, completely hairless face, smooth bare skin and chin, youthful teenage face, no facial hair`，彻底压制 Flux / SD 在古装长衫下的蓄须偏置。
- [x] 2.2 在 `PromptAssembler.mergeVariation` 中增加纯中文差异词规范化映射：当用户在正向差异词填“少年”或在负向差异词填“长胡子/胡子”等中文自然语言时，自动对齐映射为有效英文提示词（并在正向补充 `clean-shaven`，负向补充 `beard, mustache`）。
- [x] 2.3 编写单元测试验证 `CharacterTurnaroundPrompt` 的正向无须防御与中文差异词对齐。

## 3. LLM 角色提示词翻译规则强化 (Prompt Translation Constraint Enhancement)

- [x] 3.1 在 `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` 的 `_promptPromptTranslation` 提示词模板中强化约束：明确要求当中文描述指出角色为少年、儿童、青年或未蓄须者时，`prompt_positive` 必须显式输出 `clean-shaven, hairless face, smooth bare chin, youthful teenage face`，严禁泛化为 `1man` 或老掌柜；`prompt_negative` 必须同步补齐 `beard, mustache, facial hair, goatee, stubble, wrinkles, elderly, mature adult face`；并对白胖体态强制输出 `chubby build, plump body, fair-skinned`。
- [x] 3.2 验证 `AiConstraintEngine.promptTranslation` 的 Prompt 结构与 Schema 单元测试。

## 4. 界面交互与形态参考底图解耦 (UI Interaction & Reference Image Decoupling)

- [x] 4.1 在 `lib/tools/ai_video_studio/ui/series_page.dart` 的形态三视图生成面板增加「继承默认脸模」开关（默认勾选）；当用户取消勾选时，生成形态三视图不传递历史参考底图（`refImages` 为空），切断已长胡子旧图的五官克隆死锁。
- [x] 4.2 差异词输入框交互优化：在形态差异词界面提供提示文案（支持直接输入中文，如“少年”或“去除胡须”，系统自动转换为强力正向去须英文词）。

## 5. 综合验证与本地构建部署 (Verification & Local Deployment)

- [x] 5.1 运行所有相关单元测试与回归测试集，确保 100% 通过。
- [x] 5.2 按照工程规范执行 `./scripts/deploy_local.sh` 编译 Release、重签名并部署至本机 `/Applications/V8WorkToolbox.app`。
