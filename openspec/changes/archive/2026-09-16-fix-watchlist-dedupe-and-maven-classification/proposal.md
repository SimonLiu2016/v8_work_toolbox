# Proposal: fix-watchlist-dedupe-and-maven-classification

## Why

用户实测反馈"构建产物中连 java 或 spring 或 maven 都没有出现"。追查后发现三个叠加缺陷，其中两个是真 bug、一个是设计缺口。三者互相掩盖：即使补上 Maven 技术栈，watchlist 吞根仍会把所有子项目压成 `other`；即使修了去重，配置继承跳过的 12 个根仍不会回来。

## What Changes

- **watchlist 去重吞根**：`_dedupeNested` 按前缀去重时，watchlist 里的宽容器目录（如 `~/Workspace`）会吞掉其下所有自然发现的项目根。实测 782 → 553，净减 229 根。这些子项目不再各自成条目，而是被压进 `~/Workspace` 这一个巨型条目，且该条目因 `_detectTechStack` 只读顶层信号而归类为 `other`。改为**交集语义**：watchlist 条目若其下有自然根，保留自然根、丢弃该条目自身；仅当其下无任何自然根时才作为单根加入。watchlist 由此回到"manifest 门控的逃生口"定位，不再充当父前缀。

- **配置继承跳过**：`_inheritCleanBuildsConfigIfNeeded` 仅在 `extraRoots` 为空时才合并被移除工具（`clean-builds`）的根列表。用户磁盘上 `extraRoots` 非空（`~/Workspace`），导致 `clean-builds.json` 里 12 个具体根（`ctf-gitlab`、`github`、`gitee`、`vsProject`、`flink_space`、`devops`、`zeebe`、`pythonProject`、`cae`、`PycharmProjects`、`ClaudeWorkspace`、`Livespace`）静默丢弃，且 `slimmerInheritedFromCleanBuilds` 标志已置位、永不重试。改为**无条件并集合并**（按值去重，保留用户既有条目），标志仅用于一次性"已继承 N 个旧项目根"提示。此改动能自愈既有受影响用户的配置（下一次启动即补回 12 根）。

- **Maven / Java 技术栈缺失**：`ProjectTechStack` 枚举只有 `flutterDart` / `node` / `gradleAndroid` / `other` 四个值，`_detectTechStack` 也不认 `pom.xml`。UI 的组标题与筛选 chip 只读 `ProjectTechStack.values`，所以 Maven/Java 项目在 UI 层结构性不可能出现——只能落进"其他构建产物"。新增 `maven` 枚举值（标签 `Maven / Java`），`_detectTechStack` 增加 `pom.xml` 判定。优先级置于 gradle 之后（`.gradle` / `build.gradle` 是比 `pom.xml` 更强的实际构建信号），flutter 与 node 之前。

**Non-Goal：Spring。** Spring 是依赖而非构建系统，只能从 `pom.xml` 内容或 `classpath` 读到，而 Tier B 刻意不读文件内容（只读目录名与大小，这是它的性能边界）。要识别 Spring 须破这个边界，属独立变更。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `disk-analyzer`：
  - "Project build artifact discovery with manifest gating" —— watchlist 条目与其下自然发现的项目根的关系由"前缀去重、父吞子"改为"交集：有子则弃父"
  - "Project-root aggregation and technology-stack grouping" —— 技术栈分组集合新增 Maven / Java（`pom.xml` 信号）

- `settings-storage`：
  - "工具合并时的配置继承" —— 合并由"仅当承接键为空时执行"改为"无条件并集（按值去重，不覆盖用户既有条目）"，使已置位的继承标志不阻断补救

## Impact

- `lib/tools/slimmer/project_artifact_detector.dart`：`discoverProjectRoots` 的 watchlist 合并逻辑（交集替代并集 + 去重）；`_detectTechStack` 增加 maven 分支
- `lib/tools/slimmer/slimmer_models.dart`：`ProjectTechStack` 枚举新增 `maven`
- `lib/services/settings_store.dart`：`_inheritCleanBuildsConfigIfNeeded` 移除"承接键为空"的前置条件，改为并集合并
- `test/project_artifact_detector_test.dart`、`test/settings_store_test.dart`：新增 watchlist 交集语义、Maven 分类、继承自愈的测试
- 数据侧：继承改为无条件并集后，既有受影响用户（`slimmerInheritedFromCleanBuilds: true` 且 `extraRoots` 非空）在下一次启动时自动补回被移除工具的根列表，无需手工修复
- 依赖：无新增
- 与 `fix-tier-a-discovery`、`merge-clean-builds-into-slimmer` 同属"项目构建产物扫描"谱系，三者需按依赖序统一归档（merge → tier-a-discovery → 本变更）
