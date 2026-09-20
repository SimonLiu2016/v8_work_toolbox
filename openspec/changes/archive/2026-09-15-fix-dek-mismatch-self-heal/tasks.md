# Tasks

## 1. 失配/损坏分流能力（cipher 层）

- [x] 1.1 `lib/tools/password/crypto/vault_cipher.dart`：`VaultCipherException` 增加 `isAuthFailure` 标志；`decrypt` 在 GCM tag 校验失败处置位（布局损坏维持 `isIntegrityError`），两者互斥
- [x] 1.2 单测：合法密文解密通过；篡改 tag → `isAuthFailure=true`；截断密文 → `isIntegrityError=true` 且 `isAuthFailure=false`

## 2. 失配自愈（KeychainService 层）

- [x] 2.1 `lib/services/keychain_service.dart`：新增 `RebuildInfo{backupPath, at}` 与 `consumeRebuildInfo()`（一次性读取后置空）
- [x] 2.2 改造 `_ensureLoaded`：`readDecrypted` 捕获 `VaultCipherException` → `isAuthFailure` 走自愈：`VaultFileStore` 侧新增残件备份（`.secrets.bin.mismatch-yyyyMMdd-HHmmss`，copy 非 rename）→ `_secrets={}` + `_persist()` 重建 → 置 RebuildInfo；`isIntegrityError` 原样上抛（不备份不重建）
- [x] 2.3 自愈重建中 `_persist` 失败时异常上抛且备份已存在，下次启动可重试（不写死中间态）
- [x] 2.4 单测（mock KekManager/VaultFileStore，参照现有 `setKekManagerForTesting` 注入点）：匹配路径零变化；失配→备份文件生成+空库重建+信号可读+二次 consume 为空+writeSecret 立即可写；损坏→上抛且无备份无重建；重建后 consumeRebuildInfo 内容含备份路径

## 3. 消费方接入（AI 配置保存）

- [x] 3.1 `lib/shell/ai_config_page.dart` 保存成功路径：调用 `KeychainService.consumeRebuildInfo()`，非空则 SnackBar 提示「密钥库此前因密钥失配已重置，其他已存密钥需重填（残件备份： path）」
- [x] 3.2 `ai_config_store.dart` 无需改动验证：saveProvider 经自愈后 writeSecret 直接成功（回归测试确认）

## 4. 验证

- [x] 4.1 相关测试套件全绿（keychain_service / vault_cipher / ai_config 相关）；全量基线对比确认红测试不新增
- [x] 4.2 本机失配现场端到端验证：部署后保存 AI 供应商触发自愈——`.secrets.bin.mismatch-20260915-205428` 备份生成、新 DEK(20:54)+新库(20:57)重建匹配、保存成功、用户确认手动验证完成
- [x] 4.3 `openspec validate fix-dek-mismatch-self-heal --strict` 通过
