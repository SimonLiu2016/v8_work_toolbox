## Why

分镜看板生成关键帧时，模型接口已成功返回图片 URL（如腾讯云 COS `https://cos-platform-outputs.agnes-ai.cn/...`），但在下载图片并写入本地文件时，由于公网 CDN 节点安全策略、长连接复用异常或网络抖动，触发了 `ClientException with SocketException: Connection reset by peer`，导致生成任务中断。需要实现稳健的独立短连接下载客户端，并增加指数退避自动重试与标准浏览器请求标头，确保各种 CDN 节点下图片均能成功落盘。

## What Changes

- 在 `SystemAiImageAdapter` 及 `SenseAudioImageAdapter` 中抽离或升级图片下载器：
  - 弃用长连接池复用，采用独立的短连接（`Connection: close`）与真实浏览器标头（`User-Agent`、`Accept` 等）。
  - 增加对 `Connection reset by peer`、TLS 握手超时等临时性网络异常的自动重试机制（默认最多 3 次，间隔指数递增）。
  - 设置合理的单次下载超时（如 20 秒），防止死等挂起。

## Capabilities

### Modified Capabilities
- `ai-configuration`: 强化 AI 视觉模型多媒体产物的下载通道健壮性与 CDN 节点防断连重试。

## Impact

- `lib/tools/ai_video_studio/services/image_gen_adapter.dart`: 增强图片下载实现与错误恢复机制。
- `test/agnes_studio_pipeline_test.dart`: 增加 CDN 断连自动重试与成功下载的单元测试用例。
