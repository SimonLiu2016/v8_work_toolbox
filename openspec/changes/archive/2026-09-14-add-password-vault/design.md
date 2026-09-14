# Design: 密码工具 (add-password-vault)

## Context

现状（详见 proposal.md - Why）：

- `lib/services/keychain_service.dart` 对外提供 `writeSecret / readSecret / deleteSecret / containsSecret / init` 五个 API，消费方有 4 处：`ai_config_store.dart`、`privacy_security_service.dart`、`tts_engine.dart`、`ai_subtitle_service.dart`。
- 当前实现是"Keychain 双写 + XOR 混淆本地文件兜底"，`_xorMask` 编译进二进制，`.secrets.dat` 0644 权限，属于混淆而非加密。
- `ai-configuration` spec 现行 requirement 把 XOR 兜底写成正式行为（"local obfuscated secret store"），本次需修订。
- 工具箱已有可复用基建：`cryptography ^2.0.0`（AES-GCM）、`crypto ^3.0.3`（SHA-256/HMAC）、`flutter_secure_storage ^9.2.4`（Keychain 绑定）、`uuid ^4.6.0`、`privacy` 工具分类与 `openInNewWindow` 模式（见 `NotebookToolDefinition`）。
- 工具 UI 惯例：单页 + 分栏布局（参考 `SmartDiskSlimmerPage`、`NotebookPage`），中文界面，`AppTheme` 统一配色。

## Goals / Non-Goals

**Goals:**

- 把秘密存储从"XOR 混淆"升级为"AES-256-GCM + DEK-in-Keychain"，且对 4 个现有消费方 **API 签名零改动**。
- 提供一个自包含、离线优先的密码管理工具：条目 CRUD、生成器、TOTP、体检、迁移向导、DEK 备份。
- DEK 丢失/Keychain 故障时 fail-fast 并指明恢复路径，绝不静默降级。

**Non-Goals:**

- 浏览器自动填充 / 全局键盘合成（macOS Accessibility 级别工程，另行立项）
- 云同步、多账户、分享协作
- QR 扫码导入 TOTP（桌面扫码体验差，暂只支持 Base32/`otpauth://` 文本粘贴）
- 主密码体系（见 Decisions D2 —— 明确不采用）
- k-匿名泄露检测的自动化/定时化（只做手动逐条查询）

## Decisions

### D1: KEK/DEK 分离 —— Keychain 存 DEK，本地存 AES-GCM 密文

```
macOS Keychain                      ~/Library/Application Support/V8WorkToolbox/
┌──────────────────────┐            ┌──────────────────────────────┐
│ service:             │            │ .vault.bin                   │
│   com.v8worktoolbox  │            │ ┌──────────────────────────┐ │
│   .vault.dek         │──解锁──▶   │ │ nonce(12B)               │ │
│ value: 32B random DEK│            │ │ AES-256-GCM ciphertext   │ │
└──────────────────────┘            │ │ + GCM tag                │ │
   (系统级保护)                      │ └──────────────────────────┘ │
                                    │ AAD = "v8toolbox.vault.v1"   │
                                    └──────────────────────────────┘
```

- DEK 生成：`Random.secure()` 32 字节，**不做 KDF**（不是从密码派生的，无需 PBKDF2/Argon2）。
- 每次写入：新随机 12 字节 nonce（GCM nonce 复用是密码学灾难，绝不允许）；AAD 固定为 `"v8toolbox.vault.v1"`，兼具版本标记与篡改认证。
- 密文布局：`nonce(12) || ciphertext || tag(16)`，单文件原子写。

**否决的替代方案**：
- *全部条目逐条存 Keychain* —— Keychain 单 item 实际上限远小于 Vault 全量，且每次改动都要逐条同步，放弃。
- *主密码 + PBKDF2 派生密钥*（Bitwarden/1Password 模式）—— 见 D2。

### D2: 不引入主密码 —— DEK 由操作系统托管

1Password 用主密码是因为它要**跨设备、零知识**（服务器拿不到密钥）。本工具是**单机桌面工具**，macOS Keychain 本身已有系统级保护（登录密码/Touch ID 解锁），再叠加主密码属于重复防护，且带来真实成本：每次启动输密码、忘密码=数据全丢、需要恢复码机制。

**否决主密码方案的理由**：工程量（PBKDF2 + 恢复码 + 误输锁定 UI）、体验成本（每次重启输入）、以及工具箱"自治轻量"的产品气质。代价是**接受 Keychain 的威胁模型**——能读 Keychain 的攻击者同样能攻破 1Password/Chrome，这不是工具箱层能解决的边界。DEK 备份导出（D5）作为补偿控制。

### D3: 元数据明文、secret 加密 —— 单密文 blob 而非逐字段加密

