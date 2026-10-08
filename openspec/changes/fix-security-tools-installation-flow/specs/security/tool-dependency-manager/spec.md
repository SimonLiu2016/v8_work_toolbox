## Purpose

管理安全工具箱中受管工具的可用性探测、多渠道安装策略与安装日志实时诊断反馈。

## ADDED Requirements

### Requirement: 精确的批量安装结果统计反馈
系统在执行一键安装全部缺失工具结束后，SHALL 清晰区分成功与失败数量并提供准确的总结日志，不得使用容易引起混淆的单一模板。

#### Scenario: 批量安装存在失败项时的告警与总结
- **WHEN** 用户点击“一键安装”且存在工具安装失败（例如 0 个成功，9 个失败）
- **THEN** 系统在日志控制台输出明确的失败统计（如 `❌ 批量安装结束：0 个成功，9 个失败`），并提示用户查看关键错误行进行排查

#### Scenario: 批量安装全部成功时的反馈
- **WHEN** 用户点击“一键安装”且所有缺失工具均顺利安装完成
- **THEN** 系统输出成功总结日志，并在界面将所有受管工具状态无缝更新为已就绪

### Requirement: 多渠道安装支持与不支持工具友好引导
系统 SHALL 明确识别受管工具的安装渠道（Homebrew、pipx 或手动安装），不得将无 Homebrew 支持的工具强行通过 brew 命令执行。

#### Scenario: NetExec 渠道引导或自动使用 pipx
- **WHEN** 用户尝试安装 NetExec
- **THEN** 若本地存在 `pipx`，系统通过 `pipx install netexec` 执行安装；若未安装 `pipx`，系统在控制台与界面给出具体的安装指令指导（`pipx install netexec`）而不是盲目报 brew 错误

#### Scenario: Metasploit 手动安装指引
- **WHEN** 用户查看或尝试安装 Metasploit
- **THEN** 系统明确标记其为手动安装工具，提供官方安装脚本引导，禁用失效的 `brew install metasploit`

### Requirement: 子进程非交互式执行加固与输入阻断防护
系统在调用 Homebrew 安装带有依赖升级的工具时，SHALL 关闭子进程标准输入（重定向 EOF），避免进程在等待 `[y/n]` 交互时无限期挂起。

#### Scenario: 带依赖更新工具的静默安装
- **WHEN** 安装依赖需要同步更新的工具（例如 `sqlmap` 依赖 Python 升级）
- **THEN** 子进程以非交互且无悬挂方式执行，不因等待交互确认而停滞

### Requirement: 长耗时编译型工具的状态与预期管理
对于在当前平台（如 Intel macOS）缺少预编译包需本地编译（如 `httpx`、`ffuf`）或需克隆巨型仓库（如 `exploitdb`）的工具，系统 SHALL 在启动安装时给出耗时预期提示。

#### Scenario: 编译型工具安装启动提示
- **WHEN** 用户启动 `httpx`、`ffuf` 或 `searchsploit` 的安装
- **THEN** 系统在日志中打印明确提示（如“该工具需本地编译或下载大仓库，耗时可能较长，请耐心等待”），并在界面持续展示加载中状态
