## 1. 原生废纸篓回收通道

- [x] 1.1 在 `macos/Runner/AppDelegate.swift` 中增加 MethodChannel `recyclePaths` 调用，调用 `NSWorkspace.shared.recycle` 实现 100% 可逆废纸篓回收
- [x] 1.2 在 `lib/services/system_service.dart` 中封装 `recyclePaths(List<String> paths)` 原生调用接口及回退机制

## 2. 磁盘扫描与多版本/残留探测引擎

- [x] 2.1 实现 `lib/tools/slimmer/disk_scanner_service.dart`：支持三阶段渐进式扫描流水线（瞬时重灾区、多版本矩阵、深度孤立残留）
- [x] 2.2 实现 `lib/tools/slimmer/app_orphan_detector.dart`：提取 `/Applications` 已安装 Bundle ID 并交叉比对 `~/Library` 孤立残留
- [x] 2.3 实现 `lib/tools/slimmer/multi_version_scanner.dart`：探测 JetBrains/Android Studio 升级遗留版本与 Python/Node/Java 运行时版本矩阵

## 3. AI 智能研判服务

- [x] 3.1 实现 `lib/tools/slimmer/ai_disk_diagnostics_service.dart`：提取无隐私文件元数据（路径层级、文件数、体积、时间戳），构造批量研判 Prompt 并通过 `AiService` 发送
- [x] 3.2 实现诊断结果解析器与单项「让 AI 深度分析」交互协议

## 4. 瘦身分析器前端界面与工具集成

- [x] 4.1 构建 `lib/tools/slimmer/smart_disk_slimmer_page.dart`：包含磁盘用量概览卡片、分级可清理清单与实时扫描进度展示
- [x] 4.2 实现细分清理项视图卡片（孤立残留、多版本管理、大型归档包、开发构建缓存、AI 智能建议项）
- [x] 4.3 实现单项 AI 深度研判浮窗与批量 AI 分析开关
- [x] 4.4 创建 `SmartDiskSlimmerToolDefinition` 并在 `lib/tools/registry.dart` 中注册，归入「系统与配置」分类

## 5. 验证与测试

- [x] 5.1 编写 `test/disk_slimmer_test.dart`：测试多版本版本号匹配算法、孤立应用比对逻辑与 AI 元数据包装安全性
- [x] 5.2 运行 `flutter analyze --no-fatal-infos` 保持 0 错误 0 告警
- [x] 5.3 运行 `flutter build macos` 成功编译生成新版本应用
