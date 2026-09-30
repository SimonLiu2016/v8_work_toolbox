## 1. 组件层可读性（独立于分类重构，先落地）

- [x] 1.1 `AppBadge` 增加前景自动推导：传入非默认实底时，按底色语义取对应的 `on*Solid` token（accentSolid→onAccentSolid、successSolid→onSuccessSolid、errorSolid→onErrorSolid、warningSolid→onWarningSolid）；未传色时保持原样的中性前景
- [x] 1.2 新增共享开关组件 `AppSwitch`，内部固定 thumb 与 track 的配对，使「轨道与圆饼同色」在 API 表面无法表达；保留 `activeColor` 语义供调用方指定开启态主色
- [x] 1.3 替换 4 处同色胶囊调用点：`network_proxy_page.dart:87`、`ai_assistant_page.dart:141`、`ops_devops_view.dart:1733`、`ops_devops_view.dart:1916`。`private_player_view.dart:454` 经核对是 Slider 的 `thumbColor` 而非 Switch，误报，不动
- [x] 1.4 核对其余 5 处开关：`doc_audio_reader_page.dart:453`（thumb=blueAccent）、`scheduled_tasks_drawer.dart:187`、`unattended_page.dart:327`、`ops_scheduler_view.dart:248`、`ai_config_page.dart:883`（只设 thumb/activeColor，track 走 m3 默认）——两模式下 thumb 均与 track 有明度差，不同色、不退化，故不替换；强行统一会改变 5 处既有外观且与修 bug 无关
- [ ] 1.5 浅色模式下目视复核：代理开关圆饼可见、NEW 标签文字可读、AI 配置页「已连通 / 连通异常」胶囊文字可读

## 2. 工具分类重划

- [x] 2.1 `ToolCategory` 新增三个值：`ai`（AI 与资讯）、`note`（笔记与学习）、`ops`（运维与监控），各带 label 与图标；枚举顺序即活动栏展示顺序
- [x] 2.2 按语义改 6 个工具的 category：AI资讯与检索 → `ai`；笔记本、生词本 → `note`；磐石运维工具、无人值守助手 → `ops`；密码工具 → `privacy`（原本错挂在 `system`，与 `registry.tools` 里它所在的「隐私空间」注释分组不符）
- [x] 2.3 核对「系统与配置」剩余 4 个（BC配置工具、BC脚本管理、应用快捷键获取、智能磁盘瘦身）确实都属系统/配置范畴
- [x] 2.4 确认 `ActivityBar` 无需逐项接线即可渲染新增分类（它遍历 `ToolCategory.values`），并核对隐私空间仍被排除在分类列表之外
- [ ] 2.5 确认每个新分类非空、每个分类的 label 对其内容为真

## 3. 「常用软件」入口

- [x] 3.1 `ActivityViewType` 新增 `frequent`；`_getToolsForCurrentView()` 返回频率列表，`_getPanelTitle()` 返回「常用软件」
- [x] 3.2 排名按**累计使用次数**降序取前 5（`kFrequentToolLimit`），过滤掉已不存在的工具 id 与隐私分类工具；因过滤发生在截断之后，取双倍候选再截断，避免一个隐私工具就让入口只剩 4 个（用户明确要求真使用次数而非最近使用序）
- [x] 3.3 无使用记录时（`_frequentTools().isEmpty`）活动栏不渲染该入口；有记录时才出现（`hasFrequentTools`）
- [x] 3.4 `selectTool()` 的 `openInNewWindow` 分支在 `openNewWindow()` 之前也记录使用频率，隐私分类工具除外——这是笔记本/密码工具/磐石运维从不进频率列表的根因
- [ ] 3.5 确认「常用软件」与「全部工具」两个入口的选中态不互相污染（切换分类时 `_currentView` 回到原值）
- [ ] 3.6 确认进入「常用软件」时面板标题显示「常用软件」而非「全部工具」，工具计数徽标显示 5 或更少

## 4. 资讯快报来源链接

- [x] 4.1 `NewsBriefingItem` 增加 `sources`（`List<BriefingSource>`，含 title/url）字段，含 `toJson` / `fromJson`，缺省空列表
- [x] 4.2 `scheduled_news_service.dart` 构建快报条目时，从 `webResult.results` 取 title/url 一并写入（不等 AI 复述）
- [x] 4.3 `AppMarkdownView` 增加可选 `onTapLink`；快报处接到 `Process.run('open', [url])`（与项目现有 8 处外链打开方式一致，不引入 url_launcher）
- [x] 4.4 `scheduled_tasks_drawer` 的快报卡片渲染来源条目（标题 + tooltip 显 URL），点击打开原网页；历史条目（无 sources）不渲染来源区而不报错
- [ ] 4.5 确认 AI 对话框内的 markdown 回复在接入 `onTapLink` 后，链接与纯文本的选择复制行为均不退化（AI 对话框本身未传 `onTapLink`，行为与改造前一致；若也要可点需另行接线）

## 5. 测试与验证

- [x] 5.1 单测：排名按次数降序、截断到 5、过滤后仍凑满 5、一次使用不翻盘、无计数为空、仅隐私工具为空、已下线 id 被忽略（`test/frequently_used_tools_test.dart`，7 例）
- [x] 5.2 单测：无计数时不渲染常用软件入口（有计数时渲染）——由 `pickFrequent({})` 为空 + AppShell 的 `hasFrequentTools: _frequentTools().isNotEmpty` 接线共同保证
- [x] 5.3 单测：分类断言守卫「每个分类非空、系统与配置的成员集合、迁移的 5 个工具各归其位、publicTools 与隐私分类无交叠」（同文件，4 例）。独立窗口工具记次数由接线保证（`selectTool` 的 `openInNewWindow` 分支调 `_recordUsage`），并使 3.4 完成
- [x] 5.4 单测：`NewsBriefingItem` 的 sources 序列化往返；旧条目（无该字段）、null、脏数据均不致命（`test/briefing_sources_test.dart`，5 例）
- [x] 5.5 单测：每个 `ToolCategory` 至少有一个工具，且「系统与配置」的成员全部语义相符（`frequently_used_tools_test.dart` 的 category membership 组）
- [x] 5.6 运行 `flutter analyze` 与全量测试，确认无回归——`flutter analyze lib/ test/` 零 error；全量 `+976 ~3 -13`，13 个失败经 `git stash` 逐文件单跑比对，基线下同样失败（notebook 编辑器渲染、表格交互、doc_audio 落盘），与本次无关。本次造成的唯一回归（`ops_tool_test` 断言 system）与自埋的端口坑（`local_dictionary_bridge_test` 无参 start 走生产端口 8797）均已修复
- [ ] 5.7 浅色模式下目视复核全部改动点（开关圆饼、NEW 标签、连通胶囊、新分类图标、常用软件入口）

## 6. 部署

- [x] 6.1 运行 `./scripts/deploy_local.sh` 并重新启动应用——两轮部署均成功（AOT 52f3045d→6667bf1b，strict 签名通过，新实例存活、词典桥仍监听 8797）
- [x] 6.2 核对 /Applications 下的新构建签到校验通过、AOT 快照已变化——部署脚本的 verify 阶段已断言 strict 校验与快照哈希变化，两轮均通过
