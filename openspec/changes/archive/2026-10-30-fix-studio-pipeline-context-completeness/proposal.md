## Why

「AI 短视频工坊」的 AI 调用链上，下游阶段拿到的上下文比上游产出的少——用户在剧本工作台精心写的台词、机位、景别，到拆镜环节被整段丢弃；用户在分镜卡上绑定的角色素材，到生图环节被无视；用户改过分镜字段后存的视频提示词，从此不再反映最新编辑。

这些问题不会报错。AI 只是"自己编"或"用旧稿"，用户看到的是"我写的台词怎么变了""我绑的图怎么没生效"——而底层没有任何异常可查。

本变更修三类上下文断裂：**提示词输入漏传**（拆镜与剧本生成）、**参考图取材分裂**（生图与生视频读不同来源）、**缓存失效缺失**（videoPrompt 不随字段变更作废）。另含任务队列的依赖控制，消除"图未生完先跑视频"的静默降级。

> 本变更与 `fix-studio-pipeline-data-honesty-and-silent-failures`（下称「数据诚实性变更」）配套。数据诚实性变更修数据写入的可信度，本变更修 AI 输入的完整性。**本变更的任务 8.x 依赖数据诚实性变更的接力判据修正（其 tasks 3.5）先完成**——否则接力的静默覆盖会继续让正确的提示词配错的首帧。

## What Changes

### 1. 拆镜提示词补传节拍导演字段
- `AiConstraintEngine.scriptBreakdown5D` 组装的 `scenesBlock` **SHALL** 补传每个 `DramaBeat` 的：`dialogue`、`dialogueSpeaker`、`voiceType`、`subtext`、`shotSize`、`cameraStaging`、`cameraMove`、`screenPosition`、`gazeDirection`。
- 补传后，`protectedContract.utterances` 不再是台词进入拆镜上下文的唯一通道。

### 2. 两个拆镜入口的输入源统一
- `ScreenplayPanel._breakdownWithAi` 与 `StoryboardBoard._breakdown` 触发同一个「AI 五维拆镜」时，SHALL 传入一致的输入：结构化 `scenes`（含节拍）+ 最新 `screenplayText` + `protectedContract`。
- 分镜看板入口不得只传 4 行粗大纲文本框的内容而丢弃已打磨的剧本全文。

### 3. 剧本生成补传资产上下文
- `AiConstraintEngine.screenplayGeneration` **SHALL** 接收并注入：角色外貌与服装设定（`facialFeaturesZh` / `defaultAttireZh`）、已有场景卡名称列表、以及 `protectedContract`。
- 目标是让生成的场次地点名与资产库 `SceneCard.name` 对得上，减少重复场景卡。

### 4. 生图与生视频的参考图取材同源
- `ImageGenTask` 的参考图收集 **SHALL** 改用 `AssetBindingResolver`，与 `VideoGenTask`、`SegmentVideoGenTask` 读同一份 `assetBindings`。
- 生图提示词的多图编号说明 **SHALL** 按实际入选并传入的参考图文件顺序生成，而非按 `effectiveCharacters` 数组下标。
- `buildShotPrompt` 传入的 `isMultiImage` 与 `hasCharacterReferences` SHALL 依据实际参考图列表计算。

### 5. videoPrompt 缓存失效
- 分镜的 `actionZh` / `dialogue` / `characterIds` / `sceneId` / `assetBindings` 任一发生变更时，系统 SHALL 作废或同步更新该镜已缓存的 `videoPrompt`。
- 作废后，`buildVideoGenPrompt` 恢复动态组装，使【素材指代】`<Picture N>` 与【因果时间轴】重新反映最新字段。
- 作废 SHALL 对用户可见——UI 需明示「字段已变更，视频提示词已重置为自动组装」。

### 6. 任务队列依赖控制（先图后视频）
- `StudioTaskQueue` 引入任务依赖：同一分镜的 `VideoGenTask` SHALL 等待该镜 `ImageGenTask` 成功完成后才启动。
- 批量生成入口（`_enqueueSegment` / `_enqueueAllSegments`）按分镜依次入队图任务与视频任务时，SHALL 建立上述依赖，而非依赖并发槽的抢占顺序。
- 生图任务失败时，依赖它的视频任务 SHALL 标记为「前置未满足」而非裸跑。

