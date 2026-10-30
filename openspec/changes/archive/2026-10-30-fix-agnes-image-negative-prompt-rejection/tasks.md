## 1. 能力矩阵支持声明

- [x] 1.1 在 `lib/services/media_capability.dart` 中为 `MediaModelCapability` 添加 `supportsNegativePrompt` 字段并在 `agnesImage` 声明中将其设为 `false`。
- [x] 1.2 在 `test/media_capability_matrix_test.dart` 中增加对图像模型负向提示词能力声明的断言测试。

## 2. 图像适配器请求体修复

- [x] 2.1 在 `lib/tools/ai_video_studio/services/image_gen_adapter.dart` 中的 `SystemAiImageAdapter.generate` 方法内，彻底移除 `isAgnes` 分支下注入的顶层及 `extra_body` 中的 `negative_prompt`。
- [x] 2.2 增加调试/审计日志，当传入非空负向词但模型不支持时输出信息留痕。

## 3. 自动化测试与本机部署

- [x] 3.1 在 `test/agnes_studio_pipeline_test.dart` 中补充测试用例：验证当传入非空 `negativePrompt` 时，`SystemAiImageAdapter` 发往 Agnes 的请求体中不包含 `negative_prompt` 字段。
- [x] 3.2 运行 `flutter analyze` 及相关单元测试确保无回归。
- [x] 3.3 执行 `./scripts/deploy_local.sh` 重新构建并替换本机应用。
