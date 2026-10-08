## Why

在 macOS 系统上，用户通过 Metasploit 官方 Rapid7 PKG 安装包安装 Metasploit 后，其二进制文件默认放置在 `/opt/metasploit-framework/bin/`（包括 `msfconsole`, `msfvenom`, `msfrpcd`）及 `/opt/metasploit-framework/embedded/bin/`。
由于 macOS GUI 应用程序默认不读取用户 shell profile 配置，且 `SecurityProcessRunner` 仅探测系统目录、Homebrew 目录与用户目录，导致即使本机已安装 Metasploit，在安全工具箱中点击“重新检测”仍显示“未安装”。此外，`msfconsole` 在首次启动或版本探测时可能尝试交互式提示，若未关闭 stdin 会导致探测挂起阻塞。

## What Changes

- **扩展安全框架与工具默认安装路径**：
  - 在 `SecurityProcessRunner` 中引入 `kSecurityAppBinDirs`，包含 `/opt/metasploit-framework/bin` 与 `/opt/metasploit-framework/embedded/bin`。
  - 将该路径集合融入 `augmentedPath`（注入给所有子进程执行的 PATH 环境变量）以及 `resolveExecutable`（用于执行前查找存在且可执行的二进制文件路径）。
- **子进程防挂起优化**：
  - 在 `SecurityProcessRunner.runCaptured` 中，进程启动后立即关闭 `stdin`（写入 EOF），防止 `msfconsole` 或其它交互式 CLI 等待用户键盘输入而导致探测挂起直至超时。

## Capabilities

### New Capabilities
- `security/tool-dependency-manager`: 管理安全工具箱中受管工具的可用性探测、多渠道安装策略与执行环境支持。

### Modified Capabilities
<!-- 无已有 spec 变更 -->

## Impact

- `lib/tools/security_toolbox/services/security_process_runner.dart`：新增 `kSecurityAppBinDirs` 并合并至 PATH 环境变量与可执行文件解析器中；在 `runCaptured` 中安全关闭 stdin。
- 测试用例：增加针对 `/opt/metasploit-framework/bin` 的路径解析测试。
