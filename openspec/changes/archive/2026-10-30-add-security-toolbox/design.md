## Context

V8WorkToolbox 是一个 Flutter 桌面应用，已具备：`AgentLoop`（ReAct 工具调用循环）、`AiService`（多 LLM 支持）、`McpService`（MCP 协议）、`drift` SQLite ORM、`pdf` 库、`Process` Shell 执行能力、`ToolCategory` 插件体系。安全工具箱在此基础上新增 `ToolCategory.security`，复用全部基础设施。

---

## Goals / Non-Goals

**Goals:**
- 将 nmap/nuclei/metasploit 等 CLI 工具的输出实时流式呈现于 Flutter UI
- 以 SQLite 持久化完整渗透会话（资产、Finding、时间线）
- AI 在工作流各阶段提供分析、推荐和驱动能力
- Security Agent 通过现有 AgentLoop 全自动驱动多步骤渗透

**Non-Goals:**
- 实现任何 CLI 工具的功能本身（nmap/nuclei 等保持黑盒调用）
- 图形化 Metasploit 的全部功能（仅集成 exploit 执行和会话管理）
- 跨平台（仅 macOS，工具链依赖 Homebrew）
- 云端同步或多人协作

---

## Decisions

### A. 工具链执行架构：单进程流式 vs 后台守护

**决策：直接 `Process.start()` + stdout 流解析，不使用守护进程**

```
Flutter UI
    │
    ├── SecurityToolService
    │   ├── Process.start('nmap', args)
    │   ├── stdout.transform(LineSplitter)
    │   │       │
    │   │       └── JSON/XML 解析 → 写入 DB → notifyListeners()
    │   └── Process.kill() → 支持中断
    │
    └── UI 订阅 Stream<ScanEvent>，实时更新
```

**为何不用 MCP 封装工具调用？**
- MCP 适合长期运行的服务端工具（如 Filesystem、Database）
- nmap/nuclei 是一次性命令，每次调用都是新进程
- 直接 Process 调用延迟更低，无协议开销

**工具输出解析策略：**
- nmap → XML 输出（`-oX -`），用 xml 包解析（已有依赖）
- nuclei → JSONL 输出（`-json`），逐行解析
- subfinder/httpx/katana/ffuf → JSON/JSONL 输出
- sqlmap → JSON 输出（`--output-dir` + 读取 json 文件）
- Metasploit → MSFRPC HTTP JSON API

### B. AI 集成架构：三层介入模式

**B1. 分析师模式（被动）：结构化上下文注入**

工具扫描完成后，将结果序列化为紧凑 JSON（过滤无关字段），注入 AI 上下文：

```
SecurityAiContext {
  session: { name, type, scope },
  assets: [ { ip, os, ports: [{port, service, version}] } ],
  findings: [ { target, cve, severity, title, evidence_snippet } ]
}

→ 压缩后通常 < 8000 tokens
→ 直接使用 AiService.sendMessage() 接口
```

**B2. Security Prompt System：专属系统 Prompt**

```dart
const kSecuritySystemPrompt = '''
你是一名高级渗透测试工程师，拥有 OSCP/CISSP 级别的专业知识。
分析扫描结果时，你需要：
1. 按可利用性（不只是 CVSS）排序优先级
2. 识别漏洞组合利用路径
3. 给出 Metasploit 模块名或 PoC 方法
4. 技术描述精确，使用专业术语
当前工作会话：{session_json}
''';
```

**B3. Agent 驱动模式：复用 AgentLoop**

```
SecurityAgentService extends AgentLoop 的调用方模式：

1. 构建 AgentTool 列表（run_nmap / run_nuclei / ...）
2. 构建初始 system prompt（当前会话状态 + 目标描述）
3. 调用 AgentLoop.run(prompt, tools, execute)
4. execute 回调中：
   a. 解析工具名和参数
   b. 高影响操作（exploit）→ 触发 UI 审批对话框，等待用户确认
   c. 执行实际 Process 调用
   d. 返回 AgentToolOutcome
5. AgentLoop 将结果回灌给 LLM，决定下一步
6. LLM 不再调用工具时 → Agent 完成
```

**审批机制：高影响操作白名单**
```dart
const kHighImpactTools = {
  'run_msf_module',     // exploit 执行
  'run_hydra',          // 密码爆破
  'run_sqlmap_exploit', // 实际注入利用（vs 检测）
};
```
命中白名单的工具调用，在 execute 回调中通过 `Completer` 暂停，等待用户确认 Future 完成。

### C. 会话数据模型：drift SQLite 扩展

**扩展现有数据库，新增迁移版本**