Vault 磁盘结构：一个明文 JSON 存全部条目元数据 + 每条目的 secret 引用；一个密文 blob 存所有 secret 字段（`{itemId: {password, totpSeed, noteBody}}` 整体 AES-GCM 加密）。

- 列表/搜索/体检（除泄露查询外）**零解密开销**。
- 整体单 blob 而非逐条加密：条目数在个人规模（<1000）下解密耗时可忽略，且避免逐条 nonce 管理。
- 体检中的强度评分/重复检测**只针对已解锁会话内的 secret**（见 D4），不在文件层做。

**否决**：全量整体加密（搜索需全解密，性能与代码复杂度都差）；逐字段加密（nonce 管理复杂度不成比例）。

### D4: 内存会话与"解锁"语义

没有主密码不等于没有会话控制。secret 解密结果**常驻内存缓存**（进程生命周期），但：

- 密码工具页面失焦/关闭时**不清缓存**（与隐私空间 PIN 的闲置锁定不同层——Keychain 已是系统级门闩，应用内再加一层 UX 收益低、打断成本高）。
- 提供"立即锁定"按钮：清空内存缓存 + 要求重新从 Keychain 读 DEK（对用户呈现为"锁定"，实际是清缓存）。这个动作主要给"借电脑给别人看"的场景一个安心按钮。
- 剪贴板 20 秒自动清空（proposal 已定），是主要的"复制泄露"防线。

### D5: DEK 备份导出 —— 用户口令包裹（passphrase-wrapped）

导出格式：`PBKDF2(用户口令, 32B salt, 200_000 iter) → KEK`，`AES-256-GCM(KEK, DEK)`，文件含 `salt || nonce || ciphertext || tag` 与版本头。口令由用户设置（导出时强制输入两次），**工具不存储、不提示、不可恢复**——与 1Password 的 Emergency Kit 语义一致但更朴素。恢复时反向解开，写回新机器 Keychain。

- PBKDF2 迭代取 200,000（OWASP 2023 下限）；`cryptography` 包纯 Dart 实现下约 0.5–2s，一次性操作可接受。
- **否决**：不加密直接导出 DEK（等于把保险柜钥匙贴在门上）；用 Keychain 导出原生机制（不可移植、不可控格式）。

### D6: 迁移向导 —— 单次、一次性、失败保留现场

```
检测 ~/Library/.../.secrets.dat 存在
        │
        ▼
向导页：说明将迁移 N 条凭证（keychainKeyId 列表，不含明文）
        │
        ▼
XOR 解码（迁移代码内保留唯一一份 XOR 实现，仅此一处）
        │
        ▼
逐条 writeSecret 到新存储 ──失败──▶ 保留旧文件，报告失败项，可重试
        │
        ▼
校验逐条读回一致 ──失败──▶ 同上
        │
        ▼
删除 .secrets.dat
```

- 迁移逻辑单独成模块（`migration/legacy_importer.dart`），XOR 解码函数**只存在于这个文件**，主存储层不再含有任何 XOR 代码路径。
- AI Provider key（`ai_config.json` 里的 `keychainKeyId` 引用）随同迁移；`ai_config_store` 无感知。
- `ai_config.json` 中的 PIN、auto-lock 等 `privacy_security_service` 键同样走 `KeychainService` API，自动跟随。

### D7: KeychainService 重写形态

保持单例与五个对外方法签名不变，内部重组为三个协作模块：

```
KeychainService (对外 API 不变)
    ├── KekManager        ← DEK 生命周期：生成/读取/写入 Keychain
    │                       （flutter_secure_storage，固定 service 名）
    ├── VaultCipher       ← AES-256-GCM 加解密、nonce 管理、AAD
    │                       （cryptography 包）
    └── VaultFileStore    ← 密文文件原子读写
                            (.vault.bin，tmp+rename)
```

- 固定 service 名：`com.v8worktoolbox.vault.dek`（**不再用 `MacOsOptions(accountName:)` 默认派生**，避免重命名应用丢 DEK；这也是 secure-secret-storage spec 的 requirement）。
- `init(customRootDir:)` 保留参数以兼容测试注入。
- 单测注入点：抽象 `KeychainBridge` 接口供 mock（沿用现有 `setMockStorage` 思路，改为 mock DEK 桥）。

### D8: 密码生成器与体检的实现选择

- **生成器**：`Random.secure()`；每字符集"至少一个"通过"先各放一个、再填满、后 Fisher-Yates 洗牌"实现；易混淆字符集 = `Il1O0o`；passphrase 词表内置精简英文词表（~2000 高频词，参考 EFF 短词表思路，编译进资源）。
- **强度评分**：实现 zxcvbn 风格的**简化本地版**（模式匹配：字典词、序列、重复、日期 + 熵计算），不引入 `zxcvbn` dart 包（维护不活跃）。评分 0–100，分四档。诚实标注：这是启发式评分，不是 zxcvbn 官方库。
- **重复检测**：精确匹配 password 明文（在解锁会话内比较），跨条目聚类报告。
- **年龄**：条目新增 `passwordUpdatedAt` 字段，从 `updatedAt` 初始化；>180 天在体检中标记。

