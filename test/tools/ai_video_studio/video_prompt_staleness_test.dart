import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';

/// spec: 分镜字段变更作废缓存的视频提示词
///
/// 定制视频提示词（`shot.videoPrompt`）是一次性快照。`buildVideoGenPrompt`
/// 开头会原样返回它——用户存下它之后若又改了动作、台词、出场角色、场景或素材
/// 绑定，那份快照就不再反映最新字段，新绑定的 `<Picture N>` 与最新因果时间轴
/// 永远进不去生成请求。
///
/// 这里守来源键的构成与失效判定。
void main() {
  StudioShot baseShot() => const StudioShot(
    number: 1,
    actionZh: '姜七夜拱手一拜',
    dialogue: '老王：你站住！',
    characterIds: ['c1', 'c2'],
    sceneId: 's1',
    assetBindings: {
      'c1': ShotAssetBinding(materialPath: 'turnaround.png'),
      'c2': ShotAssetBinding(
        materialPath: 'upload.png',
        role: ShotAssetRole.confrontation,
      ),
    },
  );

  group('videoPromptSourceKeyOf', () {
    test('五个来源字段任一变化都改变键', () {
      final base = baseShot().videoPromptSourceKeyOf;

      expect(baseShot().copyWith(actionZh: '改了动作').videoPromptSourceKeyOf,
          isNot(equals(base)));
      expect(baseShot().copyWith(dialogue: '改了台词').videoPromptSourceKeyOf,
          isNot(equals(base)));
      expect(
        baseShot().copyWith(characterIds: ['c1']).videoPromptSourceKeyOf,
        isNot(equals(base)),
      );
      expect(baseShot().copyWith(sceneId: 's2').videoPromptSourceKeyOf,
          isNot(equals(base)));
      expect(
        baseShot().copyWith(assetBindings: const {
          'c1': ShotAssetBinding(materialPath: 'other.png'),
          'c2': ShotAssetBinding(
            materialPath: 'upload.png',
            role: ShotAssetRole.confrontation,
          ),
        }).videoPromptSourceKeyOf,
        isNot(equals(base)),
      );
    });

    test('素材分工变化也改变键', () {
      final base = baseShot().videoPromptSourceKeyOf;
      final changed = baseShot().copyWith(assetBindings: const {
        'c1': ShotAssetBinding(materialPath: 'turnaround.png'),
        'c2': ShotAssetBinding(
          materialPath: 'upload.png',
          role: ShotAssetRole.subject,
        ),
      });
      expect(changed.videoPromptSourceKeyOf, isNot(equals(base)));
    });

    test('assetBindings 的 Map 插入顺序不影响键', () {
      final forward = const StudioShot(
        number: 1,
        assetBindings: {
          'c1': ShotAssetBinding(materialPath: 'a.png'),
          'c2': ShotAssetBinding(materialPath: 'b.png'),
        },
      );
      final reversed = const StudioShot(
        number: 1,
        assetBindings: {
          'c2': ShotAssetBinding(materialPath: 'b.png'),
          'c1': ShotAssetBinding(materialPath: 'a.png'),
        },
      );
      expect(reversed.videoPromptSourceKeyOf, equals(forward.videoPromptSourceKeyOf));
    });

    test('characterIds 顺序不影响键', () {
      final a = const StudioShot(number: 1, characterIds: ['c1', 'c2']);
      final b = const StudioShot(number: 1, characterIds: ['c2', 'c1']);
      expect(b.videoPromptSourceKeyOf, equals(a.videoPromptSourceKeyOf));
    });
  });

  group('isVideoPromptStale', () {
    test('无定制提示词时不为失效', () {
      final shot = baseShot();
      expect(shot.videoPrompt, isEmpty);
      expect(shot.isVideoPromptStale, isFalse);
    });

    test('来源键匹配时定制提示词有效', () {
      final shot = baseShot();
      final saved = shot.copyWith(
        videoPrompt: '定制提示词',
        videoPromptSourceKey: shot.videoPromptSourceKeyOf,
      );
      expect(saved.isVideoPromptStale, isFalse);
    });

    test('仅改时长/画幅/分辨率不失效', () {
      final shot = baseShot();
      final saved = shot.copyWith(
        videoPrompt: '定制提示词',
        videoPromptSourceKey: shot.videoPromptSourceKeyOf,
      );
      final tweaked = saved.copyWith(durationSec: 8.0, aspectRatio: '16:9');
      expect(tweaked.isVideoPromptStale, isFalse,
          reason: '时长与画幅不改变提示词的实质内容');
    });

    test('改动作字段后定制提示词失效', () {
      final shot = baseShot();
      final saved = shot.copyWith(
        videoPrompt: '定制提示词',
        videoPromptSourceKey: shot.videoPromptSourceKeyOf,
      );
      final edited = saved.copyWith(actionZh: '姜七夜转身牵驴走出衙门');
      expect(edited.isVideoPromptStale, isTrue);
    });

    test('新增素材绑定后定制提示词失效', () {
      final shot = baseShot();
      final saved = shot.copyWith(
        videoPrompt: '定制提示词',
        videoPromptSourceKey: shot.videoPromptSourceKeyOf,
      );
      final edited = saved.copyWith(assetBindings: {
        ...saved.assetBindings,
        'c3': const ShotAssetBinding(materialPath: 'new.png'),
      });
      expect(edited.isVideoPromptStale, isTrue);
    });

    test('来源键为空（旧数据）时定制提示词先按失效处理', () {
      final shot = baseShot().copyWith(videoPrompt: '旧版定制提示词');
      expect(shot.videoPromptSourceKey, isEmpty);
      expect(shot.isVideoPromptStale, isTrue,
          reason: '从未记录来源键的旧数据至少要按当前字段校验一次');
    });
  });

  group('videoPromptSourceKey 序列化', () {
    test('往返不丢', () {
      final shot = baseShot().copyWith(
        videoPrompt: '定制提示词',
        videoPromptSourceKey: 'a=xx|d=yy',
      );
      final restored = StudioShot.fromJson(shot.toJson());
      expect(restored.videoPrompt, '定制提示词');
      expect(restored.videoPromptSourceKey, 'a=xx|d=yy');
    });

    test('缺失时反序列化为空串', () {
      final restored = StudioShot.fromJson(const {'number': 1});
      expect(restored.videoPromptSourceKey, isEmpty);
    });
  });
}
