import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;

import '../../novel_manager/services/novel_repository.dart';
import '../models/studio_models.dart';
import 'ai_constraint_engine.dart';
import 'director_validation_engine.dart';
import 'studio_project_manager.dart';
import 'video_task_ledger.dart';

/// 细粒度漫剧导演流水线核心阶段。
enum PipelineStage {
  ingest('ingest', '文本切片', '读取与切片原著章节'),
  assets('assets', '资产抽取', '提取世界观与角色场景卡'),
  beats('beats', '场次节拍', '规划剧情场次与戏剧节拍'),
  contract('contract', '契约锁定', '锁定受保护事实与台词'),
  storyboard('storyboard', '五维拆镜', '五维视听决策与动作编舞'),
  audit('audit', '门禁质检', 'C01~C09 工业级自动化质检');

  final String id;
  final String label;
  final String description;

  const PipelineStage(this.id, this.label, this.description);
}

enum StageStatus {
  pending,
  running,
  success,
  failed,

  /// 本次导入范围内未执行（spec: 导入流水线阶段状态如实反映执行情况）。
  ///
  /// 与 [pending] 的区别是终态性：全季导入只跑到分集大纲，后续的契约锁定、
  /// 五维拆镜与门禁质检对它是 [skipped] 而不是 [pending]——否则任务卡会
  /// 永远显示"未完成"。
  skipped,
}

/// 小说导入任务的执行阶段（大粗粒度兼容层）。
enum ImportPhase {
  /// 首遍：提取世界观、角色卡库与场景库。
  extracting('解构 IP 资产', 'Pass 1/2'),

  /// 次遍：全案分集规划，或单章影视化提炼。
  segmenting('规划分集大纲', 'Pass 2/2'),

  /// 写入 IP 主库与剧集大纲。
  writing('写入 IP 主库'),

  /// 成功结束。
  done('已完成'),

  /// 失败（含执行方错误与解析失败）。
  failed('失败'),

  /// 进程退出导致的中断。**不是导入失败**——请求断了，没导完。
  interrupted('已中断');

  final String label;

  /// 遍次提示；无遍次概念的阶段为空串。
  final String passLabel;

  const ImportPhase(this.label, [this.passLabel = '']);

  bool get isTerminal =>
      this == done || this == failed || this == interrupted;

  bool get isRunning => !isTerminal;
}

/// 一个小说导入任务。
class NovelImportTask {
  NovelImportTask({
    required this.localId,
    required this.seriesId,
    required this.novelTitle,
    required this.isFullSeason,
    required this.startedAt,
    this.novelId,
    this.targetEpisodeIndex,
    this.phase = ImportPhase.extracting,
    this.attempt = 1,
    this.error,
  }) {
    for (final s in PipelineStage.values) {
      stageStatuses[s] = StageStatus.pending;
    }
  }

  /// 与 ledger 条目共用的本地标识。
  final String localId;

  final String seriesId;

  /// 来源小说标识。文件导入时为 null。
  final String? novelId;

  final String novelTitle;

  /// true = 全案导入（两遍）；false = 单章导入。
  final bool isFullSeason;

  /// 单章导入时的目标集号；全案导入为 null。
  final int? targetEpisodeIndex;

  ImportPhase phase;

  /// 流水线当前正在执行的细粒度阶段
  PipelineStage currentStage = PipelineStage.ingest;

  /// 各流水线阶段的状态映射
  final Map<PipelineStage, StageStatus> stageStatuses = {};

  /// 实时滚动终端日志（最新200条）
  final List<String> liveLogs = [];

  /// 实时发现并已装配的角色卡名称列表
  List<String> discoveredCharacters = [];

  /// 实时发现并已装配的常驻场景列表
  List<String> discoveredScenes = [];

  /// 实时发现的道具列表
  List<String> discoveredProps = [];

  /// 锁定的受保护台词数
  int protectedUtteranceCount = 0;

  /// 锁定的基准事实数
  int protectedFactCount = 0;

  /// 规划的场次数
  int plannedSceneCount = 0;

  /// 规划的镜头数
  int plannedShotCount = 0;

  /// C01~C09 质检通过率 (0.0~100.0)；null 表示无可检对象。
  ///
  /// 可空是刻意的（spec: 导入流水线阶段状态如实反映执行情况）：目标集没有
  /// 分镜时，任何数值都是编造——1.0 会被读成满分，0.0 会被读成全挂。空
  /// 分镜下系统报告"无可检对象"，UI 不出数。
  double? auditPassRate;

