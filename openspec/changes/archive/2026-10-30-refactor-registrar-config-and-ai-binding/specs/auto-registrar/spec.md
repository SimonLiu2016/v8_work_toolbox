# auto-registrar Specification Delta

## ADDED Requirements

### Requirement: 注册凭据持久化与一次性配置
系统 SHALL 提供工具配置持久化能力，将 SMS-Activate 接码 Key、国家代码、安全恢复邮箱地址以及 QQ 邮箱 IMAP 授权码持久化保存，避免用户每次启动注册任务时重复输入。

#### Scenario: 自动加载已持久化的凭证
- **WHEN** 用户打开自动注册工具箱
- **THEN** 系统自动加载上次保存的 SMS 接码 Key、恢复邮箱与 IMAP 授权码，并在界面展示就绪状态

#### Scenario: 保存一次性注册凭据
- **WHEN** 用户在接码与邮箱设置面板中保存凭据
- **THEN** 系统将凭据持久化至本地配置文件中，后续任务启动直接复用

### Requirement: AI 视觉多模态自动复用系统配置
当用户选择「AI 视觉多模态」解验证码模式时，系统 SHALL 自动解析当前软件系统配置的 AI 多模态/视觉槽位及对应密钥，禁止在注册面板中要求用户重新配置 API Key、Endpoint 或 Model。

#### Scenario: 自动注入系统 AI 视觉配置启动任务
- **WHEN** 用户选择「AI 视觉多模态」并启动注册任务
- **THEN** 系统自动从系统 AI 配置存储与钥匙串中获取活跃视觉供应商的 API Key、Base URL 与 Model 并传给执行引擎，界面提示当前绑定的系统模型名称
