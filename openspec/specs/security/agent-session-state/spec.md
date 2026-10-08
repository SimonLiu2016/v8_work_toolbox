# security/agent-session-state Specification

## Purpose
管理安全测试 Agent 在多会话场景下的状态隔离与切换联动，以及 Markdown 格式化报告渲染。
## Requirements
### Requirement: Agent 会话状态隔离与切换
系统 SHALL 按渗透测试会话（Session ID）独立保存和维护 Agent 的步骤历史、运行状态与最终报告；当用户在界面中切换激活的会话时，Agent 思考日志与报告面板 SHALL 立即同步切换为该会话的对应状态。

#### Scenario: 切换到未运行过 Agent 的新会话
- **WHEN** 用户在已产生 Agent 日志的会话 A 中切换到全新的会话 B
- **THEN** Agent 思考日志恢复为空状态引导文案，进度状态显示为空闲，最终建议报告卡片隐藏

#### Scenario: 切换回已有 Agent 记录的会话
- **WHEN** 用户从会话 B 再次切回已经完成测试的会话 A
- **THEN** 界面即时恢复会话 A 对应的思考日志、步骤完成状态与综合渗透建议

### Requirement: 渗透报告 Markdown 格式化呈现
系统在呈现 Agent 最终综合分析与渗透建议时，SHALL 将模型返回的 Markdown 内容格式化渲染为包含层级标题、代码块高亮底色与清晰间距的排版视图。

#### Scenario: 渲染包含 Markdown 语法的建议内容
- **WHEN** Agent 最终报告包含标题、粗体重点、列表以及代码命令
- **THEN** 界面使用 AppMarkdownView 进行排版渲染，并保持文本可选中划词与链接可点击

### Requirement: 渗透目标草稿会话隔离与推荐任务自动填充
系统 SHALL 按渗透测试会话独立维护 Agent 目标输入框（`_taskController`）的内容与草稿；当会话未手动输入自定义目标且目标范围有效时，系统 SHALL 默认自动将该会话的推荐预设任务填入输入框。

#### Scenario: 切换到未自定义任务的 Web 会话
- **WHEN** 用户切换到一个配置了域名目标（如 `91porn.com`）且未自定义输入渗透目标的 Web 会话
- **THEN** “描述渗透目标”输入框自动显示该域名的 Web 一键侦察推荐任务描述

#### Scenario: 切换到未自定义任务的 LAN 会话
- **WHEN** 用户切换到一个配置了网段目标（如 `192.168.1.0/24`）且未自定义输入渗透目标的 LAN 会话
- **THEN** “描述渗透目标”输入框自动显示该网段的 LAN 一键渗透推荐任务描述

#### Scenario: 用户编辑草稿后跨会话保持隔离
- **WHEN** 用户在会话 A 中修改了渗透目标描述并切换到会话 B，然后再切换回会话 A
- **THEN** 会话 A 的输入框完整保留用户修改后的草稿内容，而不会被会话 B 的输入覆盖或串扰

### Requirement: 预设工作流按钮动态目标解析
用户点击一键预设工作流按钮（“Web 一键侦察”或“LAN 一键渗透”）时，系统 SHALL 动态从当前活跃会话中解析当前生效的目标（域名或网段），严禁使用组件构建时的陈旧闭包变量。

#### Scenario: 切换会话后立即点击预设工作流
- **WHEN** 用户从包含 `baidu.com` 的会话切换到包含 `91porn.com` 的会话并立即点击“Web 一键侦察”
- **THEN** 系统动态以 `91porn.com` 生成任务描述并填充到输入框中启动 Agent，绝不包含 `baidu.com`

