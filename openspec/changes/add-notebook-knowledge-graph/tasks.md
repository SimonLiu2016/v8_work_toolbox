# Tasks: 笔记本知识星图与 AI 集成

> 四阶段递进。每阶段独立可交付。后阶段依赖前阶段数据沉淀。

## 阶段一：凭证资产 + 到期提醒

### 1.1 数据模型迁移

- [ ] 1.1.1 `lib/tools/notebook/note_database.dart`：`Notes` 表增加可空列 `assetCategory` / `assetPurchaseDate` / `assetServiceUntil` / `assetExpiryDate`；`Attachments` 表加 `isCredential` bool（default false）；schemaVersion +1，写迁移 ALTER TABLE
- [ ] 1.1.2 重新生成 `note_database.g.dart`（`dart run build_runner build`）
- [ ] 1.1.3 `NoteStore` 增加资产字段 CRUD：`updateAssetFields(noteId, {...})`、`assetsDueSoon(days)`、`flagAttachmentCredential(attachmentId, bool)`
- [ ] 1.1.4 单测：迁移后旧笔记资产字段为空、凭证标识默认 false；资产查询能按到期日过滤

### 1.2 资产提醒服务

- [ ] 1.2.1 新建 `lib/tools/notebook/asset_reminder_service.dart`：30s tick 扫描到期日 ≤ now+leadWindow 且未过期且未 dismiss 的资产；复用 `ScheduledNewsService` 的 osascript 通知 + 任务级退避模式
- [ ] 1.2.2 到期前默认 30 天通知；过期后标记 expired 停止提醒；dismiss 进入冷却
- [ ] 1.2.3 在 `main.dart` 启动链注册 `AssetReminderService.instance.init()`，加 PrivacySecurityService 风格的异常守卫（单组件故障不黑屏）
- [ ] 1.2.4 单测：到期资产命中提醒、过期资产不重复提醒、dismiss 冷却

### 1.3 资产 UI

- [ ] 1.3.1 新建 `lib/tools/notebook/ui/asset_fields_panel.dart`：可折叠面板，编辑品类/购买日/服务期/到期日；附件列表勾选"标记为凭证"
- [ ] 1.3.2 笔记列表项：资产笔记显示资产徽章 + 到期倒计时；普通笔记无徽章
- [ ] 1.3.3 笔记编辑页接入资产面板（默认折叠，无资产数据时不干扰编辑面）
- [ ] 1.3.4 手工验证：登记豆浆机 5 年换新资产，到期日设 2029-09-20，列表显示徽章与倒计时

## 阶段二：AI 问答（RAG）

### 2.1 NotebookKbService 检索

- [ ] 2.1.1 新建 `lib/tools/notebook/notebook_kb_service.dart`：`retrieve(query, {limit})` 调 `NoteStore.searchNotes` 取 top-N，Delta 转纯文本片段，返回 `[{noteId, title, snippet}]`
- [ ] 2.1.2 Delta 转纯文本：标题 + 段落文本，丢表格内部；命中在表格内时整条 Delta 转 markdown 喂入
- [ ] 2.1.3 单测：retrieve 命中含关键词的笔记；无匹配返回空列表而非伪造

### 2.2 AI 问答面板

- [ ] 2.2.1 新建 `lib/tools/notebook/ui/notebook_qa_panel.dart`：问答输入 + 回答区 + 引用笔记链接列表
- [ ] 2.2.2 `NotebookKbService.ask(question)`：retrieve → 拼 context → `AiService.chat(slot:'text')` → 回答附引用 noteId
- [ ] 2.2.3 复用 `ai_assistant_service._runAgentLoop` 的正则协议，注入工具集：`notebook_search`（retrieve）、`web_search`、`scrape`
- [ ] 2.2.4 回答中引用笔记链接可点击，定位到对应笔记
- [ ] 2.2.5 无匹配笔记时告知用户"无相关笔记"而非伪造，并提议降级到 web_search
- [ ] 2.2.6 单测：ask 命中凭证笔记时回答引用凭证附件与订单号；无匹配时不伪造

### 2.3 笔记本页接入

- [ ] 2.3.1 笔记本页增加问答面板入口（侧栏按钮或顶部标签）
- [ ] 2.3.2 手工验证：问"豆浆机坏了怎么办"，AI 命中阶段一登记的凭证笔记，回答含服务名 + 凭证定位

## 阶段三：AI 主动整理

### 3.1 关联边存储

- [ ] 3.1.1 `note_database.dart`：新建 `NoteLinks` 表（sourceNoteId / targetNoteId / relation 恒 'related_to' / reason 可空 / createdAt），复合主键 (source, target)；schemaVersion +1 迁移
- [ ] 3.1.2 `NoteStore`：`createLink(sourceId, targetId, reason)`、`linksForNote(noteId)`（WHERE source=? OR target=?）、`deleteLink(...)`；永久删除笔记时级联删关联
- [ ] 3.1.3 单测：存关联、双向查询、级联删除

### 3.2 AI 整理建议

- [ ] 3.2.1 `NotebookKbService.suggestTags(noteId)`：取笔记正文 → `AiService.chat` → 解析建议标签列表（去重已有标签）
- [ ] 3.2.2 `NotebookKbService.suggestLinks(noteId)`：取笔记正文 + 候选笔记标题列表 → `AiService.chat` → 解析建议关联 + reason
- [ ] 3.2.3 单测：建议标签不重复已有；建议关联返回 reason；AI 不直接写库

### 3.3 整理 UI 与确认

- [ ] 3.3.1 笔记详情增加"AI 建议标签"与"AI 建议关联"按钮，弹窗呈现建议，用户勾选确认
- [ ] 3.3.2 仅确认项写入 `NoteStore`（标签）与 `note_links`（关联）；AI 无直接写库权限
- [ ] 3.3.3 单测：拒绝的建议不落库；接受的落库

### 3.4 关联视图

- [ ] 3.4.1 笔记详情显示"关联笔记"区，列标题 + reason，点击跳转
- [ ] 3.4.2 无关联时不显示占位
- [ ] 3.4.3 手工验证：对两条相关笔记调 AI 建议关联，确认后详情互见

## 阶段四：知识星图可视化 + 增强

### 4.1 星图视图

- [ ] 4.1.1 新建 `lib/tools/notebook/ui/knowledge_graph_view.dart`：CustomPaint 渲染节点-边，选中笔记高亮 + 邻域强调
- [ ] 4.1.2 笔记本页增加星图入口
- [ ] 4.1.3 节点点击跳转到对应笔记

### 4.2 多跳遍历

- [ ] 4.2.1 `NotebookKbService.traverse(noteId, hops)`：应用层 BFS 遍历 `note_links`，返回路径
- [ ] 4.2.2 AI 问答升级：回答可走星图路径，答案附遍历路径供用户检视每个 hop
- [ ] 4.2.3 单测：traverse 多跳路径正确；环路不无限循环

### 4.3 收尾

- [ ] 4.3.1 手工验证：星图视图展示节点-边；AI 问答能走多跳路径回答
- [ ] 4.3.2 全量回归：`flutter test`，确认无新增失败
