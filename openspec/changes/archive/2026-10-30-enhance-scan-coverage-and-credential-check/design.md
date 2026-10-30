## Context

当前 Web 流水线（`SecurityPipelineService.runWebPipeline`）Nuclei 调用只传了三个类别（cves、misconfiguration、exposures），漏掉了 `defaultLogins`。Katana 阶段的爬取结果存入 asset metadata 的 `crawled_urls` 字段但未被后续步骤利用做 sqlmap 测试。`SecurityAgentExecutor._runHydra` 对应的 case 并不存在——`kHighImpactTools` 里有 `run_hydra` 但 executor 的 switch 里没有这个分支，调用会走到 `default` 返回"未知工具"。

## Approach

### A. 补全 Web Nuclei 扫描类别（一行改动）

在 [`security_pipeline_service.dart`](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/security_toolbox/services/security_pipeline_service.dart) 的 `runWebPipeline` Nuclei 调用处，将 `categories` 补齐为：
```dart
categories: [
  NucleiCategory.cves,
  NucleiCategory.misconfiguration,
  NucleiCategory.exposures,
  NucleiCategory.defaultLogins,  // 补充
],
```

### B. Katana 端点 → sqlmap 自动衔接

在 `runWebPipeline` Katana 阶段结束（L147 之后）新增一个衔接步骤：

```
1. 从 controller.assetList 中取出所有 asset
2. 提取 metadata['crawled_urls'] 列表
3. 过滤出含查询参数的 URL（用 hasQueryParameters() 函数，web_recon_services 里已有）
4. 取前 10 条（防止扫描时间过长）
5. 调用 SqlmapService.scan(urls)，onFinding 写库
```

`SqlmapService` 已在 `vuln_scan_services.dart` 中实现，直接复用。`hasQueryParameters` 函数已在 `web_recon_services.dart` 中有导出。

### C. HydraService 新增与 AgentExecutor 接入

**新增 `lib/tools/security_toolbox/services/hydra_service.dart`**：

```
HydraFinding { target, port, service, username, password }

HydraService.scan({
  required String target,
  required String service,   // ssh / ftp / http-get
  int port,
  Duration timeout = 60s,
  void Function(HydraFinding) onFinding,
  void Function(String) onLog,
})
→ 调用 hydra -L <userlist> -P <passlist> -t 4 <target> <service>
→ 解析 stdout "[22][ssh] host: ... login: ... password: ..."
→ 通过 onFinding 回调
```

内置用户名列表（≤20条）：`root, admin, administrator, user, ubuntu, test, guest, oracle, postgres, ftp`

内置密码列表（≤50条）：`123456, password, admin, root, 12345678, 1234, 111111, 123456789, qwerty, abc123, ...`（常见 OWASP Top 弱密码）

**在 `SecurityAgentExecutor` 的 switch 新增 `case 'run_hydra'`**：
```dart
case 'run_hydra': return _runHydra(args);
```

`_runHydra` 提取 `target`、`service`（可选，默认 ssh）、`port`（可选），调用 `HydraService.scan()`，发现物写库，返回截断摘要。

### D. LAN 流水线 nmap 后自动触发 Hydra

在 `runLanPipeline` nmap 阶段完成后（L315 之后），遍历 nmapHosts，筛选开放 22 或 21 端口的主机，对每台主机调用 `HydraService.scan()`，onFinding 写 findings 库（severity: critical）。

## Risks

- **Hydra 未安装**：与其他工具保持一致，调用前用 `resolveExecutable('hydra')` 检查，未安装时打印提示日志并跳过，不中断流水线
- **Sqlmap 衔接时间**：含参数 URL 最多取 10 条，每条默认 sqlmap 超时 60s，最差情况增加 10 分钟。这是可接受的主动探测开销
- **误判成功**：Hydra 的 stdout 解析依赖固定格式（`[port][service] host: ... login: ... password: ...`），该格式是 hydra 的稳定输出，低误判风险