  /// 追加实时执行日志
  void addLog(String message) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    liveLogs.add('[$timeStr] $message');
    if (liveLogs.length > 200) {
      liveLogs.removeAt(0);
    }
  }

  /// 推进流水线阶段
  ///
  /// 回填循环把先前阶段一并标为 success，但 [StageStatus.skipped] 与
  /// [StageStatus.failed] 除外——否则一次全季导入末尾的 `_finish` 会把前面
  /// 刻意标记为"未执行"的阶段又刷成"已就绪"（spec: 未执行的阶段呈现为未执行）。
  void advancePipelineStage(PipelineStage stage, StageStatus status) {
    currentStage = stage;
    stageStatuses[stage] = status;
    for (final s in PipelineStage.values) {
      if (s.index < stage.index &&
          stageStatuses[s] != StageStatus.failed &&
          stageStatuses[s] != StageStatus.skipped) {
        stageStatuses[s] = StageStatus.success;
      }
    }
  }

  /// 当前第几次尝试（执行方内部重试计数的透出）。
  int attempt;

  final DateTime startedAt;

  String? error;

  /// 已耗时。终态任务停在这个值上，不继续涨。
  Duration get elapsed {
    final end = isTerminalAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  /// 仅供 [elapsed] 使用的终态时刻。
  DateTime? isTerminalAt;

  bool get isRunning => phase.isRunning;

  /// 人类可读的范围描述，用于 ledger 的 label 与任务抽屉。
  String get scopeLabel => isFullSeason
      ? '完整长篇小说'
      : '第 $targetEpisodeIndex 集';
}

/// 小说导入任务服务。
///
/// **为什么存在**：导入链路原本写在 `IdeaIncubatorPanel` 的 State 里，进度
/// 只有两个实例字段。工坊的页签切换是新建 Widget（`_buildStage` 不传 key、
/// 无 IndexedStack），切走即 dispose——进度归零，而 `await` 链还在跑。用户
/// 看到「小说全案深度解构中」消失，既不知道后台是否在解构，也无从再看进度。
///
/// 这个服务把任务归属从 Widget 挪到进程级单例，UI 变成纯订阅者。切页签、
/// 关窗（`AppDelegate.windowShouldClose` → `hideMainWindow()`，进程存活）
/// 都不影响任务继续，也都能再看到进度。
///
/// 与 `StudioTaskQueue` 的分工：那个是分镜/片段产物的**内存**调度器（关联键
/// 是镜号、按产物 kind 分组），导入任务没有镜号且需要**持久化**——塞进去要
/// 么加可空字段要么复用 `segmentKey` 哈希技巧，两种都是把不相关的概念拧在
/// 一起。与 `VideoTaskLedger` 的分工：ledger 是被动的记录簿，不知道导入怎么
/// 执行；这个服务持有执行体，并把关键节点写进 ledger。
class NovelImportTaskService extends ChangeNotifier {
  NovelImportTaskService._();
  static final NovelImportTaskService instance = NovelImportTaskService._();

  final _manager = StudioProjectManager.instance;

  /// 进行中与最近终态的任务。新的在前。
  final List<NovelImportTask> _tasks = <NovelImportTask>[];

  /// 终态任务保留条数——抽屉只展示最近的，无限增长会让列表变得难读。
  static const int _maxFinishedTasks = 20;

  /// ledger 里标识小说导入任务的 adapterId。
  ///
  /// 复用一个常量而不是散落字符串：`VideoTaskRecovery` 与分镜看板的
  /// `_CloudTaskSection` 都要靠它分流，两处漏一处就会出现「视频恢复去轮询
  /// 小说导入」或「看板云端任务区出现小说导入」。
  static const String adapterId = 'novel-import';

  List<NovelImportTask> get tasks => List.unmodifiable(_tasks);

  List<NovelImportTask> get runningTasks =>
      _tasks.where((t) => t.isRunning).toList();

  int get runningCount => runningTasks.length;

  NovelImportTask? taskOf(String localId) {
    for (final t in _tasks) {
      if (t.localId == localId) return t;
    }
    return null;
  }

