import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/director_validation_engine.dart';

/// spec: shot-continuity · C12 场景指涉冲突（第 7 组）
void main() {
  group('C12 场景指涉冲突', () {
    final now = DateTime(2026, 10, 24);

    SceneCard scene(String id, String name, String desc) => SceneCard(
          id: id,
          name: name,
          descriptionZh: desc,
          updatedAt: now,
        );

    ValidationReport run(List<StudioShot> shots, List<SceneCard> scenes) {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 's_01',
        index: 1,
        title: '第一集',
        shots: shots,
        createdAt: now,
        updatedAt: now,
      );
      return DirectorValidationEngine.validate(
        episode: episode,
        shots: shots,
        scenes: scenes,
      );
    }

    test('地牢场景 + 动作含「走出衙门」→ 报 C12', () {
      final shots = [
        StudioShot(
          number: 1,
          actionZh: '姜七夜拱手随意一拜，转身牵驴走出衙门',
          sceneId: 's_dungeon',
        )
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '阴冷的砖石地牢，两侧牢房以粗壮木栅封禁')]);

      final c12 = report.issues.where((i) => i.ruleId == 'C12').toList();
      expect(c12, hasLength(1));
      expect(c12.first.severity, ValidationSeverity.warning);
      expect(c12.first.shotNumber, 1);
      expect(c12.first.message, contains('衙门'));
      expect(c12.first.message, contains('巡城司大牢'));
      // suggestion 给两条出路。
      expect(c12.first.suggestion, contains('改绑'));
    });

    test('地牢场景 + 牢内动作 → 不报', () {
      final shots = [
        StudioShot(
          number: 1,
          actionZh: '姜七夜拱手告辞，转身走向牢门通道',
          sceneId: 's_dungeon',
        )
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '阴冷的砖石地牢，两侧牢房以粗壮木栅封禁')]);

      expect(report.issues.where((i) => i.ruleId == 'C12'), isEmpty);
    });

    test('场景名词已被场景描述覆盖 → 不报', () {
      final shots = [
        StudioShot(
          number: 1,
          actionZh: '姜七夜走出衙门，翻身骑上驴背',
          sceneId: 's_gate',
        )
      ];
      // 场景名与描述都含「衙门」。
      final report = run(shots, [scene('s_gate', '衙门', '衙门大门外的青石广场')]);

      expect(report.issues.where((i) => i.ruleId == 'C12'), isEmpty);
    });

    test('未关联场景的分镜不报', () {
      final shots = [
        StudioShot(number: 1, actionZh: '姜七夜拱手走出衙门', sceneId: '')
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '地牢')]);

      expect(report.issues.where((i) => i.ruleId == 'C12'), isEmpty);
    });

    test('场景卡不存在时不报', () {
      final shots = [
        StudioShot(number: 1, actionZh: '姜七夜拱手走出衙门', sceneId: 's_missing')
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '地牢')]);

      expect(report.issues.where((i) => i.ruleId == 'C12'), isEmpty);
    });

    test('一个分镜最多报一次（不刷屏）', () {
      final shots = [
        StudioShot(
          number: 1,
          actionZh: '姜七夜走出衙门，穿过长街，进客栈翻身跃上屋顶',
          sceneId: 's_dungeon',
        )
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '地牢')]);

      expect(report.issues.where((i) => i.ruleId == 'C12'), hasLength(1));
    });

    test('C12 不影响既有 C 规则', () {
      final shots = [
        StudioShot(
          number: 1,
          actionZh: '姜七夜奔跑拔剑转身跳跃出招',
          cameraMove: 'slow_push_in',
          directorDecisions: const DirectorDecisions(cameraStaging: '平视定机位'),
          sceneId: 's_dungeon',
        )
      ];
      final report = run(shots, [scene('s_dungeon', '巡城司大牢', '地牢')]);

      // C10 仍按原样触发（动作堆叠 + 运镜冲突）。
      expect(report.issues.where((i) => i.ruleId == 'C10'), isNotEmpty);
      expect(report.passCount, lessThanOrEqualTo(10));
    });
  });
}
