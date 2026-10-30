## Context

当前「智能磁盘瘦身」流水线由 `DiskScannerService` 组织，现有 4 个阶段：
1. 阶段 1：瞬时定向扫描（Xcode DerivedData、Gradle、CocoaPods 依赖缓存、以及 `~/Downloads` 下的大包）；
2. 阶段 2：IDE 与运行时多版本探测；
3. 阶段 3：已卸载应用的孤立残留（通过 `AppOrphanDetector` 建立已安装软件白名单，仅扫描未命中白名单的孤立目录）；
4. 阶段 4：工作区代码工程构建产物（`ProjectArtifactDetector`，扫描 700+ 项目的 node_modules/build 等）。

清理操作通过 `SystemService.instance.recyclePaths` 统一走 `NSWorkspace.shared.recycle`（即安全移入废纸篓）。当前体系下缺少对废纸篓自身、日常应用运行缓存、全目录安装包与单体超大文件的覆盖。

## Goals / Non-Goals

**Goals:**
- 在扫描流水线中引入系统废纸篓统计，并提供受控的原生永久清空机制（带模态防呆确认）；
- 复用已安装应用索引，动态识别活跃日常应用（微信、钉钉、QQ音乐、各大浏览器等）在 `~/Library/Caches` 和沙盒目录下的缓存，并扫描 `~/Library/Logs` 系统日志；
- 将安装包检测范围扩大到 `~/Downloads`、`~/Desktop`、`~/Documents`，结合修改天数（>7天）进行推荐；
- 基于 macOS Spotlight 元数据索引（`mdfind`）实现用户目录下超大单体文件（>100MB）毫秒级发现与体积降序排行；
- 提供条目“在访达中显示”快捷操作；
- 扩展 `SlimmerCategory` 分类与页面 Filter Chips 交互。

**Non-Goals:**
- 不支持全盘系统级只读目录（`/System`、`/usr`）扫描与修改；
- 不对大文件做耗时的全量 SHA-256 内容查重（专注于单体大空间快速回收）；
- 不在无用户二次确认的情况下执行清空废纸篓动作。

## Decisions

### 1. 废纸篓探测与清空执行 (D1)
- **探测**：扫描阶段直接遍历 `~/.Trash`，统计总大小与项数，挂载到扫描完成汇总中；
- **展示**：在页面顶部以独立状态卡片展示，与常规候选列表区分；
- **清空执行**：在 `SystemService` 中新增 `emptyTrash()` 方法，底层通过 AppleScript `tell application "Finder" to empty trash` 执行（失败时回退至批量安全清空 `~/.Trash/*`），并在 Flutter 前端强制弹出二次确认对话框；
- **替代方案考虑**：直接把废纸篓做成列表项勾选。*否决原因*：常规列表项是通过 `recyclePaths` 移入废纸篓，若废纸篓自身也走这个逻辑会出现循环依赖，且废纸篓清空是物理永久删除，语义必须截然不同。

### 2. 活跃应用缓存与已卸载残留双向分离 (D2)
- **机制**：在 `AppOrphanDetector` 初始化构建的已安装 App 白名单基础上，当遍历 `~/Library/Caches` 及 `~/Library/Containers/*/Data/Library/Caches` 时：
  - 若命中已安装 App 且目录体积大于阈值（如 >1MB）→ 生成 `SlimmerCategory.dailyAppCache` 条目，显示 App 本地化名称与图标/标签；
  - 若未命中且不是系统保护目录 → 维持原有逻辑作为 `SlimmerCategory.orphanApp`（已卸载残留）；
- **勾选策略差异化**：
  - 浏览器缓存（Chrome、Edge、Safari、Firefox）与系统日志（`~/Library/Logs`）：标记为 `SafetyRating.safe`，默认勾选；
  - 即时通讯软件（微信、钉钉、飞书等）：标记为 `SafetyRating.caution`，默认不勾选，防用户清理后抱怨聊天缩略图重拉。

### 3. 基于 Spotlight 元数据的超大文件极速排行 (D3)
- **检索命令**：
  ```bash
  mdfind -onlyin "$HOME" 'kMDItemFSSize > 104857600 && kMDItemContentTypeTree != "com.apple.application-bundle"'
  ```
- **后置过滤**：
  - 排除系统隐藏目录（如 `.Trash`、`.git/` 内部对象、`.cache`、开发编译产物目录）；
- **排序与安全**：
  - 结果按文件字节数降序排列（前 100 项）；
  - 全体默认不勾选（`isSelected = false`），安全等级标为 `SafetyRating.caution`；
  - 为大文件条目提供 `revealInFinder`（调用 `NSWorkspace.shared.activateFileViewerSelecting` 或 `open -R`）。

### 4. 废弃安装包多目录扫描 (D4)
- **范围**：针对 `~/Downloads`、`~/Desktop`、`~/Documents`；
- **扩展名**：`.dmg`, `.pkg`, `.iso`；
- **智能推荐**：
  - 距今修改时间超过 7 天：`isSelected = true`（已安装，安装包废弃）；
  - 7 天内：`isSelected = false`（可能刚下载待安装）。

### 5. 分类枚举与页面 Chips 扩展 (D5)
- 在 `SlimmerCategory` 中新增：
  - `dailyAppCache('日常应用缓存', '正在使用的应用产生的临时缓存与日志')`
  - `largeFiles('超大文件排行', '单体体积超过 100MB 的大文件，按大小降序')`
  - `installers('废弃安装包', '下载目录与桌面长期留存的 .dmg, .pkg, .iso 安装包')`
- 更新 Filter Chips，提供分组筛选与数量/体积即时统计。

## Risks / Trade-offs

- **[Spotlight 索引不可用或延迟]** → 当用户禁用 Spotlight 索引或外部盘未建索引时，`mdfind` 返回为空。
  - *缓解措施*：若 `mdfind` 返回 0 条，快速对 `~/Downloads`、`~/Desktop`、`~/Movies` 做有限深度（depth <= 2）的大小过滤作为兜底。
- **[清空废纸篓导致数据彻底丢失]** → 用户误点清空按钮。
  - *缓解措施*：弹窗必须展示红色告警、明确列出待抹除的字节数与项数，要求主动点击“确认彻底抹除”。
- **[正在运行的应用缓存被清理触发异常]** → 某些应用在前台读写缓存文件时被移走。
  - *缓解措施*：敏感 IM 软件默认不勾选；移入废纸篓使用系统 API，即使文件正被锁定，系统也会返回友好提示而非静默崩溃。
