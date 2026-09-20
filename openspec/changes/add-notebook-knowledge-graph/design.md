# Design: 笔记本知识星图与 AI 集成

## Context

现有数据模型（`note_database.dart`，drift）：
- `Notes`：id / title / deltaJson / notebookId / isPinned / isDeleted / createdAt / updatedAt
- `Attachments`：id / noteId / filename / mime / localPath / createdAt
- `NoteTags`：noteId / tagId（多对多）
- FTS5 虚拟表 `notes_fts`：title / content / note_id，已有 `searchNotes(query)` 用 `MATCH` + `rank`

现有 AI 基础设施（刚建，未接笔记本）：
- `AiService.chat(slot, messages)` — OpenAI/Anthropic/Gemini 多协议，有候选路由与冷却
- `WebSearchService.search/scrape` — 后端链降级
- `ScheduledNewsService` — 30s tick 定时器 + macOS `osascript` 通知 + 任务级退避
- `ai_assistant_service._runAgentLoop` — 正则抠 ```tool_call 代码块的 agent 循环，`maxIterations=3`

约束：
- 用户选择"加可选列到 Notes"而非新建 `note_assets` 表。
- 用户选择"泛化 related_to"而非预定义关系类型。
- 不引入向量嵌入；RAG 用 FTS5 + LLM 重排。

## Goals / Non-Goals

见 proposal。设计层补充：

**Goals**
- `NotebookKbService` 作为薄编排层，复用现有 `AiService`/`WebSearchService`/定时器模式，不重造。
- 资产字段在 `Notes` 表加可选列，drift schema 迁移，普通笔记零负担。
- 关联边 `note_links` 表，单 source/target 对 + reason，双向可见通过查询（不双写）。

**Non-Goals**
- 不做向量嵌入检索（留作未来；FTS5 + LLM 重排够用）。
- 不预定义关系类型（泛化 `related_to`，reason 自由文本承载语义）。
- 不双写关联边（单行存，查询时反向匹配）。
- 不动 appflowy 块树（资产/关联是编辑器外面板）。

## Decisions

### D1: 资产字段加到 Notes 表（用户选定 A）

`Notes` 增加可空列：`assetCategory` / `assetPurchaseDate` / `assetServiceUntil` / `assetExpiryDate`。drift `schemaVersion` +1，迁移 `ALTER TABLE notes ADD COLUMN ...`。

**为什么**：用户选 A。查询到期资产单表即可，无 JOIN；普通笔记这些列为空，零负担。`note_assets` 1:1 表更干净但多一层 JOIN 且对单用户无收益。

**凭证标识**：`Attachments` 加 `isCredential` bool 列（default false），而非新建表。一个资产可有多个凭证。

### D2: 关联边泛化 related_to（用户选定 B）

新建 `NoteLinks` 表：`sourceNoteId` / `targetNoteId` / `relation`（恒为 `'related_to'`）/ `reason`（可空自由文本）/ `createdAt`。复合主键 (source, target)。查询某笔记关联时 `WHERE source=? OR target=?`。

**为什么**：用户选泛化。预定义关系类型会让 AI 整理时被迫分类，泛化让 reason 自由承载语义，schema 简单。`relation` 列恒为 `related_to` 保留，是为了将来若决定引入类型时可平滑扩展（不破坏行）。

### D3: NotebookKbService 作为薄编排层

新 `lib/tools/notebook/notebook_kb_service.dart`，方法：
- `retrieve(query, {limit})` — FTS 检索笔记片段，返回带 noteId/title/snippet 的列表
- `ask(question)` — retrieve + 拼 context + AiService.chat + 回答附引用
- `assetsDueSoon(days)` — 查询到期日 ≤ now+days 且未过期且未 dismiss 的资产
- `suggestTags(noteId)` — 取笔记正文 → AiService.chat → 解析建议标签
- `suggestLinks(noteId)` — 取笔记正文 + 候选笔记标题列表 → AiService.chat → 解析建议关联

**为什么**：编排而非新存储。所有持久化仍走 `NoteStore`；AI 调用走 `AiService`；联网走 `WebSearchService`。NotebookKbService 不持有自己的状态机。

### D4: RAG 检索 = FTS + LLM 重排

`retrieve` 第一步 FTS5 `MATCH` 取 top-N（默认 5）笔记；第二步把每条笔记的 Delta 转纯文本片段；第三步把片段拼进 system prompt 让 LLM 重排并选最相关。不做向量嵌入。

**为什么**：用户明确不引入向量库。FTS + LLM 重排在个人知识库规模（千条以内）足够准，且复用现有 FTS5。向量检索留作未来演进。

### D5: 到期提醒复用 ScheduledNewsService 模式

新建 `AssetReminderService`，复用 `ScheduledNewsService` 的 30s tick + macOS `osascript` 通知 + 任务级退避模式，但扫描对象是资产笔记的 `assetExpiryDate`。不复用 ScheduledNewsService 实例（它的领域是检索任务）。

**为什么**：定时器+通知模式已被验证（刚做完的 DEK/检索定时任务），但扫描领域不同（资产 vs 资讯任务）。独立服务避免领域耦合。

### D6: AI 问答面板复用 agent loop

笔记本内问答面板复用 `ai_assistant_service._runAgentLoop` 的正则 ```tool_call 模式，但工具集不同：
- `notebook_search`（NotebookKbService.retrieve）
- `web_search`（WebSearchService.search，已有）
- `scrape`（WebSearchService.scrape，已有）