  /// 获取指定剧集的最新导入任务（优先正在执行，其次最近完成/中断/失败）。
  NovelImportTask? latestTaskFor(String seriesId) {
    for (final t in _tasks) {
      if (t.seriesId == seriesId && t.isRunning) return t;
    }
    for (final t in _tasks) {
      if (t.seriesId == seriesId) return t;
    }
    return null;
  }

  /// 该剧集是否已有进行中的导入。UI 用它阻止重复提交。
  bool hasRunningFor(String seriesId) =>
      _tasks.any((t) => t.isRunning && t.seriesId == seriesId);

  void resetForTesting() {
    _tasks.clear();
  }

  /// 提交一次小说导入。
  ///
  /// 返回任务标识；同一剧集已有进行中的导入时抛 [StateError]——并发导入会
  /// 让两遍 AI 调用交错写同一份 `series_profile.json`，而那是 IP 主库的
  /// 唯一事实来源。
  Future<String> submit({
    required String seriesId,
    required String novelText,
    required bool isFullSeason,
    required int targetEpisodeIndex,
    String? novelId,
    String novelTitle = '未命名小说',
    List<int> selectedChapterIndices = const [],
  }) async {
    if (hasRunningFor(seriesId)) {
      throw StateError('该剧集已有正在进行的导入任务，请等待其完成');
    }

    final series = _manager.readSeries(seriesId);
    if (series == null) {
      throw StateError('剧集项目不存在: $seriesId');
    }

    final localId =
        '${adapterId}_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
    final task = NovelImportTask(
      localId: localId,
      seriesId: seriesId,
      novelId: novelId,
      novelTitle: novelTitle,
      isFullSeason: isFullSeason,
      targetEpisodeIndex: isFullSeason ? null : targetEpisodeIndex,
      startedAt: DateTime.now(),
    );
    _tasks.insert(0, task);
    _trimFinished();
    notifyListeners();

    // 先落盘再执行：这是「轮询途中被杀也留得下线索」的顺序，与视频任务同一
    // 条契约（spec: 视频任务创建成功后立即持久化台账）。
    await VideoTaskLedger.instance.record(
      providerId: novelId ?? 'local-file',
      adapterId: adapterId,
      model: isFullSeason ? 'full-season' : 'single-episode',
      remoteTaskId: isFullSeason ? '' : '$targetEpisodeIndex',
      seriesId: seriesId,
      episodeId: isFullSeason ? '' : 'ep_$targetEpisodeIndex',
      segmentId: '',
      shotNumber: isFullSeason ? null : targetEpisodeIndex,
      label: '小说导入：$novelTitle（${task.scopeLabel}）',
      targetPath: '',
      localId: localId,
      prompt: [
        novelTitle,
        if (selectedChapterIndices.isNotEmpty)
          '章节 ${selectedChapterIndices.first}-${selectedChapterIndices.last}',
      ].join(' · '),
    );

    // 不 await：调用方（UI）要立刻拿到控制权，任务在后台跑。
    unawaited(_run(task, novelText, series.productionType.id, selectedChapterIndices));
    return localId;
  }

