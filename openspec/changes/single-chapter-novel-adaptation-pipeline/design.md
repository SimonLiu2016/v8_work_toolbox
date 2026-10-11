## Context

当前单章小说导入链路直接取 `novelContent.substring(0, 480)` 作为单集粗大纲（`synopsis`），导致原著情节后半段严重丢失。详见 `proposal.md`。

## Goals / Non-Goals

**Goals:**
- 实现单章小说全量文本输入下的短剧单集影视大纲科学提炼（`novelChapterAdaptation`）。
- 保证生成的影视大纲在 300~500 字之间，严谨覆盖【开局抓手】、【矛盾推进】、【核心高潮】与【末尾留钩】四大视听要素。
- 在 `IdeaIncubatorPanel` 导入流程中无缝串联：Pass 1 增量提炼 IP 资产 → Pass 2 全文单章剧本大纲转化，并向用户提供清晰的阶段耗时与状态反馈。
- 分镜看板基于提炼出的全章影视大纲，拆分出覆盖全篇情节的 8~16 镜镜头序列。

**Non-Goals:**
- 不在此变更中修改长篇全案多集解构流程（全案解构已有独立的 `segmentNovelEpisodes` 规划器）。
- 不破坏原有的角色卡锚点图与定制 Prompt 保护逻辑。

## Decisions

### 决策 1：新增专用的 `novelChapterAdaptation` 结构化 AI 任务
- **动机**：全案解构的 `segmentNovelEpisodes` 面向全本 8~20 集规划，输出偏简短概括；而单章导入需要深度聚焦这一章的细致情节，提炼出能直接用于拍剧的 300~500 字紧凑大纲。
- **Schema 设计**：
  ```json
  {
    "title": "短剧单集标题（10字以内）",
    "synopsis": "本集影视化完整粗大纲（300~500字，覆盖开局冲突、矛盾升级、高潮爆发、末尾悬念）",
    "summary": "本集精炼前情摘要（150字以内，供后续跨集记忆）",
    "hook": "本集末尾悬念钩子（50字以内）"
  }
  ```
- **备选方案**：
  - *备选 A：直接将数千字小说原文填入 synopsis*。缺点：小说原文多为文学描写与冗长对话，填入大纲框后过于杂乱，且下游拆镜容易迷失在细碎文字中。
  - *备选 B：复用全案分集模板*。缺点：全案模板要求输出 episodes 数组和推荐总集数，输入单章时容易产生多集幻觉或多余字段。

### 决策 2：导入流程双阶段串联与透明进度
- **流程设计**：
  1. Pass 1: `extractNovelMaster` 提炼本章新角色、新场景与世界观规则，增量入库；
  2. Pass 2: `adaptNovelChapter` 携带小说全文、已有世界观与核心角色名，提炼结构化单集影视大纲；
  3. 调用 `importChapterToEpisode` 写入目标集，并自动将剧情摘要与悬念注入跨集记忆库；
  4. 进度条显示：`正在深入分析本章全篇情节，提炼起承转合影视剧本大纲… [已耗时 Xs]`。

## Risks / Trade-offs

- **[Risk] 长小说章节（如超 8000 字）导致大模型响应超时** → 
  *Mitigation*: 为 `novelChapterAdaptation` 配置 240 秒自适应超时映射，与 `novelMasterExtract` 保持同等的重任务保护级别。
- **[Risk] AI 输出的 synopsis 依然过于简略或丢失高潮** → 
  *Mitigation*: 在 System Prompt 中注入明确硬约束与 Example，强制要求必须标注【开局抓手】、【矛盾推进】、【核心高潮】、【本集断点】四大环节，字数不足 200 字触发 schema 校验重试。
