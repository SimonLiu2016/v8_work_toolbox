## 1. StudioProjectManager 原子分镜更新与媒体自愈修复

- [x] 1.1 在 `StudioProjectManager` 中实现 `updateShot` 原子回写接口，在 `_writeChains` 锁链路中重读最新 JSON、仅定位更新单个分镜并原子写入
- [x] 1.2 修复 `_healEpisodeMediaIfNeeded` 探测逻辑，同时支持 `shot_${shot.number}.png/mp4` 与 `${shot.number}.png/mp4` 恢复
- [x] 1.3 编写/补充针对 `updateShot` 与 `_healEpisodeMediaIfNeeded` 命名探测的单元测试

## 2. 异步生成任务 (ImageGenTask / VideoGenTask) 原子化重构

- [x] 2.1 重构 `ImageGenTask`：移除回写旧 `episode` 的做法，在 `finally`（记录 `assembledPrompt`）及成功完成时均调用 `manager.updateShot`
- [x] 2.2 重构 `VideoGenTask`：完成视频生成后调用 `manager.updateShot` 更新 `clipPath`、`firstFramePath`、`lastFramePath` 与状态
- [x] 2.3 验证并发多任务模拟下，各分镜数据互不覆盖且完整保留

## 3. 场景生成 (ScenePromptBuilder) 封闭与室内场景环境词净化

- [x] 3.1 在 `ScenePromptBuilder.buildPositivePrompt` 中增加对 `isEnclosedScene` 的检测与净化处理，剔除仙山云海等室外锚点
- [x] 3.2 增加单元测试验证：仙侠修真题材下生成“巡城司大牢”场景底图时不包含云雾奇峰亭台

## 4. 提示词组装器 (PromptAssembler) 多图模式轻量化与站位解耦

- [x] 4.1 在 `PromptAssembler.buildShotPrompt` 中优化多图参考模式分支：当具备角色参考图时剔除 `basePromptPositive` 静态容貌长文
- [x] 4.2 重构 `【同框人物与站位】` 与 `【出场主体】`：专职输出画内空间站位与构图主客关系，剔除角色外观档案描述
- [x] 4.3 调整多图参考的场景保留指令为“保留场景建筑材质与环境光影，镜头根据分镜动作动态取景”，增强镜头构图多样性
- [x] 4.4 针对单角色与多角色分镜生图提示词补充单元测试，验证动作权重前置与冗余文本剥离

## 5. 工程级构建与整机验证

- [x] 5.1 运行全量 `flutter test`，确保所有测试用例通过
- [x] 5.2 按照工程级规范执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用，验证已落盘关键帧自愈展示与重新生成效果
