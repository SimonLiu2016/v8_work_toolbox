# Proposal: 密码工具 (Password Vault) — 本地优先、端到端加密的密码管理工具

## Why

V8WorkToolbox 目前把两类秘密 —— AI Provider API Key 与隐私空间 PIN —— 都塞进同一个 `KeychainService`，但它的"加密"实现是**XOR 混淆**：密钥（`_xorMask`）编译在二进制里，`.secrets.dat` 是 0644 权限的混淆字节，任何能读 `~/Library/Application Support/V8WorkToolbox/` 的人都能反解。`ai-configuration` spec 已经把这条 XOR 兜底写成了正式 requirement，等于是把"用明文冒充密文"制度化。同时，工具箱里没有一个给用户自己保管秘密的入口 —— AI key 是"我配进去就交给你"，用户没有一个"我自己管的、可体检、可生成的密码库"。

这个 change 做两件事：**把秘密存储的地基换成真加密**，**并在其上构建一个自包含的密码管理工具**。两条不是并列的选项，而是"先修地基，再建房"的自然顺序 —— 密码工具需要 Vault，Vault 需要真加密，真加密需要重写 `KeychainService` 从 XOR 到 AES-256-GCM + DEK-in-Keychain 模式。

## What Changes

- **重写秘密存储层**（`KeychainService`）：从 XOR 混淆改为 **AES-256-GCM + DEK-in-Keychain** 分离架构。DEK（32 字节随机数）存 macOS Keychain，Vault 数据密文存 `~/Library/Application Support/V8WorkToolbox/.vault.bin`，每次写入生成新的 12 字节 nonce。删除 XOR 兜底路径与 `_xorMask` 常量。**BREAKING**: `.secrets.dat` 现有 XOR 数据必须通过迁移向导读入并重新加密；旧文件在迁移完成后删除。
- **新增「密码工具」注册到工具箱**：新的 `ToolDefinition`，分类为 `privacy`，独立窗口打开（沿用 `NotebookToolDefinition.openInNewWindow` 模式）。
- **新增 Vault 条目模型与存储**：`VaultItem` 支持 `login` / `note` / `totp` 三种类型，元数据（title、url、username、tags）明文存 JSON，secret 字段整体加密。
- **密码生成器**：熵源 `Random.secure()`；支持长度 8–128、字符集开关（大小写/数字/符号/易混淆字符排除）、passphrase 模式（词袋 + 分隔符 + 可选数字）。
- **TOTP 两步验证**：RFC 6238 / HMAC-SHA1，支持 Base32 secret 导入、6 位码、30 秒周期、±1 周期时钟漂移容忍；显示剩余秒数倒计时条。**不做 QR 扫码**（需要额外依赖且 macOS 桌面扫码体验一般），后续可扩展。
- **密码体检报告**：zxcvbn 强度评分（本地实现，无网络调用）、重复密码检测（同 username 或同 password 跨条目）、密码年龄提示（>180 天标记）。**泄露检测（HIBP k-匿名 API）默认关闭**，用户主动点击"检查泄露"按钮才发起外网请求，且只发送 SHA-1 前 8 字符。
- **迁移向导**：首次启动密码工具时，若检测到旧 `.secrets.dat`，展示向导把 XOR 数据解密并写入新 Vault，然后删除旧文件。AI 配置的 API Key 通过同一个 `KeychainService` API 自动跟随迁移（对 `ai_config_store`、`privacy_security_service`、`tts_engine`、`ai_subtitle_service` 的调用签名零改动）。
- **DEK 备份与恢复**：允许用户主动导出"加密的 DEK 副本"到本地文件（用户自己指定位置，例如放自己的 1Password / Bitwarden），用于跨机器迁移；导入时要求用户输入导出时设置的口令来解密。
- **剪贴板自动清空**：复制密码后 20 秒默认自动清空剪贴板，可在设置中调整（10/20/30/60/禁用）。
- **AI 配置 spec 修订**：`ai-configuration` 中"fallback protected obfuscation store"的 requirement 需要修改 —— XOR 兜底不再是"encrypted"，替换为"AES-256-GCM 加密 + DEK 在 Keychain；DEK 丢失时 fail-fast 并提示用户从备份恢复"。

## Capabilities

### New Capabilities

- `password-vault`: 密码工具本身 —— Vault 条目 CRUD、密码生成器、TOTP、密码体检、迁移向导、剪贴板自动清空、DEK 备份/恢复。
- `secure-secret-storage`: 重写后的秘密存储层（`KeychainService` 抽象）—— AES-256-GCM 加密、DEK 生命周期管理、Keychain 与本地密文的双层职责划分、明文元数据 vs 加密 secret 的分离原则、fail-fast 失败策略。

### Modified Capabilities

- `ai-configuration`: "Secure credential storage via macOS Keychain and Protected File Fallback" 这一 requirement 的 fallback 语义从"本地混淆文件"改为"AES-256-GCM 加密文件（DEK 在 Keychain）"。用户可见行为不变（"我配的 API key 存下来了"），但底层加密实现从 XOR 变成真加密，并且 DEK 丢失时不再静默降级，而是明确报错。

## Impact

- **代码**（新增/修改）：
  - `lib/services/keychain_service.dart` —— 完全重写（保留 `writeSecret / readSecret / deleteSecret / containsSecret / init` 对外 API 签名，实现从 XOR 改为 AES-256-GCM + DEK-in-Keychain）
  - `lib/tools/password/` —— 新目录，包含 `vault_store.dart`、`vault_models.dart`、`crypto/vault_crypto.dart`、`crypto/kek_manager.dart`、`ui/password_page.dart`、`ui/item_editor.dart`、`ui/generator_panel.dart`、`ui/totp_badge.dart`、`ui/health_report.dart`、`ui/migration_wizard.dart`、`services/totp_service.dart`、`services/password_generator.dart`、`services/password_health.dart`
  - `lib/tools/registry.dart` —— 新增 `PasswordVaultToolDefinition`，注册到 `ToolCategory.privacy`
  - `lib/main.dart` —— 独立窗口路由注册
  - `test/` —— 新增 `vault_crypto_test.dart`（AES-GCM 正确性、nonce 不重复）、`kek_manager_test.dart`、`totp_service_test.dart`（RFC 6238 官方测试向量）、`password_generator_test.dart`、`password_health_test.dart`（zxcvbn 已知评分）、`migration_wizard_test.dart`、`keychain_service_v2_test.dart`
- **依赖**：无新增（`cryptography` 已在 pubspec，支持 AES-256-GCM；`crypto` 已在，用于 SHA-256；TOTP 用 HMAC-SHA1 需要 `crypto` 包的 `Hmac`）。
- **现有 spec**：
  - `openspec/specs/ai-configuration/spec.md` 的"Secure credential storage via macOS Keychain and Protected File Fallback" requirement 需修订
  - `openspec/specs/privacy-space/spec.md` 无变更（PIN 存储走同一个 `KeychainService` API，签名不变，用户可见行为不变）
- **数据迁移**：`~/Library/Application Support/V8WorkToolbox/.secrets.dat` 现有 XOR 数据需要迁移到 `.vault.bin`，向导自动执行；未迁移前旧文件保留。
- **风险**：
  - Keychain DEK 首次生成失败（例如企业 MDM 禁用 Keychain 写入）→ 需 fail-fast 并给出明确错误与"DEK 备份导入"路径
  - 用户跨机器迁移未导入 DEK 备份 → Vault 无法解密，需明确错误提示而非静默空列表
  - `flutter_secure_storage` 的 service 名需固定（不再用默认 bundle id），否则重命名应用会丢 DEK
