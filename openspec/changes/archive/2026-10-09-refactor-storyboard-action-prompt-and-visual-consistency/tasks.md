## 1. Prompt 组装器与视觉动作融合

- [x] 1.1 在 `PromptAssembler.buildShotPrompt` 中接入 `parts.actionZh` 视觉画面描述，使其作为核心内容进入生图正向 Prompt
- [x] 1.2 在空镜头（未关联角色）情况下，自动在正向 Prompt 追加环境强化词，并在负向 Prompt 注入 `person, human, face, character, people, man, woman, portrait` 等人物抑制词
- [x] 1.3 确保在有角色时正确关联角色基础 Prompt 与形态差异词

## 2. 分镜看板传参与生成任务对齐

- [x] 2.1 在 `storyboard_board.dart` 的 `_enqueueFrame` 中解析 `shot.sceneId` 对应的 `SceneCard` 并传递给 `ImageGenTask`
- [x] 2.2 在 `ImageGenTask` 中将 `shot.actionZh` 传递给 `PromptAssembler.buildShotPrompt`
- [x] 2.3 确保内联编辑动作 (`action_zh`) 与防抖重算后 Prompt 能够动态感知更新

## 3. 自动化测试与本地部署验证

- [x] 3.1 编写单元测试验证动作注入、场景参数传递与空镜头人物抑制
- [x] 3.2 运行全量短视频工坊相关单元测试
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译 Release 并热替换本机应用
