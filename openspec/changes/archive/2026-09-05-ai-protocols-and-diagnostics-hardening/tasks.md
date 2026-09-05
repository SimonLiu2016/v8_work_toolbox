## 1. 真实支持 Anthropic 与 Gemini 协议

- [x] 1.1 在 `lib/services/ai_service.dart` 中实现 Anthropic 模型发现 (`_discoverAnthropicModels`) 与对话请求 (`_chatAnthropic`)
- [x] 1.2 在 `lib/services/ai_service.dart` 中实现 Google Gemini 模型发现 (`_discoverGeminiModels`) 与内容生成 (`_chatGemini`)
- [x] 1.3 在 `lib/services/ai_service.dart` 中统一 `testConnection`，通过实际网络请求验证 Anthropic 与 Gemini 端点及 API Key 的有效性

## 2. AI 磁盘研判体验与错误透明化

- [x] 2.1 在 `lib/tools/slimmer/ai_disk_diagnostics_service.dart` 中记录单条/批量失败详情 (`lastError`)，避免错误被静默吞没
- [x] 2.2 在 `lib/tools/slimmer/smart_disk_slimmer_page.dart` 中优化批量研判选择逻辑：优先研判用户显式勾选的项目，若无勾选则研判未分析项
- [x] 2.3 在 `SmartDiskSlimmerPage` 中针对研判失败情况提供带具体原因的 SnackBar / Dialog 提示

## 3. 测试、分析与全量构建验证

- [x] 3.1 编写并更新针对 Anthropic / Gemini 请求解析与模型探测的单元测试
- [x] 3.2 运行 `flutter test` 确保所有用例通过
- [x] 3.3 运行 `flutter analyze --no-fatal-infos` 达到 0 错误 0 告警
- [x] 3.4 运行 `flutter build macos` 成功编译生成 Release 应用
