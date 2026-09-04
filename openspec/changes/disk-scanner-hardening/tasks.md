## 1. 异步扫描：消除 UI 卡顿

- [x] 1.1 将 `DiskScannerService._calcDirSize` 改为 `Future<int>` 异步方法，递归遍历中每处理 200 个文件后执行 `await Future(() {})` yield 控制权
- [x] 1.2 将 `MultiVersionScanner._quickDirSize` 改为 `Future<int>` 异步方法，同样加入定期 yield
- [x] 1.3 将 `AppOrphanDetector._measureDirQuick` 改为 `Future<DirStats>` 异步方法，同样加入定期 yield
- [x] 1.4 将 `startScan` 中对 `_scanInstantTargets`、`_versionScanner.scanMultiVersions`、`_orphanDetector.scanOrphans` 的调用适配为异步等待
- [x] 1.5 将 `startScan` 的 Stream yield 从 `List.unmodifiable(allItems)` 改为 `List.of(allItems)`，确保结果列表可修改

## 2. 复选框交互修复

- [x] 2.1 验证 `_items` 在扫描完成后为可修改列表，复选框 `onChanged` 中的 `_items[idx] = item.copyWith(...)` 正常工作
- [x] 2.2 验证 AI 批量诊断后 `_items[idx] = old.copyWith(...)` 正常工作

## 3. JetBrains 条目来源标识

- [x] 3.1 修改 `MultiVersionScanner._scanJetBrains`，根据目录来源（`Application Support` vs `Caches`）在 `title` 中添加"（配置）"或"（缓存）"标识
- [x] 3.2 确保同一产品的配置和缓存条目使用不同的 `id`（当前基于 `path.hashCode` 已天然不同）

## 4. 多层防误判检测

- [x] 4.1 在 `AppOrphanDetector` 中增加 Bundle ID 读取逻辑：遍历 `/Applications/*.app/Contents/Info.plist`，提取 `CFBundleIdentifier`，构建 `_installedBundleIds` 集合
- [x] 4.2 增加内置已知别名映射表 `_knownAliases`（约 30-50 条常见映射，如 `code` → `visual studio code`，`bilibili` → `哔哩哔哩`）
- [x] 4.3 修改名称匹配逻辑：非 bundleId 格式目录依次尝试精确匹配 → 别名映射 → 子串双向匹配（目录名长度 ≥ 4 且匹配占比 > 50%）
- [x] 4.4 修改安全等级逻辑：未匹配目录根据 `lastModified` 降级——7天内 `danger`，30天内 `caution`，90天+ `safe`
- [x] 4.5 将默认安全等级从 `SafetyRating.safe` 改为 `SafetyRating.caution`，未命中任何验证层的目录默认不勾选

## 5. 用户反馈闭环

- [x] 5.1 在 `SlimCandidateItem` 模型中增加 `userMarkedKeep` 字段（或复用 `isSelected` + 持久化逻辑）
- [x] 5.2 在 `SettingsStore` 中增加 `slimmerKeepList` 持久化：记录用户手动取消勾选的条目路径
- [x] 5.3 在扫描结果构建时，检查 `slimmerKeepList`，匹配的条目自动设置为未勾选并显示"用户标记保留"标识
- [x] 5.4 在 `_buildItemTile` 中，对用户标记保留的条目显示额外标识（如小标签"已标记保留"）

## 6. 批量操作与检测精度修复

- [x] 6.1 在顶部操作栏增加"全选"和"取消全选"按钮，作用于当前筛选视图的所有条目
- [x] 6.2 子串匹配归一化：匹配前移除连字符、空格、点号等分隔符后再比较（修复 `v8-video-downloader` → `v8videodownloader` 匹配失败）
- [x] 6.3 `_measureDirQuick` 排除系统元数据文件（`.DS_Store`、`.localized`、`Thumbs.db`、`__MACOSX`），避免其时间戳干扰"最近修改时间"判断（修复 `com.kugou.mac.Music` 误判为高风险）

## 7. 验证与构建

- [x] 7.1 运行 `flutter analyze --no-fatal-infos`：0 error、0 warning（70 条 info：`avoid_print` 与 `package_names`，不阻断）
- [x] 7.2 运行 `flutter build macos` 编译通过（Release 产物 46.5MB）
- [x] 7.3 代码验证：`_calcDirSize`/`_measureDirQuick`/`_quickDirSize` 共 3 处 `await Future(() {})` yield 控制点（UI 流畅度需真机确认）
- [x] 7.4 代码验证：`disk_scanner_service.dart` 三处 yield 均为 `List.of(allItems)`，无 `unmodifiable`（勾选交互需真机确认）
- [x] 7.5 已验证：`multi_version_scanner.dart:74` 标题 `$family ${v.version}（${v.sourceLabel}）`，来源标签由第 31/32 行 '配置'/'缓存' 注入
- [x] 7.6 已验证：测试驱动真实扫描，`Application Support/Code` 与 `bilibili` 均未出现在候选项中（Bundle ID + 别名映射生效）
- [x] 7.7 代码验证：`_applyKeepList` 在扫描完成后调用 `SettingsStore.getSlimmerKeepList`（跨重启持久化需真机确认）
- [x] 7.8 代码验证：`smart_disk_slimmer_page.dart:103/119` 实现全选/取消全选，`608/613` 渲染按钮
- [x] 7.9 已验证：`v8-video-downloader` 经归一化子串匹配，副标题不再显示"未找到关联应用"，安全等级非"高风险"
- [x] 7.10 已验证：`com.kugou.mac.Music` → safety=安全清理，modified=2020-11-13（`.DS_Store` 等元数据时间戳已被排除，不再判为"高风险"）
