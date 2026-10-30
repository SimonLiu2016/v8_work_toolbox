# Proposal: 笔记本知识星图与 AI 集成

## 背景与动机

笔记本工具当前具备块状富文本编辑（appflowy）、SQLite 持久化（Notebooks/Notes/Tags/NoteTags/Attachments）、FTS5 全文搜索与多格式导入。但笔记之间是孤岛——没有结构化关联，没有面向知识库的 AI 问答，用户无法"问 AI 我买过的延保服务"这类问题。

同期，应用刚建成的 AI 基础设施（`AiService` 对话、`WebSearchService` 联网检索与抓取、定时检索 + 通知模式）目前只服务独立的「AI 助手」聊天窗，**未接入笔记本**。

典型场景：用户在京东买豆浆机时花 24 元买了 5 年换新服务。三年后豆浆机坏了，用户既想不起买过此服务，平台入口也找不到。需要：现在把服务内容/截图/订单号存进笔记本；到期前能被提醒；坏了时问 AI 能命中凭证并指引用户换新。

## 解决方案

笔记本演进为**知识 + 资产双形态**，分四阶段闭环递进：

1. **凭证资产 + 到期提醒** — 给 `Notes` 表加可选资产列（品类/购买日/服务期/到期日），凭证走现有 Attachments；定时扫描到期日 + 系统通知。
2. **AI 问答（RAG）** — `NotebookKbService.retrieve`：FTS 命中笔记取片段拼上下文，复用 `AiService` agent loop；笔记内问答面板，回答附引用笔记链接。
3. **AI 主动整理** — `autoTag` 给普通笔记建议标签；`autoLink` 建议笔记间泛化关联（`note_links` 表，泛化 `related_to` 关系类型）；用户确认后写入，AI 不静默改库。
4. **知识星图可视化 + 增强** — 关联边表多跳遍历；星图节点-边可视化；AI 问答升级为星图推理。

## 能力（Capabilities）

**新增**
- `notebook-knowledge` — 笔记本知识库与 AI 集成：凭证资产登记、RAG 问答、AI 主动整理、关联星图。

**变更**
- `notebook-storage` — `Notes` 表增加可选资产列；新增 `note_links` 关联边表。
- `notebook-editor` — 资产字段编辑入口与关联视图（笔记详情显示关联）。

## 影响范围

- **新文件**：`lib/tools/notebook/notebook_kb_service.dart`（检索/问答/整理编排）、`lib/tools/notebook/ui/notebook_qa_panel.dart`、`lib/tools/notebook/ui/asset_fields_panel.dart`、`lib/tools/notebook/ui/knowledge_graph_view.dart`
- **修改**：`lib/tools/notebook/note_database.dart`（Notes 加列 + note_links 表 + 迁移）、`lib/tools/notebook/note_store.dart`（资产/关联 CRUD）、笔记本页 UI（问答面板入口、资产徽章、星图入口）
- **复用**：`lib/services/ai_service.dart`、`lib/services/web_search_service.dart`、`ScheduledNewsService` 的定时器+通知模式
- **无新增依赖**：FTS5、drift、appflowy 均已在 pubspec

## 非目标

- **不做显式节点-边本体**。关联边为泛化 `related_to`，不预定义关系类型（凭证/配件/同订单等）。关系语义由 AI 整理时在边的 `reason` 字段自由描述，不强制 schema。这是用户明确选择"泛化"的结果。
- **不做多用户/云端同步**。知识库仍为本地单用户。
- **不替换 FTS 为向量检索**。阶段二 RAG 用现有 FTS5 + LLM 重排，不引入嵌入向量库。向量检索作为未来演进，不在此范围。
- **不改 appflowy 编辑器内核**。资产字段与关联视图是编辑器外的面板，不侵入 appflowy 的块树。

## 分阶段交付

四阶段各自独立可交付，后阶段依赖前阶段的数据沉淀：

- 阶段一（凭证资产 + 到期提醒）：解决"登记 + 提醒"，不依赖 AI。
- 阶段二（AI 问答 RAG）：依赖阶段一的结构化资产字段做可靠命中；复用已建的 `AiService` + `WebSearchService`。
- 阶段三（AI 主动整理）：依赖阶段二已上线的问答能力做"整理建议"；产出关联边喂给阶段四。
- 阶段四（星图可视化 + 推理）：依赖阶段三的 `note_links` 数据；可视化与多跳遍历。

## 成功判据

1. 用户可把"5 年换新"服务连同截图、订单号登成资产笔记，设到期日 2029-09-20。
2. 到期前 30 天收到 macOS 系统通知，附资产标题与凭证定位。
3. 笔记本内问"豆浆机坏了怎么办"，AI 命中凭证笔记并回答"你有 5 年换新服务，凭证见附件 X，订单号 Y"，回答附引用笔记链接。
4. AI 能对普通笔记建议标签与关联，用户确认后写入；关联在笔记详情可见。
5. 星图视图能展示笔记节点与关联边，支持多跳遍历。
