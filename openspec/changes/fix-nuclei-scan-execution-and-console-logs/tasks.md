## 1. Nuclei 服务参数映射与流式日志改造

- [x] 1.1 为 `NucleiCategory` 增加标准 Tag 映射（`cve`, `exposure`, `misconfig`, `default-login`, `network`, `tech`）
- [x] 1.2 重构 `NucleiService.scan`：使用 `-tags` 代替 `-t`，移除 `-silent`，保留 `-jsonl -no-color`
- [x] 1.3 增强 `NucleiService.scan` 的 stdout/stderr 流监听：将状态信息实时派发至 `onLog`，并在进程异常退出（如 exitCode != 0）时上报明确诊断信息

## 2. Session Controller 与日志切片机制修复

- [x] 2.1 在 `SecuritySessionController` 增加 `recentLogs([int count = 100])` 尾部切片方法
- [x] 2.2 修复 `VulnScanView`、`WebReconView`、`LanReconView` 与 `ToolStatusPanel` 中的 `LogConsole` 参数调用，统一使用 `recentLogs` 代替 `logs.take(...)`

## 3. LogConsole 交互与视觉优化

- [x] 3.1 为 `LogConsole` 添加自动滚动到底部支持（新增内容时自动跟手滚动）
- [x] 3.2 在 `LogConsole` 工具栏添加「清空日志」快捷按钮，支持一键清空当前控制台内容

## 4. 验证与本地应用部署

- [x] 4.1 编写针对 `NucleiCategory` Tag 映射与 `recentLogs` 尾部切片的单元测试
- [x] 4.2 运行 `flutter analyze` 确保代码无静态警告
- [x] 4.3 运行 `flutter test` 确保全量测试通过
- [x] 4.4 执行 `./scripts/deploy_local.sh` 编译并更新本地应用
