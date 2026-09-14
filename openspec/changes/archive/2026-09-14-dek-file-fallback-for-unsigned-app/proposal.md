# Proposal: DEK 文件兜底 —— 未签名环境下的持久化修复

## Why

`add-password-vault` 重写 KeychainService 后引入了 fail-fast 语义，但在 adhoc 签名的本机部署上，macOS 拒绝 Keychain 写入（`SecItemAdd`），导致 `PrivacySecurityService.init` 在 `runApp()` 之前崩溃，应用黑屏无法启动。用户已确认应用仅在本机使用，无分发需求，因此采用"DEK 文件兜底"替代"正式签名"作为治本办法。

## What Changes

- **DEK 三级回退**：Keychain 写入失败时，回退到 `~/Library/Application Support/V8WorkToolbox/.dek`（0600 权限文件，base64 编码 DEK）。启动顺序：Keychain 读 → 文件读 → 生成新 DEK（先尝试 Keychain 写，失败则写文件）。
- **启动不再崩溃**：任何 DEK 来源（Keychain / 文件 / 新生成）都能正常初始化，消除黑屏。
- **安全语义诚实**：文件 DEK 依赖 POSIX 0600 权限（仅当前用户可读），无系统级加密；UI 在设置页明确标注当前 DEK 来源（Keychain / 本地文件）。
- **迁移感知**：若未来应用被正式签名且 Keychain 恢复可用，自动从文件迁移 DEK 到 Keychain 并删除文件。

## Capabilities

### Modified Capabilities

- `secure-secret-storage`: "Fail-fast on missing DEK" 修订——fail-fast 的对象从"任何 Keychain 不可用"收窄为"DEK 所有来源均不可用"；新增文件兜底回退语义。

## Impact

- 代码：`lib/tools/password/crypto/kek_manager.dart`（回退链）、`lib/services/keychain_service.dart`（透传）、`lib/tools/password/ui/settings_panel.dart`（DEK 来源显示）
- 测试：`test/kek_manager_test.dart`（文件回退路径、权限验证、迁移场景）
- 数据：`~/Library/Application Support/V8WorkToolbox/.dek`（新文件，0600）
- 风险：文件 DEK 的安全级别低于 Keychain（无系统级加密、无访问提示）；已通过权限收窄 + UI 明示缓解
