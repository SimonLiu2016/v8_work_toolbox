import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ffmpeg_composer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/jianying_exporter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';

/// 剪映草稿导出与备用导出的测试（tasks 8.2 / 8.3 / 8.4）。
///
/// 断言的是「结构正确 + 时间码精确 + 坏了有退路」这三件能在 CI 里验证的事。
/// 真正在剪映里打开只能靠人肉，所以自检函数 [JianyingExporter.validateDraft]
/// 的覆盖率就是这条链路的保险。
void main() {
  late Directory root;
  late StudioProjectManager manager;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('jianying_test');
    AppPaths.overrideRootForTesting(root);
  });

  setUp(() {
    manager = StudioProjectManager.instance;
    manager.resetCachesForTesting();
  });

  /// 建一部剧 + 一集，按 [specs] 造分镜并把素材写进**该集**的
  /// `clips/` 与 `audio/` 目录。
  ///
  /// 导出器按 `storyboard.json` 里的相对路径去这两个目录找文件，所以素材
  /// 必须落在同一集的目录里——写错目录的症状是"草稿生成成功但素材全是断链"。
  Future<({String seriesId, StudioEpisode episode})> fixtureWith(
    List<StudioShot> specs,
  ) async {
    final series = await manager.createSeries(name: '测试剧');
    final created = await manager.createEpisode(seriesId: series.id);
    final episode = created.episode;
    final clipsDir = manager.episodeClipsDir(series.id, episode.id);
    final audioDir = manager.episodeAudioDir(series.id, episode.id);

    final shots = <StudioShot>[];
    for (final spec in specs) {
      if (spec.clipPath != null) {
        File(p.join(clipsDir.path, spec.clipPath!)).writeAsStringSync('clip');
      }
      if (spec.audioPath != null) {
        File(p.join(audioDir.path, spec.audioPath!)).writeAsStringSync('audio');
      }
      shots.add(spec);
    }
    final saved = episode.copyWith(shots: shots);
    await manager.saveEpisode(saved);
    return (seriesId: series.id, episode: saved);
  }

  /// 一条待落盘素材的分镜规格。
  StudioShot specShot(
    int number, {
    double durationSec = 3,
    String? dialogue,
    int audioMs = 2500,
    bool withClip = true,
    bool withAudio = true,
  }) {
    return StudioShot(
      number: number,
      durationSec: durationSec,
      dialogue: dialogue ?? '台词 $number',
      clipPath: withClip ? 'shot_$number.mp4' : null,
      audioPath: withAudio ? 'shot_$number.m4a' : null,
      audioDurationMs: audioMs,
    );
  }

  group('草稿结构', () {
    test('导出产生 draft_content.json 与素材软链接', () async {
      final out = Directory.systemTemp.createTempSync('jy_out');
      try {
        final f = await fixtureWith([specShot(1)]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );

        expect(await result.draftContentFile.exists(), isTrue);
        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        expect(json['version'], draftFormatVersion);
        expect(json['canvas'], {'width': 1080, 'height': 1920, 'ratio': '9:16'});

        final tracks = (json['tracks'] as List);
        expect(tracks.map((t) => t['type']), containsAll(['video', 'audio', 'text']));

        // 素材软链接存在且指向真实文件
        final link = Link(p.join(result.materialsDir.path, 'shot_1.mp4'));
        expect(await link.exists(), isTrue);
        expect(await File(link.targetSync()).exists(), isTrue);

        // 自检通过
        expect(JianyingExporter.validateDraft(result), isEmpty);
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('视频轨时间码按分镜顺序累计（微秒）', () async {
      final out = Directory.systemTemp.createTempSync('jy_track');
      try {
        final f = await fixtureWith([
          specShot(1, durationSec: 3),
          specShot(2, durationSec: 5),
        ]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );
        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        final videoTrack = (json['tracks'] as List).firstWhere(
          (t) => t['type'] == 'video',
        ) as Map;
        final segments = (videoTrack['segments'] as List).cast<Map>();
        expect(segments, hasLength(2));
        expect(segments[0]['start'], 0);
        expect(segments[0]['duration'], 3000000);
        expect(segments[1]['start'], 3000000);
        expect(segments[1]['duration'], 5000000);
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('没有片段的镜头被跳过但时间轴仍按建议时长推进', () async {
      final out = Directory.systemTemp.createTempSync('jy_skip');
      try {
        final f = await fixtureWith([
          specShot(1, durationSec: 4),
          specShot(2, durationSec: 6, withClip: false, withAudio: false),
          specShot(3, durationSec: 2),
        ]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );
        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        final videoTrack = (json['tracks'] as List).firstWhere(
          (t) => t['type'] == 'video',
        ) as Map;
        final segments = (videoTrack['segments'] as List).cast<Map>();
        expect(segments, hasLength(2));
        // 镜 3 的起点 = 镜 1 的 4 秒 + 镜 2 的 6 秒
        expect(segments[1]['start'], 10000000);
      } finally {
        out.deleteSync(recursive: true);
      }
    });
  });

  group('字幕轨', () {
    test('SRT 时间码转微秒且与原文误差 < 50ms', () async {
      final out = Directory.systemTemp.createTempSync('jy_srt');
      try {
        const srt = '''
1
00:00:01,000 --> 00:00:03,500
第一句

2
00:00:03,500 --> 00:00:06,250
第二句
''';
        final srtFile = File(p.join(out.path, 'ep.srt'));
        srtFile.writeAsStringSync(srt);

        final f = await fixtureWith([specShot(1)]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
          srtPath: srtFile.path,
        );

        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        final textTrack = (json['tracks'] as List).firstWhere(
          (t) => t['type'] == 'text',
        ) as Map;
        final segments = (textTrack['segments'] as List).cast<Map>();
        expect(segments, hasLength(2));

        // 毫秒 → 微秒是精确换算，误差为 0。
        expect(segments[0]['start'], 1000000);
        expect(segments[0]['duration'], 2500000);
        expect(segments[0]['text'], '第一句');
        expect(segments[1]['start'], 3500000);
        expect(segments[1]['duration'], 2750000);
        expect(segments[1]['text'], '第二句');

        // 与 FfmpegComposer 解析出的秒级区间互相印证（同一份 SRT 两个消费者）。
        final entries = FfmpegComposer.parseSrt(srt);
        expect(((segments[0]['start'] as int) / 1000000).round(),
            equals(entries[0].start.round()));
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('没有 SRT 时字幕轨为空数组而不是缺失', () async {
      final out = Directory.systemTemp.createTempSync('jy_nosrt');
      try {
        final f = await fixtureWith([specShot(1)]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );
        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        final textTrack = (json['tracks'] as List).firstWhere(
          (t) => t['type'] == 'text',
        ) as Map;
        expect(textTrack['segments'], isEmpty);
      } finally {
        out.deleteSync(recursive: true);
      }
    });
  });

  group('BGM 轨', () {
    test('提供 BGM 时写入带 ducking 标记的 BGM 轨', () async {
      final out = Directory.systemTemp.createTempSync('jy_bgm');
      try {
        final bgm = File(p.join(out.path, 'bgm.mp3'));
        bgm.writeAsStringSync('bgm');
        final f = await fixtureWith([specShot(1)]);
        final result = await JianyingExporter.export(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
          bgmPath: bgm.path,
        );
        final json = jsonDecode(
          await result.draftContentFile.readAsString(),
        ) as Map;
        final bgmTrack = (json['tracks'] as List).firstWhere(
          (t) => t['type'] == 'bgm',
        );
        expect((bgmTrack['segments'] as List).first['ducking'], isTrue);
        expect((bgmTrack['segments'] as List).first['duration'], 3000000);
      } finally {
        out.deleteSync(recursive: true);
      }
    });
  });

  group('自检与备用导出', () {
    test('损坏的 draft_content.json 让自检报问题', () async {
      final out = Directory.systemTemp.createTempSync('jy_bad');
      try {
        final draftDir = Directory(p.join(out.path, 'jianying_draft'));
        await draftDir.create(recursive: true);
        File(p.join(draftDir.path, 'draft_content.json'))
            .writeAsStringSync('not json at all');
        final result = JianyingExportResult(
          draftDir: draftDir,
          draftContentFile: File(p.join(draftDir.path, 'draft_content.json')),
          materialsDir: Directory(p.join(draftDir.path, 'materials')),
        );
        final problems = JianyingExporter.validateDraft(result);
        expect(problems, isNotEmpty);
        expect(problems.first, contains('解析失败'));
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('缺 draft_content.json 时自检明确指出', () async {
      final out = Directory.systemTemp.createTempSync('jy_missing');
      try {
        final draftDir = Directory(p.join(out.path, 'jianying_draft'));
        await draftDir.create(recursive: true);
        final result = JianyingExportResult(
          draftDir: draftDir,
          draftContentFile: File(p.join(draftDir.path, 'draft_content.json')),
          materialsDir: Directory(p.join(draftDir.path, 'materials')),
        );
        expect(
          JianyingExporter.validateDraft(result),
          contains('缺少 draft_content.json'),
        );
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('备用导出产出平铺素材目录与导入说明', () async {
      final out = Directory.systemTemp.createTempSync('jy_fallback');
      try {
        final f = await fixtureWith([specShot(1)]);
        final fallback = await JianyingExporter.exportFallback(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );
        expect(await File(p.join(fallback.path, 'video', 'shot_1.mp4')).exists(), isTrue);
        expect(await File(p.join(fallback.path, 'audio', 'shot_1.m4a')).exists(), isTrue);
        final readme = File(p.join(fallback.path, '导入说明.txt'));
        expect(await readme.exists(), isTrue);
        final text = await readme.readAsString();
        expect(text, contains('剪映'));
        expect(text, contains('本地字幕'));
      } finally {
        out.deleteSync(recursive: true);
      }
    });

    test('备用导出是复制而非软链接（用户可能搬走整个目录）', () async {
      final out = Directory.systemTemp.createTempSync('jy_fallback_copy');
      try {
        final f = await fixtureWith([specShot(1)]);
        final fallback = await JianyingExporter.exportFallback(
          outputDir: out.path,
          episode: f.episode,
          shots: f.episode.shots,
        );
        final copied = File(p.join(fallback.path, 'video', 'shot_1.mp4'));
        expect(await FileSystemEntity.type(copied.path) ==
            FileSystemEntityType.notFound, isFalse);
        expect(await FileSystemEntity.isLink(copied.path), isFalse);
      } finally {
        out.deleteSync(recursive: true);
      }
    });
  });
}
