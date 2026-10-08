# 提案：Nuclei 扫描实时进度可观测性与发现物目标归属优化

## Why

用户在「漏洞扫描」模块中使用 Nuclei 时反馈两个体验痛点：
1. **多目标扫描结果缺乏归属标识**：当多个子域名开放相同服务（如 SSH 22 端口）时，漏洞列表中堆叠多个完全相同的条目（例如 7 条一模一样的 `OpenSSH Service - Detect`），由于没有标注触发的具体目标 Host/URL，导致用户误以为是目标重复或系统异常；且由于 `host:port` 格式的解析缺陷导致未能正确关联到 `assetId`；
2. **重型扫描缺乏可观测性（如同假死）**：当加载数千个模板扫描多个目标时，预计发送数万次网络请求，耗时达 10~15 分钟，但 Nuclei 默认在运行期间完全静默，导致在输出启动信息后十几分钟毫无任何控制台反馈。

## What Changes

- **开启 Nuclei 周期性统计流（实时进度汇报）**：在 `NucleiService.scan` 命令行中启用 `-stats` 与 `-si 5`（或合适周期），在后台捕获统计 JSON 并格式化为直观的进度日志（如 `[进度] 25% | 请求: 1200/4800 (95 req/s) | 发现: 1 | 耗时: 00:15`），让长时间扫描始终具备动态反馈。
- **完善 Host:Port 资产匹配机制**：强化 `matchedAt` 解析逻辑，兼容带有端口的 TCP/HTTP 目标（如 `www.v8en.com:22`），剥离端口精准命中资产库，确保漏洞 100% 绑定 `assetId`。
- **重构漏洞发现物列表展示**：在「漏洞发现」列表项中显式标注触发的具体目标资产（如域名与端口），并在副标题中呈现命中的端点信息，消除重复项混淆。
- **增加漏洞严重度（Severity）过滤支持**：支持用户按危险级别（Critical / High / Medium / Low / Info）过滤扫描模板或默认排除大量无害的 Info 级别嗅探规则，大幅降低模板总数与扫描耗时。

## Capabilities

### New Capabilities
- `security/nuclei-progress-and-attribution`: 涵盖 Nuclei 周期性统计流捕获与可视化、Host:Port 目标资产精准映射、以及漏洞列表目标归属显式渲染。

### Modified Capabilities
<!-- 无既有 spec 需求变更 -->

## Impact

- `lib/tools/security_toolbox/services/vuln_scan_services.dart`: 增加 `-stats`、`-si 5` 与可选严重度过滤参数，支持解析统计 JSON 并输出进度日志。
- `lib/tools/security_toolbox/ui/vuln_scan_view.dart`: 修复资产 `matchedAt` 端口剥离，增强 `_buildFindingList` 渲染目标标签，增加严重度过滤器交互。