  Future<void> _run(
    NovelImportTask task,
    String novelText,
    String productionTypeId,
    List<int> selectedChapterIndices,
  ) async {
    try {
      // ---- Stage 1: 原著文本摄入与切片 (Ingest) ----
      task.advancePipelineStage(PipelineStage.ingest, StageStatus.running);
      task.addLog('启动原著切片与解析流水线: ${task.novelTitle}');
      notifyListeners();

      if (novelText.trim().isEmpty) {
        if (task.novelId != null) {
          var indices = selectedChapterIndices;
          if (indices.isEmpty) {
            final allChapters = await NovelRepository.instance.getChapterIndices(task.novelId!);
            indices = allChapters.map((c) => c.chapterIndex).toList();
          }
          if (indices.isNotEmpty) {
            task.addLog('从本地小说库读取章节文本 (共 ${indices.length} 章)...');
            notifyListeners();
            final sb = StringBuffer();
            for (var i = 0; i < indices.length; i++) {
              final idx = indices[i];
              try {
                final ch = await NovelRepository.instance.getChapter(task.novelId!, idx);
                if (ch != null && ch.content.trim().isNotEmpty) {
                  sb.writeln('=== ${ch.title} ===');
                  sb.writeln(ch.content);
                  sb.writeln();
                  task.addLog('已载入第 ${i + 1}/${indices.length} 章: ${ch.title} (${ch.content.length}字)');
                } else if (ch != null) {
                  task.addLog('第 $idx 章 (${ch.title}) 内容为空');
                } else {
                  task.addLog('未能读取第 $idx 章');
                }
              } catch (e) {
                task.addLog('读取第 $idx 章异常: $e');
              }
              notifyListeners();
            }
            novelText = sb.toString();
          } else {
            task.addLog('该小说在本地数据库中尚未包含任何章节');
            notifyListeners();
          }
        }
      }

      if (novelText.trim().isEmpty) {
        task.advancePipelineStage(PipelineStage.ingest, StageStatus.failed);
        throw StateError('未获取到有效的小说正文内容（章节正文为空或尚未下载），无法开始解构');
      }

      task.addLog('原著文本切片就绪，总字数: ${novelText.length} 字');
      task.advancePipelineStage(PipelineStage.ingest, StageStatus.success);
      notifyListeners();

      // ---- Stage 2: 世界观 / 角色卡库 / 场景库 (Assets) ----
      task.advancePipelineStage(PipelineStage.assets, StageStatus.running);
      _advance(task, ImportPhase.extracting);
      task.addLog('提取世界观、角色卡库与场景库 (AI Pass 1)...');
      notifyListeners();

      final existingChars = await _manager.listCharacters(task.seriesId);
      final existingCharNames = existingChars
          .map((c) => c.name.trim())
          .where((n) => n.isNotEmpty)
          .toList();
      final existingScenes = await _manager.listScenes(task.seriesId);
      final existingSceneNames = existingScenes
          .map((s) => s.name.trim())
          .where((n) => n.isNotEmpty)
          .toList();

      final masterResult = await AiConstraintEngine.extractNovelMaster(
        novelText: novelText,
        productionType: productionTypeId,
        existingCharacterNames: existingCharNames,
        existingSceneNames: existingSceneNames,
      );

      final charList = (masterResult.data['characters'] as List?) ?? const [];
      final charNames = charList
          .whereType<Map>()
          .map((c) => (c['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();

      final sceneList = (masterResult.data['scenes'] as List?) ?? const [];
      final sceneNames = sceneList
          .whereType<Map>()
          .map((s) => (s['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();

      final propList = (masterResult.data['props'] as List?) ?? const [];
      final propNames = propList
          .whereType<Map>()
          .map((p) => (p['name'] as String? ?? '').trim())
          .where((n) => n.isNotEmpty)
          .toList();

      task.discoveredCharacters = charNames;
      task.discoveredScenes = sceneNames;
      task.discoveredProps = propNames;
      task.addLog('已提炼角色 (${charNames.length}位): ${charNames.take(5).join("、")}${charNames.length > 5 ? " 等" : ""}');
      task.addLog('已识别场景 (${sceneNames.length}处): ${sceneNames.take(4).join("、")}${sceneNames.length > 4 ? " 等" : ""}');
      task.advancePipelineStage(PipelineStage.assets, StageStatus.success);
      notifyListeners();

      if (task.isFullSeason) {
        // ---- Stage 3: 全季分集大纲规划 (Beats) ----
        task.advancePipelineStage(PipelineStage.beats, StageStatus.running);
        _advance(task, ImportPhase.segmenting);
        task.addLog('规划全季分集大纲与剧情高潮点 (AI Pass 2)...');
        notifyListeners();

        final segmentResult = await AiConstraintEngine.segmentNovelEpisodes(
          novelText: novelText,
          worldview: masterResult.data['worldview'] as String? ?? '',
          characterNames: <String>{...existingCharNames, ...charNames}.toList(),
          productionType: productionTypeId,
        );

        final episodesList = (segmentResult.data['episodes'] as List?) ?? const [];
        task.plannedSceneCount = episodesList.length;
        task.addLog('完成全季大纲规划，共设计 ${episodesList.length} 集剧集大纲');
        task.advancePipelineStage(PipelineStage.beats, StageStatus.success);

        // 全季导入只产出世界观资产与分集粗大纲：契约锁定、五维拆镜与门禁质检
        // 本次均未执行，直接标记为 skipped（绝不能先把 storyboard 置为 running，
        // 否则写入期间或异常中断时 UI 会误报「正在拆解分镜 / 拆镜失败」）。
        task.advancePipelineStage(PipelineStage.contract, StageStatus.skipped);
        task.advancePipelineStage(PipelineStage.storyboard, StageStatus.skipped);
        task.advancePipelineStage(PipelineStage.audit, StageStatus.skipped);
        task.addLog('契约锁定与分镜拆解需在单章提炼后执行，本次全季导入跳过');

        // ---- 写入工程 (Writing) ----
        _advance(task, ImportPhase.writing);
        task.addLog('写入剧集主库与大纲结构...');
        notifyListeners();

        final updated = await _manager.importNovelProject(
          seriesId: task.seriesId,
          masterExtraction: masterResult.data,
          episodeSegmentation: segmentResult.data,
        );

        // 自动对导入提取的场景补充七方位空间全息解构
        task.addLog('启动场景空间全息解构 (7方位推演)...');
        notifyListeners();
        final deconstructedCount = await _manager.deconstructAllScenesSpatialProfiles(
          task.seriesId,
          onProgress: (cur, tot, sName) {
            task.addLog('场景全息解构 [$cur/$tot]: $sName');
            notifyListeners();
          },
        );
        if (deconstructedCount > 0) {
          task.addLog('场景空间全息档案推演完成 ($deconstructedCount 处场景)');
        }

        task.addLog('全季架构导入完成，已同步入库（剧本与分镜请在单章提炼后生成）');
        await _finish(task, updated);
        return;
      }

      // ---- Stage 3: 单章影视化提炼与戏剧场次 (Beats) ----
      task.advancePipelineStage(PipelineStage.beats, StageStatus.running);
      _advance(task, ImportPhase.segmenting);
      task.addLog('单集影视化重构与戏剧场次节拍规划 (AI Pass 2)...');
      notifyListeners();

      final series = _manager.readSeries(task.seriesId);
      final existingProps = await _manager.listProps(task.seriesId);
      final knownPropNames = <String>{
        ...propNames,
        ...existingProps.map((p) => p.name.trim()).where((n) => n.isNotEmpty),
      }.toList();
      final adaptResult = await AiConstraintEngine.adaptNovelDramaChapter(
        novelText: novelText,
        seriesName: series?.name ?? '',
        worldview:
            (masterResult.data['worldview'] as String? ?? series?.worldview ?? '')
                .trim(),
        characterNames: <String>{...existingCharNames, ...charNames}.toList(),
        propNames: knownPropNames,
        productionType: productionTypeId,
        episodeIndex: task.targetEpisodeIndex ?? 1,
        memoryContext: series == null ? '' : _manager.buildMemoryContext(series),
      );

      final chapterLines = novelText
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
      final guessedTitle = chapterLines.isNotEmpty && chapterLines.first.length <= 20
          ? chapterLines.first
          : '第 ${task.targetEpisodeIndex} 集';
      final adaptedTitle = (adaptResult.data['title'] as String? ?? '').trim();
      final adaptedSynopsis = (adaptResult.data['synopsis'] as String? ?? '').trim();
      final adaptedSummary = (adaptResult.data['summary'] as String? ?? '').trim();
      final adaptedHook = (adaptResult.data['hook'] as String? ?? '').trim();

      // 解析场次
      final rawScenes = adaptResult.data['scenes'] as List?;
      final scenes = <DramaScene>[];
      if (rawScenes != null) {
        for (final s in rawScenes) {
          if (s is Map) {
            scenes.add(DramaScene.fromJson(s.cast<String, dynamic>()));
          }
        }
      }

      task.plannedSceneCount = scenes.length;
      task.addLog('完成戏剧场次提炼，共划分 ${scenes.length} 个戏剧场次节拍');
      task.advancePipelineStage(PipelineStage.beats, StageStatus.success);
      notifyListeners();

      // ---- Stage 4: 受保护契约锁定 (Contract) ----
      task.advancePipelineStage(PipelineStage.contract, StageStatus.running);
      task.addLog('锁定受保护关键台词与核心事实清单...');
      notifyListeners();

      ProtectedContract protectedContract = ProtectedContract.empty;
      final rawContract = adaptResult.data['protected_contract'];
      if (rawContract is Map) {
        protectedContract = ProtectedContract.fromJson(rawContract.cast<String, dynamic>());
      }
      task.protectedUtteranceCount = protectedContract.utterances.length;
      task.protectedFactCount = protectedContract.facts.length;
      task.addLog('已锁定 ${task.protectedUtteranceCount} 条原著金句台词，${task.protectedFactCount} 条核心因果事实');
      task.advancePipelineStage(PipelineStage.contract, StageStatus.success);
      notifyListeners();

      // ---- Stage 5: 剧集资产沉淀入库 (Storyboard) ----
      task.advancePipelineStage(PipelineStage.storyboard, StageStatus.running);
      _advance(task, ImportPhase.writing);
      task.addLog('将剧本场次与受保护契约沉淀至目标集 (第 ${task.targetEpisodeIndex} 集)...');
      notifyListeners();

      final screenplayTextRaw =
          (adaptResult.data['screenplay_text'] as String? ?? '').trim();
      final screenplayText = screenplayTextRaw.isNotEmpty
          ? screenplayTextRaw
          : DramaScene.exportToMarkdown(scenes);

      final updated = await _manager.importChapterToEpisode(
        seriesId: task.seriesId,
        masterExtraction: masterResult.data,
        targetEpisodeIndex: task.targetEpisodeIndex ?? 1,
        episodeTitle: adaptedTitle.isNotEmpty ? adaptedTitle : guessedTitle,
        episodeSynopsis: adaptedSynopsis.isNotEmpty ? adaptedSynopsis : novelText,
        episodeSummary: adaptedSummary.isNotEmpty
            ? adaptedSummary
            : '【第${task.targetEpisodeIndex}集前情】$adaptedSynopsis',
        episodeHook: adaptedHook.isNotEmpty ? adaptedHook : '章节末尾悬念展开',
        scenes: scenes,
        screenplayText: screenplayText,
        protectedContract: protectedContract,
      );

      // 自动对导入提取的场景补充七方位空间全息解构
      final scnsToDeconstruct = await _manager.listScenes(task.seriesId);
      if (scnsToDeconstruct.any((s) => !s.hasSpatialDeconstruction)) {
        task.addLog('补充场景空间全息解构 (7方位推演)...');
        notifyListeners();
        await _manager.deconstructAllScenesSpatialProfiles(
          task.seriesId,
          onProgress: (cur, tot, sName) {
            task.addLog('场景全息解构 [$cur/$tot]: $sName');
            notifyListeners();
          },
        );
      }

      final episodes = await _manager.listEpisodes(task.seriesId);
      final currentEp = episodes.firstWhere(
        (e) => e.index == (task.targetEpisodeIndex ?? 1),
        orElse: () => episodes.first,
      );
      task.plannedShotCount = currentEp.shots.length;
      task.addLog('工程写入完成，剧集与场次就绪');
      task.advancePipelineStage(PipelineStage.storyboard, StageStatus.success);
      notifyListeners();

      // ---- Stage 6: 导演门禁自动化质检 (Audit) ----
      task.advancePipelineStage(PipelineStage.audit, StageStatus.running);

      // 单章导入后 shots 被刻意置空（分镜必须由打磨后的剧本生成），此时对空
      // 列表跑 validate 会让 C01~C09 的循环一次都不进、passCount 恒为 10，
      // 算出 100% 的假满分。空列表时报告"无可检对象"（spec: 无分镜可检时
      // 不显示通过率）。
      if (currentEp.shots.isEmpty) {
        task.auditPassRate = null;
        task.addLog('门禁质检跳过：本集尚无分镜，无可检对象（请在剧本工作台生成分镜后再检）');
        task.advancePipelineStage(PipelineStage.audit, StageStatus.skipped);
        notifyListeners();
        await _finish(task, updated);
        task.addLog('漫剧解构流水线全部执行完毕！');
        return;
      }

      task.addLog('执行 C01~C09 导演规则自动化审计...');
      notifyListeners();

      final chars = await _manager.listCharacters(task.seriesId);
      final scns = await _manager.listScenes(task.seriesId);
      final report = DirectorValidationEngine.validate(
        episode: currentEp,
        shots: currentEp.shots,
        characters: chars,
        scenes: scns,
      );
      final totalRules = report.passCount + report.warningCount + report.blockingCount;
      task.auditPassRate = totalRules > 0 ? (report.passCount / totalRules * 100) : null;
      final rateLabel = task.auditPassRate == null
          ? '无可检对象'
          : '${task.auditPassRate!.toStringAsFixed(1)}%';
      task.addLog('门禁自动化审计完成: 质检通过率 $rateLabel (${report.issues.isEmpty ? "全项合规" : "${report.issues.length} 条待优化项"})');
      task.advancePipelineStage(PipelineStage.audit, StageStatus.success);
      notifyListeners();

      await _finish(task, updated);
      task.addLog('漫剧解构流水线全部执行完毕！');
    } on ConstraintParseError catch (e) {
      task.advancePipelineStage(task.currentStage, StageStatus.failed);
      _fail(
        task,
        'AI 输出无法解析（${_passName(task)}第 ${e.attempts} 次尝试）。'
        '原始输出已保留，可在 AI 调用日志中查看。',
        rawText: e.rawText,
      );
    } catch (e) {
      task.advancePipelineStage(task.currentStage, StageStatus.failed);
      _fail(task, '${_passName(task)}失败：$e');
    }
  }

  /// 推进阶段并广播。
  void _advance(NovelImportTask task, ImportPhase phase) {
    task.phase = phase;
    notifyListeners();
  }

  String _passName(NovelImportTask task) {
    if (task.phase == ImportPhase.extracting) return 'Pass 1/2 ';
    if (task.phase == ImportPhase.segmenting) {
      return task.isFullSeason ? 'Pass 2/2 ' : '单章提炼 ';
    }
    return '';
  }

  Future<void> _finish(NovelImportTask task, StudioSeries updated) async {
    task.phase = ImportPhase.done;
    task.isTerminalAt = DateTime.now();
    await VideoTaskLedger.instance.update(
      task.localId,
      status: VideoTaskLedgerStatus.completed,
    );
    // 成功导入会改写 series_profile 与集数结构，选中态必须刷新——否则 IP
    // 主库仍显示导入前的那份 series 快照。
    _manager.readSeries(task.seriesId);
    debugPrint(
      '[NovelImport] ${task.localId} 完成：${updated.name}',
    );
    notifyListeners();
  }

  void _fail(NovelImportTask task, String message, {String? rawText}) {
    task.phase = ImportPhase.failed;
    task.error = message;
    task.isTerminalAt = DateTime.now();
    VideoTaskLedger.instance.update(
      task.localId,
      status: VideoTaskLedgerStatus.failed,
      error: message,
    );
    if (rawText != null) {
      debugPrint('[NovelImport] ${task.localId} 原始输出:\n$rawText');
    }
    notifyListeners();
  }

  int _lastInterruptedCount = 0;

  /// 启动时从持久化台账（VideoTaskLedger）全量水合还原任务记录。
  ///
  /// **解决关窗重开后任务丢失的核心方法**：
  /// 1. 读取 ledger 中所有 `adapterId == novel-import` 的记录。
  /// 2. 若发现 `polling` 状态记录，说明应用或窗口在中途关闭导致进程退出。
  ///    将其更新为 `failed`（标记中断），并不自动重提以防重复计费。
  /// 3. 重建 `NovelImportTask` 对象填充至 `_tasks`，保留已有正在运行的实例。
  Future<int> hydrateFromLedger() async {
    final all = await VideoTaskLedger.instance.allEntries();
    final importEntries = all
        .where((e) => e.adapterId == adapterId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final currentRunningIds =
        _tasks.where((t) => t.isRunning).map((t) => t.localId).toSet();
    final hydrated = <NovelImportTask>[];
    var interruptedCount = 0;

    for (final entry in importEntries) {
      if (currentRunningIds.contains(entry.localId)) {
        continue;
      }

      ImportPhase phase;
      String? error = entry.error;
      DateTime? terminalAt;

      if (entry.status == VideoTaskLedgerStatus.completed) {
        phase = ImportPhase.done;
        terminalAt = entry.updatedAt;
      } else if (entry.status == VideoTaskLedgerStatus.polling) {
        // 发现未完结的残留任务：标记为中断
        interruptedCount++;
        phase = ImportPhase.interrupted;
        error = '应用退出导致中断，未完成。可手动重试。';
        terminalAt = DateTime.now();
        await VideoTaskLedger.instance.update(
          entry.localId,
          status: VideoTaskLedgerStatus.failed,
          error: error,
        );
      } else {
        if (entry.error?.contains('应用退出') == true ||
            entry.error?.contains('窗口关闭') == true ||
            entry.error?.contains('中断') == true) {
          phase = ImportPhase.interrupted;
        } else {
          phase = ImportPhase.failed;
        }
        terminalAt = entry.updatedAt;
      }

      final isFullSeason = entry.model.isNotEmpty
          ? entry.model == 'full-season'
          : (!entry.label.contains('第 ') && !entry.label.contains('集）'));
      final targetEp = entry.shotNumber;

      String title = '未命名小说';
      if (entry.label.startsWith('小说导入：')) {
        final afterPrefix = entry.label.substring('小说导入：'.length);
        final parenIdx = afterPrefix.lastIndexOf('（');
        if (parenIdx > 0) {
          title = afterPrefix.substring(0, parenIdx).trim();
        } else {
          title = afterPrefix.trim();
        }
      } else if (entry.prompt != null && entry.prompt!.isNotEmpty) {
        title = entry.prompt!.split(' · ').first.trim();
      }

      final task = NovelImportTask(
        localId: entry.localId,
        seriesId: entry.seriesId,
        novelId: entry.providerId == 'local-file' ? null : entry.providerId,
        novelTitle: title.isEmpty ? '未命名小说' : title,
        isFullSeason: isFullSeason,
        targetEpisodeIndex: targetEp,
        phase: phase,
        startedAt: entry.createdAt,
        error: error,
      );
      task.isTerminalAt = terminalAt;
      hydrated.add(task);
    }

    _lastInterruptedCount = interruptedCount;

    // 维持正在执行的任务在最前，合并水合的历史任务
    final running = _tasks.where((t) => t.isRunning).toList();
    _tasks.clear();
    _tasks.addAll(running);
    for (final task in hydrated) {
      if (!_tasks.any((t) => t.localId == task.localId)) {
        _tasks.add(task);
      }
    }
    _trimFinished();
    notifyListeners();
    return _tasks.length;
  }

  /// 启动时把「进程退出导致中断」的任务标记出来（兼容旧接口）。
  Future<int> recoverInterrupted() async {
    await hydrateFromLedger();
    return _lastInterruptedCount;
  }

  /// 移除单条任务记录（同时清理内存与持久化台账）。
  Future<void> removeTask(String localId) async {
    _tasks.removeWhere((t) => t.localId == localId);
    await VideoTaskLedger.instance.remove(localId);
    notifyListeners();
  }

  /// 清理所有已结束（完成、失败或中断）的历史任务。
  Future<void> clearFinishedTasks({String? seriesId}) async {
    final toRemove = _tasks.where((t) {
      if (t.isRunning) return false;
      if (seriesId != null && t.seriesId != seriesId) return false;
      return true;
    }).map((t) => t.localId).toList();

    for (final id in toRemove) {
      await removeTask(id);
    }
  }

  /// 用户主动重试一次被中断/失败的导入。
  ///
  /// 从 ledger 条目取回上下文（小说标题、范围），**但小说正文不在记录里**——
  /// 它可能非常大，且 Ledger 的 `prompt` 字段只存摘要。所以重试需要调用方
  /// 重新提供正文：UI 侧对「从小说库导入」的任务重新走一次选择流程。
  Future<String> retry({
    required String localId,
    required String novelText,
    required bool isFullSeason,
    required int targetEpisodeIndex,
    String? novelId,
    String novelTitle = '未命名小说',
    List<int> selectedChapterIndices = const [],
  }) async {
    final entry = await VideoTaskLedger.instance.findByLocalId(localId);
    final seriesId = entry?.seriesId ?? '';
    if (seriesId.isEmpty) {
      throw StateError('找不到该导入任务的记录，无法重试');
    }
    return submit(
      seriesId: seriesId,
      novelText: novelText,
      isFullSeason: isFullSeason,
      targetEpisodeIndex: targetEpisodeIndex,
      novelId: novelId,
      novelTitle: novelTitle,
      selectedChapterIndices: selectedChapterIndices,
    );
  }

  void _trimFinished() {
    final finished =
        _tasks.where((t) => !t.isRunning).toList()
          ..sort((a, b) => (b.isTerminalAt ?? b.startedAt)
              .compareTo(a.isTerminalAt ?? a.startedAt));
    if (finished.length <= _maxFinishedTasks) return;
    final toRemove = finished.skip(_maxFinishedTasks).map((t) => t.localId).toSet();
    _tasks.removeWhere((t) => toRemove.contains(t.localId));
  }
}
