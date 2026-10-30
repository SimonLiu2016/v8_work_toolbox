## Why

当前“安全工具箱”各功能面板（网络侦察、漏洞扫描、漏洞利用、脚本生成、Security Agent）在数据与操作层面相互割裂，用户在侦察发现存活设备与开放端口后，无法直接调用扫描与利用工具进行下一步处置，Agent 输出的威胁发现也缺乏可交互的验证与利用入口。建立跨模块的工作流串联机制与动作下钻入口，可消除功能孤岛，形成“侦测识别 → 脆弱性核查 → 验证挖掘 → 脚本定制 → 报告汇整”的完整闭环。

## What Changes

- **会话控制器导航与意图中枢**：在 `SecuritySessionController` 引入响应式跨 Tab 导航与上下文意图分发机制（`navigateWithContext` / `consumeNavigationIntent`），支持携带目标资产、端口服务、CVE 漏洞信息跨面板切换并预填。
- **侦察资产与端口动作下钻**：在局域网侦察与 Web 侦察的资产卡片、端口列表及网络拓扑节点上，提供针对主机与具体开放服务的操作入口（一键漏洞扫描、转入漏洞利用验证、委托 Agent 深入评估、生成专属测试脚本）。
- **漏洞发现项（Finding）快速验证与利用入口**：在 Nuclei 扫描与 Agent 报告的每个 Finding 卡片上提供一键验证动作（跳转 Exploit 搜索对应 CVE/模块、跳转 ScriptGenerator 生成验证脚本、跳转 AI 面板生成加固指南）。
- **Security Agent 交互式下一步动作卡片（Actionable Next Steps）**：在 Agent 审计报告中动态呈现结构化的推荐下一步行动清单，支持用户直接点击跳转并执行对应的工具链处置。
- **目标面板上下文自动消费与预填**：升级 `VulnScanView`、`ExploitView`、`ScriptGeneratorView` 和 `SecurityAgentView`，在接收到跨模块意图时自动选定目标资产、填充 RHOSTS/搜索关键字或生成专用任务 Prompt。

## Capabilities

### New Capabilities
- `security/chained-workflows`: 规范安全工具箱各模块（侦察、扫描、利用、脚本、Agent）之间的数据流转、上下文传递、资产/漏洞动作菜单及推荐行动交互链条。

### Modified Capabilities
<!-- 无现有需求规范变更 -->

## Impact

- **Affected UI Components**:
  - `lib/tools/security_toolbox/ui/security_toolbox_main_page.dart`（监听控制器 Tab 切换）
  - `lib/tools/security_toolbox/ui/lan_recon_view.dart` & `web_recon_view.dart`（资产与端口 Action 下拉/快捷按钮）
  - `lib/tools/security_toolbox/ui/vuln_scan_view.dart`（Finding 卡片 Action、消费导航意图并自动选中目标）
  - `lib/tools/security_toolbox/ui/exploit_view.dart`（消费导航意图自动填充 RHOSTS 与搜索关键字）
  - `lib/tools/security_toolbox/ui/script_generator_view.dart`（消费导航意图并自动组装脚本生成 Prompt）
  - `lib/tools/security_toolbox/ui/security_agent_view.dart`（消费导航意图设置任务、渲染交互式推荐行动卡片）
- **Affected State & Models**:
  - `lib/tools/security_toolbox/services/security_session_controller.dart`（导航意图状态与分发接口）
  - `lib/tools/security_toolbox/models/security_models.dart`（扩展 NavigationIntent 与 Agent 推荐动作模型）
