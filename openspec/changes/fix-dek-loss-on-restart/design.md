# Design: 修复 DEK 重启丢失

## Context

DEK（数据加密密钥）丢失的链路已在 proposal 中用磁盘物证定位。本设计关注**如何修**。

现有代码结构（验证过的当前状态）：

- `KekManager`（`lib/tools/password/crypto/kek_manager.dart`）持有 DEK 生命周期：`getOrCreateDek` / `getDek` / `importDek` / `destroyDek` / `lock`。读取链 Keychain → 文件 → 生成；写入链 Keychain（失败才写文件）。
- `KeychainService`（`lib/services/keychain_service.dart`）有自己的 `KekManager _kekManager = KekManager()` 字段；`VaultStore` 与 `settings_panel` 各自另持实例。
- `FlutterKeychainBridge`（`kek_manager.dart:99`）封装 `flutter_secure_storage`，`MacOsOptions(useDataProtectionKeyChain: true, accessibility: unlocked)`。
- `DefaultDekFileBridge`（`kek_manager.dart:29`）读写 `~/Library/Application Support/V8WorkToolbox/.dek`，0600。
- 自愈路径在 `KeychainService._ensureLoaded`（`keychain_service.dart:107-124`）：`VaultCipherException.isAuthFailure` → `backupMismatch()` → 空库重建 → 一次性 `RebuildInfo`。

现有 spec「DEK file fallback for unsigned environments」的触发条件是"Keychain rejects DEK writes"，假设 reject = 抛异常。现实是 write 不抛但 read-back 不可见——本设计修正这个假设。

## Goals / Non-Goals

**Goals**
- 让 ad-hoc 签名下 DEK 跨重启可读，密钥不蒸发。
- 关闭"write 成功但 read-back 不可见"的半成功状态。
- 收敛 KekManager 多实例。
- 自愈不再每次重启误触发。

**Non-Goals**（见 proposal 非目标）
- 不改签名、不弃 Keychain、不改 GCM 布局、不改自愈骨架。

## Decisions

### D1: 写后回读验证（核心修复）

`KekManager.getOrCreateDek` 与 `importDek` 在写 Keychain 后立即读回；读回失败或值不符 → 判定 Keychain 对本安装"事实不可用"，落 `.dek` 文件。

**为什么**：现在的 bug 是 `_bridge.write` 不抛异常就当成功，但 ad-hoc 签名下 write 成功不代表下次可读。写后回读是唯一能识别"半成功"状态的方法。

**被否**：仅 catch write 异常（现状，无法识别半成功）；定期后台校验（增加复杂度且仍有时窗）。

### D2: `.dek` 文件作为受维护的镜像（双写）

写 DEK 时**同时**写 `.dek` 文件（0600），不论 Keychain 是否可用。读取链：Keychain（首选）→ 文件（镜像兜底）→ 生成。

**为什么不只用文件**：Keychain 在正规签名下仍是更安全的存储（受 OS 加密，0600 文件可被本机其他 root 进程读）。双写保留了"签名修好后走 Keychain"的迁移路径，同时让文件成为始终可读的兜底。

**被否**：仅 Keychain（现状，丢失）；仅文件（放弃 Keychain 的安全增益）。

### D3: 单例 KekManager

`KekManager` 改为进程级单例（`static final KekManager instance`），移除 `KeychainService` / `VaultStore` / `settings_panel` 各自 `new KekManager()` 的字段。

**为什么**：多实例的内存缓存不共享——`lock()` 不传播，且各实例可能命中不同 Keychain 分区。单例消除分叉。测试注入点 `setKekManagerForTesting` 保留为对单例字段的注入。

**被否**：注入式 DI（每个消费者接收 KekManager 构造参数）——改动面大，且 settings_panel 的按钮回调里 `KekManager()` 是就地 new 的，DI 化要动多个调用点。

### D4: 失配时先试文件再自愈

`KeychainService._ensureLoaded` 在 GCM 认证失败时，**先尝试从 `.dek` 文件读 DEK** 重新解密；文件 DEK 也认证失败才进自愈。这修了"Keychain 不可见就误判失配"的路径。

**为什么**：proposal 物证显示 3 次 mismatch 都发生在 Keychain item 找不到之后——它们本不该是失配，而是 DEK 来源用错了。文件兜底让真正的 DEK 还在，自愈不该触发。

### D5: 自愈通知持久化

`consumeRebuildInfo` 的一次性信号在 UI 未打开时会被错过。改为：自愈触发时**同时**写一个 `.secrets.bin.rebuilt-<timestamp>` 标记文件，UI 在打开时检查该标记并提示用户，检查后删除标记。

**为什么**：现状下用户看到的是"供应商不能用了"，而非"密钥被重置了"——诊断信息丢失。持久化标记让通知跨会话存活。

## Risks / Trade-offs

**[双写 .dek 的安全降级]** → 文件 0600 但本机 root 可读，弱于 Keychain。
缓解：0600 + chmod 强制；正规签名后迁移回 Keychain 并删文件（现有 spec「Automatic migration to Keychain」已要求）。ad-hoc 签名本就是低安全场景，文件兜底是"能用 vs 蒸发"的权衡。

**[写后回读的性能开销]** → 每次 DEK 写多一次 Keychain 读。
缓解：DEK 写极少（首次生成、备份恢复），开销可忽略；不做后台周期校验。

**[单例化的测试影响]** → `setKekManagerForTesting` 现在对单例注入，测试间状态可能泄漏。
缓解：测试 setUp/tearDown 里 `KekManager.instance.resetForTesting()` 清缓存；现有测试已用注入模式。

**[.dek 文件本身丢失]** → 用户手动删了 .dek。
缓解：此时回退到现状行为（生成新 DEK → 自愈）；文件是镜像不是唯一源，删了不比现状更糟。

## Migration Plan

单步落地，无数据迁移（密文布局不变）：

1. KekManager 单例化 + 写后回读 + 文件双写 + 失配先试文件。
2. KeychainService 自愈通知持久化。
3. 调用方（VaultStore / settings_panel）改用 `KekManager.instance`。

**回滚**：单文件改动，回滚即恢复现状。无状态残留（.dek 文件可留可删，不影响 Keychain 路径）。

**对已蒸发密钥的影响**：本变更不恢复已丢失的密钥（3 个 mismatch 备份里的密文已无法解密，DEK 永远丢了）。它只防止**未来**再丢。已蒸发的 key 需用户重新填入。这点要在 UI 提示里说清，避免用户以为升级后旧 key 会回来。

## Open Questions

无。以下看似待决、实际已被决策关闭：

- ~~双写是否削弱安全性？~~ → 0600 + 迁移路径保留，ad-hoc 场景可接受（D2）。
- ~~单例后测试注入怎么保留？~~ → `setKekManagerForTesting` 注入单例字段 + `resetForTesting`（D3）。
- ~~已蒸发的密钥能恢复吗？~~ → 不能，DEK 永远丢了；本变更只防未来（Migration Plan）。
