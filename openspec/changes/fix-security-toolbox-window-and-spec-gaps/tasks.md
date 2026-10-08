## 1. 独立窗口生命周期与启动路由

- [x] 1.1 在 `lib/main.dart` 中为 `WindowKind` 枚举新增 `securityToolbox`
- [x] 1.2 在 `WindowServices.required` 中配置 `WindowKind.securityToolbox` 的必需服务清单（`AppPaths`、`SettingsStore`、`ProxySettings`、`AiConfigStore`）
- [x] 1.3 在 `lib/main.dart` 中定义 `_SecurityToolboxWindowApp`（包含主题、多语言、macOS 红绿灯避让 padding 与 `SecurityToolboxMainPage`）
- [x] 1.4 在 `lib/main.dart` 的 `main(List<String> args)` 中添加 `isSubWindow && subWindowArgument == 'security-toolbox'` 分发分支，设置窗口尺寸为 1300×850
- [x] 1.5 更新 `test/window_service_initialization_test.dart`，添加针对 `WindowKind.securityToolbox` 的必需服务断言测试

## 2. 输入控制器稳定性与内存管理

- [x] 2.1 重构 `lib/tools/security_toolbox/ui/lan_recon_view.dart` 中的网段输入框，改由 State 持有 `_targetController` 并在 `dispose()` 中释放，修复光标跳动与泄漏
- [x] 2.2 重构 `lib/tools/security_toolbox/ui/script_generator_view.dart` 中的脚本编辑器，改由 State 持有 `_codeController` 并在 `dispose()` 中释放，修复输入重置
- [x] 2.3 重构 `lib/tools/security_toolbox/ui/exploit_view.dart` 中的 ExploitDB 检索输入框，为其绑定真实 State 持有的 `_pocSearchController`，修复检索按钮传入空参的 Bug

## 3. 资产指纹无损合并与手动标注

- [x] 3.1 优化 `lib/tools/security_toolbox/services/lan_recon_services.dart` 中的 `ScannedHost.toMetadata()`，仅输出非空的 `mac` 与 `vendor` 键
- [x] 3.2 优化 `lib/tools/security_toolbox/services/security_repositories.dart` 的 `AssetRepository.upsert`，合并时排除 null 值覆盖，防止 ARP 阶段硬件信息丢失
- [x] 3.3 在 `lan_recon_view.dart` 与 `web_recon_view.dart` 的资产列表中增加备注编辑对话框，并调用 `AssetRepository.setUserNote` 写入持久化

## 4. 漏洞利用 AI 推荐与双层报告增强

- [x] 4.1 在 `vuln_scan_view.dart` 漏洞条目操作菜单中添加“AI 推荐利用方案”动作，根据漏洞详情调用 `askAi` 生成 Metasploit 模块建议
- [x] 4.2 在 `exploit_view.dart` 中接收或支持填充目标 `RHOSTS`，并在执行模块时将其作为参数传入 `MsfRpcService.executeModule`
- [x] 4.3 在 `report_view.dart` 中增加“执行摘要”与“技术报告”双层格式即时切换组件
- [x] 4.4 在 `report_view.dart` 中支持点击历史版本标签回显该版本的报告内容

## 5. 验证与回归测试

- [x] 5.1 运行全量安全工具与窗口服务初始化单测，确认全部通过
- [x] 5.2 执行 `flutter analyze` 确保代码规范无告警
