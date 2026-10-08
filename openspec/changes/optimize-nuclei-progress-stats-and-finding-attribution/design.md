## Context

用户在执行 Nuclei 漏洞扫描时遇到两类核心痛点：
1. 目标下多个子域名的同名探测项（如 `OpenSSH Service - Detect`）在前端列表中没有标注具体属于哪个目标，表现为 7 条一模一样的条目，且数据库内 `asset_id` 因解析 `host:22` 时缺失端口切分而落空；
2. 扫描大规模模板（如 7,741 个）时需要发送数万个请求，耗时十几分钟，但 Nuclei 默认期间完全静默，导致用户误认为系统卡死。

## Goals / Non-Goals

**Goals:**
- 在 `NucleiService.scan` 引入 `-stats` 与 `-si 5`，捕获周期统计 JSON，输出结构化友好的 `[进度]` 日志，并更新进度回调；
- 完善 `cleanHostForMatching(String raw)`，剥除 `https://`、`http://` 与 `:port`，确保 `www.v8en.com:22` 等网络端口发现精准匹配到 `sessionAssets`；
- 在 `VulnScanView` 的 `_buildFindingList` 中显式渲染目标标签（如 `www.v8en.com:22`），并在副标题中展现，彻底消除视觉重复混淆；
- 在 `VulnScanView` 增加 Severity 等级筛选支持（默认聚焦有效漏洞如 `critical, high, medium`，可选 `low, info`），并传给 Nuclei `-s` 参数，将模板量按需收敛 50%~80%。

**Non-Goals:**
- 不改变 Nuclei 的底层扫描逻辑与并发网络通信模型；
- 不变更现有的数据库表结构定义。

## Decisions

### 1. Stats JSON 监听与友好的文本日志转换
- **决策**：在 stdout 流监听中判断 JSON 格式：
  - 若包含 `duration`、`percent`、`requests` 等字段，说明为统计帧：
    - 组装格式为：`[扫描进度] ${percent}% | 已发请求: ${requests}/${total} (${rps} req/s) | 发现脆弱项: ${matched} | 耗时: ${duration}`；
    - 派发至 `onLog` 写入控制台日志；
    - 调用 `onProgress?.call(parsedRequests, parsedTotal)` 更新进度；
  - 若为 `NucleiFinding` JSON，则正常入库并上报发现；
  - 其余标准字符串（`[INF]` 等）原样输出。
- **理由**：既不污染控制台原始信息，又能彻底解决长达 15 分钟“无字天书”的假死感。

### 2. 健壮的主机名提取
- **决策**：创建静态辅助方法 `extractHost(String addressOrUrl)`：
  ```dart
  static String extractHost(String input) {
    var raw = input.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Uri.tryParse(raw)?.host ?? raw;
    }
    if (raw.contains(':')) {
      raw = raw.split(':').first;
    }
    return raw;
  }
  ```
- **理由**：彻底解决 Dart `Uri.tryParse('host:22')?.host == ""` 的问题，确保无论 TCP 还是 HTTP 发现物都能精准关联合法资产。

### 3. UI 列表增加目标小标签与副标题明细
- **决策**：在 `ListTile` 的标题行增加一个等宽浅色 Chip 标注该项所属目标（如 `www.v8en.com:22`），副标题中明确写出具体端点与 CVE 编号。

### 4. Severity 等级筛选
- **决策**：在 `NucleiCategory` 旁边增加 `Severity` 多选 FilterChips（默认选中 `高危`、`严重`、`中危`，可选勾选 `低危`、`信息`），在 `buildArgs` 中支持生成 `-s critical,high,medium`。

## Risks / Trade-offs

- **[Risk]** 每 5 秒输出一条进度可能使控制台日志行数增加较快。
  → **Mitigation**: 周期定为 5 秒，15 分钟扫描大约产生 180 行进度日志，完全在 Controller 500 行的缓冲区容纳范围内，且有「清空」和尾部滑动窗口保障流畅度。
