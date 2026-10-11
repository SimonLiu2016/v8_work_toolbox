## 1. 配置持久化与系统 AI 联动服务实现

- [x] 1.1 实现 `RegistrarConfigStore`，通过 `SettingsStore` 持久化 SMS Key、安全恢复邮箱、IMAP 授权码与日常注册偏好
- [x] 1.2 在 `RegistrarSidecarService` 中实现系统 AI 视觉多模态配置自动解析（从 `AiConfigStore` 槽位与 `KeychainService` 检索 API Key、Base URL 与 Model）

## 2. 界面交互精简与一次性配置抽屉/弹窗

- [x] 2.1 重构 `RegistrarTaskConsoleView`：移除表单中的 AI 视觉输入框，替换为系统 AI 模型当前绑定信息指示器
- [x] 2.2 实现「凭据与服务设置」对话框/抽屉，用于一次性配置并保存 SMS Key、恢复邮箱、IMAP 授权码与 CapSolver Key
- [x] 2.3 在主控制台增加就绪状态卡片，日常启动任务流程简化为仅需一键启动

## 3. 验证与本地部署

- [x] 3.1 编写单元测试验证配置持久化与系统 AI 配置动态解析
- [x] 3.2 运行 `./scripts/deploy_local.sh` 编译并更新本机应用进行完整验证
