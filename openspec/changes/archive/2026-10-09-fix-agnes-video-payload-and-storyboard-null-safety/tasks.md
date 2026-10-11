## 1. Agnes 视频生成 Payload 修复

- [x] 1.1 在 `lib/tools/ai_video_studio/services/video_gen_adapter.dart` 中移除 `AgnesVideoAdapter` 内非法的 `'size': '720P'` 字段，确保 payload 仅包含合法参数
- [x] 1.2 确认 `mode: keyframe` 与 `aspect_ratio: 9:16` 格式与上游网关契约完全一致

## 2. 分镜看板缩略图及相关视图空安全加固

- [x] 2.1 在 `lib/tools/ai_video_studio/ui/storyboard_board.dart` 的 `_Thumbnail` 中使用不可变局部变量缓存 `frameFile` 与 `clipFile`，移除所有非安全 `!` 强断言
- [x] 2.2 防御性检查 `_CameraMoveSheet` 与 `_MediaPreviewDialog`，消除潜在的空值回退隐患

## 3. 测试验证与本地应用热替换部署

- [x] 3.1 在 `test/agnes_studio_pipeline_test.dart` 中更新并添加针对 Agnes 视频请求体结构与无非法 size 字段的自动化测试
- [x] 3.2 运行短视频工坊相关单元测试确保全量通过
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译 Release 并热替换本机应用
