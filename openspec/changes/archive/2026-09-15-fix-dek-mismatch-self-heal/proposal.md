## Why

密钥库当前存在"DEK 静默失配"死循环：当 DEK 被重新生成（或来源切换）而 `.secrets.bin` 密文仍是旧 DEK 加密时，读取认证失败被当作数据损坏静默丢弃或原样抛出，写入路径因 `_ensureLoaded` 先读后写而永久卡死——用户保存 AI 供应商时报"写入密钥库失败"，且永远无法自愈。密钥源变化缺乏迁移/重初始化语义，违背"升级或环境变化不应让用户丢配置"的基本原则。

## What Changes

- **DEK 与密文匹配校验（R1）**：`KekManager` 每次解析出 DEK 后、上岗前，若 `.secrets.bin` 存在则必须用其做一次认证性试解密校验；匹配才上岗，不匹配禁止静默上岗并转入失配流程。
- **失配受控重建（R2）**：失配且旧 DEK 不可恢复时，系统 SHALL 将残件备份（带时间戳的 `.secrets.bin.mismatch-*` 副本）→ 以当前 DEK 重建空库 → 立即可读写，并向上层暴露"密钥库已重建、旧密钥不可恢复"的一次性信号，由 UI 告知用户重填密钥。
- **保存路径恢复动作（R3）**：密钥读写失败对调用方 MUST 携带可操作的恢复语义（区分"DEK 不可用""失配已重建""写入失败"），保存操作永远要么成功、要么得到带恢复指引的明确错误，不得静默卡死。
- **DEK 轮换防呆**：任何新生成 DEK 在上岗前 MUST 通过 R1 校验；未通过时不得缓存、不得用于加密写。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `secure-secret-storage`: 新增 DEK-密文匹配校验与失配受控重建需求；`Fail-fast on missing DEK` 与 `DEK file fallback for unsigned environments` 的失败语义需细化（区分损坏/失配/不可用，失配走自愈而非死循环）。

## Impact

- **代码**：`lib/tools/password/crypto/kek_manager.dart`（DEK 上岗前匹配校验钩子）；`lib/services/keychain_service.dart`（`_ensureLoaded` 认证失败分支：区分失配 vs 损坏，失配走备份+重建+信号）；`lib/tools/password/crypto/vault_file_store.dart`（备份残件辅助）；`lib/shell/ai_config_page.dart`（消费失配信号，提示重填）。
- **行为兼容**：DEK 与密文匹配的正常路径零变化；仅失配路径从"死循环/静默丢弃"变为"备份+重建+告知"。旧密钥在失配后本就不可恢复，不造成额外数据损失。
- **安全**：重建前强制备份残件（不删除证据）；试解密仅做认证校验，不产生明文落盘。无 BREAKING。
