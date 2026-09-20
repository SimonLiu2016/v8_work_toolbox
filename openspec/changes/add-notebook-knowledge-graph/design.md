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
- 不做向量嵌入检索（留作未来；FTS5 + bigram + LLM 重排够用）。
- 不预定义关系类型（泛化 `related_to`，reason 自由文本承载语义）。
- 不双写关联边（单行存，查询时反向匹配）。
- 不动 appflowy 块树（资产/关联是编辑器外面板）。
- 不引入外部检索工具或守护进程（见下）。

### 已评估并否决：外部检索工具 zvec-grep (zg)

探索阶段评估过用本机已装的 `zvec-grep` 作为 RAG 后端，**否决**。理由：

- **数据源错配**：zg 索引的是工作区根下的**文件**，而笔记在 SQLite 的 Quill Delta JSON 里。接入需先把笔记物化成文件副本，引入冗余明文副本 + 每次编辑的同步开销 + 常驻守护进程。
- **切块错配**：zg 按代码实体（函数/类/符号）切块，笔记是散文。
- **依赖耦合**：zg 是用户内部 harness 的依赖，引入为桌面 app 依赖会把两者的稳定性要求混在一起（harness 挂了自行重启，app 挂了用户黑屏）。
- **隔离语义不满足安全边界**：zg 的索引数据确实按工作区物理隔离（`<root>/.zvec-grep/`，0700），远端嵌入授权也是每工作区签名 grant；但守护进程是共享单进程、loopback 默认无认证，**不是安全边界**，凭证与模型缓存全局共享。

保留此记录以免重复评估。

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

### D4: RAG 检索 = 中文 bigram 分词 + FTS + LLM 重排

`retrieve` 三步：FTS5 `MATCH` 取 top-N（默认 5）笔记 → 每条笔记的 Delta 转纯文本片段 → 片段拼进 system prompt 让 LLM 重排选最相关。不做向量嵌入。

**前置约束（实测发现）**：现有 `notes_fts` 用默认 `unicode61` tokenizer，把整串连续中文当作**单个 token**，导致中文检索基本失效——实测 `MATCH '豆浆机'` / `'延保'` / `'保险'` 全部返回空，只有与整串完全相等（如标题 `豆浆机延保`）才命中。阶段二的 `retrieve` 若直接照原 D4 实现会返回零结果。

**选定：应用层 bigram 分词**。索引时把 CJK 连续段切成重叠双字（`我买了豆浆机` → `我买 买了 了豆 豆浆 浆机`）以空格分隔写入 FTS5；查询时同样 bigram 化，用 OR 拼接 + `bm25()` 排序（命中 bigram 越多分越高）。纯 Dart ~20 行，无新依赖。

**实测三方案对比**：

| 方案 | 3字查询 | 2字查询 | ASCII | 依赖 |
|---|---|---|---|---|
| 现状 `unicode61` | ❌ | ❌ | ✅ | 无 |
| `trigram` tokenizer | ✅ | ❌ | ✅ | 无 |
| **bigram + OR** | ✅ | ✅ | ✅ | 无 |

**为何否掉 `trigram`**：trigram 要求查询 ≥3 字符，实测 `延保`/`保险`/`换新`/`保单`/`车险` 全部返回空。中文词大量是两字，而这恰是资产/凭证场景的核心词（"延保""保险""保修""会员"）。trigram 在这个领域不可用。

**为何不用分词器（jieba 类）**：引入词典依赖与体积，且个人笔记的专有名词（品牌、型号）词典覆盖不到，bigram 无词典假设反而更稳。

**bigram 的已知代价**：索引体积约为原始文本 2 倍（每个字出现在最多 2 个 bigram 中）；OR 召回可能带来噪声，由后续 LLM 重排消解。接受。

**重建索引**：`notes_fts` 是派生数据，切换分词方案后必须重建（`DELETE` 全表 → 从 `notes` 表重灌），否则已有笔记的旧索引仍是未分词原始文本，搜不到。这是一次性迁移动作，放在 schema 迁移或 `beforeOpen` 中。

### D4b: 召回策略 = OR 优先，不做 AND 两段式

查询 bigram 以 OR 拼接，靠 `bm25()` 排序把命中多的笔记排前。不做"AND 精确优先 → OR 兜底"的两段式。

**为什么**：个人知识库规模小（千条以内），单次 OR 查询 + bm25 排序已能正确区分相关度——实测 `豆浆机坏了怎么办` 命中 `n1` 排首位，`不存在的词` 返回空（无误召回）。两段式增加查询复杂度与两次往返，收益不明显。若未来语料变大导致 OR 噪声显著，再引入 AND 前置。

### D5: 到期提醒复用 ScheduledNewsService 模式

新建 `AssetReminderService`，复用 `ScheduledNewsService` 的 30s tick + macOS `osascript` 通知 + 任务级退避模式，但扫描对象是资产笔记的 `assetExpiryDate`。不复用 ScheduledNewsService 实例（它的领域是检索任务）。

**为什么**：定时器+通知模式已被验证（刚做完的 DEK/检索定时任务），但扫描领域不同（资产 vs 资讯任务）。独立服务避免领域耦合。

### D6: AI 问答面板复用 agent loop（需先提取为共享组件）

笔记本内问答面板复用现有的正则 ```tool_call 循环，但工具集不同：
- `notebook_search`（NotebookKbService.retrieve）
- `web_search`（WebSearchService.search，已有）
- `scrape`（WebSearchService.scrape，已有）

**前置重构（实测发现）**：`_runAgentLoop` 当前是 `AiAssistantService` 的**私有方法**（下划线前缀），且硬编码了自己的工具执行逻辑，跨文件不可复用。需先提取为独立可共享组件（如 `lib/services/agent_loop.dart` 的 `AgentLoop`，接受工具定义 + 工具执行回调 + 消息历史），再由 `AiAssistantService` 与 `NotebookKbService` 各自注入自己的工具集。

**为什么**：不重造 agent loop，也不把笔记本逻辑写进 AI 助手的服务里。提取后职责清晰：循环负责"调 LLM → 解析 tool_call → 执行工具 → 回灌结果 → 再调"，工具集由调用方提供。正则协议本身保持"不改"（非目标），只是把它从私有提升为共享。

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
- ~~向量检索 vs FTS+重排？~~ → FTS+bigram+重排，向量留未来（D4，非目标）。
- ~~中文分词用 trigram 还是 bigram？~~ → bigram（D4，trigram 实测两字词全失效）。
- ~~召回用 AND 两段式还是 OR？~~ → OR + bm25（D4b）。
- ~~用外部工具 zvec-grep 做检索？~~ → 否决（见非目标，数据源/切块/依赖/隔离四重错配）。
