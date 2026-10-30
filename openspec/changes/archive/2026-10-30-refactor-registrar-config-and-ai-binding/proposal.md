## Why

当前「自动注册工具箱」在每次点击启动前都需要用户重复输入或确认 AI Vision API Key、Endpoint、Model 以及 SMS 接码 Key、恢复邮箱、IMAP 授权码等信息。这不仅操作繁琐，而且割裂了系统全局的 `AiConfigStore` 视觉模型配置。我们需要让 AI 视觉识别自动复用系统已有 AI 配置，同时将 SMS 接码、恢复邮箱与 IMAP 等固定凭证持久化落盘，实现“一次配置，后续一键启动”。

## What Changes

- **AI 视觉多模态直接复用系统 AI 配置**：
  - 自动从系统的 `AiConfigStore` 读取 `multimodal`（或首选视觉支持）候选供应商及其模型，并从 `KeychainService` 检索对应 API Key。
  - 从注册工作台移除手填 AI API Key / Endpoint / Model 输入框，改为显示系统绑定的 AI 状态与供应商模型名称，启动时自动解析并注入。
- **一次性凭据持久化存储与 UI 结构解耦**：
  - 将 SMS 接码 Key、国家代码、安全恢复邮箱（QQ邮箱）、IMAP 授权码、默认并发与域名等配置持久化到系统 `SettingsStore` (`config/auto-registrar.json`)。
  - 首次配置后自动保存落盘，应用启动时自动载入。
  - 主操作界面分离日常运行参数与固定凭据配置，提供专用的「接码与邮箱设置」抽屉或弹窗，主界面仅保留就绪状态指示器与一键启动。

## Capabilities

### New Capabilities
- None

### Modified Capabilities
- `auto-registrar`: 变更注册任务配置模型与执行入口，要求支持系统 AI 配置自动解析与凭证持久化加载。

## Impact

- **UI 变化**：`RegistrarTaskConsoleView` 界面大幅精简，移除冗余的 Key/Endpoint/Model 输入框，增加设置弹窗/抽屉与系统 AI 绑定状态卡片。
- **配置持久化**：新增 `lib/tools/auto_registrar/services/registrar_config_store.dart` 统一管理工具专属持久化设置。
- **系统集成**：联动 `AiConfigStore` 与 `KeychainService` 自动解析视觉大模型。
