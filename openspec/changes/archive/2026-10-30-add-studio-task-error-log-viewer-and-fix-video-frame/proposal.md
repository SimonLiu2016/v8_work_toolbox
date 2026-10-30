## Why

短视频工坊在生成关键帧与视频片段时，长任务一旦出错（如上游模型报错、网络超时或参数不匹配），目前错误信息在分镜卡片与队列抽屉中仅单行/两行省略截断展示，无法查看全文也无法复制，严重影响问题排查与用户反馈。同时，Agnes 视频生成中首帧（`first_frame`）参数未能被部分网关兼容解析，导致报 `keyframe 模式需要 first_frame`。

## What Changes

1. **分镜卡片与任务队列的报错日志弹窗与一键复制**：
   - 分镜卡片上的错误标签与任务队列抽屉中的任务条目支持点击或快捷图标弹出「任务执行详情与报错日志」对话框。
   - 对话框内提供结构化的任务信息（镜号、类型、持续时长、模型等）及完整多行错误文本，支持文本框划选，并提供全局【复制报错日志】按钮，复制后给出 Toast 提示。
2. **视频生成全链路接入 AiLogger**：
   - 为 `VideoGenAdapter`（包括 `AgnesVideoAdapter`、`SenseAudioVideoAdapter` 等）接入 `AiLogger`，在请求发出、响应返回与发生异常时均记录完整的 endpoint、model、payload 摘要及报错信息至应用系统日志文件。
3. **Agnes 视频首帧图片参数与格式兼容**：
   - 加固 `AgnesVideoAdapter` 对 `first_frame` 的处理，保证图片数据在首帧与兼容字段中的正确传递与容错。

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: 增加长任务报错日志的可视化多行查看与复制机制，规范视频生成全链路日志跟踪与首帧兼容。

## Impact

- 受影响文件：`lib/tools/ai_video_studio/ui/storyboard_board.dart`、`lib/tools/ai_video_studio/services/video_gen_adapter.dart`、`lib/tools/ai_video_studio/services/studio_task_queue.dart`。
