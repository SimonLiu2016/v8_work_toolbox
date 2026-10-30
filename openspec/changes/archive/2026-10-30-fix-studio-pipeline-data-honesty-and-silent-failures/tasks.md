## 1. 阶段状态机与质检数值诚实化

- [x] 1.1 `novel_import_task_service.dart` 的 `StageStatus` 枚举新增 `skipped`，并确认 `advancePipelineStage` 的回填循环跳过 `skipped`（不被后续 `_finish` 刷成 `success`）
- [x] 1.2 全季导入分支：把 `contract` / `storyboard` / `audit` 三个阶段的 `StageStatus.success` 改为 `StageStatus.skipped`，删除 `task.auditPassRate = 100.0` 硬编码
- [x] 1.3 `NovelImportTask.auditPassRate` 由 `double`（默认 1.0）改为 `double?`，同步更新字段文档注释
- [x] 1.4 单章导入分支：`DirectorValidationEngine.validate` 执行前判 `currentEp.shots.isEmpty`，为空时置 `auditPassRate = null` 并写日志「门禁质检无可检对象」；非空时保持现有计算
- [x] 1.5 `idea_incubator_panel.dart` 两处 `if (task.auditPassRate > 0)` 改为可空判断，无可检对象时显示「无可检对象」文案而非分数
- [x] 1.6 `idea_incubator_panel.dart` 的 `_buildStageNode` 增加 `skipped` 分支：图标与文案区别于 `success`（如虚线圆圈 + 「未执行」）
- [x] 1.7 单测：全季导入完成后，`contract` / `storyboard` / `audit` 阶段状态为 `skipped` 且 `auditPassRate` 为 null
- [x] 1.8 单测：单章导入且目标集 shots 为空时，`auditPassRate` 为 null 且日志含「无可检对象」
- [x] 1.9 单测：`advancePipelineStage` 推进到后续阶段时，已标记为 `skipped` 的阶段不被回填为 `success`

## 2. 全季重导入的破坏性删除确认

- [x] 2.1 `studio_project_manager.dart` 新增 `previewFullSeasonImportImpact(seriesId)`，返回待删集数、分镜总数与物理媒体文件总数（遍历 `frames/` `clips/` `segments/` `audio/` `exports/`）
- [x] 2.2 `importNovelProject` 保持既有删除逻辑不变（删除仍由它执行），仅在文档注释中声明「调用方 MUST 先经 previewFullSeasonImportImpact 取得用户确认」
- [x] 2.3 定位全季导入的 UI 入口（创意孵化面板或导入任务启动处），在发起前调用 2.1 并在结果非空时弹确认对话框，列明集数/分镜数/媒体数
- [x] 2.4 用户取消确认时中止导入，不得创建任务、不得删除任何数据
- [x] 2.5 首次导入（项目无既有剧集）不弹确认，直接执行
- [x] 2.6 widget 测试：有待删数据时确认对话框出现并列出正确数量；取消后既有数据原状；无既有剧集时不弹窗

## 3. 首尾帧接力判据与首帧来源记录

- [x] 3.1 `studio_models.dart` 新增 `FirstFrameSource` 枚举（`keyframe` / `relay` / `none`），`StudioShot` 新增 `firstFrameSource` 字段并完成 `toJson` / `fromJson` / `copyWith`，反序列化缺失时默认 `keyframe`
- [x] 3.2 `studio_generation_tasks.dart` 的 `VideoGenTask` 提取接力判定为独立纯函数 `canRelayFromPrev(prevShot, shot)`，实现四条件合取：同场景卡 ∧ `characterIds` 集合判等 ∧ 非正反打 ∧ 景别差 ≤ 1 档
- [x] 3.3 实现 `isReverseShot(prevShot, shot)`：任一方在 `assetBindings` 中被标记为 `confrontation` 分工，或两镜中一方为 `close_up` 另一方非 `close_up`
- [x] 3.4 实现 `shotSizeRank(StudioShotSize)`，用于景别差计算（按 特写/近景/中景/全景/远景/大远景 排序）
- [x] 3.5 `VideoGenTask.run` 的 keyframe 分支改为：先设 `inputImageFile = frameFile`（本镜关键帧），仅当 `canRelayFromPrev` 返回 true 时才改用提取出的上一镜尾帧
- [x] 3.6 `updateShot` 写回时，`firstFramePath` 写实际使用的文件，`firstFrameSource` 写 `relay` 或 `keyframe`
- [x] 3.7 单测：同场景、同主体集合、非正反打、景别差 1 档时使用上一镜尾帧且 `firstFrameSource == relay`
- [x] 3.8 单测：正反打（一方 close_up 另一方非 close_up）时使用本镜关键帧且 `firstFrameSource == keyframe`，不提取上一镜尾帧
- [x] 3.9 单测：主体集合不同（上镜 2 人本镜 1 人）时不接力
- [x] 3.10 单测：场景卡不同时不接力
- [x] 3.11 更新 `test/ai_video_studio_generation_task_test.dart` 中断言旧接力行为的既有用例

