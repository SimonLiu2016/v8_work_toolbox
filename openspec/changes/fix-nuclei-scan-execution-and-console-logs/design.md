## Context

Nuclei 是安全工具箱核心漏洞扫描引擎。当前存在三项核心问题：
1. `NucleiCategory` 的 key 在 Nuclei v3+ 模板库中找不到对应顶级目录，`-t <key>` 导致 Nuclei 启动即 fatal 崩溃；
2. `-silent` 抑制了 Nuclei 所有的 `[INF]` 状态信息与进度；
3. `LogConsole` 渲染时使用 `controller.logs.take(60)`，切片取的是最早历史数据，导致新增日志完全被隐藏。

## Goals / Non-Goals

**Goals:**
- 将 `NucleiCategory` 映射转换为可靠的 Nuclei 命令行 Tags（支持 cve, exposure, misconfig, default-login, network, tech），使 Nuclei 能正确识别并执行；
- 开放 Nuclei 运行状态输出（移除 `-silent`，保留 `-jsonl -no-color`），通过 stdout/stderr 实时流式分发状态行并保留 JSON Finding 解析能力；
- 修复 `controller.logs` 在各 View 控制台中的切片策略（采用滑动窗口展示最新的日志尾部）；
- 升级 `LogConsole`，增加自动滚动到最新行与一键清空日志能力。

**Non-Goals:**
- 不重构 Nuclei 自定义模板编辑与上传系统（保持使用本地已安装的官方模板库）；
- 不改动既有 `PentestFinding` 数据库表结构与入库逻辑。

## Decisions

### 1. 分类映射策略：优先采用 `-tags` 过滤
- **决策**：
  - `cves` $\rightarrow$ tag `cve`
  - `exposures` $\rightarrow$ tag `exposure`
  - `misconfiguration` $\rightarrow$ tag `misconfig`
  - `defaultLogins` $\rightarrow$ tag `default-login`
  - `network` $\rightarrow$ tag `network`（同时兼容 `-t network`）
  - `technologies` $\rightarrow$ tag `tech`
- **理由**：Nuclei 模板在 v3+ 之后全面使用 metadata tags，`-tags` 可以跨协议（http、network、ssl、dns 等）统一过滤对应类型的模板，避免因目录结构变动导致找不到模板。
- **备选方案**：拼接具体子路径（如 `http/cves`）。缺点是局域网扫描（IP/端口）时会丢失 `network/` 下对应的模板。使用 tag 则可全量覆盖。

### 2. 输出流与解析机制解耦
- **决策**：移除 `-silent`，在 stdout 行监听器中做模式分离：
  - 以 `{` 开头且能被解析为 JSON 的行 $\rightarrow$ 派发给 `onFinding` 并上报进度；
  - 非 JSON 行（如 `[INF] Templates loaded: ...`、`[INF] Targets loaded: ...`） $\rightarrow$ 派发给 `onLog` 写入控制台。
  - stderr 出现内容直接写入 `onLog`，并在退出码非零时明确提示。
- **理由**：既保证了实时交互性与可视化反馈，又不影响漏洞 Finding 的结构化提取。

### 3. 日志窗口获取：在 Controller 中提供 `recentLogs`
- **决策**：在 `SecuritySessionController` 提供 `List<String> recentLogs([int count = 100])`，各 Tab 统一改调 `controller.recentLogs(100)`；同时在 `LogConsole` 挂载 `ScrollController`，在日志更新时若处于底部附近则自动滚底。
- **理由**：彻底解决 `take(60)` 截取旧数据导致的日志停滞假象。

## Risks / Trade-offs

- **[Risk]** 不加 `-silent` 时 stdout 较长会增加字符串切割开销。
  → **Mitigation**: Nuclei 在非 verbose 模式下输出的 `[INF]` 状态行仅有十数条，整体开销微乎其微。
- **[Risk]** 用户未下载或模板库为空。
  → **Mitigation**: 捕获 `[FTL]` 报错并在控制台提示用户前往工具面板更新或下载 Nuclei 模板。
