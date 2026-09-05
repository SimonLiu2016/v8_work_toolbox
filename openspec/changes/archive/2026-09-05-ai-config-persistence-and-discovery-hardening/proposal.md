## Why

在之前的实际使用中，AI 配置链路暴露出两个严重影响可用性的问题：
1. **未签名/调试环境 Keychain 写入失败导致重启丢 Key**：`KeychainService` 依赖 `flutter_secure_storage`，在 macOS 未签名或缺少 Keychain entitlement 环境下抛异常后仅暂存于 RAM `_memoryFallback`，软件重启后密钥全部丢失；
2. **编辑已有供应商探测时密钥丢失与虚假回退**：编辑弹窗写死了 `keychainKeyId: 'temp'`，导致探测无法读取原有的已存 Key；且在服务端报错时回退了写死的假模型列表。

## What Changes

- **双重凭证持久化机制 (`KeychainService`)**：
  - 优先调用系统原生 Keychain；
  - 若系统 Keychain 抛出异常（如未签名/缺失权限），自动回退至本地混淆加密存储文件（`~/Library/Application Support/V8WorkToolbox/.secrets.dat`）；
  - 确保应用退出或重启后凭证 100% 能够恢复，彻底杜绝丢 Key。
- **弹窗密钥状态感知与探测链路修复 (`ai_config_page.dart` & `AiService`)**：
  - 编辑弹窗明确展示当前供应商「✓ 已保存加密密钥」状态指示；
  - 点击「自动探测发现」时，若输入框未填新 Key，自动读取已存 Key 传给 `discoverModels`；
  - 移除任何假模型静态回退，探测或测试失败时直接展示清晰的服务端状态码及错误详情；
  - 对 API Base URL 进行智能清理与规整（自动处理 `/v1` 缺失或重复）。

## Capabilities

### New Capabilities

### Modified Capabilities
- `ai-configuration`: 增加受保护的本地文件加密兜底持久化机制、密钥配置状态可视化感知，以及真实透明的模型探测与错误回显。

## Impact

- `lib/services/keychain_service.dart`
- `lib/services/ai_config_store.dart`
- `lib/services/ai_service.dart`
- `lib/shell/ai_config_page.dart`
- `test/` 相关测试用例
