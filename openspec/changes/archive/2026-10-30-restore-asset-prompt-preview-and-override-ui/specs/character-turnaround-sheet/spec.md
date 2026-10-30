## ADDED Requirements

### Requirement: 角色形态三视图生图 Prompt 预览与系统提示词覆盖 UI

系统 SHALL 在角色形态三视图生成区提供“预览 Prompt”操作入口，支持预览组装后的三视图排版、角色面部及服装提示词并支持一次性编辑。
同时，形态配置中 SHALL 支持持久化配置三视图骨架/排版约束覆盖（`systemPromptOverride`）。

#### Scenario: 预览角色三视图生成提示词
- **WHEN** 用户在角色形态配置中点击三视图生成旁的“预览 Prompt”按钮
- **THEN** 系统弹出预览对话框，展示正向与负向三视图组装结果，并支持微调后直接发起生成
