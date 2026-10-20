## Why

小说管理器（`novel-manager`）在接入时归入了 `ToolCategory.note`（笔记与学习），与它同组的是笔记本和生词本——两个组织/学习**用户自己产出**文字的工具。但小说管理器是内容资产工具：从外部书站采集、AI 断章与元数据补全、AI 改写续写、产物供短视频工坊消费，与 `ai` 分类下已有的 AI资讯与检索、AI 短视频工坊、Toonflow 漫剧工坊是同一条内容产线的工位。名字里的"库"和"书"让它看起来像笔记工具，实际不是。

`note` 与 `ai` 之间缺少一条写下来的分界，导致每次接入新工具都靠感觉判断；`notebook` 已带 AI 问答面板却仍在 `note`，说明"带 AI 能力"与"归属 ai"是两件事但从未有人说过。本次既修正小说管理器的归属，也把判定规则写成规格，使后续接入有据可依。

## What Changes

- **小说管理器分类从 `note` 迁移到 `ai`**：`NovelManagerToolDefinition.category` 由 `ToolCategory.note` 改为 `ToolCategory.ai`，并按 `password-vault` 的先例在注册处注明判定依据（为何是 ai 而非 note）。
- **新增分类归属判定规则**：一条有序的目的判定（first match wins），以"工具为用户完成什么"为输入，而非"用到什么技术"。`ai` 与 `note` 的分界是**内容的来源与所有权**——`ai` 获取或再加工外部/机器生产的内容，`note` 组织用户自己产出的文字。
- **明确"带 AI 能力不改变归属"**：防止后续给生词本加 AI 释义、给笔记本加深度的改动把工具错误迁往 `ai`，最终掏空 `note` 分类。
- **修正 `frequently_used_tools_test.dart` 中一条从小说管理器接入起就常红的断言**：`note` 分类成员集合断言漏了 `novel-manager`，实测当前为红（Expected `['notebook','vocab-book']`，Actual 含 `novel-manager`）。本次随迁移一并改为正确的两个集合，并使该测试转绿。
- **修正 `ToolRegistry.tools` 清单中误导性的分组注释**：`PasswordVaultToolDefinition()` 上方的 `// 隐私空间` 注释与其真实的 `system` 归属矛盾（`frequently_used_tools_test.dart` 明确断言它公开可见）。删除该行注释，不再制造第二处分类漂移。
- **推广"分类成员语义相符"的守卫范围**：`workspace-navigation` 规格中该场景目前只守 `系统与配置` 一个分类，改为覆盖全部分类。

## Capabilities

### New Capabilities

- `tool-category-assignment`: 工具分类归属的判定规则——按工具目的而非实现技术分类、`ai` 与 `note` 以内容来源分界、带 AI 能力不改变归属、迁移不改变工具的可见性与持久化数据。

### Modified Capabilities

- `app-shell`: 「工具注册表」要求补充分类归属的判定依据，注册新工具时其分类 SHALL 依据判定规则而非个人判断。
- `workspace-navigation`: 「分类成员语义相符」场景从只守 `系统与配置` 推广为覆盖每个分类；`note` 分类的成员范围相应收缩。

## Impact

**代码**
- `lib/tools/registry.dart:240`：`NovelManagerToolDefinition.category` 由 `note` 改为 `ai`，附判定注释。
- `lib/tools/registry.dart:537` 附近：删除 `PasswordVaultToolDefinition()` 上方误导的 `// 隐私空间` 注释。
- `lib/tools/tool_definition.dart`：`ToolCategory` 枚举注释补 `ai`/`note` 分界与"带 AI 能力不改变归属"，并指向 `tool-category-assignment` 规格。

**测试**
- `test/frequently_used_tools_test.dart`：修正 `note` 与 `ai` 两个分类成员集合断言（红→绿）；测试名「AI, note and ops categories hold their migrated tools」不再副实，随内容改为反映真实断言目标。
- 无新增测试文件；`每分类至少一个工具`、`隐私分类不泄漏进 publicTools` 等既有断言无需改动，迁移后仍成立。

**无持久化影响**：`category` 仅决定侧边栏分组，不参与持久化。`recentToolIds` 与 `getMostUsedToolIds` 存的是工具 id 字符串，常用软件排名、最近使用、代理通道（`ProxySettings.perToolEnabled` 以 id 为键）均不受影响，无需数据迁移。

**无可见性变更**：`note` 与 `ai` 都非 `privacy`，小说管理器迁移后仍出现在「全部工具」与常用软件候选中。迁移后 `note` 仍保有 2 个工具，不触发空分类删除。
