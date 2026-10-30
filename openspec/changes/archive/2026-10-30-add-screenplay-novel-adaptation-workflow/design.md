## Context

参见 `proposal.md`。当前 `ScreenplayPanel` 中无论是顶部工具栏的「AI 生成剧本」还是中央空白态的「根据大纲一键 AI 生成剧本」，均统一调用 `_generateScreenplayWithAi`，其剧情输入仅为当前集 100 字左右的粗大纲（`ep.synopsis`）。这导致大模型在缺失原著几千字对白与场景细节的情况下自由脑补，生成内容严重脱离原著。而具备原著精读与受保护台词契约（`ProtectedContract`）的 `adaptNovelDramaChapter` 此前仅能通过创意孵化面板的单集导入发起，工作流割裂。

## Goals / Non-Goals

**Goals:**
- 在 `ScreenplayPanel` 提供直通小说正文改编的入口，消除原著信息断流。
- 提供「从小说正文改编生成剧本」双通道弹窗（支持从本地小说库按章节勾选 1~3 章，或直接粘贴小说正文）。
- 顶部工具栏与空白态清晰区分「从小说正文生成剧本（强还原）」与「根据大纲扩写（轻量脑补）」。
- 改编完成后，自动沉淀文学剧本、戏剧场次、原著金句台词与因果契约，并增量合并本章新登场的角色与场景。
- 若已有精修场次，重新改编前弹出二次确认，防止误触覆盖。
- 在 Markdown 文本模式下智能识别大段小说散文并提供一键改编横幅。

**Non-Goals:**
- 不重写或破坏已有大模型 Prompt 模板（复用经过实测验证的 `novelDramaChapterAdaptation` 与 `screenplayGeneration`）。
- 不变更本地剧集与分镜存储结构（复用 `StudioEpisode`、`DramaScene` 与 `ProtectedContract`）。
- 不干涉分镜看板的拆镜逻辑。

## Decisions

### 1. 架构流转：复用成熟的 `adaptNovelDramaChapter` 与 `importChapterToEpisode`

- **选择**：在 `ScreenplayPanel` 中直接调用 `AiConstraintEngine.adaptNovelDramaChapter`，完成后调用 `StudioProjectManager.importChapterToEpisode`。
- **理由**：`importChapterToEpisode` 已完整封装了 `mergeMasterAssets`（角色新造型 Variation 增量追加、场景 7 方位解构自动补全）、场景卡自动关联（`_ensureScenesForDramaScenes`）以及受保护台词契约落盘。复用现有服务无需新增冗余管道，天然保持行为与数据一致性。
- **替代方案考虑**：完全走 `NovelImportTaskService` 后台轮询队列。评估后发现，用户在剧本工作台期待的是即时反馈的沉浸式生成，直接在面板内显示加载状态更贴合编辑场景；但底层调用相同的接口保证结果完全等价。

### 2. 组件交互：独立封装 `ScreenplayNovelAdaptDialog` 双通道弹窗

- **选择**：设计专用的 `ScreenplayNovelAdaptDialog`，包含两栏/两页签：
  - **通道 A（选择小说章节）**：若剧集已绑定 `novelId`，直接从 `NovelRepository` 加载章节列表，展示章节标题与字数，支持快捷多选连续章节，下方实时统计总字数，并高亮推荐区间（3,000~8,000 字）；若未绑定，则允许一键打开小说选择器绑定；
  - **通道 B（直接粘贴正文）**：提供多行文本编辑框与字数计数，方便用户随手粘入未收录在小说库的外部章节。
- **理由**：一次性满足“已有小说库沉淀”与“临时外部拷贝”两类核心创作场景。

### 3. 工具栏重构：主次分明与防误触保护

- **选择**：
  - 顶部主操作：`FilledButton.tonalIcon` 展示为「从小说正文生成剧本」（带书本图标），点击触发双通道正文弹窗；
  - 辅助操作：次级按钮或折叠项展示为「根据大纲扩写」，明确提示基于当前集大纲；
  - 防误触拦截：若 `_scenes.isNotEmpty`，用户触发任一种剧本生成时，先弹窗提示「当前已有编排场次，重新生成将覆盖现有剧本」，确认后才执行。
- **理由**：彻底纠正此前单一「AI 生成剧本」带来的预期错位与意外覆盖痛点。

### 4. Markdown 模式小说散文探测器

- **选择**：在 Markdown 模式下，当 `_textEditorController.text` 长度超过 500 字，且不含 `### 第`、`Scene`、`[场次]` 等剧本标记时，顶部浮动展示一条轻量 Material Banner：「检测到小说散文，是否交由 AI 改编为分场剧本？」，点击一键填入正文弹窗启动改编。
- **理由**：不少用户习惯先复制整章小说贴到文本框里，此特性贴心引导其走上正确的改编流程。

## Risks / Trade-offs

- **[Risk: 改编请求耗时较长（10~25秒）]** → **Mitigation**: 界面提供明确的加载状态提示文字（“AI 正在通读小说正文，提炼场次与锁定原著金句…”），并在用户取消时安全终止，支持重试。
- **[Risk: 章节字数过长（>15,000 字）导致大模型上下文过载]** → **Mitigation**: 在弹窗中实时显示总字数，当超过 12,000 字时给出警告条，建议用户拆分分集（推荐每次勾选 1~3 章）。
