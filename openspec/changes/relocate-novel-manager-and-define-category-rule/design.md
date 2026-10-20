## Context

动机见 proposal.md — Why。此处只记影响实现方式的现状与约束。

现状：`ToolCategory` 有七个枚举值，顺序即活动栏展示顺序；分类只被 `ToolRegistry.getByCategory` 与 `publicTools` 消费，用于侧边栏分组。`category` 不参与任何持久化——`recentToolIds` 与使用次数存的是工具 id 字符串（`SettingsStore` 以 id 为键），代理通道 `ProxySettings.perToolEnabled` 同样以 id 为键。

约束：
- `frequently_used_tools_test.dart` 有两条相关断言——「每个分类至少一个工具」与三个分类的成员集合精确匹配。后者当前为红（`note` 集合漏了 `novel-manager`），与本次迁移要改的是同一处。
- `registry.dart` 的 `tools` 清单中，`PasswordVaultToolDefinition()` 上方的分组注释写 `// 隐私空间`，而它真实归属 `system` 且被测试断言公开可见——清单注释与真实分类已矛盾。

## Goals / Non-Goals

**Goals:**
- 让分类判定从"接入者的判断"变为"可复述的规则"，规则的家在 spec，测试守其后果。
- 让红着的成员断言转绿，并使其在下次接入工具漂移时立刻报警。
- 消除清单注释与真实分类矛盾这处既有误导。

**Non-Goals:**
- 不重新裁量任何其他工具的归属。规则复现了全部 23 个现有成员的归属，本次只动小说管理器一处。
- 不引入运行时校验或 lint 规则强制分类判定——规则不可机器执行（见 Risks）。
- 不做子分组、工具间跳转或"内容产线"这类表达"流向"的结构。分类只能表达"属于"。
- 不改动 `ActivityBar`、`ToolPanel`、`SettingsStore` 任何代码。

## Decisions

### 决策 1：规则以"目的"为输入，而非"技术栈"或"是否调用 AI"

判定输入是工具为用户完成什么。若以"是否调用 AI 模型"为轴，`notebook`（已带 AI 问答面板，`notebook_page.dart` 的「问我的笔记」）和小说管理器（AI 断章/改写/续写/去重）会同时被拉向 `ai`，而 `vocab-book` 一旦加上 AI 释义也会跟着走——最终 `note` 被掏空至无工具，分类按既有规则被删除。这与用户要求保留分类的意图相反。

备选：以"产出物形态"为轴（文字→note，视频→ai）。否——小说管理器与短视频工坊的产出物都是文字与结构化数据，分不开；且它会把 `doc-audio-reader`（用户自己的文档）错划进 note。

### 决策 2：`ai` 与 `note` 的分界定为"内容来源与所有权"

`ai` = 获取外部内容，或再加工机器生产的内容，产物供后续生产或决策；`note` = 组织、学习、复用用户自己产出的文字。

小说管理器据此落 `ai`：从外部书站采集 → AI 断章与元数据补全 → AI 改写续写 → 产物供短视频工坊消费（`ai-video-studio/novel-import` capability 即该消费入口）。它与 `ai` 分类现有三成员（AI资讯与检索、AI 短视频工坊、Toonflow 漫剧工坊）是同一条内容产线的工位。

备选：按"用户是否主观意图创作"分界。否——不可观测，无法据以评审。

已知边界：`doc-audio-reader` 读的是用户自己的文档却落 `file` 不落 `note`，因为判据 6 要求"目的是组织/学习"，而它的目的是形态变换。这是规则中最需要人把握的一处，写进 spec 时保留了"以……为主"的措辞而非更硬的切割。

### 决策 3：规则写成有序 first-match-wins，而非并列标签

八条判据有真实优先级冲突：`unattended-approver` 带"安全硬地板"字样（可争 security），但它本质是无人值守自动化，落 ops。并列标签无法回答"两个都匹配时听谁的"；有序取首个匹配者可以，且顺序本身就是从最具体到最兜底。

