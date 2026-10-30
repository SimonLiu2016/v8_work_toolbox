## Context

在 macOS 下，用户通过 Rapid7 官方发布的 macOS PKG 安装 Metasploit Framework 时，文件结构通常部署在：
- 主可执行程序目录：`/opt/metasploit-framework/bin`（`msfconsole`, `msfvenom`, `msfrpcd` 等）
- 嵌入式 Ruby 与依赖程序目录：`/opt/metasploit-framework/embedded/bin`

在原有的 `SecurityProcessRunner` 实现中：
- 候选目录仅包含 `kSystemBinDirs`、`kBrewBinDirs` 与 `kUserBinDirs`。
- 子进程 PATH 环境变量没有包含 `/opt/metasploit-framework/bin`。
- `runCaptured` 启动子进程后直接监听 stdout/stderr，未关闭 `stdin`，而 `msfconsole` 在首次启动或探测时可能尝试交互提示。

## Goals / Non-Goals

**Goals:**
- 自动无缝发现 `/opt/metasploit-framework/bin` 中的安全工具（如 Metasploit `msfconsole`、`msfvenom`、`msfrpcd`）。
- 将该路径注入至安全子进程的运行环境，确保后续调用子命令（如 RPC 服务启动、生成 payload）时可以正常运行。
- 在 `runCaptured` 中安全关闭 stdin，防止进程交互阻塞。

**Non-Goals:**
- 不修改 Homebrew 自动化安装 Metasploit 的方式（仍优先支持 brew 或系统已安装版本）。
- 不引入外部路径配置文件的额外持久化机制，直接采用通用安全框架标准路径集合。

## Decisions

### 1. 增加 `kSecurityAppBinDirs` 常量并扩展 `augmentedPath` 与 `resolveExecutable`
- **决定**：在 `lib/tools/security_toolbox/services/security_process_runner.dart` 中定义：
  ```dart
  static const List<String> kSecurityAppBinDirs = [
    '/opt/metasploit-framework/bin',
    '/opt/metasploit-framework/embedded/bin',
  ];
  ```
  并在 `augmentedPath` 中追加 `...kSecurityAppBinDirs`，在 `resolveExecutable` 中将 `kSecurityAppBinDirs` 纳入候选查找目录。
- **替代方案考虑**：通过读取用户 `.zshrc` 执行 `zsh -ilc "which msfconsole"`。缺点是耗时极长（启动交互式 shell 需要额外几百毫秒），且如果用户也没有把 `/opt/metasploit-framework/bin` 写入 `.zshrc`（Rapid7 默认不自动修改 profile）依然无法生效。因此硬编码扫描官方推荐安装路径最快速、稳健。

### 2. `runCaptured` 立即关闭 stdin
- **决定**：在 `SecurityProcessRunner.runCaptured` 中，进程启动后：
  ```dart
  try {
    await process.stdin.close();
  } catch (_) {}
  ```
  向子进程 stdin 发送 EOF。
- **原因**：避免某些命令行工具在无 tty 情况下因 stdin 悬挂而无限等待。

## Risks / Trade-offs

- **[Risk]** `/opt/metasploit-framework/bin/msfconsole --version` 启动耗时较长（约 3-5 秒）。
  - **Mitigation**: `ToolStatusChecker.checkStatus` 已经对 `msfconsole` 做了 12 秒的充分超时设置，并在超时或成功时均做路径存在性兜底；关闭 stdin 避免了无意义的超时等待。
