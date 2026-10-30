## ADDED Requirements

### Requirement: 剧本工作台节拍级道具标注与分镜继承

系统在剧本工作台执行小说单章改编或根据大纲生成分场剧本时，SHALL 为每个戏剧节拍（`DramaBeat`）结构化输出出场或交互的道具名称列表（`props`），并在涉及手持动作时输出手持道具（`holdingItem`）与持握方位（`holdingHand`，包括 `right`、`left` 或 `both`）。当用户从剧本工作台触发生成分镜（一键转分镜或重新拆镜）时，系统 SHALL 自动将节拍中出现的道具名称匹配到当前剧集的道具卡，并将匹配成功的道具卡 ID 填充进 `StudioShot.propIds`；同时将手持道具与持握方位自动映射至镜头连续性台账的 `ShotContinuity.holdingRight` 或 `ShotContinuity.holdingLeft`。

#### Scenario: 剧本工作台生成带道具与手持标注的戏剧节拍
- **WHEN** 用户在剧本工作台点击“从原著小说正文改编”或“AI 剧本生成”
- **THEN** 生成的分场剧本节拍列表中，涉及道具交互的节拍条目包含 `props` 数组，且涉及手持的节拍包含 `holdingItem` 与 `holdingHand` 字段

#### Scenario: 一键转分镜自动继承节拍道具与手持连续性
- **WHEN** 用户在剧本工作台或分镜看板由已有剧本节拍生成 5D 分镜
- **THEN** 生成的每个分镜自动匹配同名道具卡并将道具卡 ID 填入该镜头的 `propIds` 列表中，且根据节拍手持信息自动填充 `continuity.holdingRight` 或 `continuity.holdingLeft`，用户无需手动重新添加道具绑定
