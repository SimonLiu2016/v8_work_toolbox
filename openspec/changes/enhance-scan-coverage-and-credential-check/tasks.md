## 1. Nuclei Web 扫描类别补全

- [x] 1.1 在 `security_pipeline_service.dart` `runWebPipeline` 的 Nuclei 调用处，在 `categories` 列表中追加 `NucleiCategory.defaultLogins`，使其与 LAN 流水线的类别覆盖对齐

## 2. Katana 端点 → sqlmap 自动衔接

- [x] 2.1 在 `runWebPipeline` Katana 阶段结束后新增"sqlmap 注入探测"阶段：从 `controller.assetList` 提取 `metadata['crawled_urls']`，过滤含查询参数的 URL（复用 `hasQueryParameters()`），取前 10 条
- [x] 2.2 对筛选出的 URL 调用 `SqlmapService.scan()`，`onFinding` 回调将注入发现以 `high` 严重度写入 findings 数据库；阶段进度通过 `agent.addThinking()` 和 `controller.log()` 推送

## 3. HydraService 实现

- [x] 3.1 新建 `lib/tools/security_toolbox/services/hydra_service.dart`，定义 `HydraFinding` 数据类（target, port, service, username, password）和 `HydraService.scan()` 静态方法
- [x] 3.2 `HydraService.scan()` 内置 20 条用户名和 50 条密码的弱口令基线字典，拼装 `hydra` CLI 命令行（`-L <userfile> -P <passfile> -t 4 <target> <service>`），流式解析 stdout 中的命中行（`[port][service] host: ... login: ... password: ...`），通过 `onFinding` 回调返回结果
- [x] 3.3 调用前用 `resolveExecutable('hydra')` 检测安装状态，未安装时打印提示日志并提前返回，不抛出异常

## 4. AgentExecutor 接入 Hydra

- [x] 4.1 在 `security_agent_executor.dart` 的 switch 中新增 `case 'run_hydra'`，调用 `HydraService.scan()`，发现物写入 findings 库，返回 ≤500 字符摘要

## 5. LAN 流水线自动触发 Hydra

- [x] 5.1 在 `security_pipeline_service.dart` `runLanPipeline` nmap 阶段结束后，遍历 `nmapHosts`，筛选开放 22（SSH）或 21（FTP）端口的主机，对每台主机调用 `HydraService.scan()` 并将发现物以 `critical` 写入 findings 数据库
- [x] 5.2 Hydra 阶段进度通过 `agent.addStep()` 和 `agent.addThinking()` 推送到 UI

## 6. 测试与部署

- [x] 6.1 在 `test/security_gaps_test.dart` 新增 HydraService 测试组：验证命令行参数拼装、stdout 解析、未安装时安全返回
- [x] 6.2 运行 `flutter analyze`，确保 No issues found
- [x] 6.3 运行 `flutter test test/security_gaps_test.dart`，全部通过
- [x] 6.4 运行 `./scripts/deploy_local.sh` 完成本地部署
