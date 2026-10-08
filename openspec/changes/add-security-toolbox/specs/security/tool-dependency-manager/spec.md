## Purpose

管理安全工具箱所依赖的外部 CLI 工具的检测、安装、更新和状态监控，确保用户无需手动配置即可启动任意安全扫描工作流。

## ADDED Requirements

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
