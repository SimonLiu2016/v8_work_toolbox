## Context

参考 `proposal.md`。当前 `RegistrarTaskConsoleView` 将 AI API Key、Endpoint、Model 与 SMS Key、QQ 邮箱 IMAP 授权码作为表单项平铺在左侧注册面板上。系统本身具备成熟的 `AiConfigStore`（统一多候选与槽位路由）和 `KeychainService`，以及 `SettingsStore` 工具配置持久化机制。本次改动旨在将两部分体验重构为“系统 AI 自动读取”与“固定凭据一次性配置并落盘”。

## Goals / Non-Goals

**Goals:**
- 将注册工作台的「AI 视觉多模态」解题模式完全对接系统已有的 `AiConfigStore`（优先 `multimodal` 槽位候选），通过 `KeychainService` 自动提取活跃 API Key，抹平手动配置成本。
- 实现 `RegistrarConfigStore`，使用系统 `SettingsStore` 将 SMS Key、恢复邮箱、IMAP 授权码及默认任务参数（并发数、代理偏好等）自动持久化至 `config/auto-registrar.json`。
- 改造 UI：在控制台左侧清晰展示当前绑定的系统 AI 模型状态与凭据就绪状态，引入「⚙️ 接码与邮箱设置」弹窗/抽屉统一管理一次性配置，主操作流变为仅需点击【启动自动化注册】。

**Non-Goals:**
- 不改变 Sidecar 底层接收的配置协议（Sidecar 依然接收 `aiVisionApiKey`, `aiVisionEndpoint`, `aiVisionModel`，只是由 Dart 端在启动前自动解析并透传）。

## Decisions

### 1. 系统 AI 视觉配置动态解析
- **决策**：在 `RegistrarSidecarService` 或控制器中新增 `resolveSystemVisionAi()` 辅助函数：
  1. 检查 `AiConfigStore.instance.slotBindings['multimodal']`；若有候选，取优先级最高（首个）候选对应的 `AiProviderConfig` 与 `model`；
  2. 若 `multimodal` 槽位为空，寻找已启用的包含 `multimodalModels` 的首个 Provider；若仍无，寻找首个启用 Provider 的默认模型；
  3. 通过 `KeychainService.instance.readSecret(provider.keychainKeyId)` 获取 API Key；
  4. 组装为 `{apiKey, endpoint: provider.baseUrl, model: candidate.model}`。
- **优点**：用户在系统「AI 设置」中修改了模型或 Key，注册工具箱立即自动同步生效，保持系统一致性。

### 2. 工具专属配置持久化 (`RegistrarConfigStore`)
- **决策**：创建 `RegistrarConfigStore` 单例，管理如下字段：
  ```dart
  class RegistrarConfig {
    final int concurrency;
    final String targetDomain;
    final bool useProxy;
    final String captchaMode; // 'ai_vision' | 'capsolver'
    final String capSolverApiKey;
    final String smsApiKey;
    final String smsCountry;
    final String recoveryEmail;
    final String imapAuth;
    final String imapServer;
    final int imapPort;
  }
  ```
  底层调用 `SettingsStore.instance.readToolConfig('auto-registrar')` 和 `writeToolConfig('auto-registrar', ...)`。

### 3. UI 交互分离
- **日常控制栏**：并发数、目标域名、代理开关、验证码模式（单选 AI 视觉 / CapSolver）、【启动自动化注册】主按钮。
- **状态卡片**：
  - AI 视觉模式下展示：`AI 模型: [供应商名] / [模型名]`（带一键跳转或刷新）。
  - 就绪状态栏：`接码平台: 已就绪 / 未配置`，`恢复邮箱: xxx@qq.com`。
- **一次性设置弹窗**：点击「⚙️ 高级凭据设置」可修改 SMS Key、QQ 邮箱、IMAP 授权码与 CapSolver Key，保存后自动写盘。

## Risks / Trade-offs

- **[Risk] 系统未配置任何 AI 供应商** → **Mitigation**: 界面给出明确告警提示“系统尚未配置 AI 供应商或模型”，并提供跳转「AI 配置」按钮，启动任务时阻止并友好报错。
