## Context

`add-security-toolbox` 的实现把服务层铺全了，但应用层（UI ↔ service 的接线）漏了四处：Agent 的 executor、Shodan 的 Key 与调用方、LHOST 的持久化、sqlmap 的结果来源。本设计只补接线与数据来源，不重写任何服务。

已就位的部分（不变）：
- `SecurityAgentTools` —— 9 个 `AgentTool` 声明 + 高影响白名单
- `SecurityAgentService.run()` —— 审批闸门、步骤流、上下文拼装
- `ShodanService.queryIp / mergeShodan` —— HTTP 查询与合并逻辑
- `SqlmapService` —— 已带 `--output-dir` 参数
- `IntelCrossMatcher.match()` —— 纯函数比对

## Goals / Non-Goals

**Goals:**
- Agent 的每次工具调用都产生真实、可追溯、可复用的结果
- Shodan / LHOST / 情报 Finding 三条链路从服务层贯通到 UI
- sqlmap 结论回归 design A 决策的 JSON 来源，并修掉 DBMS 贴错条目

**Non-Goals:**
- 新增第 10 个 Agent 工具
- 接入 SearXNG / 自部署实例之外的新情报源
- 情报 Finding 的全自动创建（明确不做，见下）

---

## Decisions

### A. Agent 执行层：UI 侧一个总 executor，按工具名分发

```
SecurityAgentService.run(executeTool: ...)
        │
        ▼
_AgentToolExecutor (security_toolbox/services/security_agent_executor.dart)
        │
        ├─ run_nmap        → NmapService.scan()        → 资产 upsert + 时间线
        ├─ run_nuclei       → NucleiService.scan()     → Finding add + 时间线
        ├─ run_subfinder    → SubfinderService.run()   → 资产 upsert
        ├─ run_httpx        → HttpxService.run()       → 资产 metadata 合并
        ├─ run_ffuf         → FfufService.run()        → URL 追加至资产
        ├─ run_sqlmap       → SqlmapService.scan()     → Finding add
        ├─ run_msf_module   → (审批后) MsfRpcService   → 会话列表刷新
        ├─ query_threat_intel → ThreatIntelRepository → 只读摘要
        └─ get_session_findings → FindingRepository    → 只读摘要
```

**为什么放在 service 层而不是 UI 层？** `SecurityAgentService` 只做编排（审批、步骤流），不认识数据库。给它注入一个 executor 实现，UI 就只剩"弹审批框"这一件事——现在 UI 里那个只 log 的假 executor 会被真正的替换。测试也能直接构造 executor，不需要 Widget。

**每个工具的返回文本统一截断到 500 字符**（`SecurityAgentService._summarize` 已有此逻辑，executor 只需保证返回紧凑 JSON 而不是裸输出）。

**无会话 / 工具未安装 → 返回 actionable 文案**，不是"失败"。AgentLoop 会把这句回灌给模型，模型据此改走别的路径——echo 现在做不到这一点，因为它永远返回"成功"。

### B. Shodan：Key 走 settings_store，查询触发点在资产列表

Key 存 `config/security-toolbox.json`（`SettingsStore.writeToolConfig`），与 GitHub token 同一处。**不用** `flutter_secure_storage`：那是密码库的凭证容器，语义不同；Shodan Key 是可从账户页随时轮换的查询令牌，随配置同步更有用。

查询入口放在 LAN / Web 侦察的设备与资产列表行内（"外部情报"按钮）。UI 层拿 `ShodanService.queryIp()`，成功后用 `mergeShodan()` 合进该资产的 metadata——**走 AssetRepository.upsert 的合并语义**，不覆盖本地扫描得到的端口。

未配 Key / 未装 CLI 都在 UI 层前置拦截，不发请求。

### C. LHOST/LPORT：settings_store + 探测本机 IP 兜底

新增 `ExploitDefaultsStore`（同构于 `IntelSettingsStore`）。三个使用点：
1. 利用 Tab 的"全局参数"卡片（保存 + 展示当前值）
2. `_execute()` 的 options 拼装（替换现在用 MSF host 顶替的写法）
3. AI 推荐的参数预填（`ExploitRecommendation` 生成时带上）

从未配置时用 `NetworkInterfaceDetector` 取第一个非 loopback 接口 IP 兜底，port 默认 4444。确认对话框里高亮这两个值——填错的 LHOST 会让 meterpreter 回连到错误地址，而这个错误只在会话建立失败后才可见。

### D. sqlmap：读 `--output-dir` 的结果文件，DBMS 按 URL 归属

sqlmap 的结果文件布局：`<output-dir>/<host>/<sanitized-url>/result.json` 或 `dump/<db>/...`。版本间路径差异大，所以策略是：

1. 跑完后**在 output-dir 下递归找 `*.json`**，按 mtime 取本次写入的
2. 优先解析 `data` 数组里的 `parameter` / `place` / `title` / `dbms`
3. 找不到结构化文件 → 回退 stdout 正则（现有逻辑），日志标注回退

修掉现在的 DBMS 贴错：`findings.add` 时就地决定 dbms，不再事后改 `findings.last`。

### E. 情报 Finding：一键落库，明确不做全自动

```
sync → IntelCrossMatcher.match() → banner（数量 + 首条示例）
                                     │
                                     └─ [生成 Finding] 按钮
                                            │
                                            ├─ 逐条 upsert（去重: sessionId+assetId+cveId）
                                            └─ 刷新列表 + 时间线 finding_update
```

**为什么不自动？** 首次同步 7 天 CVE 可能命中几十个资产。全自动会瞬间灌入几十条"待验证"，用户要先删一遍——噪音成本大于便利。spec 原文写"自动生成 Finding"，这里显式收窄为"一键生成"，已在 spec 的 MODIFIED Requirement 中改为用户确认后创建。

去重键用 `(session_id, asset_id, cve_id)`：同一资产的同一 CVE 只建一条，重复点击幂等。

### F. ffuf 字典：按架构两段查找

`/opt/homebrew/share/seclists/...` → `/usr/local/share/seclists/...`，都没有则返回 actionable 文案。seclists 本身也是 brew 装的，两个前缀必须都覆盖——本机就是 Intel（`/usr/local/bin`），写死 Apple Silicon 路径等于没写。

## Risks / Trade-offs

- **[Agent 跑长扫描会卡住 AgentLoop 的 timeout]** → executor 内各自的 `timeout` 仍是分钟级（nmap 10min / nuclei 30min），而 `AgentLoop.run` 的 `timeout`（默认 120s）只作用于单次 LLM 调用，不作用于 execute 回调。已确认无冲突。
- **[AI 推荐参数时 LHOST 未配置]** → 兜底探测本机 IP + 确认对话框高亮，两项叠加。
- **[Shodan Key 明文落盘]** → 与 GitHub token 同等对待（settings_store 的 config 文件 0600）。账户页可轮换，非系统凭证。
- **[sqlmap 结果文件路径版本间漂移]** → 递归扫描 + stdout 回退，两条路都留日志。
- **[情报 Finding 一键创建仍可能量大]** → 一次点击上限 50 条，超出提示"仅创建前 50 条，请缩小同步时间范围"。

## Migration Plan

无数据迁移。新增的 settings 键（`shodan_api_key`、`exploit_lhost`、`exploit_lport`）缺失时走兜底路径，不影响既有会话与资产。
