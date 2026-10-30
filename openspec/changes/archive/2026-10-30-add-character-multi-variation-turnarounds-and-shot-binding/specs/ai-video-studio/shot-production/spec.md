## ADDED Requirements

### Requirement: 分镜镜头级角色形态绑定与底图动态路由

系统 SHALL 支持在单个分镜（`StudioShot`）中明确绑定出场角色的具体形态版本（`CharacterVariation`）。分镜看板（`_ShotCard`）SHALL 提供角色与形态联动选择组件，允许用户为镜头指定该角色在此刻所处的服装或年龄阶段。

当生图任务队列执行关键帧生成（`ImageGenTask`）时，系统 SHALL 按以下优先级解析角色的三视图参考图：
1. 若该分镜指定了角色的具体形态，且该形态已生成专属三视图（`turnaround_${variation.id}.png`），系统 SHALL 优先采用该形态三视图作为参考图；
2. 若该形态未生成专属三视图，系统 SHALL 平滑回退使用该角色的基准默认三视图（`turnaround.png`）；
3. 若角色均未生成三视图，系统 SHALL 回退使用角色基准参考图（`referenceImages.first`）。

#### Scenario: 分镜卡中选择指定角色的具体形态

- **WHEN** 用户在分镜看板卡片上将角色李长寿的形态从「默认常服」切换为「玄铁重铠」
- **THEN** 系统 SHALL 更新该分镜数据，并在 2 秒防抖后重组该分镜的提示词（注入「玄铁重铠」的正向差异词）

#### Scenario: 生图任务自动匹配形态专属三视图底图

- **WHEN** 用户触发生成一个绑定了「玄铁重铠」形态的分镜关键帧，且该形态已拥有专属三视图
- **THEN** 任务执行器向图像生成适配器传递的 `referenceImages` 中 SHALL 包含 `turnaround_${variation.id}.png`，而非默认的常服三视图

#### Scenario: 缺失形态三视图时平滑降级

- **WHEN** 用户触发生成一个绑定了「少年采药期」形态的分镜关键帧，但该形态尚未生成专属三视图
- **THEN** 任务执行器向图像生成适配器传递的 `referenceImages` 中 SHALL 自动回落使用角色基准默认三视图 `turnaround.png`，确保生图不报错中断
