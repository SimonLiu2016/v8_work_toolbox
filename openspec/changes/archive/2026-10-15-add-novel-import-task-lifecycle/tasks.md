## 1. 服务层：导入任务服务

- [x] 1.1 新建 `lib/tools/ai_video_studio/services/novel_import_task_service.dart`：`NovelImportTaskService` 单例 + `NovelImportTask`（localId / seriesId / novelId / novelTitle / isFullSeason / phase / attempt / startedAt / error）+ `ImportPhase` 枚举（extracting / segmenting / writing / done / failed / interrupted），继承 `ChangeNotifier`
- [x] 1.2 `submit(...)`：接收 `NovelSelectionResult`（含 novelId / novelTitle / selectedChapterIndices / combinedText）、seriesId、scopeChoice；启动导入流程并返回 localId。重复提交同一 series 的进行中任务时拒绝并说明原因
- [x] 1.3 阶段推进：Pass 1 `extractNovelMaster` → extracting；Pass 2 `segmentNovelEpisodes` / `adaptNovelChapter` → segmenting；`importNovelProject` / `importChapterToEpisode` → writing；成功后 done
- [x] 1.4 进度广播：每次阶段切换 / 秒数变化 / attempt 变化都 `notifyListeners()`。**不设百分比字段**（spec: 不得编造）
- [x] 1.5 ledger 记录：任务开始时 `record(adapterId: 'novel-import', ...)` 写入 seriesId、label（含小说标题与范围）、prompt（小说标题 + 章节范围）；阶段切换 `update(...)`；终态 `update(status + error)`
- [x] 1.6 失败处理：捕获 `ConstraintParseError` 与其他异常，记录是哪一遍、第几次尝试，error 存可读原因（spec: 失败原因可观察）
- [x] 1.7 `recoverInterrupted()`：扫描 ledger 中 `adapterId == 'novel-import'` 且 `status == polling` 的条目，改为中断语义并在 error 写明「应用退出导致中断」。**只改状态，绝不重新执行**
- [x] 1.8 `retry(localId)`：由用户主动触发，用记录里的上下文重新提交导入

## 2. 台账分流（防止条目互相污染）

- [x] 2.1 `video_task_recovery.dart` 的 `_scanAndResume` 显式 `continue` 跳过 `adapterId == 'novel-import'` 的条目——不能依赖 `_buildAdapter` 返回 null 的偶然正确
- [x] 2.2 `storyboard_board.dart` 的 `_CloudTaskSection` / `_loadCloudTasks` 过滤掉 novel-import 条目，否则看板「云端任务」区会出现小说导入
- [x] 2.3 确认 `VideoTaskLedger.prune` 不会误删进行中的 novel-import 条目（`isActive` 语义覆盖）

## 3. UI：创意孵化面板改为委托服务

- [x] 3.1 `_processNovelContent` 改为接收 `NovelSelectionResult`（文件导入路径构造等价结果，novelId 为 null），透传 novelId / novelTitle / selectedChapterIndices
- [x] 3.2 删除面板内的 `_novelImporting` / `_novelImportStatus` / 局部 ticker，改为 `ListenableBuilder` 订阅 `NovelImportTaskService.instance`
- [x] 3.3 进度展示改为：阶段文案（Pass 1/2 / 写入中）+ 已耗时秒数 + 第几次尝试，无百分比
- [x] 3.4 导入范围弹窗补预计耗时说明：两遍深度分析、每遍最长 4 分钟、每遍最多 3 次尝试（spec: 开始前告知工作量）
- [x] 3.5 导入成功后保留既有行为（`session.select(updatedSeries)` + `_loadHistoryAndEpisodes` + SnackBar + `onConfirmed()`），仅把执行体换成服务调用

## 4. UI：工坊级任务可见性

- [x] 4.1 `studio_shell.dart` 顶栏（刷新按钮左侧）加导入任务指示，样式复用 `storyboard_board.dart` 的 `_ActiveBadge`；有进行中任务时常驻可见
- [x] 4.2 新建 `lib/tools/ai_video_studio/ui/novel_task_drawer.dart`：任务抽屉，列出进行中任务（阶段 + 已耗时 + 尝试次数）与最近终态任务（成功/失败/中断 + 时间 + 原因），中断条目提供「重试」按钮
- [x] 4.3 中断态展示为「已中断」而非「失败」（存储复用 failed，UI 按 adapterId 翻译语义，design 决策 3）
- [x] 4.4 `_bootstrap` 在 `VideoTaskRecovery.instance.startOnce()` 之后调用 `NovelImportTaskService.instance.recoverInterrupted()`

## 5. AI 调用日志入口

- [x] 5.1 `studio_settings_dialog.dart` 补「查看调用日志」入口，调现成的 `AiLogDialog.show(context)`

## 6. 验证

- [x] 6.1 单元测试：`NovelImportTaskService` 提交后阶段按 extracting → segmenting → writing → done 推进（mock `AiConstraintEngine.chatFn`）
- [x] 6.2 单元测试：任务进行中调用 `resetForTesting` 模拟"UI 销毁"，任务状态不丢、ledger 条目仍在
- [x] 6.3 单元测试：`recoverInterrupted()` 把 polling 态改为中断、写 error、**不触发任何重新提交**（断言 chatFn 调用次数不变）
- [x] 6.4 单元测试：失败时 error 含遍次与尝试次数；`ConstraintParseError` 被正确分类
- [x] 6.5 单元测试：ledger 记录含 novelId 与小说标题；文件导入（novelId 为 null）不报错
- [x] 6.6 回归测试：`VideoTaskRecovery` 跳过 novel-import 条目（种子一条 novel-import polling 条目，断言不重建适配器、不轮询）
- [ ] 6.7 实机：导入进行中切到 IP 主库再回来，进度仍在且任务完成
- [ ] 6.8 实机：导入进行中关窗（红叉）再重开，任务仍在并最终成功
- [ ] 6.9 实机：导入进行中 ⌘Q 退出，重启后看到「已中断」且未自动重新导入（观察供应商控制台请求计数）
- [ ] 6.10 实机：分镜看板的云端任务区不出现小说导入条目
- [x] 6.11 运行 `flutter test` 与 `flutter analyze`，确认无回归
- [x] 6.12 部署：`scripts/deploy_local.sh`
