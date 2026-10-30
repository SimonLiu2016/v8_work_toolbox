# security/tool-dependency-manager Specification

## Purpose
管理安全工具箱所依赖的外部 CLI 工具的检测、安装、更新和状态监控，确保用户无需手动配置即可启动任意安全扫描工作流。
## Requirements
### Requirement: 工具清单注册

系统 SHALL 维护一份受管工具清单，每条记录包含：工具 ID、显示名称、Homebrew 包名（`brew_name`）、用途分类（lan_recon / web_recon / vuln_scan / exploit / intel / script）、最低版本要求、以及版本检测命令。

#### Scenario: 工具清单查询

- **WHEN** 安全工具箱加载时
- **THEN** 系统 SHALL 向清单中所有工具并行发出版本探测，在 5 秒内完成

### Requirement: 工具安装状态检测

系统 SHALL 通过执行 `which <tool>` 和版本命令探测每个受管工具是否已安装及其版本，结果分为：已安装且满足最低版本、已安装但版本过旧、未安装。

#### Scenario: 检测结果展示

- **WHEN** 用户打开"工具状态"面板
- **THEN** 系统 SHALL 显示每个工具的状态（已就绪 / 需更新 / 未安装）及当前版本号

### Requirement: 一键安装与更新

系统 SHALL 支持通过 `brew install <brew_name>` 安装缺失工具，通过 `brew upgrade <brew_name>` 更新旧版工具，并实时流式展示安装日志。

#### Scenario: 单工具安装

- **WHEN** 用户点击某个"未安装"工具的"安装"按钮
- **THEN** 系统 SHALL 执行对应的 brew install 命令，实时展示进度，完成后刷新该工具状态

#### Scenario: 批量安装所有缺失工具

- **WHEN** 用户点击"一键安装全部"
- **THEN** 系统 SHALL 依次安装所有状态为"未安装"的工具，每个安装完成后立即更新其状态

### Requirement: Nuclei 模板管理

系统 SHALL 单独管理 nuclei 模板库，支持初始化下载（`nuclei -update-templates`）和增量更新，并展示模板总数和最后更新时间。

#### Scenario: 模板初始化

- **WHEN** nuclei 首次被检测为已安装且无本地模板
- **THEN** 系统 SHALL 提示用户下载模板库，确认后自动执行下载

#### Scenario: 模板更新

- **WHEN** 用户点击"更新模板"
- **THEN** 系统 SHALL 执行 `nuclei -update-templates` 并展示新增/更新的模板数量

### Requirement: Homebrew 依赖前置检查

系统 SHALL 在首次使用安装功能前检测 Homebrew 是否已安装，未安装时展示 Homebrew 官方安装指引链接，而非直接尝试安装工具。

#### Scenario: Homebrew 缺失提示

- **WHEN** 用户触发任何工具安装操作且 Homebrew 未安装
- **THEN** 系统 SHALL 显示友好提示，提供 brew.sh 官网链接，安装按钮保持禁用

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

### Requirement: 依赖安装状态机与视觉加载反馈
系统 SHALL 在用户触发单工具安装或更新时，即时将该工具操作按钮置为加载中状态（展示进度指示器与“安装中…”或“更新中…”文本）并禁用该按钮，防止重复点击。

#### Scenario: 单工具点击安装
- **WHEN** 用户在工具依赖面板中点击某个未安装工具的“安装”按钮
- **THEN** 系统立即将该按钮切换为禁用加载态，展示进度转圈与“安装中…”，直到该工具安装命令结束

#### Scenario: 安装完成刷新
- **WHEN** 工具的安装或更新进程正常或异常退出
- **THEN** 按钮退出加载态，系统立即刷新该工具的版本探测状态并更新状态徽章

### Requirement: 实时安装日志流与 LogConsole 监控
系统 SHALL 在工具依赖面板底部提供实时的日志控制台（LogConsole），并将底层 Homebrew 安装进程输出的每一行 stdout/stderr 实时流式呈现在控制台中。

#### Scenario: 查看实时安装日志
- **WHEN** 用户点击“安装”或“一键安装”触发外部命令执行
- **THEN** 底部的日志控制台实时滚动输出执行的命令行与 Homebrew 下载、解压、安装输出

### Requirement: 一键批量安装全局进度与状态刷新
系统 SHALL 在用户触发“一键安装”时，将顶部“一键安装”按钮切换为“正在安装全部…”加载态，并向日志控制台输出结构化进度（如 `[1/N] 开始安装 <tool>...`）。

#### Scenario: 触发一键安装
- **WHEN** 用户点击“一键安装”按钮
- **THEN** 按钮进入禁用加载态，系统依次执行缺失工具的安装，实时输出每个工具的安装日志与总进度，并在全部完成后刷新整块工具状态板

### Requirement: Homebrew 非交互式与静默索引保护
系统 SHALL 在调用 Homebrew 子进程时强制注入 `HOMEBREW_NO_AUTO_UPDATE=1` 与 `NONINTERACTIVE=1` 环境变量，避免因后台长时间自动更新索引或等待交互输入而假死。

#### Scenario: 避免 brew 自动更新阻塞
- **WHEN** 系统启动 `brew install` 或 `brew upgrade` 子进程
- **THEN** 子进程环境包含 `HOMEBREW_NO_AUTO_UPDATE=1`，跳过无谓的 tap 更新直接执行软件包下载与安装

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

