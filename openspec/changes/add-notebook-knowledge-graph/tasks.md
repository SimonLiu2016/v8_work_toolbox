# Tasks: 笔记本知识星图与 AI 集成

> 四阶段递进。每阶段独立可交付。后阶段依赖前阶段数据沉淀。

## 阶段一：凭证资产 + 到期提醒

### 1.1 数据模型迁移

- [x] 1.1.1 `lib/tools/notebook/note_database.dart`：`Notes` 表增加可空列 `assetCategory` / `assetPurchaseDate` / `assetServiceUntil` / `assetExpiryDate`；`Attachments` 表加 `isCredential` bool（default false）；schemaVersion +1，写迁移 ALTER TABLE
- [x] 1.1.2 重新生成 `note_database.g.dart`（`dart run build_runner build`）
- [x] 1.1.3 `NoteStore` 增加资产字段 CRUD：`updateAssetFields(noteId, {...})`、`assetsDueSoon(days)`、`flagAttachmentCredential(attachmentId, bool)`
- [x] 1.1.4 单测：迁移后旧笔记资产字段为空、凭证标识默认 false；资产查询能按到期日过滤

### 1.2 资产提醒服务

- [x] 1.2.1 新建 `lib/tools/notebook/asset_reminder_service.dart`：30s tick 扫描到期日 ≤ now+leadWindow 且未过期且未 dismiss 的资产；复用 `ScheduledNewsService` 的 osascript 通知 + 任务级退避模式
- [x] 1.2.2 到期前默认 30 天通知；过期后标记 expired 停止提醒；dismiss 进入冷却
- [x] 1.2.3 在 `main.dart` 启动链注册 `AssetReminderService.instance.init()`，加 PrivacySecurityService 风格的异常守卫（单组件故障不黑屏）
- [x] 1.2.4 单测：到期资产命中提醒、过期资产不重复提醒、dismiss 冷却

### 1.3 资产 UI

- [x] 1.3.1 新建 `lib/tools/notebook/ui/asset_fields_panel.dart`：可折叠面板，编辑品类/购买日/服务期/到期日；附件列表勾选"标记为凭证"
- [x] 1.3.2 笔记列表项：资产笔记显示资产徽章 + 到期倒计时；普通笔记无徽章
- [x] 1.3.3 笔记编辑页接入资产面板（默认折叠，无资产数据时不干扰编辑面）
- [ ] 1.3.4 手工验证：登记豆浆机 5 年换新资产，到期日设 2029-09-20，列表显示徽章与倒计时

## 阶段二：AI 问答（RAG）

### 2.0 前置：中文分词修复（必须先于 2.1，否则 retrieve 哑火）

实测：现有 `notes_fts` 用默认 `unicode61`，整串连续中文被当作单个 token，`MATCH '豆浆机'`/`'延保'`/`'保险'` 全部返回空。分词方案见 design D4。

- [x] 2.0.1 新建中文 bigram 分词工具（如 `lib/tools/notebook/cjk_tokenizer.dart`）：CJK 连续段切重叠双字，ASCII 词原样保留，标点丢弃；提供 `tokenize(text)` 与 `toFtsQuery(text)`（OR 拼接）
- [x] 2.0.2 `note_database.dart` 的 `indexNote` 写入前对 title/content 做 bigram 化
- [x] 2.0.3 `note_database.dart` 的 `searchNotes` 查询前对 query 做 bigram 化，`MATCH` 表达式用 OR 拼接，`ORDER BY bm25(notes_fts)`
- [x] 2.0.4 一次性 FTS 索引重建：升级时 `DELETE FROM notes_fts` 后从 `notes` 表重灌（派生数据，可安全重建）。放 schema 迁移或 `beforeOpen`
- [x] 2.0.5 单测：两字词（`延保`/`保险`）命中、三字词（`豆浆机`）命中、自然语言问句（`豆浆机坏了怎么办`）命中正确笔记且排首位、不相关词返回空、ASCII（`ABC123`）不回归
- [x] 2.0.6 单测：索引重建后旧笔记可被新分词方式搜到

### 2.1 NotebookKbService 检索

- [x] 2.1.1 新建 `lib/tools/notebook/notebook_kb_service.dart`：`retrieve(query, {limit})` 调 `NoteStore.searchNotes` 取 top-N，Delta 转纯文本片段，返回 `[{noteId, title, snippet}]`
- [x] 2.1.2 Delta 转纯文本：标题 + 段落文本，丢表格内部；命中在表格内时整条 Delta 转 markdown 喂入
- [x] 2.1.3 单测：retrieve 命中含关键词的笔记；无匹配返回空列表而非伪造

