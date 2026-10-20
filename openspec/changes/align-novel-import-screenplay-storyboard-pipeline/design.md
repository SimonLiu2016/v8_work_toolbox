## Context

参见 `proposal.md`。当前代码库在小说单章导入（`NovelImportTaskService._run`）中调用 `AiConstraintEngine.adaptNovelDramaChapter`，只提取了粗略的 `scenes` 骨架并将对白塞进独立的 `protected_contract`，而 `StudioProjectManager.importChapterToEpisode` 构造 `StudioEpisode` 时漏掉了 `screenplayText`，并且保留了已有集数的旧 `shots`（`existingTarget?.shots ?? const []`）。在导入完成时，`IdeaIncubatorPanel` 仅跳转到 `StudioStage.series`，未将新写入的目标集选入 `session.episode`。导致用户切换到剧本工作台时无内容，而切换到分镜看板时因自动抢占第一集并展示陈旧旧分镜，造成严重的因果混乱。

## Goals / Non-Goals

**Goals:**
- 实现小说单章导入到剧本工作台的数据无缝流转：自动生成分场文学剧本（Markdown `screenplayText`）及带台词、说话人、潜台词的结构化节拍（`DramaBeat`）。
- 在单章导入更新指定集时，重置旧分镜（`shots: []`），防止旧镜号与新剧情串台。
- 导入完成后自动选中该集，并无缝切入「剧本工作台」供用户审阅与打磨。
- 分镜看板增加空状态剧本引导卡，强化分镜从剧本派生的正确认知。

**Non-Goals:**
- 不重构全季多集规划（`importNovelProject`）的基础存储格式（全季规划为跨集大纲架构，单章细化依旧交由单章导入或单集扩写）。
- 不破坏现有通过剧本工作台一键生成 5D 分镜看板（`_convertToStoryboard`）的成熟逻辑。

## Decisions

### 决策 1：升级 `adaptNovelDramaChapter` 的 Prompt 与 Schema，统一节拍对白结构
- **背景**：`_promptNovelDramaChapterAdaptation` 提炼的 beats 缺少 `dialogue_speaker`、`dialogue`、`subtext` 等关键字段，而 `ScreenplayPanel` 渲染与微动作检测严重依赖这些字段。
- **决定**：让 `novelDramaChapterAdaptation` 的输出 Schema 中的 `beats` 显式包含：
  - `name`: 动作节拍主题
  - `action`: 聚焦单动词的微动作描述（20~50字）
  - `dialogue_speaker`: 说话人角色名
  - `dialogue`: 角色台词（含预估秒数）
  - `subtext`: 潜台词与内心戏口吻
  - `estimated_sec`: 预估时长
- **剧本文本生成**：同时要求模型输出 `screenplay_text`（符合影视文学剧本规范的 Markdown 文本），或者由流水线根据提炼的 `scenes` 与 `beats` 自动拼接为标准 Markdown 剧本存入 `screenplayText`。

### 决策 2：`importChapterToEpisode` 完整持久化并重置目标集分镜
- **背景**：若目标集（如第 1 集）之前有过分镜测试，重新导入原著时若保留 `shots: existingTarget?.shots`，会导致“小说换了，分镜还是旧的”。
- **决定**：在 `importChapterToEpisode` 中：
  ```dart
  shots: const [], // 单章重新导入时，重置分镜列表，分镜必须后续由打磨后的剧本重新生成
  screenplayText: screenplayText,
  ```
  这样用户导入小说后，分镜看板处于合法的空状态，等待用户在剧本工作台审阅无误后点击生成。

### 决策 3：导入终态回调自动注入 `session.selectEpisode` 并跳转「剧本工作台」
- **背景**：导入完成后原本调用 `widget.onConfirmed()` 跳转到 `StudioStage.series`（IP 主库），且 `session.episode` 保持为 `null`。
- **决定**：
  1. `NovelImportTaskService._finish` 后，在 `IdeaIncubatorPanel` 的任务完成回调中，读取刚导入的目标集 `StudioEpisode`。
  2. 调用 `widget.session.selectEpisode(targetEpisode)`，使当前集立即可用。
  3. 外壳导航将页面直接跳转至 `StudioStage.screenplay`（剧本工作台），并弹出气泡提示：“小说第一章剧本与分场已就绪，请审阅对白与微动作”。

### 决策 4：分镜看板空状态强化剧本转换指引
- **背景**：当分镜为空时，分镜看板如果仅显示生硬的大纲输入框，用户可能会习惯性再次点击“AI 拆分分镜”，导致再次绕过剧本工作台。
- **决定**：在 `StoryboardBoard` 中，若检测到 `_episode?.scenes.isNotEmpty == true` 且 `_episode?.shots.isEmpty == true` 时，在看板中央展示醒目的卡片：“本集已具备影视分场文学剧本（共 N 场）”，并提供主按钮【前往剧本工作台审阅】和【直接根据剧本生成 5D 分镜】。

## Risks / Trade-offs

- **[Risk 1] AI 单次调用输出 JSON 长度增加导致超时**
  - *缓解*：单章影视化提炼已配置 240s 充足超时；限制场次为 2~4 场，每场 2~4 个节拍，聚焦核心冲突。
- **[Risk 2] 用户原有的测试分镜被重置**
  - *缓解*：小说单章导入属于整集结构重建行为，原有分镜若与新小说正文不匹配，保留旧分镜只会导致更大的逻辑混乱与音画脱节。重置分镜符合短剧工业制作生命周期。
