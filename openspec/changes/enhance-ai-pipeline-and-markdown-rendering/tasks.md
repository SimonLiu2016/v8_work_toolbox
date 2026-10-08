## 1. Markdown 格式化渲染

- [x] 1.1 将 `vuln_scan_view.dart` L894 的 `SelectableText(_response)` 替换为 `AppMarkdownView(data: _response, selectable: true)`（`_AiRemediationDialog` 单漏洞弹窗）
- [x] 1.2 将 `vuln_scan_view.dart` L1076 的 `SelectableText(_response)` 替换为 `AppMarkdownView(data: _response, selectable: true)`（`_BatchRemediationDialog` 批量加固弹窗）
- [x] 1.3 确认 `vuln_scan_view.dart` 顶部已导入 `AppMarkdownView` 所在组件库；如未导入则添加

## 2. AdaptiveAgentPipeline 实现

- [x] 2.1 在 `security_pipeline_service.dart` 新增 `AdaptiveAgentPipeline` 类，包含 `run(controller, target, sessionType)` 静态方法；内部先调用 `SecurityPipelineService.instance.runWebPipeline()` 或 `runLanPipeline()` 完成基础阶段
- [x] 2.2 基础阶段完成后，构建摘要 context（资产数量 + 发现物 top-10 标题与严重度），调用 `SecurityAgentService.instance.run()` 进行 AI 研判循环（`maxIterations: 5`）；executeTool 回调使用 `runAgentTool(controller, name, args)`
- [x] 2.3 AI 研判循环最多执行 3 轮（用外层 for 循环控制，每轮判断 `AgentLoopResult.executions.isEmpty` 或关键词宣告完成则提前退出）
- [x] 2.4 循环结束后调用 `SecurityAgentService.instance.generateDefensiveReport()` 生成最终报告，通过 `updateFinalReport()` 推送到 UI
- [x] 2.5 高影响工具（`kHighImpactTools`）在 `AdaptiveAgentPipeline` 中的 `onApproval` 回调直接返回 `true`（自动批准），并在 `AgentStep` 记录 `[自动批准]` 前缀

## 3. 防拒绝提示词三层框架强化

- [x] 3.1 更新 `SecurityAgentService._buildSystemPrompt()`：加入 Layer 1 合规授权声明段落
- [x] 3.2 更新 `SecurityAgentTools.all` 中工具的 `description` 字段：run_msf_module、run_sqlmap、run_hydra、run_ffuf 均改为合规框架语言

## 4. 一键全量评估 UI 入口

- [x] 4.1 在 `security_agent_view.dart` 的控制按钮区新增"⚡ 全量评估"按钮；点击调用 `AdaptiveAgentPipeline.run()`
- [x] 4.2 按钮在流水线运行中变为"■ 停止"并调用 `SecurityPipelineService.instance.cancel()`

## 5. 测试与部署

- [x] 5.1 运行 `flutter analyze`，确保 No issues found
- [x] 5.2 运行 `flutter test test/security_gaps_test.dart`，全部 44 项通过
- [ ] 5.3 运行 `./scripts/deploy_local.sh` 完成本地部署
