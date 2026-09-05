## 1. 凭证双层持久化加固

- [x] 1.1 在 `lib/services/keychain_service.dart` 中实现 `.secrets.dat` 本地加密文件持久化兜底，支持在 Keychain 不可用时稳定跨进程恢复密钥
- [x] 1.2 编写针对 KeychainService 本地文件回退与重启恢复的单元测试

## 2. 弹窗密钥状态感知与探测链路修复

- [x] 2.1 在 `lib/shell/ai_config_page.dart` 中展示当前供应商的密钥存储状态（“✓ 已配置加密密钥”）
- [x] 2.2 在 `ai_config_page.dart` 中修正探测逻辑，支持优先使用输入框新 Key，空时自动回退读取已存 Key
- [x] 2.3 在 `lib/services/ai_service.dart` 中移除所有探测假模型 Fallback，遇到错误直接抛出真实原因
- [x] 2.4 在 `ai_config_page.dart` 中增加常用供应商快速预设模板（OpenAI / DeepSeek / Claude / Gemini / Ollama / SiliconFlow）

## 3. 全量测试与构建验证

- [x] 3.1 运行 `flutter test` 确保全套测试用例通过
- [x] 3.2 运行 `flutter analyze --no-fatal-infos` 达到 0 错误 0 告警
- [x] 3.3 运行 `flutter build macos` 成功编译生成最新 Release 应用
