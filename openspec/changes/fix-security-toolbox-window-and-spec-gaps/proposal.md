## Why

用户点击"安全工具"菜单时，应用没有弹出安全工具箱独立窗口，而是递归弹出了一个完整的主应用窗体（`V8WorkToolboxApp`）。经排查，根因在于 `lib/main.dart` 遗漏了 `security-toolbox` 的独立窗口路由分支与 `WindowKind` 服务声明。同时，代码审计发现安全工具箱在多处 UI 输入控制器、数据合并、AI Exploit 推荐与双层报告预览上存在显著偏差与缺陷，需系统性统一修复。

## What Changes

- **修复独立窗口生命周期与路由**：在 `lib/main.dart` 中新增 `WindowKind.securityToolbox`，在 `WindowServices.required` 注册必需的基础服务（`AppPaths`、`SettingsStore`、`ProxySettings`、`AiConfigStore`），在 `main(args)` 中捕获 `subWindowArgument == 'security-toolbox'` 并启动 `_SecurityToolboxWindowApp`，并同步更新 `window_service_initialization_test.dart`。
- **修复 UI 控制器生命周期与内存泄漏**：将 `LanReconView` 目标网段、`ScriptGeneratorView` 脚本内容、`ExploitView` PoC 检索框的 `TextEditingController` 提升至 State 生命周期管理，并在 `dispose` 中清理，彻底解决输入时光标跳动、代码输入被重置与内存泄漏问题；修复 PoC 检索按钮传空参的问题。
- **修复资产 Metadata 覆盖缺陷**：在 `lan_recon_services.dart` 与 `AssetRepository.upsert` 中仅合并非空键值，防止第 2 阶段 nmap 扫描将第 1 阶段 ARP 扫描发现的 `mac` 与 `vendor` 冲刷为 `null`。
- **补齐 AI 辅助 Exploit 推荐**：在漏洞发现物（Finding）菜单中加入"推荐利用方案"动作，自动提取目标与 CVE 并调用 AI 推荐匹配的 Metasploit 模块；在 `_execute` 中将目标 `RHOSTS` 正确注入模块参数。
- **补齐双层报告格式与历史预览**：在 `ReportView` 中支持"执行摘要"与"技术报告"双层格式的即时切换；点击历史版本标签时支持动态加载该版本报告内容。
- **补齐资产手动标注 UI**：在 `LanReconView` 与 `WebReconView` 的资产列表项中提供备注（`userNote`）编辑对话框，并持久化到数据库。

## Capabilities

### New Capabilities

（无，全部为对现有安全能力的修复与缺口补齐）

### Modified Capabilities

- `security/session-manager`: 独立窗口路由与生命周期分发、资产手动备注（userNote）的 UI 交互与持久化
- `security/lan-recon`: 修复输入框 Controller 稳定性与生命周期；防止深度扫描覆盖 ARP MAC/厂商元数据
- `security/exploit-manager`: 接入 AI Exploit 推荐并携带 RHOSTS；修复 ExploitDB 检索空参问题
- `security/pentest-report`: 支持执行摘要与技术报告双层格式无缝切换；支持历史版本查看与回显
- `security/script-generator`: 修复代码编辑器 Controller 重建引起的光标与输入异常

## Impact

- `lib/main.dart`: 新增 `WindowKind.securityToolbox`、必需服务清单与 `_SecurityToolboxWindowApp`。
- `test/window_service_initialization_test.dart`: 覆盖新窗口类型的服务初始化断言。
- `lib/tools/security_toolbox/ui/`: `lan_recon_view.dart`、`script_generator_view.dart`、`exploit_view.dart`、`vuln_scan_view.dart`、`report_view.dart`、`web_recon_view.dart` 等界面。
- `lib/tools/security_toolbox/services/`: 补齐 AI 利用方案推荐及安全元数据合并。
