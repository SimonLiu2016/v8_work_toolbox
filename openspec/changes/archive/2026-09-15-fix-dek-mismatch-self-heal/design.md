## Context

故障现场（详见 conversation 排查与 proposal.md）：

- `.secrets.bin`（9/15 11:12，DEK-A 加密）与 `.dek`（9/15 14:27 重建，DEK-B）失配 → `KeychainService._ensureLoaded` 在 `readDecrypted` 抛 `VaultCipherException`（GCM 认证失败），`writeSecret` 先读后写 → **保存永久死循环**。
- 已有一个 `.secrets.bin.corrupt-K1-20260915-104205` 残件，但代码库搜不到 `corrupt-K1` 来源——说明曾存在过某个失配处理逻辑（可能已删除或在原生侧），恢复路径半残。
- `KekManager` 非单例（`kek_manager.dart:155`，每处 `KekManager()` 新实例），内存缓存仅限单实例；`getOrCreateDek` 生成路径（`:200-218`）在"首次生成"后直接 `_cachedDek = fresh` 上岗，**不检查已有密文是否匹配**——这是失配的结构性入口。
- `KeychainService` 与密码保险库 `VaultStore` 各自持有独立 `KekManager` 实例，但共享同一对 `.dek` / `.secrets.bin` 文件——校验与自愈必须放在两层都经过的点上。

约束：

- 失配后旧密钥**不可恢复**（旧 DEK 已不存在），自愈目标不是找回数据而是"止死循环 + 保留证据 + 用户知情"。
- 不能为了自愈削弱正常路径安全：匹配路径零开销变化，试解密只发生在"缓存冷启动"或"新 DEK 上岗"时。

## Goals / Non-Goals

**Goals:**

- 任何 DEK 上岗前必须通过密文匹配校验（有密文时），从结构上消灭"锁换了保险柜不知道"。
- 失配时：备份残件 → 当前 DEK 重建空库 → 读写立即可用 → 一次性用户信号。
- 失败分类清晰：DEK 缺失 / 失配（可自愈）/ 密文损坏（fail-fast 但保留文件）。
- 消费方（AI 配置保存、密码保险库）无需各自实现恢复逻辑——自愈发生在 storage 层。

**Non-Goals:**

- 不恢复失配前的旧密钥（密码学上不可能）。
- 不改变 Keychain/file 双源策略本身（useDataProtectionKeyChain 的 entitlement 整改是另一个话题）。
- 不引入 DEK 版本化/多 DEK 并存（一把锁一个柜，轮换走重建）。
- 不排查 9/15 14:27 `.dek` 被重建的触发源（无代码路径，属环境操作；本变更使此类事件不再致命）。

## Decisions

### D1: 匹配校验放 `KeychainService._ensureLoaded`，而非 `KekManager.getOrCreateDek`

`KekManager` 不知道密文的存在（职责单一：管 DEK）；密文在 `VaultFileStore`/`KeychainService` 层。校验点放在 `_ensureLoaded`：

```
  _ensureLoaded（改造后）
  ════════════════════════════════════════════════
  _secrets 已有缓存 → 直接返回（正常热路径，零变化）
        │ 冷启动
        ▼
  dek = kekManager.getOrCreateDek()     ← 可能抛 DekUnavailableException（DEK 缺失，fail-fast，不变）
        │
        ▼
  readDecrypted(cipher, dek)
        │ 成功 → 正常返回（匹配，零变化）
        │ VaultCipherException（认证失败）
        ▼
  区分失配 vs 损坏：
    · 密文布局合法（nonce/len 完整）但认证失败 → 失配 → 自愈流程
    · 布局损坏（长度不足等 isIntegrityError） → 损坏 → 保留文件 + fail-fast
```

**为什么不在 KekManager**：那里没有密文上下文，校验会变成跨层调用；且 `getOrCreateDek` 还被 settings_panel 等纯 DEK 管理场景调用，那些场景不该触发密文操作。

**备选**：在 `getOrCreateDek` 生成分支加回调钩子 → 拒绝，钩子把两层耦合成了隐式契约，不如在密文所在层显式处理。

### D2: 失配自愈为"备份 + 重建 + 信号"三步，同步完成

