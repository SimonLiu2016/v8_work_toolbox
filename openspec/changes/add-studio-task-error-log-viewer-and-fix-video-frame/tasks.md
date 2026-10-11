## 1. 任务报错详情弹窗与复制机制

- [x] 1.1 在 `lib/tools/ai_video_studio/ui/storyboard_board.dart` 中实现 `_TaskErrorDetailDialog` 弹窗，支持划选完整报错文本、查看任务时间/类型并一键复制到剪贴板
- [x] 1.2 在 `_ShotCard` 的失败提示区域增加可点击交互及日志图标，点击触发错误弹窗
- [x] 1.3 在 `_QueueDrawer` 队列抽屉的失败任务 ListTile 上增加点击与复制日志交互

## 2. 视频生成接入 AiLogger 与参数加固

- [x] 2.1 在 `lib/tools/ai_video_studio/services/video_gen_adapter.dart` 的 `AgnesVideoAdapter` 中完整接入 `AiLogger`（请求、响应与异常日志记录）
- [x] 2.2 在 `AgnesVideoAdapter` 中加固首帧图片参数构造，确保上游网关稳定识别

## 3. 验证与本地应用热替换部署

- [x] 3.1 编写单元测试验证日志记录与任务详情弹窗能力
- [x] 3.2 运行短视频工坊相关自动化测试
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译 Release 并热替换本机应用
