## ADDED Requirements

### Requirement: 片段任务多参考图模式流转

在提交片段大段视频生成任务（`SegmentVideoGenTask`）时，系统 SHALL 显式将生成模式标记为 `reference`（多参考图模式）。适配器在收到携带多张参考图且无关键首尾帧的请求时，SHALL 将所有参考图装配进请求体的 `images` 数组中，并在日志与台账中准确记录参考图总数。系统 SHALL NOT 将多参考图静默降级为单张图片的首帧关键帧模式。

#### Scenario: 片段任务以 reference 模式提交多张图片
- **WHEN** 片段大段视频任务启动，收集到 3 位角色与 1 处场景共 4 张参考图
- **THEN** 系统以 `reference` 模式构建云端请求，将 4 张图片全量包含在 `images` 中发送至视频模型，任务台账与日志中正确记录 4 张参考图已被提交。
