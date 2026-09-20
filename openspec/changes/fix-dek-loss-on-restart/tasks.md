# Tasks: 修复 DEK 重启丢失

## 1. KekManager 单例化

- [x] 1.1 `lib/tools/password/crypto/kek_manager.dart`：`KekManager` 改为 `static final KekManager instance = KekManager._()`，私有构造；保留 `setKekManagerForTesting` 注入单例字段；新增 `resetForTesting()` 清 `_cachedDek` 与 `_source`
- [x] 1.2 `lib/services/keychain_service.dart`：移除 `KekManager _kekManager = KekManager()` 字段，改用 `KekManager.instance`
- [x] 1.3 `lib/tools/password/vault_store.dart`：移除 `_kekManager` 字段与构造注入，改用 `KekManager.instance`
- [x] 1.4 `lib/tools/password/ui/settings_panel.dart`：3 处 `KekManager()` 改为 `KekManager.instance`
- [x] 1.5 验证：跑密码库与 keychain 相关测试，确认单例注入路径无回归

## 2. 写后回读验证（核心修复）

- [x] 2.1 `KekManager.getOrCreateDek`：写 Keychain 后立即 `_bridge.read` 回读；读回值与刚写入值不符或为空 → 判定 Keychain 事实不可用，落 `.dek` 文件
- [x] 2.2 `KekManager.importDek`：同样的写后回读验证
- [x] 2.3 回读比较用解码后的 DEK 字节，而非原始字符串（避免 marker 前缀差异误判）
- [x] 2.4 单测：mock KeychainBridge write 成功但 read 返回 null → 断言 `.dek` 文件被写入

## 3. `.dek` 文件镜像（双写）

- [x] 3.1 `KekManager`：写 DEK 时**同时**写 Keychain 与 `.dek` 文件（0600），不论 Keychain 是否抛异常
- [x] 3.2 读取链保持 Keychain 首选 → 文件镜像 → 生成；Keychain 不可读时文件镜像兜底
- [x] 3.3 单测：Keychain 不可读 + `.dek` 文件存在 → 读取成功，不触发失配自愈
- [x] 3.4 单测：Keychain 与文件均不可读 → 生成新 DEK 并双写

## 4. 失配时先试文件再自愈

- [x] 4.1 `lib/services/keychain_service.dart` 的 `_ensureLoaded`：GCM 认证失败（`isAuthFailure`）时，**先**尝试从 `KekManager.instance.getDek()`（含文件镜像）重新取 DEK 解密；仍失败才进自愈
- [x] 4.2 单测：Keychain 不可见 + `.dek` 镜像存在 + 密文有效 → 不触发 `backupMismatch`，密钥可读
- [x] 4.3 单测：Keychain 与文件 DEK 均无法认证密文 → 触发自愈（保留现有行为）

## 5. 自愈通知持久化

- [x] 5.1 `KeychainService`：自愈触发时写标记文件 `.secrets.bin.rebuilt-<timestamp>`（空文件即可，仅作存在性标记）
- [x] 5.2 新增 `bool consumeRebuildNotice()`：检查标记文件存在则返回 true 并删除标记；UI 启动时调用
- [x] 5.3 AI 配置页启动时检查 `consumeRebuildNotice()`，若 true 弹提示告知"密钥库此前被重置，已存密钥需重新填入"
- [x] 5.4 单测：自愈触发后 `consumeRebuildNotice()` 返回 true 且标记文件被删除

## 6. 测试与回归

- [x] 6.1 跑 `test/keychain_service_v2_test.dart`，确认自愈路径与 DEK 桥接 mock 注入无回归
- [x] 6.2 跑 `test/vault_crypto_test.dart` 与 `test/dek_mismatch_self_heal_test.dart`，确认失配恢复行为
- [x] 6.3 新增单测：写后回读验证（task 2.4）
- [x] 6.4 新增单测：文件镜像兜底（task 3.3）
- [x] 6.5 新增单测：失配先试文件（task 4.2）
- [x] 6.6 全量回归：`flutter test`，确认无新增失败

## 7. 手工验证（成功判据）

- [ ] 7.1 配置供应商并重启 3 次，API Key 仍可读取，聊天/检索正常
- [ ] 7.2 重启后不产生新的 `.secrets.bin.mismatch-*` 文件
- [ ] 7.3 首次保存密钥后 `.dek` 文件存在，权限 0600
- [ ] 7.4 即便 Keychain item 不可见，`.dek` 兜底使密文可解，自愈不误触发