备选：每个工具挂多个标签，侧边栏按标签过滤。否——活动栏是单选分类（`ActivityViewType.category` + `currentCategory` 单值），多标签需要改外壳交互，远超本次范围。

### 决策 4：规则的守卫是成员集合精确断言，不是规则本身

规则不可机器执行——测试能断言"`note` 恰好是 {notebook, vocab-book}"，不能断言"为什么它在 note"。因此：
- 规则的可执行部分 = 现有两条断言（成员集合精确匹配 + 每分类至少一个工具），本次只修正成员集合内容并转绿。
- 规则的不可执行部分 = 判据 5 与 6 的边界判断，其家是 spec 正文与注册处注释。

不引入"分类名与成员名的关键词匹配"这类伪校验——它会产生假警报（小说管理器含"管理器"，`smart-disk-slimmer` 含"智能"）且无法真正验证语义。

### 决策 5：测试名随断言内容改，不再沿用"migrated"

现有测试名为「AI, note and ops categories hold their migrated tools」——"migrated"是 2026-09-30 分类重划时留下的说法，此后 `ai-video-studio`、`toonflow-studio`、`novel-manager` 相继接入都是"新增"而非"迁移"，名字已不副实（`ai` 分类漏改断言导致常红的注释就写在它上方 4 行）。改为反映真实断言目标。

### 决策 6：注册处注释采用 password-vault 的先例

`registry.dart` 中 `PasswordVaultToolDefinition.category` 已有一段注释解释"归属仍是 system，改为 privacy 会让它掉出全部工具"。小说管理器同样在注册处注明"为何是 ai 而非 note"——判断依据跟着代码走，读代码的人不必先去翻 spec。同时删除 `// 隐私空间` 那行误导注释，不制造新的第二处漂移。

## Risks / Trade-offs

- **[规则不可机器执行，可能被绕过]** → 成员集合精确断言守其后果；注册处注释给下一个人判定依据；spec 场景明确"带 AI 能力不改变归属"这一最可能被违反的条目。仍可能出现评审看不准的边界 case（`doc-audio-reader` 即一例），届时的纠错成本是一次分类迁移 + 一次断言修正，不涉及数据迁移。
- **[用户对"小说管理器在 AI 分类下"的预期]** → 分类是导航分组而非功能声明；工具名、副标题、图标均不变，最近使用与常用软件排名不变。若实际观感不佳，回滚是一行 category。
- **[迁移后 `ai` 分类有 4 个成员，`note` 剩 2 个]** → 不触发任何空分类删除；两分类均仍满足"至少一个工具"。
- **[顺手修测试可能掩盖"测试本来就该红"的争议]** → 该断言描述的是"三个分类的成员集合"，`novel-manager` 归 note 本就是接入时的疏漏而非有意设计（归档 change 的 tasks/design 均未记 note 归属理由）。修正内容与本次迁移方向一致，非借修测试之名行迁移之实。
- **[顺手删 `// 隐私空间` 注释超出最小范围]** → 该注释与测试断言直接矛盾，留着会让下一个人在 password-vault 归属上做出错误推断。属同一类问题（清单注释与真实分类漂移）的清理。

## Migration Plan

无数据迁移。部署顺序：

1. 改 `registry.dart`：小说管理器 category 改为 `ai` 并加判定注释；删除误导的 `// 隐私空间` 注释。
2. 改 `tool_definition.dart`：枚举注释补 `ai`/`note` 分界与"带 AI 能力不改变归属"，指向 `tool-category-assignment`。
3. 改 `frequently_used_tools_test.dart`：两个成员集合断言随迁移修正，测试名改为反映真实断言目标。
4. 跑 `flutter test test/frequently_used_tools_test.dart`，确认由红转绿（当前红，`note` 集合缺 `novel-manager`）。

回滚：还原第 1 步的一行 category 与注释即可；无持久化状态需要清理。
