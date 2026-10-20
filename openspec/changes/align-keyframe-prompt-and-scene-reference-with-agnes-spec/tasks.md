## 1. UI & Task Pipeline Scene Injection

- [x] 1.1 在 `StoryboardBoard._enqueueFrame` 中按 `shot.sceneId` 从 `_scenes` 检索 `SceneCard` 并传入 `ImageGenTask`
- [x] 1.2 在 `ImageGenTask.run` 中增加防漏兜底逻辑：若 `scene == null` 且 `shot.sceneId.isNotEmpty`，通过 `StudioProjectManager.readSceneCard` 自动反查补齐
- [x] 1.3 在 `ImageGenTask._referenceImages` 中确保分镜场景关联的七方位空间主图（如 `spatial_front` / `spatial_back`）可靠注入多参考图列表中
- [x] 1.4 在 `StoryboardBoard._reassemblePrompt` 中补齐 `actionZh`、`scene`、`characters` 等完整上下文，消除提示词单镜重组时的动作与场景丢失

## 2. PromptAssembler Multi-Image & Attention Inversion Architecture

- [x] 2.1 重构 `PromptAssembler.buildShotPrompt`，废弃单一 `promptEn` 回退链，优先提取场景与机位视角的中文物理空间细节（`descriptionZh`）
- [x] 2.2 严格按照 Agnes 官方多图合成规范，在多图输入时首部生成自然语言声明：`[参考图角色与保留要求]`（明确第 1 张图为主要角色、第 N 张图为背景场景，声明保留面容、服装与场景布局）
- [x] 2.3 实施注意力权重纠偏：将分镜核心动作 (`actionZh`) 与视觉焦点前置，角色外貌精简为身份特征锚点，避免百字立绘流水账稀释核心动作
- [x] 2.4 实现室内/封闭场景画风自适应净化：当场景为内景或地下大牢/水牢/密室时，自动剔除“云海雾气、广阔天地、日出日落”等室外互斥词，注入室内微光与环境光影

## 3. Verification & Local Deployment

- [x] 3.1 编写并运行单元测试，验证多图指引词构造、场景中文描述注入、室内词净化及动作焦点前置
- [x] 3.2 执行 `flutter analyze` 确保类型与代码规范健全
- [x] 3.3 严格执行 `./scripts/deploy_local.sh` 编译重新签名并替换本机运行应用
