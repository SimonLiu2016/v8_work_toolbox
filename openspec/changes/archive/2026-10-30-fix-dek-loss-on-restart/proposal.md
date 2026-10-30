# Proposal: 修复 DEK 重启丢失导致密钥静默蒸发

## 背景与问题

「模型供应商」配置好并测试通过的 API Key，每次重启软件后即失效。用户直觉"key 没有真正保存"，实际更严重——**key 确实加密落盘了，但加密它的主密钥（DEK）每次重启都换了一把新的**，导致旧密文无法解密，被"自愈"机制静默清空。

### 磁盘物证（2026-09-20 实测）

```
~/Library/Application Support/V8WorkToolbox/
├── ai_config.json          Sep 20 00:35:49   供应商配置（keychainKeyId=key_provider_...）
├── .secrets.bin            Sep 20 09:11:41   30 字节 = GCM 空 {} 的开销（key 已没）
├── .secrets.bin.mismatch-20260915-205428   161 B  ← 3 次 DEK 失配
├── .secrets.bin.mismatch-20260918-111456   195 B
├── .secrets.bin.mismatch-20260920-091141   244 B  ← 5 天内 3 次
├── .secrets.bin.corrupt-K1-20260915        244 B
└── .dek                                       不存在
```

- `security find-generic-password -s 'com.v8worktoolbox.vault.dek' -a 'dek'` → **找不到**
- `.dek` 文件兜底 → **不存在**
- app 签名：`flags=0x2(adhoc)`，`TeamIdentifier=not set`，无 `keychain-access-groups` entitlement

### 根因链

```
首次保存：Keychain write "成功"（不抛异常）→ 不触发 .dek 文件兜底 → DEK 只在内存 + Keychain
测试连接：✅（_cachedDek 还在内存）
重启：KekManager 新实例，_cachedDek=null → 读 Keychain → 找不到（adhoc 签名下 item 对新进程不可见）
     → 无 .dek 文件兜底 → 生成【新 DEK】→ 解 .secrets.bin → GCM 认证失败
     → isAuthFailure → 自愈：备份 + 清空 → key 蒸发
```

核心漏洞：`KekManager.getOrCreateDek`（`kek_manager.dart:203-216`）只在 Keychain write **抛异常**时才写 `.dek` 文件。但 ad-hoc 签名下 `flutter_secure_storage` 的 write **不抛异常**——它把 item 写进了某个 Keychain 分区，写入"成功"，下次启动却搜不到。文件兜底分支永远不被触发。

### 次生问题：KekManager 多实例

```
KeychainService._kekManager       ← AI key 用这个
VaultStore._kekManager            ← 密码库用另一个
settings_panel: KekManager()      ← 每次按钮点击新建一个
```

内存缓存不共享，任一 `lock()` 不影响他人。非本次主因，但是设计债，顺带收敛。

### 现有 spec 的漏洞

`secure-secret-storage` spec 已有「DEK file fallback for unsigned environments」要求，但其触发条件是"Keychain rejects DEK writes"——假设 write 失败 = 抛异常。现实是 **write 成功但 read-back 不可见**，这个半成功状态没被识别，兜底永不触发。

## 解决方案

四项组合（B+D+E+自愈修正）：

**D（核心）：DEK 写后回读验证**
写 Keychain 后立即读回；读回失败或值不符 → 判定 Keychain 对本安装"事实不可用"，落 `.dek` 文件。关闭"写成功却不可见"的半成功状态。

**B：`.dek` 文件作为受维护的镜像**
不再仅在 Keychain 失败时才写文件。写 DEK 时**同时**写文件（0600），使文件成为重启后始终可读的兜底。Keychain 仍是首选读源，文件是镜像。

**E：KekManager 单例化**
消除 `KeychainService` / `VaultStore` / `settings_panel` 各自持有 `KekManager` 实例的分叉，内存缓存统一。

**自愈修正：失配时显式通知，且先试文件再自愈**
保留自愈（避免写入死循环），但：重启读 DEK 失败时**先尝试 `.dek` 文件**再判定失配；自愈触发时弹持久通知（不只是一次性 `consumeRebuildInfo` 信号），让用户知道"密钥被重置了"而非"供应商不能用了"。

## 能力（Capabilities）

**变更**
- `secure-secret-storage` — DEK 持久化机制修正：写后回读验证、文件镜像、单例化、失配恢复路径修正。

## 影响范围

- **修改**：`lib/tools/password/crypto/kek_manager.dart`（写后回读 + 文件镜像 + 单例）、`lib/services/keychain_service.dart`（自愈通知持久化）、`lib/tools/password/vault_store.dart`（使用单例 KekManager）、`lib/tools/password/ui/settings_panel.dart`（使用单例）
- **无新增依赖**
- **不受影响**：`VaultCipher` / `VaultFileStore` 加密与文件布局不变；`AiConfigStore` 的 `saveProvider` 流程不变；DEK 备份恢复（`importDek`）入口不变

## 非目标

- **不改为正规 Developer ID 签名**。那需要 Apple 开发者账号与本变更无关；本变更让 ad-hoc 签名下也能可靠工作。
- **不放弃 Keychain 作为首选读源**。文件是镜像兜底，不是替代；签名修好后仍走 Keychain 并迁移删文件。
- **不改自愈的"备份 + 重建"骨架**。只改触发时机（先试文件）与通知可见性，不删备份机制。
- **不改 GCM 加密参数或密文布局**。`VaultCipher` 不动。

## 已验证的事实

- Keychain 中无 `com.v8worktoolbox.vault.dek` item（`security find-generic-password` 找不到）
- `.dek` 文件不存在
- app 为 ad-hoc 签名，无 `keychain-access-groups` entitlement
- 5 天内 3 次 mismatch 备份，每次都清空了密钥库
- `flutter_secure_storage` 用 `useDataProtectionKeyChain: true` + `accessibility: unlocked`

## 成功判据

1. 配置供应商并重启，API Key 仍可读取，聊天/检索正常工作。
2. 连续重启 3 次，不产生新的 `.secrets.bin.mismatch-*` 文件。
3. `.dek` 文件在首次保存密钥后即存在，权限 0600。
4. 即便 Keychain 不可见，`.dek` 文件兜底使密文可解；自愈不再每次重启触发。
