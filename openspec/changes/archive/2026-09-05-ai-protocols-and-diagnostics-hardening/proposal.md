## Why

在实际使用智能磁盘瘦身与 AI 配置时，发现三个核心问题：
1. **AI 协议虚假实现**：Anthropic 和 Gemini 协议在模型探测与连通性测试中返回写死的静态数据，未发起实际网络请求，导致无法正确校验配置，且在对话调用时抛出未支持异常；
2. **AI 批量研判错误吞没与条目选择偏离**：研判失败时异常被静默捕获返回 0 项，用户无法获取失败原因；且在手动批量研判时忽视用户当前显式勾选的条目；
3. **文件清理权限失败引导缺失**：在清理沙盒受限目录失败时缺乏直观的 FDA 权限引导。

## What Changes

- **真实支持多 AI 供应商协议 (`AiService`)**：
  - 为 `Anthropic` 实现真实的模型发现 (`/v1/models`)、连通性探测及消息对话 (`/v1/messages`) 请求；
  - 为 `Gemini` 实现真实的模型发现 (`/v1beta/models`)、连通性探测及内容生成 (`generateContent`) 请求；
  - 确保“测试连接”基于真实网络握手返回成功与否，而非本地非空判断。
- **AI 研判容错与诊断错误透明化 (`AiDiskDiagnosticsService` & `SmartDiskSlimmerPage`)**：
  - 研判过程中捕获单条及批量异常并提取可读错误摘要（如 401 密钥失效、网络超时、格式解析异常等）；
  - 当研判返回 0 个或部分失败时，在 UI 提供明确的错误原因提示；
  - 修正手动触发批量研判的目标选取逻辑：若用户有勾选条目，优先针对选中的条目（最多前 8 项）发起研判，若无勾选则按未研判条目选取。
- **清理权限失败引导强化**：
  - 当移入废纸篓抛出权限受限错误时，提供友好提示并可一键打开系统设置。

## Capabilities

### New Capabilities

### Modified Capabilities
- `ai-configuration`: 增加 Anthropic 与 Gemini 真实 API 探测与连通性验证。
- `ai-disk-diagnostics`: 增加诊断失败错误原因回显，以及批量研判目标条目的用户显式勾选优先原则。

## Impact

- `lib/services/ai_service.dart`
- `lib/tools/slimmer/ai_disk_diagnostics_service.dart`
- `lib/tools/slimmer/smart_disk_slimmer_page.dart`
- `test/` 相关测试用例
