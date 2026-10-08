## Purpose

管理安全测试 Agent 在多会话场景下的状态隔离与切换联动，以及 Markdown 格式化报告渲染。

## ADDED Requirements

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
