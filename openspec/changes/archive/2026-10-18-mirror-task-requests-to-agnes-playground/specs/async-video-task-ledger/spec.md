## ADDED Requirements

### Requirement: 视频任务请求快照高保真留痕

系统在向云端提交视频生成请求时，SHALL 在台账记录中完整保留本次调用的请求快照。快照 SHALL 明确区分首帧（firstFramePath）、尾帧（lastFramePath）与参考素材（referencePaths）的本地文件路径，保留画幅比例（aspectRatio）、清晰度档位、时长、种子与提示词，并持久化发往云端的真实脱敏 HTTP 请求体 JSON（将 base64 图片数据脱敏替换为体积摘要），以保证任务的可追溯性与镜像复现能力。

#### Scenario: 任务创建时留存高保真快照
- **WHEN** 系统向云端提交一次包含参考图或首尾帧的视频任务
- **THEN** 系统写入台账的请求快照中 SHALL 包含独立的首尾帧路径、参考图路径列表与画幅比例字段
- **AND** 系统写入台账的请求快照中 SHALL 包含真实发往云端的脱敏 HTTP 请求体 JSON

#### Scenario: 从台账追溯真实请求体
- **WHEN** 用户或上层模块查询台账记录的请求快照
- **THEN** 系统 SHALL 能直接读取脱敏后的真实请求 JSON，且提示词内容与提交给云端接口的完全一致
