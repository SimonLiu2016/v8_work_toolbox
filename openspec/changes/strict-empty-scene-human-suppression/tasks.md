## 1. 肯定式无人空镜专有词典与首尾夹逼架构

- [x] 1.1 在 `ScenePromptBuilder` 中重构正向提示词常量，将 `no humans` 彻底替换为肯定式建筑/环境专有词典（`emptyHeadLock`, `emptyTailLock`）
- [x] 1.2 重构 `ScenePromptBuilder.buildPositivePrompt`，实现 Prompt 首尾双重夹逼拓扑（头部底板锁 + 时代风格环境 + 视角 + 清洗后陈设 + 尾部收尾锁）

## 2. 提示词实体与动作敏感情报清洗器 (Sanitizer)

- [x] 2.1 在 `ScenePromptBuilder` 中实现 `sanitizeBasePrompt(String basePrompt)`，正则剥离人物实体、人称代词、职业称谓与互动动作词
- [x] 2.2 在 `ScenePromptBuilder.buildPositivePrompt` 与 `_generateDirectionImage` / `_generateMultiAngleImages` 中接入前置清洗

## 3. 图像生成适配器负向提示词全链路打通

- [x] 3.1 改造 `SystemAiImageAdapter.generate`，使 `isAgnes` 分支与 OpenAI 兼容分支均完整装配并传递 `negative_prompt`
- [x] 3.2 改造 `SenseAudioImageAdapter.generate`，将 `negative_prompt` 纳入 payload 中传递给接口

## 4. AI 空间解构与提示词翻译模板源头强化

- [x] 4.1 升级 `AiConstraintEngine._promptSceneSpatialDeconstruction`，增加硬性物理置景约束，杜绝 LLM 在英文 Prompt 中夹带人称代词与职业人物
- [x] 4.2 升级 `series_page.dart` 中场景 Prompt 翻译（`_translatePrompt`）的提示语与约束

## 5. 验证与本地构建部署

- [x] 5.1 运行静态代码检查与单元测试（`flutter analyze` 与 `flutter test`）
- [x] 5.2 执行 `./scripts/deploy_local.sh` 重新构建、重新签名并替换本机应用完成端到端验证
