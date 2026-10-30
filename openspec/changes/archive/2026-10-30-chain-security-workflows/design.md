## Context

当前安全工具箱通过 `SecurityToolboxMainPage`（左侧导航 + 内容区 + AI 侧板）承载各功能 Tab。目前 Tab 切换由主页面的局部私有变量 `_activeTab` 控制，各功能面板（`LanReconView`、`WebReconView`、`VulnScanView`、`ExploitView`、`ScriptGeneratorView`、`SecurityAgentView`）通过 `widget.controller` 共享会话数据。

然而，控制器中缺乏全局导航控制与上下文携带机制，导致各 Tab 沦为功能孤岛：
1. 侦察模块发现的主机与开放端口无法一键转入扫描、利用或 Agent 深度分析；
2. 漏洞扫描与 Agent 报告发现的高危脆弱点（Finding）无法一键转入利用模块验证或脚本生成；
3. 用户在完成侦察或扫描后，必须手动记录 IP 与端口，并切至目标 Tab 重复输入。

详细业务诉求与规范约束见 `proposal.md` 与 `specs/security/chained-workflows/spec.md`。

## Goals / Non-Goals

**Goals:**
- 在 `SecuritySessionController` 中建立统一的响应式 Tab 导航与瞬态意图分发机制（`activeTab`, `navigateToTab`, `currentIntent`, `consumeIntent`）。
- 升级 `SecurityToolboxMainPage`，使其导航栏受控制器驱动并能响应跨视图跳转事件。
- 为 `LanReconView`（局域网侦察）及 `WebReconView`（Web 侦察）的资产列表与端口组件增加交互动作菜单（Action Menu），支持针对目标主机及具体端口一键跳转到漏洞扫描、漏洞利用、脚本生成或 Agent 任务。
- 为 `VulnScanView` 的 Finding 发现项卡片增加验证入口（跳转 Exploit 预填 CVE、跳转 ScriptGenerator 预填 PoC 提示词）。
- 为 `SecurityAgentView` 的审计分析卡片增设结构化的「下一步行动（Next Actions）」交互按钮。
- 使目的地面板（`VulnScanView`、`ExploitView`、`ScriptGeneratorView`、`SecurityAgentView`）能够消费导航意图并自动填充表单状态。

**Non-Goals:**
- 不修改底层 SQLite 数据库持久化结构（导航意图为纯内存瞬态交互状态，不落盘）。
- 不破坏现有安全工具的独立手动输入能力（仍允许用户自由覆盖或清空输入框）。
- 不在客户端硬编码未经授权的自动化攻击执行，始终遵循“携带参数与建议 → 跳转至对应工具面板 → 用户确认后启动”的安全交互准则。

## Decisions

### 1. 导航与意图状态下沉至 SessionController
- **决定**：将主界面的活动 Tab 状态（`activeTab`）从 `_SecurityToolboxMainPageState` 移至 `SecuritySessionController`，并在控制器中增加 `NavigationIntent? _pendingIntent`。
- **理由**：`SecuritySessionController` 已经作为统一的 `ChangeNotifier` 被主页面和所有子 Tab 监听。让控制器管理当前激活的 Tab，子视图只需要调用 `controller.navigateToTab('vuln', intent: ...)` 即可完成视图切换并通知目的地视图。
- **备选方案**：
  - *通过逐层 Widget 回调传递*：需要将跳转函数穿透多层组件（从 `LanReconView` -> 设备列表 -> 端口标签），代码层级冗余度高，极易引发维护断层。
  - *使用全局 EventBus*：引入了全局无类型消息事件，不易追踪且与已有的 Controller 架构模式脱节。

### 2. 瞬态意图（NavigationIntent）的设计与单次消费模型
- **决定**：定义不可变的数据类 `NavigationIntent`：
  ```dart
  class NavigationIntent {
    final String targetTab;
    final PentestAsset? targetAsset;
    final PentestFinding? targetFinding;
    final int? port;
    final String? service;
    final String? initialQuery;
    final Map<String, dynamic> extra;
  }
  ```
  控制器提供 `consumeIntent()` 方法。目的地视图在渲染或处理时读取意图并调用 `consumeIntent()` 清理控制器中的暂存，确保用户后续手动点击左侧侧边栏切换 Tab 时，不会反复触发自动填充。

### 3. 资产与端口 Action 下拉交互
- **决定**：在资产卡片与开放端口 Chip 上使用 Flutter 原生 `PopupMenuButton`，提供带色彩图标的操作项：
  - `[漏洞扫描]`: 目标选中该 IP
  - `[漏洞利用]`: 填入 RHOSTS，若选中了端口则带入服务检索词
  - `[委托 Agent]`: 填入针对该主机及端口的专业渗透评估提示词
  - `[生成脚本]`: 预填针对该协议/服务的探测测试脚本 Prompt
- **理由**：PopupMenu 不占用列表行的横向紧凑空间，同时提供清晰的操作层级和提示说明。

### 4. Finding 与 Agent 报告的可行动纽带 (Actionable Findings & Next Steps)
- **决定**：
  - 在 `VulnScanView` 的 Finding 详情区域和列表项右侧，增加快捷动作按钮（“验证/利用”和“生成脚本”）。
  - 在 `SecurityAgentView` 中，基于会话中发现的资产/高危 Finding 动态解析出 1~3 条精炼的行动建议卡片（如“验证 CVE-2021-44228 影响范围”、“对 192.168.1.93 开展 Nuclei 全量扫描”），每条卡片内置一键跳转执行按钮。

## Risks / Trade-offs

- **[Risk] Tab 切换时子视图重建导致生命周期乱序** → 
  *Mitigation*: 意图存放在全局 Controller 中，目的地视图在 `initState` 或 `didChangeDependencies`（以及 `ListenableBuilder` 驱动的更新）中检测并安全消费，即使视图由于 Tab 切换刚完成挂载也能可靠提取意图。
- **[Risk] 预填参数覆盖用户正在编辑的未保存草稿** → 
  *Mitigation*: 仅当意图明确携带参数且通过显式动作触发时才执行预填；若输入框非空且与意图目标不一致时，优先采用意图目标并记录日志提示。
