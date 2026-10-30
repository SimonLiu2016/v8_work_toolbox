## 1. Agent 工具真实执行

- [x] 1.1 新建 `lib/tools/security_toolbox/services/security_agent_executor.dart`，定义 `SecurityAgentExecutor` 类：构造时注入 `SecuritySessionController`，暴露 `Future<AgentToolOutcome> call(String name, Map<String, dynamic> args)`
- [x] 1.2 实现无会话守卫：`current == null` 时返回 `AgentToolOutcome.success('请先创建会话…')`，不写库
- [x] 1.3 实现 `run_nmap`：调 `NmapService.scan()`，结果 upsert 资产（含端口）+ `recordEvent(tool_run)`，返回紧凑摘要（`{ip, open_ports:[{port,service,version}]}` 截断 500 字符）
- [x] 1.4 实现 `run_nuclei`：调 `NucleiService.scan()`，每条发现经 `CveEnricher` 补 CVSS 后 `findings.add()`，返回 `{findings:[{title,severity,cve,cvss}]}` 摘要
- [x] 1.5 实现 `run_subfinder`：调 `SubfinderService.run()`，逐条 upsert 资产（type=url），返回 `{count, sample:[…]}`
- [x] 1.6 实现 `run_httpx`：调 `HttpxService.run()`，按 host upsert 并合并 `toMetadata()`，返回存活数 + 技术栈抽样
- [x] 1.7 实现 `run_ffuf`：调 `FfufService.run()`，发现路径追加到对应资产 metadata 的 `crawled_urls`，返回命中数
- [x] 1.8 实现 `run_sqlmap`：调 `SqlmapService.scan()`（用 1.9 修好的版本），每条注入点 `findings.add()`，返回摘要
- [x] 1.9 实现 `run_msf_module`：读全局 LHOST/LPORT（3.x）拼 options，调 `MsfRpcService.executeModule()`，3 秒后轮询 `listSessions()`，发现新会话则把对应 Finding 标为已利用
- [x] 1.10 实现 `query_threat_intel`：读 `ThreatIntelRepository`，按关键词过滤返回 `{count, top:[{cve,cvss,is_kev}]}`
- [x] 1.11 实现 `get_session_findings`：读 `controller.findingList`，返回全部 Finding 的 `toJson()` 列表（截断 500 字符）
- [x] 1.12 统一工具名分发（`switch`），未知工具名返回 `AgentToolOutcome.failure('未知工具: $name')`
- [x] 1.13 替换 `security_agent_view.dart` 里的假 executor：`executeTool: (name, args) => SecurityAgentExecutor(controller).call(name, args)`，删掉只 log 的占位实现
- [x] 1.14 单测：注入假 controller（内存库）验证 `run_nmap` 的资产 upsert 与时间线写入；验证无会话守卫不写库；验证未知工具名返回 failure

## 2. sqlmap 与 ffuf 的数据来源修复

- [x] 2.1 `SqlmapService.scan` 改为跑完后在 output-dir 下递归查找 `.json` 文件，按本次启动后的 mtime 过滤
- [x] 2.2 解析结果文件：提取 `parameter` / `place` / `title` / `dbms`，构造 `SqlmapFinding` 时即确定 dbms（修掉 `findings.last` 贴错）
- [x] 2.3 结构化解析失败时回退现有 stdout 正则逻辑，并在 `onLog` 输出"结果文件解析失败，回退 stdout"字样
- [x] 2.4 单测：构造临时目录 + 假 result.json，验证字段提取与 DBMS 归属；构造空目录验证回退路径被触发
- [x] 2.5 `FfufService` 新增字典路径解析：依次查找 `/opt/homebrew/share/seclists`、`/usr/local/share/seclists`，均无则 `onLog` 明确提示并返回空列表（不让 ffuf 带空路径启动）
- [x] 2.6 单测：验证默认字典路径按传入前缀列表查找（注入前缀参数）；验证两处都无时返回空且日志含"未找到默认字典"

## 3. Shodan 链路贯通

