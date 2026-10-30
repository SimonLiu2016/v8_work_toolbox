## 1. 原生流水线服务实现 (SecurityPipelineService)

- [x] 1.1 创建 `SecurityPipelineService`，提供 `runWebPipeline`（subfinder → httpx → katana → nuclei）与 `runLanPipeline`（ARP/网卡 → nmap → nuclei）
- [x] 1.2 在流水线中实现步骤广播（`AgentStep` 状态上报）、日志回写与随时停止（`cancel()`）机制
- [x] 1.3 确保流水线每个阶段产出即时入库（`sessionAssets`、`sessionFindings`、`timelineEvents`）

## 2. 防御与合规审计 AI 提示词体系改造

- [x] 2.1 重构 `SecurityAgentService` 和 `SecuritySessionController` 的系统提示词为企业安全防御架构师与合规审计专家角色
- [x] 2.2 实现 `generateDefensiveReport(sessionId)`，将聚合后的资产与风险转化为中立合规的结构化分析 Prompt 请求 AI
- [x] 2.3 增加大模型通用拒答检测（Refusal Guard）与本地离线结构化报告自动降级生成逻辑

## 3. UI 交互与一键预设工作流接线

- [x] 3.1 改造 `SecurityAgentView` 中的“Web 一键侦察”与“LAN 一键渗透”按钮：直接调度本地原生流水线，不再向 Agent 发送攻击性自然语言文本
- [x] 3.2 保持“步骤与执行进度”、“思考日志”与“综合分析建议”卡片的实时动态刷新，流水线完成后自动联动防御型 AI 报告展示
- [x] 3.3 提供“停止流水线”操作按钮并支持状态安全复位

## 4. 验证与本地部署

- [x] 4.1 编写针对 Native Pipeline 与防拒答报告降级的单元测试
- [x] 4.2 运行 `flutter analyze` 校验代码规范
- [x] 4.3 执行 `./scripts/deploy_local.sh` 编译并更新本地应用
