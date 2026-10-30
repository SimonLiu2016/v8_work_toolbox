## Context

当前漏洞发现物列表通过 `_buildFindingList` 呈现，每个发现物右上角有 Popup 菜单，其中“AI 推荐利用方案”调用 `SecuritySessionController.askAi`。
目前存在：
1. 请求携带 `sessionContextJson()`（包含多达 50 个全局资产与 50 条全局漏洞）及未截断证据，且提示词显式索要 Metasploit/PoC 攻击参数，极易触发商业大模型安全拦截与长达 90 秒的等待超时；
2. 一旦发生超时，底层 `AiService` 将候选供应商拉黑 60 秒冷却，导致用户在弹窗关闭后点击其他漏洞项时瞬间报 `SlotUnavailableException` 错误；
3. 发现物列表没有批量选择与批量操作机制，且缺乏全局漏洞整改方案生成入口。

## Goals / Non-Goals

**Goals:**
- 将漏洞研判的 AI Prompt 重构为中立合规的系统防御加固与应急缓解指引，彻底消除触发安全审查的攻击性词汇；
- 对 AI 请求做轻量化重构（截断 evidence 至 500 字符内，不带冗余全局资产），并支持单次请求自定义超时（如 40 秒）；
- 在研判弹窗中增加「强制重试」按钮（调用带 `ignoreCooldown: true`），打破 60 秒冷却拦截；
- 实现离线标准化安全防御建议生成器（基于 CVE、服务名与严重度等级匹配），在 AI 失败或离线时自动兜底；
- 在 `VulnScanView` 中支持 Checkbox 多选机制（全选/反选/仅选高危）、批量动作工具条（批量标记状态）、以及「一键全量漏洞加固汇总」弹窗。

**Non-Goals:**
- 不修改底层 `AiService` 的 60 秒全局冷却策略（由调用方在用户显式重试时显式传入 `ignoreCooldown: true`）；
- 不引入外部新依赖，全部基于现有 Flutter Material 3、Drift 数据库与现有服务架构。

## Decisions

### 1. 轻量化与防御型提示词构建
- **决策**：在 `SecuritySessionController` 或辅助类中新增 `askFindingRemediation(PentestFinding finding, String targetHost, {bool forceRetry = false})` 专门用于漏洞研判。
- **提示词规范**：
  - 角色设定为“企业系统安全架构师与应急响应专家”；
  - 输出结构限定为：【漏洞成因与风险影响】、【应急临时防护措施】、【官方修补加固方案】、【复测验证方法】；
  - 自动从 `finding.evidence` 中提取关键行并截断至最多 500 字符，不加载不相干资产数据。
- **替代方案对比**：原 `askAi` 泛型接口保留用于全局问答，新接口专司漏洞防御研判。

### 2. 抗熔断冷却重试与离线兜底建议
- **决策**：
  - `_AiRemediationDialog`（原 `_AiExploitDialog` 升级改名）在捕获异常时，不仅展示错误原因，同时提供「强制重试」与「查看离线防御建议」两个操作；
  - 实现 `OfflineRemediationAdvisor.build(finding, targetHost)` 离线建议生成器：
    - 若包含 SSH，提供密钥认证、禁用 root、修改端口、fail2ban 加固建议；
    - 若包含 CVE，给出官方安全公告查询、版本升级、PoC 流量 WAF 拦截规则；
    - 若包含 sqlmap/注入，给出参数化查询、输入过滤、DB 最小权限建议；
    - 其他未匹配项给出通用系统加固清单。
- **价值**：断网或 AI 审查挂起时用户依然可以获取有价值的防御方案，不会空手而归。

### 3. 多选模式与批量状态标记
- **决策**：
  - `_VulnScanViewState` 增加 `Set<String> _selectedFindingIds = {}`；
  - 列表顶部增加工具条：全选 / 反选 / 仅选高危 (Critical + High)；
  - 选中有项目时，展开批量操作栏，提供「批量标记为：已整改 / 误报 / 已验证」；
  - 调用 `SecuritySessionController` 新增的 `batchSetFindingStatus(List<String> ids, String status)` 一次性批量提交数据库，提升响应速度。

### 4. 一键全量漏洞加固汇总清单 (Batch Summary)
- **决策**：
  - 在发现物卡片顶部增加「一键 AI 全量加固清单」按钮；
  - 对当前会话的所有发现物进行内存聚合与去重（相同 templateId/title 按目标汇总，统计影响面）；
  - 调用 AI 生成系统级整改计划（或在离线时生成本地汇总清单），以 Markdown 弹窗形式展示并支持一键复制整改报告。

## Risks / Trade-offs

- **[Risk]** 批量选中的漏洞过多时，一次性生成全量报告可能超过上下文上限。
  - **Mitigation**：聚合前做分组统计（去重合并相同服务的探测项，保留 top 20 核心漏洞项），严格控制输入 token 在 2000 以内。
- **[Risk]** 离线兜底建议的规则匹配可能覆盖不全。
  - **Mitigation**：采用分层回退策略（特定服务/CVE → 漏洞类型 → 严重度级别通用加固指引），保证任何发现物都能得到清晰合理的步骤。