- [x] 3.1 在 `IntelSettingsStore` 同文件新增 `SecuritySettingsStore`（或扩展该类）：`shodan_api_key` 读写 + `exploit_lhost` / `exploit_lport` 读写，均走 `SettingsStore.readToolConfig/writeToolConfig`
- [x] 3.2 新增 `ExploitDefaultsStore`：`load()` 返回 `ExploitDefaults`（缺省时用 `NetworkInterfaceDetector` 探测本机 IP + 4444）、`save(lhost, lport)`
- [x] 3.3 Shodan Key 读取方法 + 脱敏展示helper（`maskKey`，仅留末 4 位）
- [x] 3.4 利用 Tab 新增"全局利用参数"卡片：LHOST / LPORT 两个输入框 + 保存按钮，保存后即时生效于 `_execute()` 的 options
- [x] 3.5 `exploit_view.dart` 的 `_execute()` 改为读 `ExploitDefaultsStore.load()`，删除用 `_config.host/_config.port` 顶替的写法
- [x] 3.6 LAN 侦察 `lan_recon_view.dart` 设备列表行与 Web 侦察 `web_recon_view.dart` 资产列表行各加一个"外部情报"图标按钮：已配 Key 且有 IP 时调 `ShodanService.queryIp()`，成功后 `mergeShodan()` 合并进该资产 metadata 并刷新
- [x] 3.7 未配 Key → 弹出引导对话框（含 Key 输入框，保存后立即重试查询）；未装 shodan CLI → snackbar 提示去工具依赖面板
- [x] 3.8 Web 侦察面板顶部新增"Shodan API Key"配置入口（与 LAN 侧共用同一 store）
- [x] 3.9 单测：`maskKey` 各类输入（空串 / 短串 / 正常 key）；`ExploitDefaultsStore` 缺省值的 lhost 探测；ffuf 字典前缀注入（已在 2.6）

## 4. 情报 Finding 一键落库

- [x] 4.1 `FindingRepository.add` 增加去重查询辅助：`existsFor(sessionId, assetId, cveId)`
- [x] 4.2 `threat_intel_view.dart` 在命中 banner 上加"生成 Finding"按钮：逐条 `findings.add(source: intel_match, status: open, severity: entry.severity, cvssScore: entry.cvssScore, cveId, title: '情报匹配: <cveId>', assetId)`
- [x] 4.3 单次点击上限 50 条，超出时 snackbar 提示且只创建前 50 条
- [x] 4.4 去重：已存在 `(session, asset, cve)` 组合时跳过并在完成后 toast 报告"新建 X 条，跳过 Y 条已存在"
- [x] 4.5 创建后刷新 `controller.reloadSessionData()` + `recordEvent(finding_update)`，banner 切换为"已生成 N 条情报 Finding"
- [x] 4.6 `IntelDigestScheduler.generate` 注入改为写文件 `AppPaths.securityDir/news_digests.json`（列表，保留最近 7 天），情报面板新增日报列表（时间 + 摘要首行，点击展开）
- [x] 4.7 `threat_intel_view.dart` 的"AI 日报"按钮改为：生成后同时落列表并展示
- [x] 4.8 单测：去重逻辑（同一命中两次点击只建一条）；50 条上限；digest 列表读写与 7 天裁剪

## 5. 验证与部署

- [x] 5.1 `flutter analyze lib/ test/` 零 error（与改动前 info/warning 集合一致）
- [x] 5.2 运行 `test/security_toolbox_test.dart`、`test/security_parsing_test.dart`、`test/security_toolchain_e2e_test.dart` 全绿
- [x] 5.3 新增测试全绿（1.14 / 2.4 / 2.6 / 3.9 / 4.8）
- [x] 5.4 全量 `flutter test`，确认失败集合与改动前逐字相同（已知 13 个 notebook/table 既有失败）
- [x] 5.5 更新 `docs/security_toolbox.md`：补 Agent 真实执行、Shodan 配置、全局 LHOST 三节
- [x] 5.6 执行 `./scripts/deploy_local.sh` 完整部署（含 clean + strict 签名校验 + AOT 哈希比对）
- [x] 5.7 部署后从终端启动采样 stderr，确认无未捕获异常、无黑屏
