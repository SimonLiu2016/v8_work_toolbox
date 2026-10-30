## Purpose

管理安全工具箱中受管工具的可用性探测、多渠道安装策略与执行环境支持。

## ADDED Requirements

### Requirement: 独立安装包框架路径探测支持
系统 SHALL 在应用运行环境与子进程环境变量中自动识别位于 `/opt/metasploit-framework/bin` 与 `/opt/metasploit-framework/embedded/bin` 等独立安装包目录下的外部安全工具与可执行文件。

#### Scenario: 成功探测 /opt/metasploit-framework 中的工具
- **WHEN** 用户通过官方 Rapid7 安装包安装了 Metasploit（位于 `/opt/metasploit-framework/bin/msfconsole`）并触发工具重新检测
- **THEN** 系统探测工具状态时能够成功解析到该二进制路径，提取版本号并将 Metasploit 状态标记为已就绪

### Requirement: 探测子进程非阻塞与安全隔离
系统在执行工具版本探测等只读命令时，SHALL 立即关闭子进程的标准输入（stdin），防止交互式命令行工具因等待用户输入而挂起阻塞。

#### Scenario: 探测存在初次交互提示的工具
- **WHEN** 系统启动 `msfconsole --version` 探测工具版本
- **THEN** 子进程的标准输入被主动写入 EOF 并关闭，避免交互式会话阻塞，使版本输出快速返回并完成检测
