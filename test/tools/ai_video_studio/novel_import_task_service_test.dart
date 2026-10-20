import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/novel_import_task_service.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_task_ledger.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_task_recovery.dart';

/// 小说导入任务服务的契约回归。
///
/// 守四件容易回退的事：
/// 1. **阶段推进顺序**——用户看到的 "Pass 1/2 → Pass 2/2 → 写入" 必须与真实
///    执行一致，否则进度显示变成谎言；
/// 2. **UI 销毁不影响任务**——这是本次改动存在的理由。任务是服务级单例持有的，
///    `resetForTesting` 只清内存任务列表，模拟的正是"Widget 没了但服务还在"；
/// 3. **重启后不自动重提**——自动重提 = 二次计费。这条用"chatFn 调用次数不变"
///    来断言，比看状态字段更硬；
/// 4. **元数据保留**——ledger 记录必须带小说标识，否则"这是从哪本导入的"不可回溯。
void main() {
  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  ChatResult chatOf(String text) => ChatResult(
    text: text,
    usedProviderId: 'agnes',
    usedModel: 'agnes-3.0-pro',
    routingTrace: const [],
  );

  /// Pass 1 的合法输出（世界观 + 角色 + 场景，见 `_SchemaValidators`）。
  String masterJson() => '''
{"worldview": "架空民国异能都市。",
 "style_tokens": "cinematic 90s hong kong tone",
 "characters": [{"name": "陆寒川", "description_zh": "黑风衣，眼神冷冽"}],
 "scenes": [{"name": "雨夜废弃工厂", "description_zh": "锈蚀钢管与雨水倒影"}]}
''';

  /// Pass 2 的合法输出（分集规划）。
  String segmentJson() => '''
{"total_recommended_episodes": 2,
 "episodes": [
   {"index": 1, "title": "潜行", "synopsis": "潜入工厂", "summary": "发现图纸", "hook": "枪响"},
   {"index": 2, "title": "脱困", "synopsis": "反击", "summary": "击退杀手", "hook": "印章"}
 ]}
''';

  /// 单章提炼的合法输出（synopsis 需 ≥100 字）。
  String chapterJson() => '''
{"title": "墨大夫的图谋",
 "synopsis": "暴雨之夜，韩立推开神手谷密室木门，赫然发现墨大夫面色铁青，手中短刃寒光逼人，二人周旋试探，最终墨大夫骤然暴起施展鹰爪功锁喉，韩立生死一线间反手掷出毒粉迷其双目，近身扭打撞翻药架，短刃脱手刺入地面，墨大夫虽中剧毒却突然发出诡异怪笑，双目泛起渗人幽绿荧光，夺舍残魂破体而出悬浮半空。",
 "summary": "墨大夫图谋夺舍未果。",
 "hook": "长春功第四层的隐秘即将揭晓。"}
''';

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('novel_import_task_test');
    AppPaths.overrideRootForTesting(tempDir);
    VideoTaskLedger.instance.resetForTesting();
    NovelImportTaskService.instance.resetForTesting();
  });

  tearDown(() {
    AiConstraintEngine.resetForTesting();
    VideoTaskLedger.instance.resetForTesting();
    NovelImportTaskService.instance.resetForTesting();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 等一个任务到达终态。用于"任务在后台跑、测试要在 tearDown 前收尾"的场景。
  ///
  /// 等到终态后还要再多等一拍：终态本身也要写 ledger，而 ledger 的写是串行
  /// 链。不等待这一拍，tearDown 删掉 tempDir 时那条写可能还在队列里——
  /// 表现就是下一个测试报 PathNotFoundException / AppPaths 未初始化。
  Future<void> waitTerminal(NovelImportTask task) async {
    for (var i = 0; i < 200; i++) {
      if (!task.isRunning) break;
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }

  group('阶段推进', () {
    test('全案导入按 extracting → segmenting → writing → done 推进', () async {
      final series = await manager.createSeries(name: '导入测试剧');
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        // 第一次 = Pass 1 资产解构，第二次 = Pass 2 分集规划。
        return chatOf(calls == 1 ? masterJson() : segmentJson());
      };

      // 记录提交后立刻能看到的阶段：应该是 Pass 1。
      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '一部很长的民国异能小说正文',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelId: 'novel_abc',
        novelTitle: '民国异闻录',
      );
      final task = NovelImportTaskService.instance.taskOf(localId)!;
      expect(task.phase, ImportPhase.extracting);
      expect(task.novelId, 'novel_abc');
      expect(task.novelTitle, '民国异闻录');

      await waitTerminal(task);

      expect(task.phase, ImportPhase.done, reason: '两遍都成功后应到达 done');
      expect(calls, 2, reason: '全案导入是两遍 AI 调用');
      expect(await manager.listEpisodes(series.id), hasLength(2),
          reason: 'Pass 2 规划的两集应已写入');
      expect(await manager.listCharacters(series.id), hasLength(1));
    });

    test('单章导入走 adaptNovelChapter 并沉淀到目标集', () async {
      final series = await manager.createSeries(name: '单章测试剧');
      // 单章路径：第一遍返回 master，第二遍返回 chapter。
      var calls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        calls++;
        return chatOf(calls == 1 ? masterJson() : chapterJson());
      };

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '第七章 神手谷',
        isFullSeason: false,
        targetEpisodeIndex: 1,
        novelTitle: '凡人修仙',
      );
      final task = NovelImportTaskService.instance.taskOf(localId)!;
      await waitTerminal(task);
      expect(task.phase, ImportPhase.done);
      final episodes = await manager.listEpisodes(series.id);
      expect(episodes, hasLength(1));
      expect(episodes.first.title, '墨大夫的图谋');
    });
  });

  group('任务不依赖发起它的界面', () {
    test('清空内存任务列表后，ledger 记录仍在且任务状态可查', () async {
      final series = await manager.createSeries(name: 'UI销毁测试剧');
      // 让第一遍卡住：任务停在 extracting，模拟"正在跑"。
      final gate = Completer<void>();
      var pass = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        await gate.future;
        pass++;
        // 两遍都要能过 schema，否则任务会以 failed 收场，断言就失去意义。
        return chatOf(pass == 1 ? masterJson() : segmentJson());
      };

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '正在导入的小说',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: '进行中的小说',
      );
      final task = NovelImportTaskService.instance.taskOf(localId);

      // 任务已在 ledger 里落盘（先落盘再执行）。
      final entry = await VideoTaskLedger.instance.findByLocalId(localId);
      expect(entry, isNotNull, reason: '提交后必须立即有台账记录');
      expect(entry!.adapterId, NovelImportTaskService.adapterId);
      expect(entry.status, VideoTaskLedgerStatus.polling);
      expect(entry.seriesId, series.id);

      // 模拟 UI 被销毁：内存任务列表清空（服务本身还在，这是进程级单例）。
      NovelImportTaskService.instance.resetForTesting();
      expect(NovelImportTaskService.instance.taskOf(localId), isNull,
          reason: '内存任务已随 UI 一起被清空');

      // 但持久事实还在——这正是"切页签/关窗后仍可追索"的存储侧保证。
      final afterReset = await VideoTaskLedger.instance.findByLocalId(localId);
      expect(afterReset, isNotNull);
      expect(afterReset!.status, VideoTaskLedgerStatus.polling);

      gate.complete();
      // 放开后任务继续跑完（执行体不被 UI 销毁影响）。
      // 必须在这里等它终态：tearDown 会 reset AppPaths，而 _finish/_fail 仍要
      // 写 ledger——晚一步就是 "Bad state: AppPaths 尚未初始化"。
      if (task != null) {
        await waitTerminal(task);
      }
      final done = await VideoTaskLedger.instance.findByLocalId(localId);
      expect(done!.status, VideoTaskLedgerStatus.completed);
    });

    test('同一剧集已有进行中导入时拒绝重复提交', () async {
      final series = await manager.createSeries(name: '并发测试剧');
      final gate = Completer<void>();
      var pass = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        await gate.future;
        pass++;
        return chatOf(pass == 1 ? masterJson() : segmentJson());
      };

      final firstId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '第一本',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: '第一本',
      );

      expect(
        () => NovelImportTaskService.instance.submit(
          seriesId: series.id,
          novelText: '第二本',
          isFullSeason: true,
          targetEpisodeIndex: 1,
          novelTitle: '第二本',
        ),
        throwsA(isA<StateError>()),
        reason: '并发导入会让两遍 AI 调用交错写同一份 series_profile.json',
      );

      // 放开后等它终态再结束。tearDown 会 reset AppPaths，而终态仍要写
      // ledger——不等到终态，下一次 tearDown 之后就会有后台写撞上
      // "AppPaths 尚未初始化"。
      gate.complete();
      final first = NovelImportTaskService.instance.taskOf(firstId);
      if (first != null) await waitTerminal(first);
    });
  });

  group('重启后的中断语义', () {
    test('recoverInterrupted 标记中断且不重新提交', () async {
      final series = await manager.createSeries(name: '重启测试剧');
      var chatCalls = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        chatCalls++;
        return chatOf(masterJson());
      };

      // 先完成一次导入，留一条 completed 记录。
      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '已完成的小说',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: '已完成的小说',
      );
      final t = NovelImportTaskService.instance.taskOf(localId);
      if (t != null) await waitTerminal(t);
      expect(chatCalls, greaterThan(0));

      // 再造一条"进程退出时仍在跑"的记录：直接注入 polling 态。
      await VideoTaskLedger.instance.record(
        providerId: 'novel_x',
        adapterId: NovelImportTaskService.adapterId,
        model: '',
        remoteTaskId: '',
        seriesId: series.id,
        episodeId: '',
        segmentId: '',
        shotNumber: null,
        label: '小说导入：被打断的小说（完整长篇小说）',
        targetPath: '',
        localId: 'novel-import_interrupted_one',
      );

      final before = chatCalls;
      final recovered = await NovelImportTaskService.instance.recoverInterrupted();

      expect(recovered, 1, reason: '应标记一条被中断的任务');
      final entry = await VideoTaskLedger.instance
          .findByLocalId('novel-import_interrupted_one');
      expect(entry!.status.isActive, isFalse, reason: '中断后不再是 active');
      expect(entry.error, contains('应用退出'),
          reason: '必须写明是应用退出导致，用户才知道不是导入本身失败');

      // 关键断言：恢复过程绝不重新发起导入请求（= 绝不二次计费）。
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(chatCalls, before,
          reason: 'recoverInterrupted MUST NOT 触发任何 AI 调用');
    });

    test('已完成的导入记录不会被 recoverInterrupted 触碰', () async {
      final series = await manager.createSeries(name: '完成保护剧');
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async =>
          chatOf(masterJson());

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: 'x',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: 'x',
      );
      final t = NovelImportTaskService.instance.taskOf(localId);
      if (t != null) await waitTerminal(t);

      expect(await NovelImportTaskService.instance.recoverInterrupted(), 0);
    });
  });

  group('失败处理', () {
    test('AI 输出无法解析时记录失败原因与遍次', () async {
      final series = await manager.createSeries(name: '失败测试剧');
      // 永远回坏 JSON：引擎内部重试 3 次后抛 ConstraintParseError。
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async =>
          chatOf('这不是 JSON，是一段抱怨');

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '无法解析的小说',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: '无法解析的小说',
      );
      final task = NovelImportTaskService.instance.taskOf(localId)!;
      await waitTerminal(task);

      expect(task.phase, ImportPhase.failed);
      expect(task.error, isNotNull);
      expect(task.error, contains('Pass 1/2'),
          reason: '必须说明失败发生在哪一遍');
      expect(task.error, contains('3'),
          reason: '必须说明是第几次尝试（引擎最多 3 次）');

      final entry = await VideoTaskLedger.instance.findByLocalId(localId);
      expect(entry!.status, VideoTaskLedgerStatus.failed);
    });

    test('剧集不存在时提交抛错且不留下台账条目', () async {
      expect(
        () => NovelImportTaskService.instance.submit(
          seriesId: 'no_such_series',
          novelText: 'x',
          isFullSeason: true,
          targetEpisodeIndex: 1,
          novelTitle: 'x',
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('元数据保留', () {
    test('从小说库导入时记录带 novelId 与标题', () async {
      final series = await manager.createSeries(name: '元数据测试剧');
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async =>
          chatOf(masterJson());

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '正文',
        isFullSeason: false,
        targetEpisodeIndex: 2,
        novelId: 'novel_xyz',
        novelTitle: '剑来',
        selectedChapterIndices: [3, 4, 5],
      );
      final t = NovelImportTaskService.instance.taskOf(localId);
      if (t != null) await waitTerminal(t);

      final all = await VideoTaskLedger.instance.allEntries();
      final entry = all.firstWhere(
        (e) => e.adapterId == NovelImportTaskService.adapterId,
      );
      expect(entry.prompt, contains('剑来'), reason: '标题要能认得出是哪本');
      expect(entry.prompt, contains('3-5'), reason: '章节范围要可回溯');
      expect(entry.label, contains('剑来'));
      expect(entry.label, contains('第 2 集'), reason: '单章导入要能看出目标集');
    });

    test('文件导入（novelId 为 null）不报错', () async {
      final series = await manager.createSeries(name: '文件导入剧');
      var pass = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        pass++;
        return chatOf(pass == 1 ? masterJson() : segmentJson());
      };

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '本地文件正文',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: 'my_novel.txt',
      );
      expect(localId, isNotEmpty);
      // 台账记录在提交后立即就有——不用等任务跑完（spec: 先落盘再执行）。
      final entry = await VideoTaskLedger.instance.findByLocalId(localId);
      expect(entry, isNotNull);
      expect(entry!.prompt, contains('my_novel.txt'));

      // 等终态再结束：tearDown 会 reset AppPaths，后台仍要写 ledger。
      final task = NovelImportTaskService.instance.taskOf(localId);
      if (task != null) await waitTerminal(task);
    });
  });

  group('与视频任务台账的隔离', () {
    test('导入条目会进入 pendingEntries，但恢复路径不碰它', () async {
      // 这条守的是一个真实的交叉污染风险：导入条目的 status 是 polling，
      // 会出现在 VideoTaskLedger.pendingEntries() 里，而恢复扫描会遍历它。
      // 若没有显式跳过，_buildAdapter 返回 null 只会被当成"供应商配置丢了"，
      // 导入条目于是以"云端仍在处理"的姿态永远挂在那里。
      await VideoTaskLedger.instance.record(
        providerId: 'novel_y',
        adapterId: NovelImportTaskService.adapterId,
        model: '',
        remoteTaskId: '',
        seriesId: 's1',
        episodeId: '',
        segmentId: '',
        shotNumber: null,
        label: '小说导入：隔离测试',
        targetPath: '',
        localId: 'novel-import_isolation',
      );

      final pending = await VideoTaskLedger.instance.pendingEntries();
      expect(
        pending.where((e) => e.adapterId == NovelImportTaskService.adapterId),
        isNotEmpty,
        reason: '确认这条确实会进入 pending——所以恢复路径必须显式跳过它',
      );

      // 恢复扫描跑完后，导入条目必须原封不动：
      // 状态仍是 polling（没被误改成终态）、没被 remove。
      VideoTaskRecovery.instance.resetForTesting();
      await VideoTaskRecovery.instance.startOnce();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final after = await VideoTaskLedger.instance
          .findByLocalId('novel-import_isolation');
      expect(after, isNotNull, reason: '恢复路径 MUST NOT 删除导入条目');
      expect(after!.status, VideoTaskLedgerStatus.polling,
          reason: '恢复路径 MUST NOT 改动导入条目状态');
    });
  });

  group('hydrateFromLedger 跨重启水合还原', () {
    test('从 ledger 还原已完成任务与标记中断任务', () async {
      final service = NovelImportTaskService.instance;
      service.resetForTesting();
      expect(service.tasks, isEmpty);

      // 模拟磁盘上有 1 个已完成任务和 1 个上次关窗遗留的 polling 任务
      await VideoTaskLedger.instance.record(
        providerId: 'local-file',
        adapterId: NovelImportTaskService.adapterId,
        model: 'full-season',
        remoteTaskId: '',
        seriesId: 'series_hyd_1',
        episodeId: '',
        segmentId: '',
        shotNumber: null,
        label: '小说导入：遮天（完整长篇小说）',
        targetPath: '',
        localId: 'novel-import_completed_1',
      );
      await VideoTaskLedger.instance.update(
        'novel-import_completed_1',
        status: VideoTaskLedgerStatus.completed,
      );

      await VideoTaskLedger.instance.record(
        providerId: 'novel_x',
        adapterId: NovelImportTaskService.adapterId,
        model: 'single-episode',
        remoteTaskId: '3',
        seriesId: 'series_hyd_1',
        episodeId: 'ep_3',
        segmentId: '',
        shotNumber: 3,
        label: '小说导入：仙逆（第 3 集）',
        targetPath: '',
        localId: 'novel-import_interrupted_1',
      );

      // 执行水合
      final count = await service.hydrateFromLedger();
      expect(count, 2);
      expect(service.tasks, hasLength(2));

      final completedTask = service.taskOf('novel-import_completed_1');
      expect(completedTask, isNotNull);
      expect(completedTask!.phase, ImportPhase.done);
      expect(completedTask.novelTitle, '遮天');
      expect(completedTask.isFullSeason, isTrue);

      final interruptedTask = service.taskOf('novel-import_interrupted_1');
      expect(interruptedTask, isNotNull);
      expect(interruptedTask!.phase, ImportPhase.interrupted);
      expect(interruptedTask.novelTitle, '仙逆');
      expect(interruptedTask.isFullSeason, isFalse);
      expect(interruptedTask.targetEpisodeIndex, 3);
      expect(interruptedTask.error, contains('应用退出'));

      // 验证最新任务查询
      final latest = service.latestTaskFor('series_hyd_1');
      expect(latest, isNotNull);

      // 验证清理完成任务
      await service.clearFinishedTasks(seriesId: 'series_hyd_1');
      expect(service.tasks, isEmpty);
    });
  });
}