## 4. 本地剧本映射的去占位化

- [x] 4.1 `ai_constraint_engine.dart` 的 `convertScenesToShots` 把 `directorDecisions.temporalEvolution` / `aestheticTexture` / `physicalMomentum` 的常量文本改为空串（`physicalMomentum` 在 `beat.subtext` 非空时仍保留透传）
- [x] 4.2 检查 `continuity` 中其余常量赋值（`cameraAxis` 的「机位处于180度轴线右侧…」）是否同样造成质检豁免，若是则一并改空
- [x] 4.3 单测：本地映射产出的分镜，其 `temporalEvolution` 与 `aestheticTexture` 为空，且含反应性台词时报 C11 因果倒置
- [x] 4.4 更新 `test/ai_constraint_engine_test.dart` 中依赖上述常量字段非空的既有断言
- [x] 4.5 跑 `flutter test test/ai_constraint_engine_test.dart test/tools/ai_video_studio/director_validation_causality_test.dart`，确认 C11 相关断言全部转为预期行为

## 5. 全文文本编辑模式的差异保护

- [x] 5.1 `screenplay_panel.dart` 抽取 `bool _hasUnsyncedTextEdits()`，比对 `_textEditorController.text` 与 `_exportToMarkdown(_scenes)`
- [x] 5.2 模式切换按钮的 `onPressed` 增加判定：从文本模式切回结构化视图且 `_hasUnsyncedTextEdits()` 为真时，弹确认对话框（「保留文本修改」/「丢弃并用结构化数据覆盖」）
- [x] 5.3 用户选择「保留文本修改」时，仅完成视图切换，SHALL NOT 覆盖 `_textEditorController.text`；用户的编辑已由 `_saveChanges` 的 `screenplayText` 分支持久化
- [x] 5.4 用户选择「丢弃」时，执行既有的 `_textEditorController.text = _exportToMarkdown(_scenes)` 覆盖逻辑
- [x] 5.5 无差异时直接切换，不弹窗
- [x] 5.6 widget 测试：文本模式有修改时切回结构化视图弹确认；选保留后控制器内容不变；无修改时直接切换

## 6. 分镜看板拆镜不回写剧集概要

- [x] 6.1 `storyboard_board.dart` 的 `_breakdown` 删除 `episode.copyWith(synopsis: synopsis, ...)` 中的 `synopsis` 参数
- [x] 6.2 在粗大纲文本框附近补一句说明文案，告知用户该文本仅作为本次拆镜输入，不会改写剧集概要（文案待实现时定）
- [x] 6.3 单测：调用拆镜流程后，剧集 `synopsis` 字段保持拆镜前值

## 7. 回归与验证

- [x] 7.1 全量 `flutter test`，确认无新增失败；对既有失败按记忆中的环境性红测试甄别后记录
      （studio 域 312 通过 / 3 失败，3 项全部为改动前既有红：asset_library_page_test 的 3 个 widget 测试。
      已用 `git stash` 回退 lib/ 后复跑确认同样失败。全量跑另有 cinematic_director、studio_preset_store、
      evernote_import 3 项既有红，同样经 stash 验证与本次改动无关。）
- [x] 7.2 `flutter analyze lib/` 确认 0 error
- [x] 7.3 `openspec validate fix-studio-pipeline-data-honesty-and-silent-failures --strict` 通过
- [x] 7.4 确认 `openspec/changes/fix-studio-pipeline-context-completeness/` 跟踪提案已创建且引用了本变更的接力与阶段状态修正（见下方跟踪说明）
