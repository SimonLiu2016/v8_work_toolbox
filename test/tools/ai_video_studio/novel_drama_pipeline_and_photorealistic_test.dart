import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/novel_import_task_service.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/prompt_assembler.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_task_ledger.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/novel_selector_dialog.dart';
import 'package:V8WorkToolbox/tools/novel_manager/models/novel_models.dart';

void main() {
  late Directory tempDir;
  final manager = StudioProjectManager.instance;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('novel_drama_pipeline_test');
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

  group('NovelSelectionResult 内联范围集成', () {
    test('支持携带全季或单集选择状态，避免二次弹窗', () {
      final novel = NovelMetadata(
        id: 'novel_123',
        title: '人族镇魔司',
        author: '白驹易逝',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final fullSeasonResult = NovelSelectionResult(
        novel: novel,
        selectedChapterIndices: const [1, 2, 3],
        combinedText: '',
        isFullSeason: true,
        targetEpisodeIndex: 1,
      );
      expect(fullSeasonResult.isFullSeason, isTrue);
      expect(fullSeasonResult.selectedChapterIndices, equals([1, 2, 3]));

      final singleEpisodeResult = NovelSelectionResult(
        novel: novel,
        selectedChapterIndices: const [1],
        combinedText: '第一章内容',
        isFullSeason: false,
        targetEpisodeIndex: 5,
      );
      expect(singleEpisodeResult.isFullSeason, isFalse);
      expect(singleEpisodeResult.targetEpisodeIndex, equals(5));
    });
  });

  group('PhotorealisticPromptCompiler 原生中文导演语言与音画分流', () {
    test('编译生成纯原生中文结构化导演指令 (去伪渲染器咒语)', () {
      final shot = StudioShot(
        number: 1,
        shotSize: StudioShotSize.closeUp,
        cameraMove: 'slow push-in tracking',
        actionZh: '拔出玄铁斩妖刀，刀尖指向黑月妖，周身气血翻涌',
        dialogue: '【消耗五十点杀戮值，纯阳功提升至圆满】',
        durationSec: 4,
      );

      final prose = PhotorealisticPromptCompiler.compileShot(
        shot: shot,
        character: CharacterCard(
          id: 'c1',
          name: '沈长青',
          descriptionZh: '大夏镇魔司见习除魔使，身着玄黑镇魔服',
          basePromptPositive: 'young swordsman, black leather armor',
          updatedAt: DateTime.now(),
        ),
        scene: SceneCard(
          id: 'sc1',
          name: '临安城外乱葬岗',
          descriptionZh: '阴森破败的荒冢废墟，残月笼罩',
          promptEn: 'misty graveyard, ruins',
          updatedAt: DateTime.now(),
        ),
      );

      // 验证原生纯中文结构化导演指令标签
      expect(prose, contains('【镜头景别与运镜】'));
      expect(prose, contains('【空间与光影】'));
      expect(prose, contains('【出场主体】'));
      expect(prose, contains('【动作叙事】'));
      expect(prose, contains('【声音与画面约束】'));

      // 验证优先提取纯中文角色与场景描述，不含过时英文伪渲染器咒语与套皮词
      expect(prose, contains('大夏镇魔司见习除魔使，身着玄黑镇魔服'));
      expect(prose, contains('阴森破败的荒冢废墟，残月笼罩'));
      expect(prose, isNot(contains('Phase 1')));
      expect(prose, isNot(contains('UE5')));
      expect(prose, isNot(contains('Octane')));

      // 验证音画分流：系统属性信息被转为浮字特效，对白转为画外配音，画面指令要求闭口
      expect(prose, contains('浮字特效'));
      expect(prose, contains('画外配音: 【消耗五十点杀戮值，纯阳功提升至圆满】'));
      expect(prose, contains('闭口神态'));
      expect(prose, contains('无画内文字'));
    });

    test('普通对话对白剥离为后期配音且不破坏画面', () {
      final shot = StudioShot(
        number: 2,
        shotSize: StudioShotSize.medium,
        cameraMove: 'static',
        actionZh: '冷冷注视前方，眼神如铁',
        dialogue: '妖魔作乱，当诛！',
        durationSec: 3,
      );

      final prose = PhotorealisticPromptCompiler.compileShot(shot: shot);

      expect(prose, contains('画外配音: "妖魔作乱，当诛！"'));
      expect(prose, contains('闭口神态'));
      expect(prose, contains('严禁开口嘴型与画内文字'));
    });

    test('角色内心独白（OS）执行严格音画分流与微表情保持', () {
      final shot = StudioShot(
        number: 3,
        shotSize: StudioShotSize.closeUp,
        cameraMove: 'slow push-in',
        actionZh: '姜七夜嘴角微挑，眼神戏谑',
        dialogue: '姜七夜（内心 OS）：高空抛物，放前世拘你半个月。',
        durationSec: 3,
      );

      final prose = PhotorealisticPromptCompiler.compileShot(shot: shot);

      expect(prose, contains('角色心声/画外音: "姜七夜（内心 OS）：高空抛物，放前世拘你半个月。"'));
      expect(prose, contains('画面主体保持自然闭口与从容微表情'));
      expect(prose, contains('严禁开口嘴型与画内文字'));
    });

    test('默认负向提示词包含字幕、字符乱码与面部扭曲抑制词', () {
      final neg = PromptAssembler.defaultNegativePrompt;
      expect(neg, contains('subtitles'));
      expect(neg, contains('on-screen text'));
      expect(neg, contains('deformed mouth'));
      expect(neg, contains('speech bubble'));
    });
  });

  group('NovelImportTask 流水线阶段与实时控制台日志', () {
    test('记录六阶段状态流转与资产提炼', () async {
      final series = await manager.createSeries(name: '漫剧流水线测试剧');
      var callCount = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        callCount++;
        if (callCount == 1) {
          return ChatResult(
            text: '''
{"worldview": "大夏王朝，妖魔横行，人族设立镇魔司镇守四方。",
 "style_tokens": "oriental dark fantasy, photorealistic",
 "characters": [{"name": "沈长青", "description_zh": "青年除魔使"}],
 "scenes": [{"name": "镇魔司大殿", "description_zh": "庄严肃穆，青石石柱"}],
 "props": [{"name": "斩妖刀", "description_zh": "玄铁锻造"}]}
''',
            usedProviderId: 'mock',
            usedModel: 'mock',
            routingTrace: const [],
          );
        } else {
          return ChatResult(
            text: '''
{"title": "初入镇魔司",
 "synopsis": "沈长青通过见习考验正式加入镇魔司，被东方诏亲自授予斩妖刀与除魔令。殿堂之内晨光熹微，青石柱矗立，气氛庄严肃穆。沈长青立誓斩妖除魔庇佑人族，随即奉命前往临安城调查诡异妖祸。临安城外暗流涌动危机四伏，黑风呼啸残月如钩，未知妖魔已然悄然潜入，一场恶战一触即发。",
 "summary": "沈长青入职镇魔司受命出征。",
 "hook": "临安城黑风起，妖魔悄然潜入。",
 "scenes": [
   {"id": "sc1", "title": "镇魔司大殿授刀", "location": "大殿", "time_of_day": "清晨"}
 ],
 "protected_contract": {
   "facts": [{"id": "f1", "content": "沈长青获得玄铁斩妖刀"}],
   "utterances": [{"id": "u1", "speaker": "东方诏", "text": "斩妖除魔，护我人族！"}]
 }}
''',
            usedProviderId: 'mock',
            usedModel: 'mock',
            routingTrace: const [],
          );
        }
      };

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '镇魔司大殿之上，晨光破晓。沈长青立于殿前，手握除魔令。东方诏神情肃穆，正色道：“斩妖除魔，护我人族！”',
        isFullSeason: false,
        targetEpisodeIndex: 1,
        novelTitle: '人族镇魔司',
      );

      final task = NovelImportTaskService.instance.taskOf(localId);
      expect(task, isNotNull);

      // 等待任务执行完毕
      for (var i = 0; i < 200; i++) {
        if (!task!.isRunning) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(task!.phase, equals(ImportPhase.done));
      expect(task.currentStage, equals(PipelineStage.audit));
      expect(task.stageStatuses[PipelineStage.ingest], equals(StageStatus.success));
      expect(task.stageStatuses[PipelineStage.assets], equals(StageStatus.success));
      expect(task.stageStatuses[PipelineStage.beats], equals(StageStatus.success));
      expect(task.stageStatuses[PipelineStage.contract], equals(StageStatus.success));
      expect(task.stageStatuses[PipelineStage.storyboard], equals(StageStatus.success));
      // 单章导入后 shots 被重置为空（分镜必须由打磨后的剧本生成），此时对空
      // 列表跑 validate 会算出假满分——门禁质检应为 skipped 且不出数。
      expect(task.stageStatuses[PipelineStage.audit], equals(StageStatus.skipped));
      expect(task.auditPassRate, isNull);

      // 验证实时资产发现
      expect(task.discoveredCharacters, contains('沈长青'));
      expect(task.discoveredScenes, contains('镇魔司大殿'));
      expect(task.discoveredProps, contains('斩妖刀'));
      expect(task.protectedUtteranceCount, equals(1));
      expect(task.protectedFactCount, equals(1));

      // 验证实时终端日志
      expect(task.liveLogs.isNotEmpty, isTrue);
      expect(task.liveLogs.any((l) => l.contains('原著切片与解析流水线')), isTrue);
      expect(task.liveLogs.any((l) => l.contains('沈长青')), isTrue);
      expect(task.liveLogs.any((l) => l.contains('无可检对象')), isTrue);
    });

    test('全季导入未执行的后继阶段标记为 skipped，不伪造质检通过率', () async {
      final series = await manager.createSeries(name: '全季阶段状态测试剧');
      var callCount = 0;
      AiConstraintEngine.chatFn = ({
        slot = 'text',
        explicitProviderId,
        explicitModel,
        required messages,
        timeout,
        ignoreCooldown = false,
      }) async {
        callCount++;
        if (callCount == 1) {
          return ChatResult(
            text: '''
{"worldview": "大夏王朝，妖魔横行。",
 "style_tokens": "oriental dark fantasy",
 "characters": [{"name": "沈长青", "description_zh": "青年除魔使"}],
 "scenes": [{"name": "镇魔司大殿", "description_zh": "庄严肃穆"}],
 "props": []}
''',
            usedProviderId: 'mock',
            usedModel: 'mock',
            routingTrace: const [],
          );
        }
        return ChatResult(
          text: '''
{"episodes": [
 {"index": 1, "title": "初入镇魔司", "synopsis": "沈长青加入镇魔司。", "summary": "入职。", "hook": "临安城黑风起。"},
 {"index": 2, "title": "临安妖祸", "synopsis": "沈长青前往临安城。", "summary": "出征。", "hook": "妖魔现身。"}
]}
''',
          usedProviderId: 'mock',
          usedModel: 'mock',
          routingTrace: const [],
        );
      };

      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: '镇魔司大殿之上，晨光破晓。沈长青立于殿前。',
        isFullSeason: true,
        targetEpisodeIndex: 1,
        novelTitle: '人族镇魔司',
      );

      final task = NovelImportTaskService.instance.taskOf(localId);
      for (var i = 0; i < 200; i++) {
        if (!task!.isRunning) break;
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(task!.phase, equals(ImportPhase.done));
      expect(task.plannedSceneCount, equals(2));
      // 全季导入只跑到分集大纲：契约锁定、五维拆镜与门禁质检本次均未执行。
      expect(task.stageStatuses[PipelineStage.beats], equals(StageStatus.success));
      expect(task.stageStatuses[PipelineStage.contract], equals(StageStatus.skipped));
      expect(task.stageStatuses[PipelineStage.storyboard], equals(StageStatus.skipped));
      expect(task.stageStatuses[PipelineStage.audit], equals(StageStatus.skipped));
      expect(task.auditPassRate, isNull);
    });

    test('advancePipelineStage 不把已 skipped 的阶段回填为 success', () {
      final task = NovelImportTask(
        localId: 'local-backfill',
        seriesId: 'series-backfill',
        novelTitle: '回填测试',
        isFullSeason: true,
        startedAt: DateTime.now(),
      );

      task.advancePipelineStage(PipelineStage.contract, StageStatus.skipped);
      task.advancePipelineStage(PipelineStage.audit, StageStatus.skipped);
      // 推进到另一分支时，先前的 skipped 必须保留。
      task.advancePipelineStage(PipelineStage.storyboard, StageStatus.success);

      expect(task.stageStatuses[PipelineStage.contract], equals(StageStatus.skipped));
      expect(task.stageStatuses[PipelineStage.audit], equals(StageStatus.skipped));
      expect(task.stageStatuses[PipelineStage.storyboard], equals(StageStatus.success));
    });
  });
}
