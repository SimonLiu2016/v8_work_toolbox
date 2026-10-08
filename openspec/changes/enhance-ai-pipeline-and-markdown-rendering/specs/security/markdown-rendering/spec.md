## Purpose

在安全工具箱的 AI 响应弹窗（单漏洞研判、批量加固清单）中将模型返回的 Markdown 文本格式化渲染为富文本视图。

## ADDED Requirements

### Requirement: 弹窗内 Markdown 富文本渲染
系统 SHALL 在"AI 漏洞研判与加固建议"弹窗和"全量加固清单"弹窗中，将 AI 返回的 Markdown 文本渲染为包含层级标题、粗体、列表、代码块的格式化视图，而不是纯文本。

#### Scenario: 单漏洞研判弹窗渲染
- **WHEN** AI 返回包含标题、列表和代码块的 Markdown 格式加固建议
- **THEN** "_AiRemediationDialog" 弹窗以格式化富文本展示内容，标题可见层次结构，代码块具有高亮背景

#### Scenario: 批量加固清单弹窗渲染
- **WHEN** AI 返回包含多漏洞分段的 Markdown 格式全量报告
- **THEN** "_BatchRemediationDialog" 弹窗以格式化富文本展示，各漏洞段落层次清晰

#### Scenario: 离线降级内容同样格式化
- **WHEN** AI 超时触发离线降级，`OfflineRemediationAdvisor` 返回 Markdown 格式的本地建议
- **THEN** 弹窗同样以格式化富文本展示离线内容，而不降级为纯文本
