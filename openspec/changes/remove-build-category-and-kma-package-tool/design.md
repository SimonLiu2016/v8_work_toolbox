## Context

见 proposal.md 的 Why。本设计只解释"怎么删"的技术选择。

约束（已核实的现状）：

- `ToolCategory` 是 `enum`，`ActivityBar` 直接遍历 `ToolCategory.values` 渲染入口（`lib/shell/activity_bar.dart:106`），零改动即自动跟随枚举变化。
- `lib/` 根部住着一批旧工具页（`batch_rename_tool.dart`、`image_resize_tool.swift` 等同类），新工具都在 `lib/tools/<id>/` 下。KMA 的 11 个文件散在 `lib/` 根部与 `lib/components/` 根部。
- `test/frequently_used_tools_test.dart:95` 有"每个分类至少一个工具"的断言，注释写着理由："分类为空——活动栏会出现点进去什么都没有的入口"。

## Goals / Non-Goals

**Goals:**

- 删除 KMA 包生成及其专属代码后，不留下任何可见的空分类入口或不显眼的死引用。
- 删除动作对旧数据（最近使用、使用次数）零副作用、零迁移需求。
- 每一步删除后代码库保持可编译、单测可通过——不出现"先红一阵"的中间态。

**Non-Goals:**

- 不把 `lib/` 根部剩余的同构旧工具搬进 `lib/tools/<id>/`。那是独立的结构收尾，会显著扩大 diff 与评审面。
- 不动 `pubspec.yaml` / `pubspec.lock`。
- 不 remediate git history 中的密钥泄露。
- 不修正 `settings_store.dart` 中"上限由工具总数决定（16 个）"这类过时注释（见 Risks）。

## Decisions

### 决策 1：删空分类枚举值，而非保留一个空分类

`ToolCategory.build` 随之从 `tool_definition.dart` 删除。

**为什么**：活动栏按 `ToolCategory.values` 遍历渲染，保留空枚举值 = 每次点击都进一个空面板，而 `frequently_used_tools_test.dart` 那条断言本就是为拦住这个而存在的。只删工具不删枚举，当天测试就红。

**考虑过的替代**：

| 方案 | 结论 |
|---|---|
| 保留枚举，在 `ActivityBar` 过滤空分类 | 把"分类非空"这条业务规则泄漏到外壳 UI，且要新增过滤逻辑；测试虽会绿但靠的是 UI 层绕过，规格里的意图被稀释 |
| 保留枚举 + 让测试容忍空分类 | 直接删掉一条有人写下来守着的回归测试，理由只是"没人用" |

### 决策 2：`removedToolRedirects` 不新增 `kma-package` 条目

KMA 打包无功能承接者。硬映射到 `smart-disk-slimmer` 会把用户骗去磁盘清理——比不跳转更糟。

**为什么不需要**：已验证两条消费路径对未注册标识都优雅降级：

```
getRecentToolIds() → app_shell.dart:66  仅用于挑初始工具，findById==null 则跳过
                                          → 落到 publicTools.first，无空条目
getMostUsedToolIds() → app_shell.dart:174 findById==null → continue，不渲染
```

`_recentToolIds` 从不作为列表渲染源，所以点不开的条目在结构上不可能出现。

**考虑过的替代**：

| 方案 | 结论 |
|---|---|
| 映射到 `smart-disk-slimmer` | 功能不相关，违反规格新增的"不重定向到功能不相关的工具" |
| 启动时清洗 `recentTools`/`toolUsageCounts` 里的残留 id | 需要写迁移代码与迁移测试，收益只是让配置文件少几个字节 |

代价（已评估，可接受）：`config/app.json` 的 `toolUsageCounts` 可能残留一个 `kma-package` 计数。它不进排名、不渲染、不报错。

### 决策 3：删除顺序为"先删分类、再删工具"，保证测试不出现中间红态

`frequently_used_tools_test.dart` 的"每个分类至少一个工具"在「工具还在、枚举值没了」和「工具没了、枚举值还在」两种中间态下都会红。同一笔提交内先改 `tool_definition.dart` 再改 `registry.dart`，提交完成时两者一致。

### 决策 4：`encrypt` 依赖留在 pubspec

删除后 `lib/` 内零引用（已 grep 确认仅 `kma_package_util.dart` 引用过）。但摘依赖必须动 `pubspec.lock`，而本项目有 `flutter pub get` 挂起会截断 lockfile 的记录；省的这点依赖不值这个风险。写成 tasks 里的显式"不做"，避免实现时手滑。

**考虑过的替代**：单独一笔清理依赖的变更。认可其价值，但不该和一捆删除挤在同一笔里互相挡评审。

## Risks / Trade-offs

**[历史密钥仍可复原]** 删除工作区文件不给 git history 里的百度翻译 Key 做任何 remediate。→ 本变更不改写历史（会动 3 个 commit，影响所有后续历史）；是否轮换/改写由用户单独决定，已在 proposal Impact 中显式记录为未 remediate。少一份持密代码本身仍是净收益。

**[过时注释继续骗人]** `settings_store.dart:388` "上限由工具总数决定（16 个）"在删除后更不准（19 → 18）。→ 本变更不修（non-goal），但它已经是错的且本次无人触碰该文件的语义，单独一笔更正更合适。

**[删除范围判定错误]** 若那 9 个 `components/` 里有被低估的消费者，删除会破坏编译。→ 已逐个类名 grep 确认唯一消费者是 `kma_package_tool.dart`；编译 + 全量单测是最终兜底。

**[README 与现实早已脱节]** README 的表格仍列着已移除的"清理构建产物"（`clean-builds`），说明这张表没有被当成事实来源维护。→ 本变更只删 KMA 那一行，不做全面校对；不值得为一笔删除重读整张表。

## Migration Plan

无数据迁移。回滚即还原本次提交——枚举值、注册表条目、11 个文件全部回到原状，旧数据（`recentTools`、`toolUsageCounts`）从始至终未被本变更触碰。

## Open Questions

（无。）