**为什么**：不重造 agent loop。`_runAgentLoop` 的正则协议是非目标"不改"，但工具定义可注入——笔记本面板传入自己的工具集，循环逻辑共享。

### D7: AI 整理不静默改库

`suggestTags` / `suggestLinks` 只返回建议，UI 呈现确认弹窗，用户点接受才走 `NoteStore.createTag` / 写 `note_links`。AI 无直接写库权限。

**为什么**：知识图谱的正确性依赖人审。AI 静默建图会累积错误关联，污染后续推理。

### D8: 星图视图用自绘 Canvas/SVG

阶段四 `knowledge_graph_view.dart` 用 Flutter CustomPaint 或 graphview 包渲染节点-边。多跳遍历查询：递归 CTE 或应用层 BFS。

**为什么**：不引入重型图库。节点数（笔记数）个人规模，CustomPaint 够。多跳遍历用应用层 BFS 而非递归 CTE，避免 SQLite 递归 CTE 的可读性与调试负担。

## Risks / Trade-offs

**[Delta 转纯文本的损耗]** → appflowy Delta 含表格/代码块，转纯文本做 RAG 会丢结构。
缓解：只取标题 + 段落文本，丢表格内部；若检索命中关键片段在表格内，用 LLM 重排时把整条 Delta 转 markdown 喂入而非纯文本。

**[泛化 related_to 的查询语义弱]** → 所有关系都是 related_to，多跳推理时 AI 难判断"这是凭证关系还是同订单关系"。
缓解：`reason` 字段自由文本在 LLM 重排时作为上下文；AI 推理时把 reason 一起喂入。接受：用户选泛化，语义由 reason 承载，这是取舍。

**[AI 整理的成本]** → 对每条笔记调 LLM 建议标签/关联，token 消耗与延迟。
缓解：用户主动触发（非后台自动），且分批（一次最多 N 条）。不做后台静默整理。

**[到期提醒的准确性]** → 用户填的到期日可能不准（凭主观）。
缓解：UI 在资产面板提示"以服务条款为准"；提醒是辅助非契约。

## Migration Plan

四阶段递进，每阶段独立可交付：

**阶段一**：`Notes`/`Attachments` schema 加列迁移；`NoteStore` 资产 CRUD；`AssetReminderService`；UI 资产面板 + 徽章。无 AI 依赖。

**阶段二**：`NotebookKbService.retrieve` + `ask`；笔记内问答面板；复用 agent loop 注入 `notebook_search` 工具。依赖阶段一的资产字段做可靠凭证命中。

**阶段三**：`note_links` 表迁移；`NoteStore` 关联 CRUD；`suggestTags`/`suggestLinks`；确认 UI；笔记详情关联视图。依赖阶段二已上线问答做"整理建议"。

**阶段四**：星图视图；多跳 BFS 遍历；AI 问答升级星图推理。依赖阶段三的 `note_links` 数据。

**回滚**：每阶段独立。阶段一回滚 = schema 加列保留（空列无害），移除资产面板。后续阶段类似。

## Open Questions

无。用户已定 A（加列）与 B（泛化）。以下看似待决、实际已关闭：

- ~~资产字段加列 vs 关联表？~~ → 加列（D1）。
- ~~关系类型预定义 vs 泛化？~~ → 泛化 related_to（D2）。
- ~~向量检索 vs FTS+重排？~~ → FTS+重排，向量留未来（D4，非目标）。
