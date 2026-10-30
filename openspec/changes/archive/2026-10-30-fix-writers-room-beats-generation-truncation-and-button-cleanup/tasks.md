## 1. 按钮层级与交互精简 (WritersRoomDialog)

- [x] 1.1 移除小节标题 `🎬 全季分集规划与断章钩子` 右侧重复多余的 `TextButton.icon('重新规划本季大纲')`
- [x] 1.2 确保规格栏（Row 2）右侧常驻按钮与空状态主操作按钮的职责分明、心智统一

## 2. AI 约束引擎长篇抗截断生成与保底重构 (AiConstraintEngine)

- [x] 2.1 优化 `_promptWritersRoomSeasonBeats` 与 `planWritersRoomSeasonBeats` 提示词：当目标集数大于 24 集时，引导模型聚焦规划 4~6 幕宏观篇章与 12~16 个核心高能节拍大纲骨架，规避单次生成 80 集导致的输出 Token 截断与 JSON 损毁
- [x] 2.2 强化 `_SchemaValidators.writersRoomSeasonBeats` 的解析容错与平滑插值韧性，确保返回的 `episodes` 数组长度严格等于目标集数且闭环输出

## 3. 空状态就地错误展示与重试交互 (WritersRoomDialog)

- [x] 3.1 在 `_WritersRoomDialogState` 中引入 `_beatsPlanError` 状态管理，并在 `_planSeasonBeats()` 发生异常时精确捕获并记录错误原因
- [x] 3.2 重构 `_buildEmptyBeatsCard()`，增加规划失败时的就地错误卡片展示与【重新规划】重试主按钮，彻底消除静默失败现象

## 4. 验证与本地应用部署

- [x] 4.1 运行单元测试与静态分析，确保 80 集及大集数规划平滑插值与 Schema 校验 100% 通过
- [x] 4.2 执行 `./scripts/deploy_local.sh` 重新编译并替换本机应用，端到端验证界面无多余同名按钮且点击规划能够稳定输出分集大纲
