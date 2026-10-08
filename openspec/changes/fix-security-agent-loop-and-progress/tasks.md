## 1. 服务层增强与状态流

- [x] 1.1 在 `SecurityAgentService` 中增加 `currentTool`（当前运行中工具名）与 `finalReport`（最终总结文本）字段及重置逻辑
- [x] 1.2 将 `SecurityAgentService.run` 的默认 `maxIterations` 调整为 8，并接入 `AgentLoop.onToolCallStart` 实时通知正在执行的工具
- [x] 1.3 在 `SecurityAgentService.run` 结束时捕获并存储 `result.text` 至 `finalReport`

## 2. 界面展示重构

- [x] 2.1 彻底重写 `SecurityAgentView._buildProgress`，移除硬编码的 `/9`，动态展示当前步骤序数与当前正在执行的工具名（或模型思考中）
- [x] 2.2 在 `SecurityAgentView` 中增加「Agent 综合分析与渗透建议」卡片，当 `finalReport` 生成后高亮渲染并提供复制按钮

## 3. 验证与本地部署

- [x] 3.1 运行单元测试并执行 `flutter analyze` 确保无报错
- [x] 3.2 运行 `./scripts/deploy_local.sh` 编译并热更新本地 `/Applications/V8WorkToolbox.app`
