import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// 片段化改造的迁移契约测试（spec: 旧版分镜数据迁移）。
///
/// 固定三件事：
/// 1. 旧版 `storyboard.json`（无 `segments`）加载后自动分组，且**不产生磁盘
///    写入」——读取路径有写副作用会让「打开即修改」无法解释，也让失败可能
///    污染用户数据（design 决策 2）；
/// 2. 迁移是幂等的——连续两次保存后片段划分不变；
/// 3. 已有分镜的媒体路径、台词、字段值一个字节都不改。
void main() {
  group('legacy segment grouping', () {
    test('3 的倍数按 3 镜分组', () {
      final segments =
          StudioEpisode.buildLegacySegments([1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(segments, hasLength(3));
      expect(segments[0].shotNumbers, [1, 2, 3]);
      expect(segments[1].shotNumbers, [4, 5, 6]);
      expect(segments[2].shotNumbers, [7, 8, 9]);
    });

    test('余 4 时拆 2+2 而不是 3+1', () {
      // 剩 4 镜时拆 2+2：末组只含 1 镜没有「片段」的意义。
      final segments = StudioEpisode.buildLegacySegments(
        List.generate(4, (i) => i + 1),
      );
      expect(segments.map((s) => s.shotNumbers.length), [2, 2]);
    });

    test('7 镜（3+3+1 会末组单镜）按 3+2+2 拆', () {
      final segments = StudioEpisode.buildLegacySegments(
        List.generate(7, (i) => i + 1),
      );
      expect(segments.map((s) => s.shotNumbers.length), [3, 2, 2]);
    });

    test('10 镜按 3+3+2+2 拆', () {
      final segments = StudioEpisode.buildLegacySegments(
        List.generate(10, (i) => i + 1),
      );
      expect(segments.map((s) => s.shotNumbers.length), [3, 3, 2, 2]);
    });

    test('少于 3 镜时各成一段', () {
      expect(
        StudioEpisode.buildLegacySegments([1]).single.shotNumbers,
        [1],
      );
      expect(
        StudioEpisode.buildLegacySegments([1, 2]).single.shotNumbers,
        [1, 2],
      );
    });

    test('空序列返回空列表', () {
      expect(StudioEpisode.buildLegacySegments(const []), isEmpty);
    });

    test('submittedDurationSec 序列化往返', () {
      final json = const StudioSegment(
        id: 'seg-1',
        targetDurationSec: 15,
        shotNumbers: [1, 2],
        submittedDurationSec: 12,
      ).toJson();
      expect(json['submitted_duration_sec'], 12);
      final restored = StudioSegment.fromJson(json);
      expect(restored.submittedDurationSec, 12);
      expect(restored.durationWasAdjusted, isTrue,
          reason: '请求 15s 提交 12s 时必须标记为已调整');
    });

    test('未生成过的片段 submittedDurationSec 为 null', () {
      const seg = StudioSegment(id: 'seg-1', targetDurationSec: 12);
      expect(seg.submittedDurationSec, isNull);
      expect(seg.durationWasAdjusted, isFalse);
    });

    test('提交时长与请求一致时不算调整', () {
      const seg = StudioSegment(
        id: 'seg-1',
        targetDurationSec: 12,
        submittedDurationSec: 12,
      );
      expect(seg.durationWasAdjusted, isFalse);
    });

    test('迁移片段的 boundaryReason 标明来源', () {
      final segments = StudioEpisode.buildLegacySegments([1, 2, 3]);
      expect(
        segments.every((s) => s.boundaryReason == '旧版数据自动分组'),
        isTrue,
        reason: '用户必须能区分「AI 划的边界」与「系统补的分组」',
      );
    });

    test('迁移片段 id 从 seg-1 起连续', () {
      final segments = StudioEpisode.buildLegacySegments(
        List.generate(8, (i) => i + 1),
      );
      expect(segments.map((s) => s.id), ['seg-1', 'seg-2', 'seg-3']);
    });
  });

  group('StudioEpisode.migrateSegmentsIfNeeded', () {
    StudioEpisode episode({List<StudioShot>? shots, List<StudioSegment>? segments}) {
      final now = DateTime(2026);
      return StudioEpisode(
        id: 'ep1',
        seriesId: 's1',
        shots: shots ??
            List.generate(
              6,
              (i) => StudioShot(number: i + 1, durationSec: 3),
            ),
        segments: segments ?? const [],
        createdAt: now,
        updatedAt: now,
      );
    }

    test('无 segments 时补齐分组', () {
      final migrated = episode().migrateSegmentsIfNeeded();
      expect(migrated.segments, hasLength(2));
      expect(migrated.segments[0].shotNumbers, [1, 2, 3]);
      expect(migrated.segments[1].shotNumbers, [4, 5, 6]);
    });

    test('已有 segments 时原样返回（幂等）', () {
      final existing = episode(
        segments: const [
          StudioSegment(id: 'seg-custom', shotNumbers: [1]),
        ],
      );
      final migrated = existing.migrateSegmentsIfNeeded();
      expect(migrated.segments, hasLength(1));
      expect(migrated.segments.single.id, 'seg-custom');
    });

    test('shots 为空时不产出片段', () {
      final migrated = episode(shots: const []).migrateSegmentsIfNeeded();
      expect(migrated.segments, isEmpty);
    });
  });

  group('旧版 storyboard.json 读取不写盘', () {
    late Directory tempDir;
    late StudioProjectManager manager;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('segment_migration');
      AppPaths.overrideRootForTesting(tempDir);
      manager = StudioProjectManager.instance;
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('加载旧文件不改变其 mtime，保存后片段划分稳定', () async {
      await manager.createSeries(name: '测试剧集');
      final series = (await manager.listSeries()).first;

      // 手工写一份「旧版」storyboard.json：没有 segments 字段，分镜上也没有
      // segmentId / continuity。
      final created = await manager.createEpisode(seriesId: series.id);
      final storyboardFile =
          manager.episodeStoryboardFile(series.id, created.episode.id);
      final legacy = <String, dynamic>{
        'id': created.episode.id,
        'series_id': series.id,
        'index': 1,
        'title': created.episode.title,
        'synopsis': '旧版大纲',
        'shots': List.generate(
          6,
          (i) => {
            'number': i + 1,
            'duration_sec': 3.0,
            'shot_size': 'medium',
            'mood': 'warm',
            'function': 'advance',
            'action_zh': '动作$i',
            'dialogue': '',
            'character_ids': <String>[],
            'scene_id': '',
            'camera_move': '',
            'assembled_prompt': '',
            'frame_path': null,
            'clip_path': null,
            'audio_path': null,
            'audio_duration_ms': null,
            'bgm_path': null,
            'status': 'done',
          },
        ),
        'variation_overrides': <String, String>{},
        'created_at': DateTime(2026).toIso8601String(),
        'updated_at': DateTime(2026).toIso8601String(),
      };
      storyboardFile.writeAsStringSync(
        const JsonEncoder().convert(legacy),
        flush: true,
      );

      final before = storyboardFile.lastModifiedSync();

      // 等 1ms 让 mtime 有机会变化（文件系统时间精度可能很粗）。
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final loaded = manager.readEpisode(series.id, created.episode.id)!;
      expect(loaded.segments, hasLength(2));
      expect(loaded.shots, hasLength(6));
      // 旧版分镜的媒体路径与状态字段必须原样读出。
      expect(loaded.shots.every((s) => s.status == ShotGenerationStatus.done),
          isTrue);
      expect(loaded.shots.first.segmentId, isEmpty);
      expect(loaded.shots.first.continuity.isEmpty, isTrue);

      expect(storyboardFile.lastModifiedSync(), before,
          reason: '读取旧文件不该触发写盘');

      // 保存一次后，片段结构落盘；再读应识别到已有 segments 而不重新划分。
      await manager.saveEpisode(loaded);
      final reloaded = manager.readEpisode(series.id, created.episode.id)!;
      expect(reloaded.segments.map((s) => s.shotNumbers).toList(), [
        [1, 2, 3],
        [4, 5, 6],
      ]);

      // 保存后的文件里 shots 的媒体路径与状态没有被迁移改写。
      final decoded = jsonDecode(storyboardFile.readAsStringSync())
          as Map<String, dynamic>;
      final shots = decoded['shots'] as List;
      expect(shots, hasLength(6));
      expect(
        shots.every((s) => (s as Map)['status'] == 'done'),
        isTrue,
      );
    });
  });
}
