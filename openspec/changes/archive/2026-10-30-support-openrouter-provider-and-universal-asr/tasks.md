## 1. 供应商体系扩展与预设集成

- [x] 1.1 在 `lib/services/ai_config_store.dart` 的 `AiProtocolType` 枚举中添加 `openrouter('OpenRouter 协议')`
- [x] 1.2 在 `lib/services/ai_service.dart` 中为 `AiProtocolType.openrouter` 复用 OpenAI 模型发现与会话路由
- [x] 1.3 在 `lib/shell/ai_config_page.dart` 中添加 `OpenRouterPreset` 常量定义及添加供应商弹窗的 ActionChip 预设

## 2. 统一 ASR 抽象与 OpenRouter 客户端实现

- [x] 2.1 创建 `lib/tools/live_translator/services/live_asr_client.dart`，定义 `LiveAsrClient` 统一接口
- [x] 2.2 在 `lib/tools/live_translator/services/openrouter_asr_client.dart` 中实现 `OpenRouterAsrClient`，包含内存级 `pcmToWav` 封装与 HTTP POST 请求
- [x] 2.3 修改 `lib/tools/live_translator/services/stepfun_asr_client.dart`，使其实现 `LiveAsrClient` 接口

## 3. 实时翻译协调器槽位自适应重构

- [x] 3.1 修改 `lib/tools/live_translator/services/live_translator_coordinator.dart`，移除对 `stepfun` 的硬编码过滤，按 `stt` 槽位自适应构建 `StepFunAsrClient` 或 `OpenRouterAsrClient`
- [x] 3.2 更新错误提示，支持提示通用的 STT 槽位配置引导

## 4. 单元测试与部署验证

- [x] 4.1 在 `test/live_translator_test.dart` 中增加 OpenRouter 端点解析、PCM 转 WAV 封包及多供应商 ASR 路由测试
- [x] 4.2 运行 `flutter test test/live_translator_test.dart` 与 `flutter analyze` 确保 0 错误
- [x] 4.3 执行 `./scripts/deploy_local.sh` 编译 Release、重签名并在本地部署生效