### D9: TOTP 实现

- `crypto` 包 `Hmac(sha1)`，RFC 6238 官方测试向量（`GEZDGNBV...` 系列）直接进单测。
- Base32 解码自实现（约 30 行，RFC 4648 字母表，容忍大小写与 padding 缺失——Google Authenticator 导出的 seed 常见无 padding）。
- `otpauth://` URI 解析：`totp` 类型，提取 `secret`/`issuer`/`digits`/`period`，忽略不支持的参数并提示。
- 时钟漂移：显示当前周期码，同时校验 ±1 周期用于"上一个/下一个码"辅助显示（1Password 风格），帮助用户在边界时刻成功登录。

### D10: UI 布局与导航

沿用工具箱三栏惯例：

```
┌────────────────────────────────────────────────────────────┐
│ 🔐 密码工具     [搜索_______]  [＋新建▾]  [体检]  [🔒锁定]  │
├──────────┬─────────────────────────────────────────────────┤
│ 全部 (n) │  条目列表（当前标签过滤）      │ 详情面板          │
│ 标签树   │  - GitHub      simon@…  ●●●● │ 名称/URL/用户名   │
│ ──────── │  - GitLab      work@…   ●●●● │ 密码 [显][复制]   │
│ 生成器   │  - AWS         deploy@… ●●●● │ TOTP 码 + 倒计时  │
│ ──────── │                               │ 备注 / 标签编辑   │
│ 体检报告 │                               │ [检查泄露]        │
│ (最近)   │                               │ 修改/删除          │
├──────────┴─────────────────────────────────────────────────┤
│ [⚙ 设置: 剪贴板清空 20s ▾ | DEK 备份…]                       │
└────────────────────────────────────────────────────────────┘
```

- 生成器做成底部抽屉（`showModalBottomSheet`），生成结果一键"填入当前条目"或"复制"。
- 体检报告做成右侧滑入面板，列出弱/重复/超龄三组。
- 迁移向导是全屏 `Stepper`，仅在检测到 legacy 数据时出现。
- 独立窗口：复制 `NotebookToolDefinition` 的 `openInNewWindow` + `WindowController` 模式，`arguments: 'password-vault'`；`main.dart` 增加 window 分支。

## Risks / Trade-offs

- **[Keychain 访问被拒绝（企业 MDM/签名问题）] →** DEK 无法读写时 fail-fast（spec 已定），UI 提供两条出路：修复指引（签名/授权诊断说明）+ DEK 备份恢复。开发期未签名环境如无法访问 Keychain，允许通过环境变量注入测试 DEK（仅 debug 构建）。
- **[用户换机未带 DEK 备份 → Vault 永久不可读] →** 解锁失败时明确提示"恢复路径：导入密钥备份"，绝不显示空列表伪装成"没有条目"。备份导出在设置页显著入口。
- **[GCM nonce 复用风险] →** nonce 每次写入由 CSPRNG 新生成；单测断言连续两次写入同明文产生不同密文。
- **[迁移中途中断导致双份状态] →** 迁移是"逐条写入→读回校验→最后删旧文件"三段式，任意前段失败旧文件保留；删除是最后一步且不可回退。
- **[简化版 zxcvbn 评分与业界标准偏差] →** UI 明示"本地启发式评分"；不承诺与 zxcvbn 官方分数一致。
- **[泄露检测被误解为常驻联网] →** 功能入口只在条目详情（单条触发），健康报告明确标注"纯本地，无网络"；每次调用前显示将要发送的 SHA-1 前缀。
- **[flutter_secure_storage 行为差异（macOS service 名语义）] →** 这是本次最大的技术不确定点， tasks 里第一个任务即为 spike 验证：固定 service 名下 DEK 的写入/读取/跨重启/重签名行为，验证不过则回退调整 KekManager 而不影响上层 API。

## Migration Plan

1. 新存储层与旧 XOR 层**并存一个版本周期**：新代码默认写新存储；检测到 `.secrets.dat` 时提示迁移。
2. 迁移完成后（读回校验通过）删除旧文件；任何失败保留旧文件可重试。
3. 回滚策略：新存储层文件 `.vault.bin` 与 DEK 独立于旧数据；若需回退到旧版本应用，旧版应用读不到 `.vault.bin` 但 `.secrets.dat` 若未被删除仍可用（即：**删除旧文件是迁移的不可逆点**，置于最后一步）。

## Open Questions

- 内置 passphrase 词表的规模与语言（暂定英文 2000 高频词；是否需要中文词表待用户反馈）。
- 体检报告的"弱密码"阈值档位（暂定 0–40 弱 / 40–70 中 / 70+ 强）是否需要可配置。
