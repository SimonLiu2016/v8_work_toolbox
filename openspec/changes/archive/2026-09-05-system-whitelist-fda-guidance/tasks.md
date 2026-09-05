## 1. 静态分析 Warning 清除与代码健康

- [x] 1.1 在 `lib/tools/slimmer/ai_disk_diagnostics_service.dart` 中移除未引用的私有函数 `_parseJsonArray`，确保静态分析无 warning

## 2. 系统服务与 CLI 开发者工具豁免白名单

- [x] 2.1 在 `lib/tools/slimmer/app_orphan_detector.dart` 中增加 `_systemProtectedNames` 系统服务保护白名单，跳过 `AddressBook`, `GeoServices`, `CoreTelephony` 等系统目录
- [x] 2.2 在 `lib/tools/slimmer/app_orphan_detector.dart` 中增加 `_developerCliProtectedNames` 开发者工具保护白名单，跳过 `Homebrew`, `rtk`, `claude-cli-nodejs`, `mysql`, `Docker Desktop` 等目录

## 3. FDA 权限感知与 AI 导航引导

- [x] 3.1 在 `lib/tools/slimmer/disk_scanner_service.dart` 中感知完全磁盘访问权限 (FDA) 受限异常
- [x] 3.2 在 `lib/tools/slimmer/smart_disk_slimmer_page.dart` 中展示 FDA 提示横幅并支持一键打开 macOS 隐私设置
- [x] 3.3 在 `SmartDiskSlimmerPage` 中针对未配置 AI 供应商的情形增加友好弹窗并引导跳转至 AI 配置页

## 4. 验证与构建

- [x] 4.1 运行 `flutter test` 保证全套测试通过（更新 verify 测试确保 AddressBook/Homebrew 等不再报高风险）
- [x] 4.2 运行 `flutter analyze --no-fatal-infos` 达到 0 错误 0 告警 (exit code 0)
- [x] 4.3 运行 `flutter build macos` 成功编译生成最新 Release 应用
