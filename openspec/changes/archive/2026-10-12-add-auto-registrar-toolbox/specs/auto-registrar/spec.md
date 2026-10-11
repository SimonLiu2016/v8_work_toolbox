## Purpose

提供平台化的自动注册工具箱，集成 Outlook/Hotmail 等自动化批量注册能力，通过防检测浏览器引擎、验证码识别与接码平台完成账号自动化注册。

## ADDED Requirements

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
