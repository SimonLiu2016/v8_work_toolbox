## ADDED Requirements

### Requirement: 场景生图 Prompt 预览与系统提示词持久化覆盖 UI

系统 SHALL 在场景编辑视图的全景母图生成区与各方位机位视角生成区均提供“预览 Prompt”操作按钮，点击后弹出 `AssetPromptPreviewDialog`，支持一次性编辑调整后直接发起生成。
同时，场景编辑视图底部 SHALL 提供可折叠的“系统提示词组件与覆盖 (高级)”面板，支持修改并持久化保存方位空镜底板词覆盖（`systemPromptOverride`）与全景透视规范词覆盖（`panoramaSystemPromptOverride`）。

#### Scenario: 预览全景或方位生图提示词
- **WHEN** 用户在场景编辑视图点击全景母图或方位视角的“预览 Prompt”按钮
- **THEN** 系统弹出预览对话框，展示完整的系统约束、时代环境锚点与用户描述分层，支持直接发起生成

#### Scenario: 持久化覆盖场景系统提示词
- **WHEN** 用户在场景高级配置中填写了方位空镜或全景透视覆盖词并保存
- **THEN** 对应场景卡持久化记录覆盖配置，后续生图严格遵循覆盖定义
