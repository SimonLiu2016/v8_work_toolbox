## Context

目前 macOS 端在未签名或开发模式下，`flutter_secure_storage` 无法正常调用系统 Keychain。原有的内存回退机制在应用退出后丢失所有已配置的 API Key。同时，UI 弹窗在重新打开已有供应商时无法利用已存储凭证进行模型探测。

## Goals / Non-Goals

**Goals:**
- 在 `KeychainService` 中实现双层存储：
  - Layer 1: 系统 `flutter_secure_storage` (macOS Keychain)
  - Layer 2: 本地受保护混淆/加密文件 (`~/Library/Application Support/V8WorkToolbox/.secrets.dat`)
- 在应用冷启动、热重启或测试环境下，凭证均能 100% 稳定读取；
- 编辑弹窗中显示已存凭证状态，探测时正确传入已有 `keychainKeyId` 或当前输入框的新 Key；
- 移除所有协议探测中的假数据 Fallback，失败时真实报告错误；
- 提供常用主流服务商 Base URL 与推荐模型的快速预设（OpenAI、DeepSeek、Claude、Gemini、Ollama、SiliconFlow）。

**Non-Goals:**
- 不引入外部对称加密 C 库依赖，使用标准 Base64 + XOR 混淆密钥掩码，结合只有当前 macOS 用户账户权限能访问的目录实现轻量安全兜底。

## Decisions

### 1. KeychainService 双层持久化机制
- 写入时：先写系统 Keychain；若成功且有本地文件，同步更新；若 Keychain 抛异常，写入 `.secrets.dat` 并保留在内存中。
- 读取时：优先读系统 Keychain；若为空或抛异常，从 `.secrets.dat` 读取并恢复到内存中。
- 删除时：同时清理 Keychain、本地 `.secrets.dat` 及内存 Map。

### 2. 弹窗交互增强
- 若 `provider != null`，异步检查 `KeychainService.containsSecret(provider.keychainKeyId)`；
- 若已配置，显示绿色 `✓ 已配置加密密钥` 标签，提示用户若无需更换则留空；
- 点击「自动探测发现」时：
  `final keyToUse = keyCtrl.text.trim().isNotEmpty ? keyCtrl.text.trim() : (provider != null ? await KeychainService.instance.readSecret(provider.keychainKeyId) : null);`
  若 `keyToUse` 为空，直接提示“请先输入 API Key 再进行探测”。
