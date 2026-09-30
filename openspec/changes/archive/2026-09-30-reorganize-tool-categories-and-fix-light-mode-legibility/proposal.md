## Why

四条用户实测反馈，前三条是浅色主题的可读性缺陷，第四条是功能缺失，第一条是导航结构失衡。

它们共同的根源是同一类问题：**项目在浅色主题上只迁移了颜色，没有迁移"颜色如何组合"的契约。** 主题 token（`accentText` / `accentSolid` / `onAccentSolid`）是齐的，但控件层没有强制"实底必须配可见前景"，导致每个新调用点都可能造出一个看不见的胶囊。同时，`ToolCategory` 只有四个分类，其中「系统与配置」塞了 10 个工具（一半的工具），标题已经名不副实。

## What Changes

### 1. 工具分类重划 + 新增「常用软件」入口

- `ToolCategory` 从 4 个扩到 7 个：新增 `ai`（AI 与资讯）、`note`（笔记与学习）、`ops`（运维与监控）。
- 「系统与配置」从 10 个工具收缩到 4 个：智能磁盘瘦身、BC配置工具、BC脚本管理、应用快捷键获取——它们才是名副其实的系统/配置类。其余 6 个按语义迁入新分类。
- 新增「常用软件」**独立入口**（不是 `ToolCategory` 的第八个值）：按使用频率列 top 5，排序即频率序，无使用记录时隐藏。工具可同时出现在常用软件与原分类中——常用软件是快捷入口，不是搬家。
- 修复频率埋点的断点：`openInNewWindow` 工具（笔记本、密码工具、磐石运维）在 `selectTool()` 中提前 `return`，从不调用 `_recordUsage()`，因此永远不会进入常用软件。这恰是最常用的几个工具。

### 2. 浅色主题控件可读性（比用户报告的范围更广）

用户报告两处，实测同类问题至少 5 处：

| 位置 | 症状 | 是否被报告 |
| --- | --- | --- |
| `network_proxy_page.dart:87` | Switch 轨道与圆饼同色，圆饼消失 | ✓ |
| `ai_assistant_page.dart:141` | 同上 | ✓ |
| `ops_devops_view.dart:1733, 1916` | 同上 | ✗ 同病 |
| `private_player_view.dart:454` | 同上（深色下不明显） | ✗ 同病 |
| `scheduled_tasks_drawer.dart:291` | `AppBadge` 实底 + 默认深灰前景 = 色块 | ✓ |
| `ai_config_page.dart:858, 868` | 同上（"已连通/连通异常"胶囊） | ✗ 同病 |

根因不是某个调用点写错，而是**组件层不阻止这种组合**。逐个修调用点能治今天，治不了下一次。

- `AppBadge`：传入非默认实底时，前景自动切到对应的 `on*Solid` token；调用点不再需要同时记得传两个颜色。
- 新增共享开关组件，把 thumb / track 的配对收在一处，使"轨道与圆饼同色"在 API 表面无法表达。

### 3. 资讯快报的来源链接

- `NewsBriefingItem` 增加 `sources` 字段，把检索结果的原始 URL 存进历史——目前 URL 只被拼进喂给 AI 的文本，入库时丢弃。
- `AppMarkdownView` 支持 `onTapLink`，让 AI 复述的链接可点击。
- 在快报卡片上渲染来源条目，**不依赖 AI 是否把 URL 抄进摘要**。快报要能"点回原始网页"，把这件事交给 AI 的复述准确率是把关键路径交给概率。

## Capabilities

### New Capabilities

- `frequently-used-tools`: 「常用软件」独立入口——按使用频率取 top 5、按频率排序、无记录时隐藏；独立窗口工具的开启也计入频率；工具可同时归属常用软件与原分类。

### Modified Capabilities

- `workspace-navigation`: 分类集合从四类扩为七类，「系统与配置」的内容范围收窄；活动栏新增「常用软件」入口。
- `shared-markdown-theme-contrast`: `AppBadge` 与开关控件在实底之上必须呈现可读前景；`AppMarkdownView` 的链接可点击。
- `ai-news-assistant`: 快报历史条目携带结构化来源，且来源可点击访问原始网页。

## Impact

- **Flutter 层**：`lib/tools/tool_definition.dart`（枚举 + 归属）、`lib/tools/registry.dart`（各工具 `category`）、`lib/shell/activity_bar.dart`（七个分类 + 常用软件入口）、`lib/shell/app_shell.dart`（`_recordUsage` 覆盖独立窗口）、`lib/components/app_components.dart`（`AppBadge` 前景契约 + 新开关组件）、`lib/components/markdown_view.dart`（`onTapLink`）、`lib/services/scheduled_news_service.dart`（`sources` 字段）、`lib/tools/ai_assistant/ui/scheduled_tasks_drawer.dart`（来源渲染）、5 处 Switch 调用点。
- **数据**：`app.json` 的 `recentTools` 上限从 8 提升到足以支撑 top 5（现有上限已够，但只对非独立窗口工具生效——修的是漏记，不是容量）；`news_briefings.json` 的条目新增 `sources`，旧条目读到时为空数组，无需迁移。
- **规范**：`workspace-navigation` 中「Activity bar and tool panel split navigation」的场景需反映新分类集合。
- **非目标**：不做自定义排序/置顶/拖拽（频率排序已覆盖诉求）；不为 Safari/Firefox 提供外链打开（项目本就 macOS 目标平台）。
