import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ai_constraint_engine.dart';

void main() {
  group('Scene & Shot Hierarchy and Storyboard Controls Tests', () {
    test('CharacterCard aliases JSON 序列化与反序列化保持双向兼容', () {
      final card = CharacterCard(
        id: 'char_001',
        name: '姜七夜',
        aliases: const ['姜七少', '七少', '少东家'],
        updatedAt: DateTime(2026, 10, 19),
      );

      final json = card.toJson();
      expect(json['aliases'], ['姜七少', '七少', '少东家']);

      final restored = CharacterCard.fromJson(json);
      expect(restored.name, '姜七夜');
      expect(restored.aliases, ['姜七少', '七少', '少东家']);

      // 旧 JSON 没有 aliases 字段时默认为空
      final legacy = CharacterCard.fromJson({
        'id': 'char_002',
        'name': '李四',
      });
      expect(legacy.aliases, isEmpty);
    });

    test('convertScenesToShots 正确将场次绑定到真实 SceneCard.id，并支持角色别名与代称识别', () {
      final scenes = [
        const DramaScene(
          id: 'SC001',
          sceneNumber: 1,
          title: '天人居大酒楼',
          location: '天人居三楼雅间',
          beats: [
            DramaBeat(
              id: 'beat_1',
              sceneId: 'SC001',
              order: 1,
              action: '姜七少推门而入，目光警惕地打量四周。',
              dialogue: '少东家在何处？',
              dialogueSpeaker: '姜七少',
            ),
            DramaBeat(
              id: 'beat_2',
              sceneId: 'SC001',
              order: 2,
              action: '余小白从屏风后走出，拱手施礼。',
              dialogue: '七夜兄，别来无恙。',
              dialogueSpeaker: '余小白',
            ),
          ],
        ),
      ];

      final characters = [
        CharacterCard(
          id: 'char_jiang',
          name: '姜七夜',
          aliases: const ['姜七少', '七少'],
          updatedAt: DateTime(2026, 10, 19),
        ),
        CharacterCard(
          id: 'char_yu',
          name: '余小白',
          aliases: const ['少东家'],
          updatedAt: DateTime(2026, 10, 19),
        ),
      ];

      final sceneCards = [
        SceneCard(
          id: 'scene_tianrenju_001',
          name: '天人居三楼雅间',
          descriptionZh: '雕梁画栋，红木桌椅，窗外可鸟瞰寒阳城全景。',
          updatedAt: DateTime(2026, 10, 19),
        ),
      ];

      final shots = AiConstraintEngine.convertScenesToShots(
        scenes,
        characters: characters,
        sceneCards: sceneCards,
      );

      expect(shots.length, 2);

      // 验证场景映射到真实 sceneCard.id
      expect(shots[0].sceneId, 'scene_tianrenju_001');
      expect(shots[1].sceneId, 'scene_tianrenju_001');

      // 验证首镜识别姜七少（匹配到姜七夜）与少东家（匹配到余小白）
      expect(shots[0].characterIds, contains('char_jiang'));
      expect(shots[0].characterIds, contains('char_yu'));

      // 验证第二镜识别余小白与七夜
      expect(shots[1].characterIds, contains('char_yu'));
      expect(shots[1].characterIds, contains('char_jiang'));

      // 验证大段归属
      expect(shots[0].segmentId, 'seg-1');
      expect(shots[1].segmentId, 'seg-1');
    });

    test('StudioEpisode.buildSegmentsFromScenes 按场次 1:1 归组且时长为镜头之和无 12s 上限', () {
      final scenes = [
        const DramaScene(
          id: 'SC001',
          sceneNumber: 1,
          title: '演武场大比',
          location: '寒阳城外校场',
          beats: [
            DramaBeat(id: 'b1', sceneId: 'SC001', order: 1, action: '起手式'),
            DramaBeat(id: 'b2', sceneId: 'SC001', order: 2, action: '拔剑出鞘'),
            DramaBeat(id: 'b3', sceneId: 'SC001', order: 3, action: '雷霆万钧一击'),
            DramaBeat(id: 'b4', sceneId: 'SC001', order: 4, action: '收剑回鞘'),
          ],
        ),
      ];

      final shots = [
        const StudioShot(number: 1, durationSec: 5.0, beatId: 'b1', segmentId: 'seg-1'),
        const StudioShot(number: 2, durationSec: 6.0, beatId: 'b2', segmentId: 'seg-1'),
        const StudioShot(number: 3, durationSec: 8.0, beatId: 'b3', segmentId: 'seg-1'),
        const StudioShot(number: 4, durationSec: 4.0, beatId: 'b4', segmentId: 'seg-1'),
      ];

      final segments = StudioEpisode.buildSegmentsFromScenes(scenes, shots);
      expect(segments.length, 1);
      final seg = segments.first;
      expect(seg.id, 'seg-1');
      expect(seg.shotNumbers, [1, 2, 3, 4]);
      // 5 + 6 + 8 + 4 = 23 秒，完全打破 12 秒上限
      expect(seg.targetDurationSec, 23);
      expect(seg.boundaryReason, contains('演武场大比'));
    });

    test('StudioEpisode.buildSegmentsFromScenes 多场次 beatId 编号相同时片段严格独占且互斥', () {
      final scenes = [
        const DramaScene(
          id: 'SC001',
          sceneNumber: 1,
          title: '地牢提刑斩首',
          beats: [
            DramaBeat(id: 'B01', sceneId: 'SC001', order: 1, action: '押赴刑场'),
            DramaBeat(id: 'B02', sceneId: 'SC001', order: 2, action: '鬼头刀起'),
            DramaBeat(id: 'B03', sceneId: 'SC001', order: 3, action: '黑气入体'),
          ],
        ),
        const DramaScene(
          id: 'SC002',
          sceneNumber: 2,
          title: '长街拔刀接鸡',
          beats: [
            DramaBeat(id: 'B01', sceneId: 'SC002', order: 1, action: '红衣女子抛鸡'),
            DramaBeat(id: 'B02', sceneId: 'SC002', order: 2, action: '斩鸡入袋'),
          ],
        ),
        const DramaScene(
          id: 'SC003',
          sceneNumber: 3,
          title: '破屋珠醒炼化',
          beats: [
            DramaBeat(id: 'B01', sceneId: 'SC003', order: 1, action: '盘膝打坐'),
            DramaBeat(id: 'B02', sceneId: 'SC003', order: 2, action: '金光游走全身'),
          ],
        ),
      ];

      final shots = [
        const StudioShot(number: 1, durationSec: 10.0, beatId: 'B01', segmentId: 'seg-1'),
        const StudioShot(number: 2, durationSec: 9.0, beatId: 'B02', segmentId: 'seg-1'),
        const StudioShot(number: 3, durationSec: 6.0, beatId: 'B03', segmentId: 'seg-1'),
        const StudioShot(number: 4, durationSec: 7.0, beatId: 'B01', segmentId: 'seg-2'),
        const StudioShot(number: 5, durationSec: 8.0, beatId: 'B02', segmentId: 'seg-2'),
        const StudioShot(number: 6, durationSec: 5.0, beatId: 'B01', segmentId: 'seg-3'),
        const StudioShot(number: 7, durationSec: 7.0, beatId: 'B02', segmentId: 'seg-3'),
      ];

      final segments = StudioEpisode.buildSegmentsFromScenes(scenes, shots);
      expect(segments.length, 3);

      expect(segments[0].id, 'seg-1');
      expect(segments[0].shotNumbers, [1, 2, 3]);
      expect(segments[0].targetDurationSec, 25);

      expect(segments[1].id, 'seg-2');
      expect(segments[1].shotNumbers, [4, 5]);
      expect(segments[1].targetDurationSec, 15);

      expect(segments[2].id, 'seg-3');
      expect(segments[2].shotNumbers, [6, 7]);
      expect(segments[2].targetDurationSec, 12);

      // 验证互斥：各片段镜号完全独占
      final allAssigned = segments.expand((s) => s.shotNumbers).toList();
      expect(allAssigned, [1, 2, 3, 4, 5, 6, 7]);
      expect(allAssigned.toSet().length, 7);
    });

    test('StudioEpisode deleteShot 自动平移连续镜号并更新大段时长', () {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 'series_1',
        scenes: const [
          DramaScene(id: 'SC001', sceneNumber: 1, title: '客栈'),
        ],
        shots: const [
          StudioShot(number: 1, durationSec: 4.0, actionZh: '镜1', segmentId: 'seg-1'),
          StudioShot(number: 2, durationSec: 5.0, actionZh: '镜2', segmentId: 'seg-1'),
          StudioShot(number: 3, durationSec: 6.0, actionZh: '镜3', segmentId: 'seg-1'),
        ],
        segments: const [
          StudioSegment(id: 'seg-1', shotNumbers: [1, 2, 3], targetDurationSec: 15),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 删除第 2 镜
      final updated = episode.deleteShot(2);
      expect(updated.shots.length, 2);
      expect(updated.shots[0].number, 1);
      expect(updated.shots[0].actionZh, '镜1');
      expect(updated.shots[1].number, 2); // 原第 3 镜平移为第 2 镜
      expect(updated.shots[1].actionZh, '镜3');

      // 大段时长重算：4 + 6 = 10
      expect(updated.segments.first.shotNumbers, [1, 2]);
      expect(updated.segments.first.targetDurationSec, 10);
    });

    test('StudioEpisode insertShotAfter 插入新镜头并重编后续镜号', () {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 'series_1',
        scenes: const [
          DramaScene(id: 'SC001', sceneNumber: 1, title: '客栈'),
        ],
        shots: const [
          StudioShot(number: 1, durationSec: 4.0, sceneId: 'scene_001', segmentId: 'seg-1'),
          StudioShot(number: 2, durationSec: 5.0, sceneId: 'scene_001', segmentId: 'seg-1'),
        ],
        segments: const [
          StudioSegment(id: 'seg-1', shotNumbers: [1, 2], targetDurationSec: 9),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // 在第 1 镜后插入新镜头
      final updated = episode.insertShotAfter(1);
      expect(updated.shots.length, 3);
      expect(updated.shots[0].number, 1);
      expect(updated.shots[1].number, 2); // 新插入的空白镜头
      expect(updated.shots[1].durationSec, 4.0);
      expect(updated.shots[1].sceneId, 'scene_001'); // 继承前镜场景
      expect(updated.shots[2].number, 3); // 原第 2 镜后移为第 3 镜

      // 大段包含 3 镜，时长 4 + 4 + 5 = 13
      expect(updated.segments.first.shotNumbers, [1, 2, 3]);
      expect(updated.segments.first.targetDurationSec, 13);
    });

    test('StudioEpisode clearShots 清空分镜与大段', () {
      final episode = StudioEpisode(
        id: 'ep_1',
        seriesId: 'series_1',
        shots: const [StudioShot(number: 1)],
        segments: const [StudioSegment(id: 'seg-1')],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final cleared = episode.clearShots();
      expect(cleared.shots, isEmpty);
      expect(cleared.segments, isEmpty);
    });

    test('DramaScene.sceneCardId 字段 JSON 序列化与反序列化保持双向兼容', () {
      const scene = DramaScene(
        id: 'SC001',
        sceneNumber: 1,
        title: '值房对峙',
        location: '巡城司后院值房',
        sceneCardId: 'card_jail_uuid',
      );

      final json = scene.toJson();
      expect(json['scene_card_id'], 'card_jail_uuid');

      final restored = DramaScene.fromJson(json);
      expect(restored.sceneCardId, 'card_jail_uuid');
      expect(restored.id, 'SC001');

      // 缺失 scene_card_id 的遗留 JSON 反序列化为空串
      final legacy = DramaScene.fromJson({
        'id': 'SC002',
        'title': '长街',
      });
      expect(legacy.sceneCardId, '');
    });

    test('AiConstraintEngine.resolveSceneCardId 分词打分精准匹配且杜绝回退 SC001', () {
      final sceneCards = [
        SceneCard(
          id: 'card_jail',
          name: '巡城司大牢',
          descriptionZh: '牢狱阴森潮湿，牢头值房设于外间。',
          updatedAt: DateTime.now(),
        ),
        SceneCard(
          id: 'card_street',
          name: '寒阳城长街',
          descriptionZh: '宽阔青石街道，商铺林立。',
          updatedAt: DateTime.now(),
        ),
        SceneCard(
          id: 'card_palace',
          name: '宣王府',
          descriptionZh: '朱漆大门，巍峨高耸。',
          updatedAt: DateTime.now(),
        ),
      ];

      // 1. "巡城司后院值房" 命中 "巡城司大牢"（分词命中"巡城司"、描述命中"值房"）
      const scene1 = DramaScene(
        id: 'SC001',
        title: '巡城司值房训斥',
        location: '巡城司后院值房',
      );
      final id1 = AiConstraintEngine.resolveSceneCardId(scene1, sceneCards);
      expect(id1, 'card_jail');

      // 2. "寒阳城天人居酒楼前长街" 命中 "寒阳城长街"（分词命中"寒阳城"与"长街"）
      const scene2 = DramaScene(
        id: 'SC002',
        title: '长街拔刀接鸡',
        location: '寒阳城天人居酒楼前长街',
      );
      final id2 = AiConstraintEngine.resolveSceneCardId(scene2, sceneCards);
      expect(id2, 'card_street');

      // 3. 显式指定 sceneCardId 优先于文本模糊推断
      const sceneExplicit = DramaScene(
        id: 'SC002',
        title: '长街拔刀接鸡',
        location: '寒阳城天人居酒楼前长街',
        sceneCardId: 'card_palace', // 用户手动改选为宣王府
      );
      final idExplicit = AiConstraintEngine.resolveSceneCardId(sceneExplicit, sceneCards);
      expect(idExplicit, 'card_palace');

      // 4. 全新地点（破旧小院）无足够置信度时返回空字符串，绝不回退为 SC003
      const scene3 = DramaScene(
        id: 'SC003',
        title: '归家珠醒明悟',
        location: '姜七夜租住的破旧小院',
      );
      final id3 = AiConstraintEngine.resolveSceneCardId(scene3, sceneCards);
      expect(id3, isEmpty);
      expect(id3, isNot('SC003'));
    });
  });
}

