## Why

「清理构建产物」与「智能磁盘瘦身」做的是同一件事（清除可再生的开发缓存）却挂在两个入口、两套删除策略下：前者永久删除且需要用户预先登记项目根，后者移入废纸篓、零配置、但完全不发现项目树内的构建产物。结果是一个能力缺口——`node_modules`、`build/`、`.gradle` 这类产物既不在全局共享缓存位置，也没有任何扫描器会遍历发现它。合并后瘦身的覆盖面才完整，用户也只需要一个心智模型。

## What Changes

- **BREAKING**：移除工具注册表中的 `clean-builds`（清理构建产物）条目及其页面 `lib/clean_builds_tool.dart`，功能整体并入 `smart-disk-slimmer`。
- 新增扫描器 `ProjectArtifactDetector`，作为分级扫描的第 4 阶段，分两层：Tier A 只做浅层 manifest 发现（HOME 下 maxdepth 3 识别 `.git` / `package.json` / `pubspec.yaml` / `build.gradle` / `Podfile` / `CMakeLists.txt` 等项目根，秒级完成），Tier B 在每个被识别的项目根内做剪枝遍历收集产物目录（不下降进 `.git`、`node_modules` 自身等，按根设时间预算）。
- 产物命中 MUST 经 manifest 门控——只在被识别为项目根的目录下计数；`~/node_modules` 这类目录名相同但不在项目根内的路径不产出候选项。
- 新增 `SlimmerCategory.projectArtifacts`（项目构建产物），与现有 `buildCache`（全局共享缓存）区分。
- 新增发现预算的显式上报：超出单根时间预算或命中数量上限的根 MUST 标记为"扫描超时/未完整"，MUST NOT 静默丢弃。
- 条目粒度为项目根聚合：每个项目根一个 `SlimCandidateItem`，`subtitle` 内含产物目录数量与按类型的构成摘要；展开可查看该根内的明细。
- 列表层按技术栈分组呈现（Flutter/Dart、Node、Gradle/Android 等），组为列表行、项目根为组的展开明细；列表只呈现"≥1 个命中且 ≥10MB"的根。
- 构建产物走与现有候选项一致的 macOS 废纸篓回收与物理校验流程，**BREAKING**：取代原工具的永久删除（`delete(recursive: true)`），删除行为由不可逆变为可逆。
- 迁移 `clean-builds` 的持久化数据（watchlist `configs` 与 `artifactOptions`）到瘦身的配置键，作为"额外指定项目根"的补充输入，不迁移即静默丢失用户数据。
- **BREAKING**：最近使用中出现的历史 `clean-builds` 标识重定向到 `smart-disk-slimmer`，避免用户点击一个已不存在的入口。

## Capabilities

### New Capabilities

（无。本变更不引入新的 capability 路径，三项行为分别落在既有 capability 上。）

### Modified Capabilities

- `disk-analyzer`: 分级扫描新增第 4 阶段（项目构建产物，manifest 门控 + 发现预算），新增 `projectArtifacts` 分类、项目根聚合条目粒度、列表按技术栈分组、列表仅呈现 ≥10MB 的根；构建产物经废纸篓回收与物理校验（取代永久删除）。
- `disk-scanner-async`: 新增非阻塞的项目根剪枝遍历与单根时间预算约束，Tier A 完成即渐进式上抛候选项；超预算的根以"未完整"状态呈现而非静默丢弃。
- `app-shell`: 注册表移除 `clean-builds`；工具计数表述由硬编码"8 个工具"改为对注册表内容自洽（不枚举具体工具清单）；最近使用遇到已移除的工具标识时重定向到瘦身工具而非丢弃或报错。
- `settings-storage`: 新增工具合并时的配置继承要求——被移除工具的既有配置 MUST 迁移到承接工具的可读取路径，复制而非移动、只执行一次、不覆盖用户在承接键中的后续修改；不允许静默丢弃被移除工具的用户数据。

## Impact

- 代码：删除 `lib/clean_builds_tool.dart`（559 行）；`lib/tools/registry.dart`（移除 `CleanBuildsToolDefinition` 与注册表条目、删除 import）；新增 `lib/tools/slimmer/project_artifact_detector.dart`；扩展 `lib/tools/slimmer/slimmer_models.dart`（`SlimmerCategory` 新值 + 聚合项字段）与 `lib/tools/slimmer/disk_scanner_service.dart`（第 4 阶段接入）；`lib/tools/slimmer/smart_disk_slimmer_page.dart`（分组呈现、watchlist 迁移入口、未完整标记）；`lib/services/settings_store.dart`（配置键迁移，`clean-builds` 迁移表项保留以承接 watchlist 数据）。
- 分类：`ToolCategory.build` 合并后仅剩 KMA 包生成一个工具——本变更不处理该分类的空置问题，只记录为后续事项。
- 依赖：无新增。
- 测试：`test/settings_store_test.dart` 与 `test/evernote_import_*` 等以 `'clean-builds'` 作为迁移测试夹具字符串的用例需评估是否改名（迁移表项本身保留，故夹具可保留原值，仅新增瘦身键的迁移断言）；新增 `project_artifact_detector` 的检测、门控、预算、聚合与分组测试；新增配置迁移测试。
- 数据：`~/.v8_cleaner_config.json` → `config/clean-builds.json` 的迁移链路保留；新增从瘦身配置键读取 watchlist 的读路径。
- 性能基线（本机实测，用于约束实现）：剪枝遍历 `~/` 排除 `Library`/`.git` 耗时 88s 且命中 5571 个同名目录；`-maxdepth 8` 为 50s / 2390 个命中；而按最终提议的 Tier A 实测（`HOME` 下 `maxdepth 3`、7 个 manifest 信号、无剪枝）为 2.5s / 672 个根，去嵌套后 670 个。因此 Tier A 与 Tier B 必须分离，Tier B 不得升级为无界全盘遍历。另外实测发现 `~/` 顶层存在裸 `package.json`，会让整个 `HOME` 被识别为一个项目根并在去嵌套时吞掉全部其他根——Tier A MUST 排除 `HOME` 自身作为根。