```
PentestSession (sessions)
  id          TEXT PK
  name        TEXT
  type        TEXT  -- 'lan' | 'web'
  scope       TEXT  -- JSON array of targets
  status      TEXT  -- 'active' | 'paused' | 'complete'
  created_at  INTEGER
  updated_at  INTEGER

PentestAsset (assets)
  id          TEXT PK
  session_id  TEXT FK
  type        TEXT  -- 'host' | 'url'
  address     TEXT  -- IP or URL
  metadata    TEXT  -- JSON (os, ports, tech_stack, etc.)
  risk_level  TEXT  -- 'critical'|'high'|'medium'|'low'|'info'|'unknown'
  created_at  INTEGER

PentestFinding (findings)
  id          TEXT PK
  session_id  TEXT FK
  asset_id    TEXT FK (nullable)
  cve_id      TEXT (nullable)
  title       TEXT
  severity    TEXT  -- 'critical'|'high'|'medium'|'low'|'info'
  cvss_score  REAL
  status      TEXT  -- 'open'|'verified'|'exploited'|'false_positive'
  evidence    TEXT  -- raw tool output snippet
  source      TEXT  -- 'nuclei'|'manual'|'intel_match'|'msf'
  created_at  INTEGER

TimelineEvent (timeline_events)
  id          TEXT PK
  session_id  TEXT FK
  event_type  TEXT  -- 'tool_run'|'ai_analysis'|'status_change'|'finding_update'
  title       TEXT
  detail      TEXT  -- JSON (command, output, duration, ai_text, etc.)
  created_at  INTEGER

ThreatIntelCache (threat_intel)
  cve_id      TEXT PK
  title       TEXT
  cvss_score  REAL
  severity    TEXT
  description TEXT
  published   INTEGER
  is_kev      INTEGER  -- 0|1
  poc_url     TEXT
  synced_at   INTEGER

ReportVersion (report_versions)
  id          TEXT PK
  session_id  TEXT FK
  version     INTEGER
  format      TEXT  -- 'executive'|'technical'
  content     TEXT  -- Markdown
  created_at  INTEGER
```

**Why TEXT PK over INTEGER AUTOINCREMENT？**
与现有 notebook/ops_tool 表风格一致（UUID），便于跨会话引用。

### D. LAN 拓扑可视化实现

**决策：用 Flutter CustomPainter 实现力导向图，不引入新依赖**

原因：
- 无合适的 Flutter 图可视化库（dart 生态贫乏）
- 安全拓扑图节点数通常 < 50，CustomPainter 性能足够
- 力导向布局自行实现（100 行内），或固定星形布局（路由器为中心，主机环绕）
- 节点支持点击（GestureDetector 包裹）展示详情侧边栏

### E. Metasploit 连接策略

**决策：MSFRPC over HTTP（本地），不依赖 socket**

```
本地 msfrpcd 启动：
  msfrpcd -P password -a 127.0.0.1 -p 55553 -S (SSL off for local)

Flutter 通过 http 包发送 JSON-RPC 请求：
  POST http://127.0.0.1:55553/api/v1/auth/login
  POST http://127.0.0.1:55553/api/v1/modules/execute

MSFRPC 支持的关键操作：
  - module.search → 模块搜索
  - module.execute → 执行模块（返回 job_id）
  - session.list → 活跃会话列表
  - job.list → 后台任务列表
```

**首次连接流程：**
1. 检测 msfrpcd 是否运行（TCP connect 127.0.0.1:55553）
2. 未运行 → 提示用户通过 App 启动（`Process.run('msfrpcd', ...)`）
3. 已运行 → 发送 auth/login 获取 Token，后续请求携带 Token

---

## Risks / Trade-offs

- **[nmap 需要 sudo] → 缓解**：`sudo nmap` 需要密码。使用 macOS entitlements 的 `com.apple.security.network.client` 权限，OS 侦测的部分功能不需要 root（可降级）；或在 README 中说明通过 `sudo visudoers` 免密执行 nmap
- **[nuclei 模板库体积] → 缓解**：模板库约 200MB，首次下载需要告知用户，提供跳过选项（仅下载特定分类）
- **[AI Token 消耗] → 缓解**：扫描结果先截断（每类 Finding 最多 5 条详情，其余只保留 title），上下文 < 8000 tokens，避免 context overflow
- **[MSFRPC 稳定性] → 缓解**：每次请求前检测连接状态，断连后自动重试 3 次并提示用户
- **[SQLite 并发写] → 缓解**：扫描数据写入通过 drift `batch()` 操作，UI 读写通过 `watchQuery()` 订阅，不存在并发冲突
- **[沙盒限制] → 缓解**：macOS App 沙盒限制 `Process.run()` 的执行路径。已有项目通过 entitlements 豁免（ops_tool 中已有先例），安全工具需要 `com.apple.security.temporary-exception.files.absolute-path.read-write` 和 `com.apple.security.temporary-exception.sbpl`

---

## Migration Plan

1. 新增 `ToolCategory.security` 枚举值（无破坏性，按位插入枚举）
2. drift 数据库版本从当前版本 +1，新增 5 张表（仅追加，不改现有表）
3. 注册 `SecurityToolboxDefinition`（registry.dart 追加一行）
4. 工具库初始状态：全部显示"未检测"，不阻塞启动

## Open Questions

- Shodan API Key 是否应存入 `flutter_secure_storage`（与现有密码 vault 共享），还是单独存为 settings？→ 实现时决定，不影响整体架构
- nuclei 模板分类是否需要在 UI 中提供细粒度选择，还是"全选 / 仅 Critical 相关" 两档？→ 初版先两档，后期迭代