```
  自愈流程（_ensureLoaded 认证失败分支）
  ════════════════════════════════════════════════
  1. 备份：.secrets.bin → .secrets.bin.mismatch-yyyyMMdd-HHmmss
     （copy 不是 rename——原文件稍后会被重建覆盖，副本留证）
  2. 重建：_secrets = {} → _persist()（当前 DEK 加密空 map 写入）
  3. 信号：置 _lastRebuildInfo = RebuildInfo{backupPath, at}
     → KeychainService 暴露 consumeRebuildInfo() 一次性读取
     → 调用方（保存路径）拿到信号后 SnackBar 告知"密钥库已重置，请重填"
```

**为什么 copy 而非 rename**：rename 后若 `_persist` 失败（磁盘满等），现场彻底消失；copy 保证任何时刻至少一份残件在盘上。重建失败则异常上抛，残件与信号都还在，下次启动重试。

**为什么信号是一次性 consume 而非持久标记**：避免每次启动都恐吓用户；信号只在"本次会话发生过重建"时存在。

### D3: 损坏与失配的区分标准 = 密文布局合法性

`VaultCipherException.isIntegrityError` 当前覆盖"长度不足"（`vault_cipher.dart:67`）。GCM 认证失败与布局损坏都是 `VaultCipherException`，需要区分：

- **布局损坏**：字节长度 < nonce(12)+mac(16) 或 base64 解码失败 → 真损坏，fail-fast，文件原样保留（不备份不重建——损坏文件可能部分可读，留给用户/取证）。
- **失配**：布局完整但 GCM tag 校验失败 → DEK 不匹配，走 D2 自愈。

实现上给 `VaultCipherException` 增加 `isAuthFailure` 标志（decrypt 的 tag 校验点置位），`_ensureLoaded` 按标志分流。

### D4: 消费方最小接入——只在保存路径提示

`ai_config_page.dart` 保存按钮已修好异常显示（上一 change）。本变更后：

- `saveProvider` → `writeSecret` 正常成功（自愈已在 storage 层完成）
- 保存成功后 UI 调 `KeychainService.consumeRebuildInfo()`，非空则追加提示"⚠️ 密钥库此前因密钥失配已重置，其他已存密钥需重填（残件备份： …）"
- 密码保险库（VaultStore）共享同一文件——但它是独立 vault 文件？**不是**：`KeychainService.secretsFileName = '.secrets.bin'` 与 password vault 的 vault 文件是不同文件（vault 有自己的 store）。自愈只作用于 `.secrets.bin`，password vault 的 DEK 失配问题同构但不在本次范围（见 Open Questions）。

### D5: 不为 `KekManager` 引入单例化

失配的结构性入口之一是"多实例各自缓存"，但本变更后：冷启动必走 `_ensureLoaded` 校验，多实例最多重复校验（幂等，读路径），不会各自上岗不同 DEK（`.dek` 文件是唯一事实源）。单例化是更大范围的重构，不值得搭进这个修复。

## Risks / Trade-offs

- [自愈重建使用户其他已存密钥"静默消失"（API Key、TTS key 等）] → D2 信号机制 + 保存路径提示；残件备份留证；这本来就是不可恢复状态，只是把"死循环 + 无提示"变成"可用 + 一次性提示"。
- [试解密增加冷启动开销] → 一次 GCM 解密（<1ms 级），且只在缓存冷启动时发生。
- [损坏/失配误分流：真损坏被当失配重建，损坏文件被覆盖] → D3 分流后损坏路径**只保留不重建**；失配路径必先 copy 备份再重建。
- [多实例并发触发自愈（KeychainService 与 VaultStore 各自的 KekManager）] → 自愈作用文件仅为 `.secrets.bin`（KeychainService 专属），VaultStore 的 vault 文件不经过 `_ensureLoaded`；并发写由既有原子写（tmp+rename）兜底。
- [用户在重建提示前已重填 Key，提示又出现造成困惑] → 提示文案明确"其他已存密钥"，且 consume 一次性。

## Migration Plan

- 无数据迁移：匹配用户（绝大多数）零感知。
- 当前已处于失配状态的本机：首次读写触发自愈 → `.secrets.bin.mismatch-*` 备份生成 → 空库重建 → 用户重填 API Key 后完全恢复。
- 回滚 = revert；已重建的库回滚后仍匹配当前 `.dek`，不受影响；残件备份文件不受代码回滚影响。

## Open Questions

- password vault（`VaultStore` + 独立 vault 文件）存在同构的 DEK 失配风险，但它的 vault 文件与 `.secrets.bin` 分离。本次只修 `.secrets.bin` 链路；vault 侧是否套用同一自愈模式，待用户确认后另开 change（模式已在本设计中，可直接复用）。
