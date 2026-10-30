import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/drama_director_contract.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';

/// spec: ai-video-studio/shot-causality-ordering · C11 因果倒置规则
///
/// C11 在消耗生成额度前拦截「反应台词排在触发动作之前」的分镜配置。
/// 判据是启发式（说话人 ≠ actionZh 中首个出现的角色名），所以定为 WARNING
/// 而非 BLOCKING——误报不该卡住用户，但风险要让用户在花钱前看见。
void main() {
  final now = DateTime(2026, 10, 23);

  StudioEpisode episodeWith(List<StudioShot> shots) => StudioEpisode(
    id: 'ep_1',
    seriesId: 's_01',
    index: 1,
    title: '第一集',
    shots: shots,
    createdAt: now,
    updatedAt: now,
  );

  final jiang = CharacterCard(
    id: 'c_jiang',
    name: '姜七夜',
    descriptionZh: '青年',
    updatedAt: now,
  );
  final wang = CharacterCard(
    id: 'c_wang',
    name: '老王',
    descriptionZh: '牢头',
    updatedAt: now,
  );

  group('C11 因果倒置规则', () {
    test('反应台词 + 无相位声明 → 报 C11 WARNING', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门，老王在背后跳脚',
        dialogue: '老王：你！你站住！反了你了！（预估2.0秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang, wang],
      );

      final c11 = report.issues.where((i) => i.ruleId == 'C11').toList();
      expect(c11, hasLength(1));
      expect(c11.first.severity, ValidationSeverity.warning);
      expect(c11.first.shotNumber, 1);
      // message 要点名说话人与首个动作执行者，用户才知道谁前谁后。
      expect(c11.first.message, contains('老王'));
      expect(c11.first.message, contains('姜七夜'));
      // suggestion 要给两条出路：拆分镜头或补相位声明。
      expect(c11.first.suggestion, contains('独立分镜'));
      expect(c11.first.suggestion, contains('temporal_evolution'));
    });

    test('同分镜但有 temporalEvolution 相位声明 → 不报 C11', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门，老王在背后跳脚',
        dialogue: '老王：你！你站住！反了你了！（预估2.0秒）',
        characterIds: ['c_jiang', 'c_wang'],
        directorDecisions: const DirectorDecisions(
          temporalEvolution: '前2.0秒姜七夜拱手转身牵驴向门口，后1.5秒老王跳脚喝骂',
        ),
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang, wang],
      );

      expect(report.issues.where((i) => i.ruleId == 'C11'), isEmpty);
    });

    test('内心独白不触发 C11', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜面无表情垂手而立，老王在旁瞪视',
        dialogue: '姜七夜（内心 OS）：又来了，这老头每月俸禄被扣，就拿我撒气。（预估3.0秒）',
        voiceType: UtteranceVoiceType.innerVoice,
        characterIds: ['c_jiang', 'c_wang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang, wang],
      );

      expect(report.issues.where((i) => i.ruleId == 'C11'), isEmpty);
    });

    test('说话人即首个动作执行者 → 不报 C11', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手一拜，转身牵驴离去',
        dialogue: '姜七夜：告辞了。（预估1.5秒）',
        characterIds: ['c_jiang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang],
      );

      expect(report.issues.where((i) => i.ruleId == 'C11'), isEmpty);
    });

    test('无台词 → 不报 C11', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门',
        characterIds: ['c_jiang', 'c_wang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang, wang],
      );

      expect(report.issues.where((i) => i.ruleId == 'C11'), isEmpty);
    });

    test('C11 是 WARNING 不阻断生成', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门，老王在背后跳脚',
        dialogue: '老王：反了你了！（预估1.5秒）',
        characterIds: ['c_jiang', 'c_wang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang, wang],
      );

      expect(report.issues.any((i) => i.ruleId == 'C11'), isTrue);
      expect(report.blockingCount, 0);
      expect(report.isValid, isTrue);
    });

    test('新增 C11 不影响既有 C01~C10 的既有断言', () {
      final shot = StudioShot(
        number: 1,
        actionZh: '奔跑然后拔剑转身跳跃出招',
        cameraMove: 'slow_push_in',
        directorDecisions: const DirectorDecisions(cameraStaging: '平视定机位'),
        dialogue: '姜七夜心声：“好险，老王又来了。”',
        characterIds: ['c_jiang'],
      );

      final report = DirectorValidationEngine.validate(
        episode: episodeWith([shot]),
        shots: [shot],
        characters: [jiang],
      );

      // C10 仍按原样触发（动作堆叠 + 运镜冲突）。
      expect(report.issues.where((i) => i.ruleId == 'C10'), isNotEmpty);
      // 10 分制评分基线未被 C11 改变。
      expect(report.passCount, lessThanOrEqualTo(10));
      expect(report.warningCount, greaterThan(0));
    });

    test('本地剧本映射产出的分镜不因占位时间相位而免检 C11', () {
      // convertScenesToShots 曾给 temporalEvolution 写常量「动作处于启动及
      // 推进相位」，而 C11 判空跳过——常量占位让本地映射的分镜永久免检，
      // AI 拆镜的反而要查（spec: 本地剧本映射不产出占位型导演决策）。
      final shots = AiConstraintEngine.convertScenesToShots([
        DramaScene(
          id: 'scene-1',
          sceneNumber: 1,
          title: '长街',
          location: '寒阳城长街',
          beats: [
            DramaBeat(
              id: 'beat-1',
              sceneId: 'scene-1',
              order: 1,
              name: '喝骂',
              action: '姜七夜拱手转身牵驴向门口走去',
              dialogueSpeaker: '老王',
              dialogue: '你站住！反了你了！',
            ),
          ],
        ),
      ]);

      expect(shots, hasLength(1));
      expect(shots[0].directorDecisions.temporalEvolution, isEmpty);
      expect(shots[0].directorDecisions.aestheticTexture, isEmpty);

      final report = DirectorValidationEngine.validate(
        episode: episodeWith(shots),
        shots: shots,
        characters: [jiang, wang],
      );
      expect(report.issues.any((i) => i.ruleId == 'C11'), isTrue);
    });
  });
}
