## 1. 数据模型与底层系统服务

- [x] 1.1 在 `lib/tools/slimmer/slimmer_models.dart` 中扩展 `SlimmerCategory` 枚举，新增 `dailyAppCache`（日常应用缓存）、`largeFiles`（超大文件排行）与 `installers`（废弃安装包）
- [x] 1.2 在 `lib/services/system_service.dart` 中新增 `emptyTrash()` 方法，底层通过 AppleScript `tell application "Finder" to empty trash` 执行清空并进行物理存在性后置验证
- [x] 1.3 在 `lib/services/system_service.dart` 中新增 `revealInFinder(String path)` 方法，用于在 macOS 访达中高亮选定目标文件或文件夹

## 2. 扫描器流水线与规则实现

- [x] 2.1 在 `DiskScannerService` 中新增废纸篓统计：快速计算 `~/.Trash`（及可读外置卷）的总字节数与条目数
- [x] 2.2 实现活跃日常应用缓存与系统日志扫描：复用已安装应用索引，遍历 `~/Library/Caches` 及沙盒目录匹配活跃应用（提取本地化中文名），并扫描 `~/Library/Logs`
- [x] 2.3 扩展安装包扫描器：遍历 `~/Downloads`、`~/Desktop`、`~/Documents` 下的 `.dmg`, `.pkg`, `.iso` 文件，依据修改时间区分推荐勾选（>7天默认勾选，<=7天默认不勾选）
- [x] 2.4 实现超大单体文件发现扫描器：通过 macOS `mdfind` 高性能元数据检索用户目录下 `>100MB` 的非 `.app` 且非 `.git` 内部对象单体文件，并按体积降序排列，默认不勾选

## 3. 界面呈现与交互优化

- [x] 3.1 在 `SmartDiskSlimmerPage` 顶部区域新增废纸篓独立卡片，包含实时体积展示与“清空废纸篓”危险操作按钮
- [x] 3.2 实现清空废纸篓二次防呆确认弹窗，明确展示待永久清空的项数、体积及不可撤销风险提示
- [x] 3.3 升级顶部 Filter Chips 分类筛选栏，增加「日常应用与系统」、「废弃安装包」、「超大文件排行」独立选项与体积汇总
- [x] 3.4 为大文件排行榜与安装包条目增加「在访达中显示」快捷按钮，支持一键定位文件

## 4. 自动化测试与回归验证

- [x] 4.1 编写废纸篓统计与清空逻辑的单元测试
- [x] 4.2 编写活跃应用缓存动态匹配与系统日志发现测试，验证敏感即时通讯工具默认不勾选与浏览器缓存默认勾选策略
- [x] 4.3 编写安装包天数过滤与大文件检索结果解析与排序测试
- [x] 4.4 运行瘦身全量测试套件，确保已有编译缓存、多版本、项目构建产物等功能零回归
