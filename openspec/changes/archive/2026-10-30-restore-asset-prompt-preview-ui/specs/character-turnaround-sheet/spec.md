## ADDED Requirements

### Requirement: 角色三视图生图 Prompt 预览与微调

系统在触发角色三视图生成前，SHALL 提供「预览 Prompt」操作入口。弹窗 SHALL 展示分层组件（三视图骨架排版规范、时代服装锚点、角色容貌与体态特征等），允许用户实时编辑修改正向与负向提示词，并支持直接使用修改后的提示词发起生成。同时，系统在形态编辑区 SHALL 提供系统提示词覆盖卡片，支持用户自定义持久化 `systemPromptOverride`。

#### Scenario: 预览并微调角色三视图 Prompt 发起生图
- **WHEN** 用户在角色操作栏点击「预览 Prompt」
- **THEN** 系统弹出 Prompt 预览弹窗，展示分层组件与正负向 Prompt
- **AND** 用户修改提示词并点击「立即以此 Prompt 生成」时，系统以微调后的提示词提交三视图生成请求
