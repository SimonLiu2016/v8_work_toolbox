## Why

在短视频工坊生成大段视频或分镜视频时，用户需要排查底层发往 AI 视频生成模型的实际请求内容。当前通过任务队列与看板将任务导入「Agnes 试炼场」时，存在画幅比例字段不一致导致比例丢失、首尾帧与参考素材角色混淆导致模式冲突、以及无法一键复制底层真实脱敏 HTTP Request Body 等问题，使得试炼场无法 100% 镜像真实发送的请求，阻碍用户复现实验与调优提示词。

## What Changes

- **画幅比例与参数键名对齐**：解决 `aspectRatio` 与 `ratio` 序列化命名字段不一致导致的比例丢失，确保时长、清晰度档位、种子、画幅比例 100% 还原。
- **媒体素材角色分工精准还原**：在 `VideoTaskLedgerEntry.requestSnapshot` 中显式分离 `firstFramePath`、`lastFramePath` 与 `referencePaths`，导入试炼场时严格还原对应素材角色（首帧、尾帧、参考图），杜绝将首尾帧误标为参考素材触发的模式互斥拦截。
- **真实 HTTP Request Body 镜像快照与一键复制**：适配器在向网络层发起请求前，记录高保真脱敏请求体 JSON（将巨型 base64 替换为易读尺寸摘要），在试炼场与任务队列条目中提供一键「复制真实请求 JSON」与查看对话框。
- **任务队列全量 AI 调用可追溯**：在看板任务队列抽屉中，使每个任务单元均可查看其对应的 AI 请求快照，并支持一键转入 Agnes 试炼场调试与重新发起。

## Capabilities

### Modified Capabilities

- `agnes-playground`: 增强从工坊台账一键导入时的参数与素材角色对齐能力，增加真实 HTTP 脱敏请求 JSON 的一键查看与复制。
- `async-video-task-ledger`: 增强请求快照字段，区分首尾帧与参考图路径，并持久化真实脱敏请求 Payload。

## Impact

- `lib/tools/ai_video_studio/services/video_gen_adapter.dart`: 丰富 `requestSnapshot` 字段，保存脱敏 Payload 与明确的素材角色。
- `lib/tools/ai_video_studio/services/video_task_ledger.dart`: 支持读取和保存真实请求体快照。
- `lib/tools/agnes_playground/models/playground_models.dart`: 改造 `PlaygroundDraft.fromLedgerEntry`，支持键名容错与首尾帧角色恢复。
- `lib/tools/agnes_playground/ui/playground_page.dart`: 在脱敏请求弹窗中支持一键复制完整 JSON 请求体。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: 优化任务队列的试炼场调试入口与参数传递。
