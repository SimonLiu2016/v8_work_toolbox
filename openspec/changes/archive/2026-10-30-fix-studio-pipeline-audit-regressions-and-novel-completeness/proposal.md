## Why

在对前序两个流水线修复变更（`fix-studio-pipeline-data-honesty-and-silent-failures` 与 `fix-studio-pipeline-context-completeness`）进行代码级审计时，发现 7 处关键实现回归/漏洞导致修复在真实运行链路中被短路失效（如分镜看板拆镜被默认粗大纲文本框短路而永远读不到文学剧本、单镜服装形态切换未将原默认形态置为 `active: false`、视频提示词弹窗保存抹除 `<Picture N>` 多图指令、批量接力生视频未建立跨镜串行依赖等），同时长篇小说 `>35,000` 字中部硬截断、同名角色/场景增量属性演进合并及剧本双轨矛盾尚未覆盖，亟需通过本次变更一并闭环。

## What Changes

- **修复分镜看板拆镜被粗大纲短路（Bug 1）**：在 `StoryboardBoard` 与 `BreakdownInput.synopsisOf` 中，仅当用户在分镜看板修改了粗大纲文本框（与 `episode.synopsis` 不同）或 `episode.screenplayText` 为空时才使用粗大纲，确保打磨后的 `episode.screenplayText` 真正作为默认最高优先级拆镜输入。
- **修复单镜服装形态激活未互斥重置（Bug 2）**：在 `ImageGenTask`、`StoryboardBoard._ensureDefaultBindings` 与分镜卡片 `_AssetRow._loadCandidates` 中，按 `ShotVariationResolver` 构造临时 `CharacterCard` 时将全部形态执行互斥设置 `v.copyWith(active: v.id == resolved.id)`，确保 `activeVariation` 准确命中分镜专属形态而非永远停留在第 0 项「默认」。
- **补齐 `buildVideoGenPrompt` 过期校验与弹窗 `<Picture N>` 保留（Bug 3）**：在 `PromptAssembler.buildVideoGenPrompt` 与 `buildSanitizedVideoPrompt` 内部统一校验 `!shot.isVideoPromptStale`；在 `_VideoPromptDialog`（预览、重置、AI 消解冲突）及 `AiConstraintEngine.rewriteVideoPrompt` 中解析并传入当前分镜绑定的 `materials`，防止打开或保存视频提示词弹窗后丢失 `<Picture N>` 多图引用指令。
- **修复剧本工作台内存态丢失与双轨拆镜冲突（Bug 4 & Gap 1）**：
  - 在 `ScreenplayPanel` 全文模式下点击切换视图并选择「保留修改」时，立即将 `_textEditorController.text` 同步至 `_screenplayText` 并持久化；
  - 在 `ScreenplayPanel` 点击「AI 拆分分镜」或「本地同步至分镜」前，先将当前内存中的 `_scenes` 与 `_screenplayText` 改动落盘，禁止用磁盘旧数据覆盖内存修改；
  - 当全文剧本相较于结构化场次发生过独立修改时，AI 拆镜提示词以最新全文剧本为主权威来源，避免旧场次节拍与新全文在同一个 Prompt 内自相矛盾。
- **修复批量视频接力并发竞态与反打判据漏判（Bug 5 & Bug 6）**：
  - 在 `_enqueueSegment` 与 `_enqueueAllSegments` 批量入队时，当相邻两镜满足 `canRelayFrameFromPrev(prevShot, shot)` 时，使后一镜视频任务串联等待前一镜视频任务（以及本镜关键帧任务），保证提取上一镜尾帧时前序视频文件已生成完毕；
  - 强化 `canRelayFrameFromPrev` 判据：除同场景、同角色集合、景别差 ≤ 1 档外，增加机位俯仰角（`cameraAngle`）、空间高度层（`elevationLevel`）一致性及视线/画面站位（`gazeDirection` / `screenPosition`）非镜像反打校验。
- **修正全季导入阶段状态时机与单章增量上下文（Bug 7 & Gap 4）**：全季导入在 `importNovelProject` 落盘期间不再错误标记 `storyboard` 阶段为 `running`；单章导入在调用 `extractNovelMaster` 时传入当前剧集已有角色与场景名录作为增量上下文，避免同人异名重复建卡。
- **消除长篇小说 `>35,000` 字中部硬截断（Gap 2）**：改造 `AiConstraintEngine.extractNovelMaster` 与 `extractNovelEpisodes` 的长文采样策略，当原文超过 35,000 字时采用「首尾完整保留 + 中部多窗口均匀分块采样」替代原先直接丢弃中间全部章节的截断方式。
- **支持同名角色与场景资产的增量丰富与新形态演进（Gap 3）**：改造 `StudioProjectManager.mergeMasterAssets`，当后续章节提炼出同名角色更详尽的外貌/生图描述时自动升级过短的旧描述，当提炼出与现有形态不同的新服饰描述时自动追加为新的 `CharacterVariation`（保留已有锚点图与当前激活态不变），同名场景同样支持描述升级与新增方位视角合并。

## Capabilities

### New Capabilities

（无新增顶层 capability，全部归入既有规格增量）

### Modified Capabilities

- `ai-video-studio/novel-import`: 长篇小说超长文本采用全书多段均匀采样覆盖中部章节，单章导入注入既有资产上下文，修正全季导入阶段状态标记时机。
- `ai-video-studio/series-asset-library`: 同名角色与场景在增量导入时支持描述升级及新服饰形态（`CharacterVariation`）自动追加，而非仅在字段为空时写入。
- `ai-video-studio/script-workshop`: 修复分镜看板拆镜被默认粗大纲短路、剧本工作台视图切换与未保存拆镜丢失内存改动，以及全文修改后与旧结构化场次在拆镜时的优先级冲突。
- `ai-video-studio/shot-production`: 修复单镜服装形态激活互斥重置、`buildVideoGenPrompt` 与弹窗 `<Picture N>` 多图指令保留、批量接力生视频的跨镜依赖链，以及 `canRelayFrameFromPrev` 机位/高度层/视线反打判据。

## Impact

- **受影响代码**：
  - `lib/tools/ai_video_studio/services/breakdown_input.dart`
  - `lib/tools/ai_video_studio/services/ai_constraint_engine.dart`
  - `lib/tools/ai_video_studio/services/studio_project_manager.dart`
  - `lib/tools/ai_video_studio/services/novel_import_task_service.dart`
  - `lib/tools/ai_video_studio/services/prompt_assembler.dart`
  - `lib/tools/ai_video_studio/services/studio_generation_tasks.dart`
  - `lib/tools/ai_video_studio/services/studio_task_queue.dart`
  - `lib/tools/ai_video_studio/ui/screenplay_panel.dart`
  - `lib/tools/ai_video_studio/ui/storyboard_board.dart`
- **测试影响**：新增及更新针对上述 7 项实现回归修复与长篇采样/资产增量合并的单元测试。
