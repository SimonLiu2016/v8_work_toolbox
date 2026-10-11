## Why

在短视频工坊的分镜看板使用过程中，用户遇到两个阻断级问题：
1. 点击“关键帧”生成图片后，虽然图片文件已成功落盘，但界面抛出 `Null check operator used on a null value` 错误，降低了操作体验并可能打断后续渲染。
2. 点击“视频”生成片段时，上游中转网关返回 HTTP 400 报错 `Bad state: Agnes API 返回 HTTP 400: plugin usage enum is not an allowed value`，导致视频无法生成。实机探测确认原请求体中携带了非法的 `"size": "720P"` 参数枚举，被网关拦截拒绝。

## What Changes

1. **修正 Agnes 视频请求体参数契约**：移除 `AgnesVideoAdapter` 中非法的硬编码 `'size': '720P'` 字段，对齐 Agnes/兼容网关推荐的 `model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, `first_frame` 契约。
2. **强化看板缩略图与渲染空安全**：在 `storyboard_board.dart` 的 `_Thumbnail` 及运镜候选面板中消除对 getter 的重复求值与非安全 `!` 强断言，采用局部不可变缓存变量保障在异步刷新时稳定渲染。
3. **补充单元测试与回归校验**：验证 Agnes 视频生成请求体的 Payload 结构不含非法 `size` 字段；验证缩略图及分镜渲染空安全。

## Capabilities

### Modified Capabilities
- `storyboard-visual-composition`: 规范视频生成请求 Payload 契约与看板缩略图防崩溃安全渲染保证。

## Impact

- 受影响代码：`lib/tools/ai_video_studio/services/video_gen_adapter.dart`、`lib/tools/ai_video_studio/ui/storyboard_board.dart`。
- 测试代码：`test/agnes_studio_pipeline_test.dart`。
