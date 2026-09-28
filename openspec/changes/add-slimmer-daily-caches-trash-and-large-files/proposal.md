## Why

当前「智能磁盘瘦身」工具主要聚焦在开发者专属的编译构建缓存（Xcode DerivedData、Gradle、CocoaPods）与本地代码工程产物（node_modules、build、target 等），而完全缺失了 macOS 用户高频消费的「系统废纸篓」、「日常应用运行缓存与系统日志」（如 Chrome、QQ音乐、系统日志等）以及「废弃安装包」与「超大单体文件发现」能力。这使得用户在日常系统清理和定位大文件时不得不依赖第三方清理软件（如腾讯柠檬清理），无法在 V8 工具箱内形成闭环。

## What Changes

- **新增系统废纸篓检测与清空**：
  - 毫秒级探测 `~/.Trash`（及外部卷废纸篓）的项数与体积大小；
  - 提供醒目的废纸篓卡片展示，支持通过系统原生 AppleScript 执行不可逆清空，并具备强制二次确认弹窗防护。
- **新增日常应用缓存与系统日志探测**：
  - 动态扫描 `~/Library/Caches` 及沙盒容器 `~/Library/Containers/*/Data/Library/Caches`，智能匹配已安装的应用（如 Chrome、QQ音乐、微信、钉钉等）并提取本地化应用名称；
  - 扫描用户级系统日志 `~/Library/Logs`；
  - 确立安全勾选分级：通用浏览器与媒体缓存默认勾选，敏感聊天工具缓存默认不勾选。
- **强化废弃安装包扫描**：
  - 跨越 `~/Downloads`、`~/Desktop`、`~/Documents` 定向探测 `.dmg`、`.pkg`、`.iso` 等安装包；
  - 依据下载修改天数（如 >7 天）进行推荐勾选，并提供快捷在 Finder 中定位的能力。
- **新增超大单体文件发现排行榜**：
  - 基于 macOS Spotlight 元数据索引（`mdfind`）毫秒级检索 `>100MB` 的非应用程序大文件（视频、虚拟盘镜像、压缩包、大表格等）；
  - 结果按文件体积从大到小严格排序，默认不勾选（防误删资产），支持一键“在 Finder 中定位”。
- **UI 分类与筛选栏升级**：
  - 在顶部 Filter Chips 中新增「日常应用与系统」、「废弃安装包」、「超大文件发现」独立分类标签与汇总指标。

## Capabilities

### New Capabilities
（无全新独立 capability，统一集成至 `disk-analyzer`）

### Modified Capabilities
- `disk-analyzer`: 扩展扫描管线与分类模型，增加系统废纸篓、日常活跃应用缓存、废弃安装包多目录扫描及超大单体文件发现。

## Impact

- **核心服务层**：`lib/tools/slimmer/disk_scanner_service.dart`（新增阶段或扫描器方法）、`lib/tools/slimmer/slimmer_models.dart`（新增分类枚举与文件元数据扩展）。
- **系统能力层**：`lib/services/system_service.dart`（新增清空废纸篓方法与在 Finder 中显示路径方法）。
- **界面展现层**：`lib/tools/slimmer/smart_disk_slimmer_page.dart`（废纸篓顶部卡片、新增分类 Chip、大文件排行榜展示与操作项）。
- **测试用例**：新增与更新对应的自动化单元测试与模拟扫描测试。
