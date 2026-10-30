## 1. 数据模型与 JSON 兼容扩展

- [x] 1.1 为 `SceneCard` 添加 `systemPromptOverride` 和 `panoramaSystemPromptOverride` 字段及 `copyWith`/`toJson`/`fromJson` 兼容
- [x] 1.2 为 `CharacterVariation` 添加 `systemPromptOverride` 字段及 `copyWith`/`toJson`/`fromJson` 兼容
- [x] 1.3 为 `PropCard` 添加 `systemPromptOverride` 字段及 `copyWith`/`toJson`/`fromJson` 兼容

## 2. 提示词组装器支持覆盖与组件拆解

- [x] 2.1 修改 `ScenePromptBuilder.buildPanoramaPrompt` 支持 `panoramaSystemPromptOverride` 覆盖头尾透视锚点
- [x] 2.2 修改 `ScenePromptBuilder.buildPositivePrompt` 优先采用 `systemPromptOverride` 覆盖空镜环境底板
- [x] 2.3 修改 `CharacterTurnaroundPrompt.buildForVariation` 支持 `systemPromptOverride` 覆盖三视图骨架与布局规范
- [x] 2.4 修改 `PropPromptBuilder.buildPositivePrompt` 支持 `systemPromptOverride` 覆盖单品资产规范

## 3. 通用生图 Prompt 预览/编辑对话框

- [x] 3.1 创建 `AssetPromptPreviewDialog` 组件，展示正向 Prompt、负向 Prompt、组件概览与字数统计，支持一次性编辑生成与还原默认

## 4. 资产编辑界面交互集成

- [x] 4.1 在场景编辑弹窗中集成全景母图与方位视角生图的 Prompt 预览/编辑入口，增加系统提示词组件折叠覆盖面板
- [x] 4.2 在角色形态三视图生成区集成 Prompt 预览/编辑入口，增加系统提示词组件折叠覆盖面板
- [x] 4.3 在道具编辑弹窗中集成道具图生成的 Prompt 预览/编辑入口，增加系统提示词组件折叠覆盖面板

## 5. 验证与工程部署

- [x] 5.1 编写单元测试覆盖覆盖字段序列化/反序列化及各 PromptBuilder 覆盖生效逻辑
- [x] 5.2 运行相关测试套件确保全部 PASS
- [x] 5.3 执行 `./scripts/deploy_local.sh` 完成 Release 构建与本地应用替换部署
