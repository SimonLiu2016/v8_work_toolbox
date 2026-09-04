## 1. 用户主动触发瘦身扫描改造

- [x] 1.1 在 `lib/tools/slimmer/smart_disk_slimmer_page.dart` 中移除 `initState` 的自动扫描，仅保留毫秒级容量查询 `_loadDiskSpace()`
- [x] 1.2 在 `SmartDiskSlimmerPage` 中设计并实现就绪待扫态卡片（大号「🚀 开始全盘智能分析」按钮、安全废纸篓与 AI 诊断特性介绍）
- [x] 1.3 完善就绪态、扫描中、扫描完成三态流畅切换体验

## 2. 工作区外壳懒加载优化

- [x] 2.1 在 `lib/shell/app_shell.dart` 中引入 `_activatedToolIndices` 激活集合，改造 `IndexedStack` 仅对用户访问过的工具进行真实组件挂载与状态保持

## 3. 验证与构建

- [x] 3.1 运行 `flutter test` 确保所有 11 项单元测试通过
- [x] 3.2 运行 `flutter analyze --no-fatal-infos` 保证 0 错误 0 告警
- [x] 3.3 运行 `flutter build macos` 编译生成最新 Release 应用包并验证秒开体验
