## 1. 工具元数据与安装渠道扩展

- [x] 1.1 在 `lib/tools/security_toolbox/services/security_tool_registry.dart` 中新增 `InstallMethod` 枚举（brew, pipx, manual）与耗时标记属性
- [x] 1.2 将 `netexec` 配置为 `pipx` 渠道，将 `metasploit` 配置为 `manual` 渠道，并将编译型工具（`httpx`, `ffuf`, `searchsploit`）标记提示信息

## 2. 安装执行服务与子进程加固

- [x] 2.1 在 `lib/tools/security_toolbox/services/brew_install_service.dart` 的 `install` 中为子进程立即关闭 stdin（`process.stdin.close()`）以防交互挂起
- [x] 2.2 在 `brew_install_service.dart` 中支持 `pipx` 安装渠道（探测 pipx 并执行 `pipx install <pkg>`）
- [x] 2.3 提取错误关键行（如 Lock timeout、No available formula、Disabled 等）并打印诊断日志
- [x] 2.4 重构 `installAllMissing` 的总结日志，将成功与失败数量清晰拆分呈现（杜绝“成功安装 0/9 个”误解），跳过 manual 渠道工具并在批量开始时列出清单

## 3. UI 交互与手动引导支持

- [x] 3.1 在 `lib/tools/security_toolbox/ui/tool_status_panel.dart` 中针对 `manual` 工具（Metasploit）展示“查看安装指引”弹窗或外链，不展示无效的 brew 安装按钮
- [x] 3.2 针对编译型或长耗时工具，在点击安装后展示提示气泡或在控制台打印耗时预估

## 4. 验证与本地部署

- [x] 4.1 运行单元测试集 `flutter test test/security*` 确保无回归
- [x] 4.2 执行 `flutter analyze lib/tools/security_toolbox/` 确保零告警
- [x] 4.3 执行 `./scripts/deploy_local.sh` 编译并热替换本地 `/Applications/V8WorkToolbox.app`
