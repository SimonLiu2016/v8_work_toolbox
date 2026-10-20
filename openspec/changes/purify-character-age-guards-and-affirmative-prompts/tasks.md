## 1. 纯肯定式正向骨骼身量与体态比例重构

- [x] 1.1 在 `PromptAssembler` 中重构 `resolveAgeStagingGuard`，彻底清除所有否定句式（“非低幼儿童”、“非小娃娃”等），替换为具象肯定表达（少年：接近成人的纵向骨骼身长拉伸、165~170cm、宽阔肩膀、成年人头身比）。
- [x] 1.2 重构 `resolveProportionAnchor` 中矮壮与微胖的体态表达，移除“非低幼矮短”否定句，采用写实青年敦实体魄与舒展身长描述。
- [x] 1.3 增加 `sanitizePositiveAffirmative` 纯肯定式安全清洗过滤器，在组装下发生图引擎前自动剔除任何遗漏的否定词句，兜底防止“粉色大象效应”。

## 2. 角色年龄回溯与置顶保护机制（Age Inheritance）

- [x] 2.1 在 `PromptAssembler` 与 `CharacterTurnaroundPrompt` 中实现 `extractExplicitAgeAnchor`，当细分容貌体态描述缺漏年龄时，自动回溯 `description_zh` 抓取明确年龄数字（如“十五六岁”），并将标准年龄与青年男子身份置顶注入到正向生图提示词最前列。
- [x] 2.2 在 `series_page.dart` 的 `_generateTurnaround` 中传递完整角色卡或回溯文本，确保界面点击生成三视图时触发年龄回溯置顶保护。

## 3. 小说主资产全案解构 System Prompt 强化

- [x] 3.1 在 `AiConstraintEngine.buildNovelMasterExtractionPrompt` 中强化 `facial_features_zh` 提炼规则，强制保留原著中角色的明确年龄数字或人生阶段，严禁在解耦时剔除年龄。
- [x] 3.2 同步检查并更新 `_SchemaValidators.novelMasterExtraction` 与相关测试断言。

## 4. 出厂提示词模板升级与存储自愈

- [x] 4.1 在 `studio_models.dart` 中更新 `character_age_staging` 出厂模板内置默认值为新版纯肯定规范。
- [x] 4.2 在 `StudioPresetStore` 中增加旧版否定词模板平滑升级逻辑，并验证单测与自愈机制。

## 5. 单元测试验证与本地部署

- [x] 5.1 编写或更新单元测试：验证余小白（16岁白胖少年）正向提示词中绝对不含任何“非低幼”、“儿童”、“小娃娃”等词，且置顶包含显式年龄数字与青年骨骼身长。
- [x] 5.2 运行相关全套单元测试，确保全部绿灯通过。
- [x] 5.3 按照工程规范执行 `./scripts/deploy_local.sh` 重新构建并部署替换本机 `/Applications/V8WorkToolbox.app`。
