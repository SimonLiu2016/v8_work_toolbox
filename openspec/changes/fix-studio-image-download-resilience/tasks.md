## 1. 稳健图像下载器实现

- [x] 1.1 在 `image_gen_adapter.dart` 中实现通用 `downloadImageWithRetry` 工具函数，配置 `Connection: close` 与标准 User-Agent
- [x] 1.2 为图片下载集成 3 次退避重试（处理 SocketException、HandshakeException、Connection reset 等异常）
- [x] 1.3 在 `SystemAiImageAdapter` 与 `SenseAudioImageAdapter` 中接入稳健下载器

## 2. 单元测试与部署验证

- [x] 2.1 编写单元测试验证下载重试机制与网络异常容错
- [x] 2.2 执行 `./scripts/deploy_local.sh` 编译并热替换部署本机应用

