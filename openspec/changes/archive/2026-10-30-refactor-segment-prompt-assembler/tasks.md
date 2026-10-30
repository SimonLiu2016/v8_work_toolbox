## 1. 预设清洗与短语去重工具

- [x] 1.1 在 `studio_models.dart` 中修正 `StudioProductionType.anime3d`，移除 `Octane render` 冲突渲染器词。
- [x] 1.2 在 `prompt_assembler.dart` 中实现 `deduplicatePhrases` 短语级去重与互斥渲染管线过滤工具方法。

## 2. 重构片段提示词组装逻辑

- [x] 2.1 在 `PromptAssembler.buildSegmentPrompt` 中采用官方 `<Picture N>` 占位符替代 `(reference {{ref N}})`。
- [x] 2.2 实现主物理场景锁定机制，并实现 `filterEmptySceneTokens` 过滤有角色出场时的 `empty room`、`no humans` 等排他词。
- [x] 2.3 剥离 `dialogue:` 对白台词文本，去除 `shot N |`、`camera:`、`state:` 等剧本符号，整合连贯的视觉动作。
- [x] 2.4 移除 `total duration Xs` 与 `continuous single take` 文本泄露，优化运镜与机位指令协调。

## 3. 自动化测试与工程验证

- [x] 3.1 编写单元测试验证 `buildSegmentPrompt`：验证 `<Picture N>` 语法、短语去重、排他词清洗、台词剥离与动作叙事整合。
- [x] 3.2 运行 `flutter analyze` 与针对性单元测试确保无错误与回归。
- [x] 3.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用。
