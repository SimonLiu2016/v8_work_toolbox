import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';

/// 时间轴插入的序列化与 episode 承载回归。
///
/// 守两件事：插入位置（afterShotNumber）跨重启不丢；旧剧集（无该字段）
/// 加载后是空列表而不是崩。
void main() {
  group('StudioTimelineInsert', () {
    test('toJson / fromJson 往返不丢位置', () {
      const ins = StudioTimelineInsert(
        assetId: 'a3f8c1d2',
        afterShotNumber: 3,
      );
      final back = StudioTimelineInsert.fromJson(ins.toJson());
      expect(back, isNotNull);
      expect(back!.assetId, 'a3f8c1d2');
      expect(back.afterShotNumber, 3);
    });

    test('afterShotNumber = 0 表示最前面，能被正确读回', () {
      const ins = StudioTimelineInsert(assetId: 'x', afterShotNumber: 0);
      final back = StudioTimelineInsert.fromJson(ins.toJson());
      expect(back!.afterShotNumber, 0);
    });

    test('缺 asset_id 的条目被跳过而不是崩溃', () {
      expect(
        StudioTimelineInsert.fromJson({'after_shot_number': 2}),
        isNull,
      );
    });
  });

  group('StudioEpisode.timelineInserts', () {
    StudioEpisode baseEpisode() => StudioEpisode(
      id: 'e1',
      seriesId: 's1',
      createdAt: DateTime.utc(2026, 10, 13),
      updatedAt: DateTime.utc(2026, 10, 13),
    );

    test('默认空列表——旧剧集加载后无需迁移', () {
      final ep = baseEpisode();
      expect(ep.timelineInserts, isEmpty);
    });

    test('序列化往返保留插入列表', () {
      final ep = baseEpisode().copyWith(timelineInserts: const [
        StudioTimelineInsert(assetId: 'a1', afterShotNumber: 0),
        StudioTimelineInsert(assetId: 'a2', afterShotNumber: 4),
      ]);
      final back = StudioEpisode.fromJson(ep.toJson());
      expect(back.timelineInserts, hasLength(2));
      expect(back.timelineInserts[0].afterShotNumber, 0);
      expect(back.timelineInserts[1].afterShotNumber, 4);
    });

    test('旧 JSON（无 timeline_inserts 字段）加载后是空列表', () {
      final ep = baseEpisode();
      final json = ep.toJson()..remove('timeline_inserts');
      final back = StudioEpisode.fromJson(json);
      expect(back.timelineInserts, isEmpty);
    });

    test('copyWith 只改插入，不动分镜', () {
      final ep = baseEpisode();
      final updated = ep.copyWith(timelineInserts: const [
        StudioTimelineInsert(assetId: 'a1', afterShotNumber: 1),
      ]);
      expect(updated.timelineInserts, hasLength(1));
      expect(updated.shots, ep.shots);
    });
  });
}
