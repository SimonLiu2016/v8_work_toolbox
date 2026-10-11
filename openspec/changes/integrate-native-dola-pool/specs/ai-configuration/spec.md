## ADDED Requirements

### Requirement: Builtin Dola Video Provider Candidate
系统 SHALL 支持检测并识别内置的 Dola 免费号池引擎，并允许用户在系统全局视频模型槽位（Video Slot）中将其候选模型（如 `seedance-2.5`、`seedance-2.0`）加入候选列表。

#### Scenario: Bind Dola pool model to video slot
- **WHEN** 用户在 AI 基础设施设置中配置或选择内置 Dola 号池
- **THEN** 系统列出可用的 Seedance 模型，允许用户将其加入 video 槽位候选列表并调整优先级
