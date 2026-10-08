## Purpose

管理安全工具箱中受管工具的可用性探测、多渠道安装策略与安装日志实时诊断反馈。

## ADDED Requirements

### Requirement: pipx 与用户目录二进制探测支持
系统 SHALL 在应用运行环境中自动识别位于 `$HOME/.local/bin` 的外部工具，并在使用 pipx 安装特定工具时使用正确的源地址与版本参数。

#### Scenario: 成功探测 ~/.local/bin 中的工具
- **WHEN** 工具（如 NetExec）已被 pipx 安装至用户目录 `$HOME/.local/bin/netexec`
- **THEN** 系统探测工具状态时能够成功解析到该绝对路径，并以 `--version` 正确提取版本号标记为已就绪

#### Scenario: NetExec pipx 安装参数正确
- **WHEN** 用户触发 NetExec 的 pipx 安装
- **THEN** 系统调用 `pipx install git+https://github.com/Pennyw0rth/NetExec` 而非无效的裸包名

### Requirement: 控制台日志可复制与划选支持
系统在所有展示日志控制台的界面中，SHALL 允许用户通过鼠标自由划选日志文本进行复制，并提供一键将全部日志拷贝至系统剪贴板的功能。

#### Scenario: 划选日志文本复制
- **WHEN** 用户在 LogConsole 内通过鼠标拖拽选中任意一段或多行日志并按 Cmd+C
- **THEN** 所选日志文本被成功复制到系统剪贴板

#### Scenario: 一键复制全部日志
- **WHEN** 用户点击 LogConsole 工具栏上的“复制全部”按钮
- **THEN** 系统将当前控制台内的所有日志行拼接复制到剪贴板，并向用户展示复制成功提示
