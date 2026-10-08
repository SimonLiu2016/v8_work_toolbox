import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/models/studio_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_project_manager.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ffmpeg_composer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_sound_design.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// SRT 时间轴与 BGM 匹配的测试（spec 6.2 / 6.3 / 6.4）。
///
/// 不起真实 TTS：用 [FakeTtsEngine] 返回可控字节，让时长确定，时间码才能
/// 被精确断言——用真实语音测时间轴，失败时永远分不清是算法错还是网络抖。
void main() {
  late Directory root;
  late StudioProjectManager manager;

  setUpAll(() {
    root = Directory.systemTemp.createTempSync('studio_sound');
    AppPaths.overrideRootForTesting(root);
  });

  setUp(() {
    manager = StudioProjectManager.instance;
    manager.resetCachesForTesting();
  });

  StudioEpisode episodeOf(List<StudioShot> shots) {
    final now = DateTime(2026);
    return StudioEpisode(
      id: 'ep1',
      seriesId: 's1',
      index: 1,
      shots: shots,
      createdAt: now,
      updatedAt: now,
    );
  }

  group('SRT 时间轴累计', () {
    test('时间码按分镜顺序累加，字幕时长 = 音频时长', () {
      final episode = episodeOf([
        shot(1, durationSec: 3, dialogue: '第一句'),
        shot(2, durationSec: 4, dialogue: '第二句'),
      ]);
      final srt = StudioSrtWriter.build(
        episode: episode,
        lines: const [
          SynthesizedLine(shotNumber: 1, fileName: 'a.m4a', durationMs: 2500),
          SynthesizedLine(shotNumber: 2, fileName: 'b.m4a', durationMs: 3800),
        ],
      );

      expect(srt, contains('1\n00:00:00,000 --> 00:00:02,500\n第一句'));
      // 第二句起点 = 第一条音频时长（2500ms），不是第一条分镜的建议时长。
      expect(srt, contains('2\n00:00:02,500 --> 00:00:06,300\n第二句'));
    });

    test('无台词分镜占时间但不出字幕', () {
      final episode = episodeOf([
        shot(1, durationSec: 3, dialogue: '有台词'),
        shot(2, durationSec: 5, dialogue: ''),
        shot(3, durationSec: 3, dialogue: '又有台词'),
      ]);
      final srt = StudioSrtWriter.build(
        episode: episode,
        lines: const [
          SynthesizedLine(shotNumber: 1, fileName: 'a', durationMs: 2000),
          SynthesizedLine(shotNumber: 2, fileName: '', durationMs: 0),
          SynthesizedLine(shotNumber: 3, fileName: 'c', durationMs: 2000),
        ],
      );

      // 只有 2 条字幕
      expect(RegExp(r'^\d+$', multiLine: true).allMatches(srt), hasLength(2));
      // 第三条字幕起点 = 2000（第一句音频）+ 5000（无台词分镜的建议时长）= 7000
      expect(srt, contains('2\n00:00:07,000 --> 00:00:09,000\n又有台词'));
    });

    test('TTS 比分镜建议时长长时以音频为准（口型优先）', () {
      final episode = episodeOf([
        shot(1, durationSec: 2, dialogue: '很长很长的一句话'),
      ]);
      final srt = StudioSrtWriter.build(
        episode: episode,
        lines: const [
          SynthesizedLine(shotNumber: 1, fileName: 'a', durationMs: 6000),
        ],
      );
      expect(srt, contains('00:00:00,000 --> 00:00:06,000'));
    });

    test('超过一小时的时间码格式正确', () {
      final episode = episodeOf([
        shot(1, durationSec: 3, dialogue: 'x'),
      ]);
      final srt = StudioSrtWriter.build(
        episode: episode,
        lines: const [
          SynthesizedLine(shotNumber: 1, fileName: 'a', durationMs: 3725000),
        ],
      );
      // 01:01:61,000 不合法——秒与分必须进位。
      expect(srt, contains('00:00:00,000 --> 01:02:05,000'));
    });

    test('SRT 文件落到 audio/ep_<id>.srt', () async {
      final dir = Directory.systemTemp.createTempSync('srt_out');
      try {
        final file = await StudioSrtWriter.write(
          srtText: '1\n00:00:00,000 --> 00:00:01,000\nhi\n',
          episodeAudioDir: dir.path,
          episodeId: 'ep42',
        );
        expect(p.basename(file.path), 'ep_ep42.srt');
        expect(await file.exists(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('生成的 SRT 可被 Ducking 解析回同一批区间', () {
      final episode = episodeOf([
        shot(1, durationSec: 3, dialogue: '甲'),
        shot(2, durationSec: 3, dialogue: '乙'),
      ]);
      final srt = StudioSrtWriter.build(
        episode: episode,
        lines: const [
          SynthesizedLine(shotNumber: 1, fileName: 'a', durationMs: 1200),
          SynthesizedLine(shotNumber: 2, fileName: 'b', durationMs: 1500),
        ],
      );
      final ranges = FfmpegComposer.duckingRangesFromSrt(srt);
      expect(ranges, hasLength(2));
      expect(ranges[0][0], closeTo(0.0, 0.001));
      expect(ranges[0][1], closeTo(1.2, 0.001));
      expect(ranges[1][0], closeTo(1.2, 0.001));
      expect(ranges[1][1], closeTo(2.7, 0.001));
    });
  });

  group('StudioTtsService', () {
    test('有台词的分镜落盘并返回时长', () async {
      final dir = Directory.systemTemp.createTempSync('tts_out');
      try {
        final service = StudioTtsService(
          engine: _FakeTtsEngine(byteLength: 48000),
        );
        final lines = await service.synthesizeEpisode(
          episode: episodeOf([
            shot(1, durationSec: 3, dialogue: '你好'),
          ]),
          audioDir: dir.path,
          resolveVoiceId: (_) => '',
        );
        expect(lines, hasLength(1));
        expect(lines.first.fileName, 'shot_1.m4a');
        // afinfo 读不到就按 48kbps 估算：48000 字节 = 8 秒。
        expect(lines.first.durationMs, greaterThan(0));
        expect(File(p.join(dir.path, 'shot_1.m4a')).existsSync(), isTrue);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('无台词分镜返回空文件名而不是报错', () async {
      final dir = Directory.systemTemp.createTempSync('tts_empty');
      try {
        final service = StudioTtsService(engine: _FakeTtsEngine(byteLength: 12000));
        final lines = await service.synthesizeEpisode(
          episode: episodeOf([
            shot(1, durationSec: 3, dialogue: '   '),
          ]),
          audioDir: dir.path,
          resolveVoiceId: (_) => '',
        );
        expect(lines.single.fileName, '');
        expect(lines.single.durationMs, 0);
        expect(lines.single.shotNumber, 1, reason: '占位也要带镜号');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('角色未绑音色时逐级回落到剧集默认、再到 Edge 默认', () async {
      final dir = Directory.systemTemp.createTempSync('tts_voice');
      try {
        final engine = _FakeTtsEngine(byteLength: 12000);
        final service = StudioTtsService(engine: engine);
        await service.synthesizeEpisode(
          episode: episodeOf([
            shot(1, durationSec: 3, dialogue: '甲'),
            shot(2, durationSec: 3, dialogue: '乙'),
          ]),
          audioDir: dir.path,
          resolveVoiceId: (s) => s.number == 1 ? 'zh-CN-YunxiNeural' : '',
          defaultVoiceId: 'zh-CN-XiaoxiaoNeural',
        );
        expect(engine.requestedVoices, ['zh-CN-YunxiNeural', 'zh-CN-XiaoxiaoNeural']);
      } finally {
        dir.deleteSync(recursive: true);
      }
    });
  });

  group('BgmMatcher', () {
    test('情绪标签命中两层库，来源层级透出', () async {
      final series = await manager.createSeries(name: '雨夜');
      // 全局库：放一首 battle
      final globalBgmDir = Directory(
        p.join(AppPaths.videoStudioGlobalLibDir.path, 'bgm'),
      );
      await globalBgmDir.create(recursive: true);
      File(p.join(globalBgmDir.path, '战斗_高潮.mp3')).writeAsStringSync('x');

      // IP 库：放一首 battle
      final seriesBgmDir = Directory(
        p.join(seriesDir(series.id).path, 'library', 'bgm'),
      );
      await seriesBgmDir.create(recursive: true);
      File(p.join(seriesBgmDir.path, 'battle_theme.mp3')).writeAsStringSync('y');

      final candidates = await const BgmMatcher().recommend(
        seriesId: series.id,
        moodId: 'battle',
      );
      expect(candidates, isNotEmpty);
      expect(candidates.every((c) => c.score == 100), isTrue);
      final layers = candidates.map((c) => c.asset.sourceLayer).toSet();
      expect(layers, containsAll(['global', 'series']));
      expect(candidates.first.sourceLabel, isNotEmpty);
    });

    test('没有精确匹配时返回全部候选（分数 0）而不是空列表', () async {
      final series = await manager.createSeries(name: '晴日');
      // 全局库索引带缓存，前一个测试已经建过目录；这里强制重扫。
      File(p.join(
        AppPaths.videoStudioGlobalLibDir.path, 'bgm', '轻松_午后.mp3',
      )).writeAsStringSync('x');
      manager.resetCachesForTesting();

      final candidates = await const BgmMatcher().recommend(
        seriesId: series.id,
        moodId: 'sad',
        limit: 10,
      );
      // 全局库有文件就不该空手而归。
      expect(candidates, isNotEmpty);
      expect(candidates.every((c) => c.score == 0), isTrue,
             reason: '兜底候选不带分数，UI 才能区分"推荐"与"仅有的几个"');
    });
  });
}

Directory seriesDir(String seriesId) =>
    Directory(p.join(AppPaths.videoStudioSeriesDir.path, seriesId));

StudioShot shot(
  int number, {
  double durationSec = 3,
  String dialogue = '',
}) {
  return StudioShot(
    number: number,
    durationSec: durationSec,
    dialogue: dialogue,
  );
}

class _FakeTtsEngine implements TtsEngine {
  _FakeTtsEngine({required this.byteLength});

  final int byteLength;
  final List<String> requestedVoices = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    requestedVoices.add(config.voiceId);
    // afinfo 读不出时长，测试断言的是「读不到就按比特率估算」的兜底。
    return Uint8List(byteLength);
  }
}
