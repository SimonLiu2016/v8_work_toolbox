## 1. 核心导航与意图基础设施

- [x] 1.1 在 `security_models.dart` 中定义 `NavigationIntent` 数据模型，包含目标 Tab、目标资产、目标漏洞项、端口、服务、初始检索词及扩展参数
- [x] 1.2 在 `SecuritySessionController` 中新增 `activeTab`、`pendingIntent` 属性，并实现 `navigateToTab` 与 `consumeIntent` 方法
- [x] 1.3 改造 `SecurityToolboxMainPage` 侧边栏，将局部 `_activeTab` 状态与控制器 `controller.activeTab` 深度绑定并响应切换事件

## 2. 侦察模块动作下钻

- [x] 2.1 在 `LanReconView` 的资产列表卡片中新增「操作」菜单（PopupMenuButton），支持一键转入漏洞扫描、漏洞利用、委托 Agent 及生成脚本
- [x] 2.2 在 `LanReconView` 的设备端口详情与拓扑图交互中增设特定开放服务端口的快捷下钻动作
- [x] 2.3 在 `WebReconView` 的子域名与资产端点列表中增加对应的跨模块跳转操作入口

## 3. 漏洞扫描与利用模块联动

- [x] 3.1 改造 `VulnScanView`，消费 `NavigationIntent` 并自动勾选目标资产，支持直接定位至目标扫描
- [x] 3.2 在 `VulnScanView` 的 Finding 发现项卡片中添加“验证/利用”（带 CVE 跳转 Exploit）与“生成测试脚本”动作按钮
- [x] 3.3 改造 `ExploitView`，消费 `NavigationIntent` 自动填充目标主机的 RHOSTS 输入框并在 PoC / MSF 模块中填入检索关键字

## 4. 脚本生成与 Security Agent 闭环打通

- [x] 4.1 改造 `ScriptGeneratorView`，消费 `NavigationIntent` 并自动拼接针对目标主机、协议服务或 CVE 的脚本生成提示词
- [x] 4.2 改造 `SecurityAgentView`，消费 `NavigationIntent` 自动组装并填充针对特定主机与开放端口的定制渗透评估任务
- [x] 4.3 在 `SecurityAgentView` 的分析报告卡片底部动态解析并渲染「推荐下一步行动（Actionable Next Steps）」交互按钮，支持一键触发后续工具链跳转

## 5. 测试与验证

- [x] 5.1 编写 `SecuritySessionController` 跨模块导航与意图消费的单元测试
- [x] 5.2 编写针对动作菜单点击及各面板表单自动预填的测试用例
- [x] 5.3 执行项目测试套件（`flutter test`）确保所有功能测试通过且无回归缺陷
