## Context

参考 `proposal.md`。V8WorkToolbox 为 Flutter macOS 原生桌面端应用，拥有成熟的系统服务架构（如 `PasswordVaultStore`、`NetworkProxyService` 等）。本次需要将 `mail_tools` 的 Outlook 批量注册引擎迁移至本应用，并扩展为通用的平台化「自动注册工具箱」，支持账号库集中存储、Excel导入导出以及向密码保险箱跨模块推入。

## Goals / Non-Goals

**Goals:**
- 将 `mail_tools` 的完整防检测注册引擎以轻量独立 Node Sidecar 服务的形式整合入 V8WorkToolbox，保留 100% 的 Anti-detect、CDP微动模拟、PerimeterX物理长按、QQ邮箱 IMAP 自动接验证码及多模态打码能力。
- 在 Flutter 侧构建现代化、易用的「自动注册工具箱」UI，支持实时任务进度监控与日志控制台。
- 构建中央账号资产库 (`RegisteredAccountStore`)，统一存储账号信息，支持多格式（Excel/CSV/TXT/JSON）导出。
- 实现 `/Users/simon/Downloads/邮箱信息.xlsx` 文件的无损导入解析与去重归档。
- 实现与「密码保险箱 (`PasswordVault`)」的一键凭证同步，并暴露 `AccountHubService` 供后续自动化工具复用。

**Non-Goals:**
- 不用纯 Dart 重新编写浏览器反检测引擎（避免因缺少 patchright/stealth 导致极高被风控率）。
- 本期不实现除 Outlook/Hotmail 以外的注册引擎（但架构对未来平台如 Proton/Gmail/社媒账号保持开放）。

## Decisions

### 1. 引擎执行模式：Node.js Sidecar 独立常驻服务
- **决策**：将 `mail_tools` 的注册引擎核心提炼为轻量 Node CLI/RPC Sidecar，由 Flutter 的 `Process.start` 负责生命周期调度与通信。
- **通信协议**：通过标准输入输出 (Stdio) 流式 JSON-RPC / NDJSON 进行指令与事件通信（如 `{"action":"start", ...}` 与 `{"event":"log", ...}`）。
- **备选方案及淘汰原因**：
  - *纯 Dart 实现*：Dart 缺乏定制的 Patchright/Stealth 反爬内核与 CDP 鼠标微动算法，微软极易检测出自动化特征并直接拦截。

### 2. 账号资产存储：独立持久化加密与内存模型 (`RegisteredAccountStore`)
- **决策**：采用双层持久化结构。元数据与账号记录持久化于 `AppPaths.root/registered_accounts.json`，敏感密码字段使用与系统一致的 AES-256 加密。
- **数据模型**：
  ```dart
  class RegisteredAccount {
    final String id;
    final String platform; // 'outlook' | ...
    final String email;
    final String password;
    final String firstName;
    final String lastName;
    final String birthDate;
    final String? recoveryEmail;
    final String? recoveryPhone;
    final String? proxyUsed;
    final String status; // 'SUCCESS' | 'FAILED' | 'REGISTERING'
    final DateTime createdAt;
    final String? errorLog;
    final bool verified;
    final DateTime? verifiedAt;
  }
  ```

### 3. Excel 导入导出集成
- **决策**：利用成熟的 Dart excel 库或由 python/node 辅助脚本进行 `.xlsx` 读写，支持解析表头并无缝对接现有 57 个历史账号文件 `/Users/simon/Downloads/邮箱信息.xlsx`。

### 4. 跨工具互通架构
- **决策**：在 `RegisteredAccountStore` 中注入 `PasswordVaultStore`，提供 `syncToPasswordVault(List<String> accountIds)` 方法。
- 当用户触发同步时，自动在 Vault 中生成 `VaultEntryType.login` 条目，打上标签 `Auto-Registered` 与 `Outlook`。

## Risks / Trade-offs

- **[Risk] Node.js 运行环境依赖** → **Mitigation**: 系统自动探测系统全局 `node` 路径（如 `/usr/local/bin/node`、`~/.nvm/`、`/opt/homebrew/bin/node`），在启动前进行健康检测；若未检测到给出友好指引。
- **[Risk] 代理连接冲突** → **Mitigation**: 优先复用应用内正在运行的 `NetworkProxyService` 端口 (6160)，避免重复启动代理冲突。
