# auto-registrar Specification

## Purpose
提供平台化的自动注册工具箱，集成 Outlook/Hotmail 等自动化批量注册能力，通过防检测浏览器引擎、验证码识别与接码平台完成账号自动化注册。
## Requirements
### Requirement: Outlook 自动化注册任务调度与执行
系统 SHALL 提供 Outlook/Hotmail 自动化注册执行能力，支持配置并发数、目标域名（outlook.com/hotmail.com）、人机验证模式（Arkose物理模拟/CapSolver/AI视觉）、SMS接码配置与安全恢复邮箱配置。

#### Scenario: 启动并执行注册任务
- **WHEN** 用户在注册控制台配置参数并点击「启动任务」
- **THEN** 系统启动指定并发的后台 Worker 实例，自动打开反检测浏览器，模拟真人轨迹输入、通过人机验证并在成功后绑定恢复邮箱，实时向界面推流进度日志与成功/失败统计

#### Scenario: 停止注册任务
- **WHEN** 用户点击「停止任务」
- **THEN** 系统优雅中止所有进行中的 Worker 实例并释放浏览器进程资源

### Requirement: 代理网络集成
系统 SHALL 支持与内置网络代理服务（Mihomo/Clash）或自定义代理进行联动，在注册各 Worker 启动时分配独立代理出口。

#### Scenario: 启用代理分流注册
- **WHEN** 用户在注册配置中启用代理
- **THEN** 每个浏览器 Worker 实例均通过指定的本地代理端口或动态提取的代理节点建立网络连接

### Requirement: 注册结果自动留存
系统 SHALL 在注册成功或失败后自动生成结构化账号记录，并将成功账号持久化保存至中央账号资产库。

#### Scenario: 注册成功自动归档
- **WHEN** 某个 Worker 完成微软注册流程并成功验证
- **THEN** 系统自动构建包含邮箱、密码、姓名、出生年月、恢复邮箱、注册时间、注册状态等字段的记录并写入资产库

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