### 2.2 AI 问答面板

- [x] 2.2.0 前置重构：把 `AiAssistantService._runAgentLoop` 提取为共享组件（如 `lib/services/agent_loop.dart`），接受工具定义 + 工具执行回调；`AiAssistantService` 改为使用该组件并注入自己的工具集，行为不变（见 design D6）
- [x] 2.2.1 新建 `lib/tools/notebook/ui/notebook_qa_panel.dart`：问答输入 + 回答区 + 引用笔记链接列表
- [x] 2.2.2 `NotebookKbService.ask(question)`：retrieve → 拼 context → `AiService.chat(slot:'text')` → 回答附引用 noteId
- [x] 2.2.3 经 2.2.0 的共享 agent loop 注入工具集：`notebook_search`（retrieve）、`web_search`、`scrape`
- [x] 2.2.4 回答中引用笔记链接可点击，定位到对应笔记
- [x] 2.2.5 无匹配笔记时告知用户"无相关笔记"而非伪造，并提议降级到 web_search
- [x] 2.2.6 单测：ask 命中凭证笔记时回答引用凭证附件与订单号；无匹配时不伪造

### 2.3 笔记本页接入

- [x] 2.3.1 笔记本页增加问答面板入口（侧栏按钮或顶部标签）
- [ ] 2.3.2 手工验证：问"豆浆机坏了怎么办"，AI 命中阶段一登记的凭证笔记，回答含服务名 + 凭证定位


## 阶段三：AI 主动整理

### 3.1 关联边存储

- [x] 3.1.1 `note_database.dart`：新建 `NoteLinks` 表（sourceNoteId / targetNoteId / relation 恒 'related_to' / reason 可空 / createdAt），复合主键 (source, target)；schemaVersion +1 迁移
- [x] 3.1.2 `NoteStore`：`createLink(sourceId, targetId, reason)`、`linksForNote(noteId)`（WHERE source=? OR target=?）、`deleteLink(...)`；永久删除笔记时级联删关联
- [x] 3.1.3 单测：存关联、双向查询、级联删除

### 3.2 AI 整理建议

- [x] 3.2.1 `NotebookKbService.suggestTags(noteId)`：取笔记正文 → `AiService.chat` → 解析建议标签列表（去重已有标签）
- [x] 3.2.2 `NotebookKbService.suggestLinks(noteId)`：取笔记正文 + 候选笔记标题列表 → `AiService.chat` → 解析建议关联 + reason
- [x] 3.2.3 单测：建议标签不重复已有；建议关联返回 reason；AI 不直接写库

### 3.3 整理 UI 与确认

- [x] 3.3.1 笔记详情增加"AI 建议标签"与"AI 建议关联"按钮，弹窗呈现建议，用户勾选确认
- [x] 3.3.2 仅确认项写入 `NoteStore`（标签）与 `note_links`（关联）；AI 无直接写库权限
- [x] 3.3.3 单测：拒绝的建议不落库；接受的落库

### 3.4 关联视图

- [x] 3.4.1 笔记详情显示"关联笔记"区，列标题 + reason，点击跳转
- [x] 3.4.2 无关联时不显示占位
- [ ] 3.4.3 手工验证：对两条相关笔记调 AI 建议关联，确认后详情互见

## 阶段四：知识星图可视化 + 增强

### 4.1 星图视图

- [x] 4.1.1 新建 `lib/tools/notebook/ui/knowledge_graph_view.dart`：CustomPaint 渲染节点-边，选中笔记高亮 + 邻域强调
- [x] 4.1.2 笔记本页增加星图入口
- [x] 4.1.3 节点点击跳转到对应笔记

### 4.2 多跳遍历

- [x] 4.2.1 `NotebookKbService.traverse(noteId, hops)`：应用层 BFS 遍历 `note_links`，返回路径
- [x] 4.2.2 AI 问答升级：回答可走星图路径，答案附遍历路径供用户检视每个 hop
- [x] 4.2.3 单测：traverse 多跳路径正确；环路不无限循环

### 4.3 收尾

- [ ] 4.3.1 手工验证：星图视图展示节点-边；AI 问答能走多跳路径回答
- [x] 4.3.2 全量回归：`flutter test`，确认无新增失败
