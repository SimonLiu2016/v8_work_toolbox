## Context

当前安全工具箱定义了 14 个 CLI 工具，统一绑定了 `brewName` 并通过 `brew install` 尝试拉取。但在实际 macOS 环境下：
1. `netexec` 在 Homebrew 官方核心源中不存在（官方由 pipx 维护）；
2. `metasploit` 在 macOS Cask 中因 Gatekeeper 被官方禁用；
3. 本机为 Intel x86_64 架构，Homebrew 将其降级为 Tier 3，部分带依赖的包（如 `sqlmap`）会触发非交互 stdin 挂起，部分工具（`httpx`、`ffuf`）无 bottle 需本地编译 Go 代码；
4. 批量安装完成日志因文字编排让用户误以为全部成功安装。

## Goals / Non-Goals

**Goals:**
- 将 `SecurityTool` 扩展安装方式元数据（如渠道类型 `InstallMethod.brew`、`InstallMethod.pipx`、`InstallMethod.manual`），避免对不支持 brew 的工具发送失效命令。
- 在 `BrewInstallService` 中增加对 `pipx` 渠道的直接支持（检测 `pipx` 并执行 `pipx install netexec`）。
- 对 `metasploit` 提供官方安装脚本指导与外链，禁用 brew 一键触发。
- 在子进程启动中对 `stdin` 传入 EOF / 立即关闭，杜绝任何 `[y/n]` 挂起可能。
- 重构批量日志与单项日志反馈，将成功数与失败数精确分开展示，提取关键错误行。
- 对需要本地编译或拉取大仓库的工具（`httpx`, `ffuf`, `exploitdb`）增加提示。

**Non-Goals:**
- 不自建第三方二进制分发 CDN。
- 不自动帮用户安装 Metasploit 的大型系统级 PKG 安装包（该操作需 root 权限且涉及系统安全性）。

## Decisions

### 1. 工具安装方式扩展（`InstallMethod` 枚举）
- **决定**：在 `SecurityTool` 中增加 `InstallMethod installMethod`（默认为 `brew`，可选 `pipx` 与 `manual`）。
- **理由**：
  - `netexec` 的官方标准方式是 `pipx`；
  - `metasploit` 官方 cask 已废弃，必须引导用户走官方安装器；
  - 避免在 UI 层硬编码 `if (tool.id == 'netexec')`。

### 2. 子进程 stdin 关闭
- **决定**：在 `Process.start` 之后立即执行 `await process.stdin.close()`。
- **理由**：
  - Homebrew 在遇到非预期依赖更新确认时，若发现 stdin 已关闭（EOF），会按照非交互模式的默认策略处理，而不会无限期挂起等待用户终端键盘输入。

### 3. 日志与错误高亮机制
- **决定**：
  - 批量安装结果改为：
    - 若全成：`✓ 批量安装完成：全部 N 个工具均已安装就绪`
    - 若部分失败：`⚠️ 批量安装结束：X 个成功，Y 个失败。请查看上方失败详情`
  - 单工具安装失败时，从 stderr/stdout 中匹配提取关键错误行（如 `No available formula`, `already locked`, `disabled because`），直接高亮输出。

## Risks / Trade-offs

- **[Risk]** 用户机器未安装 `pipx` 时 `netexec` 安装仍然会失败。
  - **Mitigation**：执行前检测 `resolveExecutable('pipx')`；若未安装，在控制台提示 `未检测到 pipx，请先运行 brew install pipx 后再试`。
- **[Risk]** Go 源码编译工具（`httpx`, `ffuf`）在 Intel Mac 上耗时较长（3~5 分钟）。
  - **Mitigation**：安装开始时在日志中明确提示耗时预期，并展示进度动画。