### 7. 视频提示词编译器的收敛方向
- 本变更**不合并** `buildVideoGenPrompt` / `buildSegmentPrompt` / `PhotorealisticPromptCompiler` / `SeedanceTaskCompiler` 四套编译器——那是大重构，另行立项。
- 但 SHALL 修掉一处直接矛盾：分镜卡「视频提示词」对话框的初始文本来自 `buildSanitizedVideoPrompt`（即 `buildVideoGenPrompt` 的血脉），用户保存后进 `shot.videoPrompt`，随后 `buildVideoGenPrompt` 原样返回——导出给他人看的文本与真正提交给模型的文本从此分家。本变更要求对话框在保存时明示该提示词已成为定制覆盖。

## Capabilities

### New Capabilities
<!-- 无新增 capability -->

### Modified Capabilities
- `ai-video-studio/script-workshop`: 五维拆镜的上下文输入要求——节拍级的台词、说话人、发声类型、潜台词与导演预设（景别、机位、运镜、画面位置、视线）SHALL 全部注入；两个拆镜入口 SHALL 传入一致的输入；剧本生成 SHALL 注入角色外貌服装设定、已有场景卡名与受保护契约。
- `ai-video-studio/shot-production`: 关键帧生图的参考图取材 SHALL 与视频生成读同一份素材绑定；生图提示词的多图编号 SHALL 按实际传入的参考图顺序；分镜级视频任务 SHALL 等待同镜关键帧生成成功后才启动；分镜字段变更 SHALL 作废已缓存的视频提示词。
- `ai-video-studio/segment-production`: 片段级生成的前置依赖与分镜级一致——片段内首镜关键帧未就绪时不得静默以降级模式提交。

## Impact

**代码**
- `lib/tools/ai_video_studio/services/ai_constraint_engine.dart` — `scriptBreakdown5D` 的 scenesBlock 补传 9 个节拍字段；`screenplayGeneration` 新增角色设定、场景卡名与契约三个入参。
- `lib/tools/ai_video_studio/ui/screenplay_panel.dart` — `_breakdownWithAi` 输入源统一；`_generateScreenplayWithAi` 补传上下文。
- `lib/tools/ai_video_studio/ui/storyboard_board.dart` — `_breakdown` 输入源统一；批量入队建立图→视频依赖；videoPrompt 失效的 UI 提示。
- `lib/tools/ai_video_studio/services/studio_generation_tasks.dart` — `ImageGenTask._referenceImages` 改用 `AssetBindingResolver`；`VideoGenTask` 的前置依赖检查。
- `lib/tools/ai_video_studio/services/prompt_assembler.dart` — `buildShotPrompt` 的多图编号按实际参考图顺序；`buildAgnesMultiImageDirective` 的编号来源修正。
- `lib/tools/ai_video_studio/services/studio_task_queue.dart` — 任务依赖（`requiresTaskId` 或等价的阻塞判定）。
- `lib/tools/ai_video_studio/models/studio_models.dart` — `StudioShot` 可能需要记录 videoPrompt 的来源字段快照用于失效比对（或用既有 `updatedAt` 近似）。

**依赖与测试**
- `test/ai_video_studio_prompt_assembler_test.dart` — 多图编号断言需按新规则重写。
- `test/ai_video_studio_generation_task_test.dart` — `ImageGenTask` 取材断言需更新。
- `test/ai_video_studio_task_queue_test.dart` — 新增依赖行为的用例。
- `test/ai_constraint_engine_test.dart` — `scriptBreakdown5D` 提示词内容断言需更新。

**不在本变更范围**
- 四套视频提示词编译器的合并（大重构，另行立项）。
- `scenes` / `screenplayText` / `synopsis` 的单一事实源重构（需产品决策）。
- markdown → `DramaScene` 反向解析。
- >35000 字小说的分段提炼与角色属性增量富化（属于长文处理，另行立项）。
