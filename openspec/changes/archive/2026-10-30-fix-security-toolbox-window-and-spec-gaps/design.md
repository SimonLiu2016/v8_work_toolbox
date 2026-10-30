## Context

本应用采用 `desktop_multi_window` 多进程模型，各个独立子窗口（如笔记本 `notebook`、运维工具 `ops-tool`）启动时均独立执行 `main(args)`。安全工具箱此前虽在 `registry.dart` 声明了 `openInNewWindow => true`，但未在 `lib/main.dart` 注册其专属 `WindowKind` 与参数分支，导致子进程穿透到主程序外壳。此外，界面层若干控制器直接在 `build` 方法中声明导致光标乱跳与泄漏。

## Goals / Non-Goals

**Goals:**
- 将安全工具箱以独立桌面窗口（1300×850）正常启动并加载专用外壳，隔离主界面。
- 重构所有 `build()` 内直接初始化的 `TextEditingController`，修复光标跳动与内存泄漏。
- 修复深度扫描无损元数据合并，确保 ARP 发现的硬件/厂商指纹不丢失。
- 贯通 Finding 详情与 AI Exploit 推荐链路，执行 Metasploit 模块时注入实际 `RHOSTS`。
- 实现渗透报告的双层格式（执行摘要 vs 技术报告）即时切换与历史版本回显。
- 在局域网与 Web 资产列表中增加手动备注（userNote）的查看与编辑弹窗。

**Non-Goals:**
- 不重写 Metasploit RPC 底层协议，不引入新的外部框架依赖。
- 不修改既有 SQLite 数据库 schema（既有表已具备 `userNote` 与所需字段）。

## Decisions

### 1. 窗口启动与服务拓扑

遵循 `_OpsToolWindowApp` 的成熟模式：
- 在 `WindowKind` 中追加 `securityToolbox`。
- 在 `WindowServices.required` 声明：`AppPaths`、`SettingsStore`、`ProxySettings`、`AiConfigStore`。
- 在 `main()` 中截获 `isSubWindow && subWindowArgument == 'security-toolbox'`，设置窗体尺寸 1300×850，启动 `_SecurityToolboxWindowApp`（内含 macOS 红绿灯避让 padding 与多语言支持）。
- 在 `test/window_service_initialization_test.dart` 补齐回归测试。

### 2. 控制器生命周期规范化

- `LanReconView`: `_targetController` 在 `initState` 中初始化，`onChanged` 同步更新 `_target`，`dispose` 中注销；网段快速切换按钮通过 `_targetController.text = ...` 同步更新。
- `ScriptGeneratorView`: `_codeController` 在 State 中持有并统一在 `dispose` 中释放。
- `ExploitView`: 为 PoC 检索框绑定 `_pocSearchController`，修复点击检索按钮传空参的 Bug。

### 3. 元数据无损合并策略

在 `ScannedHost.toMetadata()` 与 `AssetRepository.upsert` 中：
- 序列化指纹时仅保留非空键值：`if (mac != null) 'mac': mac`、`if (vendor != null) 'vendor': vendor`。
- 在 `upsert` 合并时，新 metadata 中的非空字段才覆盖旧字段，避免 nmap 扫描无 root 时将 ARP 识别出的硬件地址抹除。

### 4. 漏洞利用 AI 推荐与参数联动

- 在 `vuln_scan_view.dart` 漏洞条目的更多操作菜单中添加"AI 推荐利用方案"。
- 构造上下文调用 `askAi`，解析出推荐的模块名称与参数，自动携带该漏洞所在资产的 IP/Host 作为 `RHOSTS`，填入 `ExploitView` 提交执行。

### 5. 双层报告与历史预览

- 在 `ReportView` 预览区增加 `SegmentedButton`（执行摘要 / 技术报告）。
- 选择"执行摘要"时只渲染 Overview 与管理层建议；选择"技术报告"时渲染完整 Finding 表格、复现步骤与技术建议。
- 点击历史版本 Chip 时，解析历史 content 并更新当前预览内容。

## Risks / Trade-offs

- [Risk] 子窗口如果漏初始化某个服务，可能导致特定功能静默报错。
  → Mitigation: `WindowServices.required` 清单式拓扑序初始化，且单测必须覆盖该窗口类型的每一个服务断言。
- [Risk] AI 生成的推荐利用方案格式可能偏离预期。
  → Mitigation: 给出明确的 prompt 格式要求（必须包含 JSON 代码块），解析失败时优雅回退为纯文本建议并允许手动填入模块名。
