## Purpose

为安全工具箱外部 CLI 依赖项的单工具安装与批量一键安装提供状态机跟踪、防重点击反馈、实时流式安装日志展示与 LogConsole 监控。

## ADDED Requirements

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
