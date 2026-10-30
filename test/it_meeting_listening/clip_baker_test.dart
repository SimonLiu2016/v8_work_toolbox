import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 假引擎：返回一段**真实的** mp3 字节（测试固件），不触网。
///
/// 必须是真 mp3：烘焙管线会把各轮音频用 ffmpeg concat 拼起来，喂假字节
/// 会让 ffmpeg 直接报错，测的就不是管线而是 ffmpeg 的报错信息了。
class _FakeEngine implements TtsEngine {
  final List<String> requestedTexts = [];
  final List<String> requestedVoices = [];
  int calls = 0;

  /// 模拟"偶发空音频"：第 n 次调用返回空。
  final Set<int> emptyOnCalls;

  /// 真实 mp3 字节固件。
  final Uint8List fixture;

  _FakeEngine({this.emptyOnCalls = const {}, required this.fixture});

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(
      String text, TtsSynthesisConfig config) async {
    calls++;
    requestedTexts.add(text);
    requestedVoices.add(config.effectiveVoiceId);
    if (emptyOnCalls.contains(calls)) return Uint8List(0);
    return fixture;
  }
}

/// 生成一段 0.5 秒的静音 mp3 作为固件。
Future<Uint8List> _makeMp3Fixture(Directory dir) async {
  final out = p.join(dir.path, 'fixture.mp3');
  final r = await Process.run('ffmpeg', [
    '-y', '-loglevel', 'error', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono',
    '-t', '0.5', '-b:a', '48k', out,
  ]);
  if (r.exitCode != 0) {
    throw StateError('无法生成测试固件（需要 ffmpeg）: ${r.stderr}');
  }
  return Uint8List.fromList(await File(out).readAsBytes());
}

SpeakerTurn _turn(String speaker, String role, String text) => SpeakerTurn(
      speaker: speaker,
      role: role,
      rawText: text,
      synthesisText: text,
      voice: '',
    );

void main() {
  group('ClipBaker.segment 切分', () {
    test('短对话不切分', () {
      final turns = [
        _turn('A', 'Scrum Master', 'one'),
        _turn('B', 'Backend', 'two'),
      ];
      final segs = ClipBaker.segment(turns, 'note');
      expect(segs, hasLength(1));
      expect(segs.single.turns, hasLength(2));
    });

    test('切分点落在完整轮次边界上', () {
      // 每轮约 15 个词（≈6.6s），30 轮约 198s → 超过 180s 上限，应切为多段
      // 且不切断任何一轮。
      final longLine = List.filled(15, 'word').join(' ');
      final turns =
          List.generate(30, (i) => _turn('S$i', 'Backend', 'line $i $longLine'));
      final segs = ClipBaker.segment(turns, '');
      expect(segs.length, greaterThan(1));
      // 所有轮次都还在，且顺序不变
      final flat = segs.expand((s) => s.turns).toList();
      expect(flat, hasLength(30));
      for (var i = 0; i < flat.length; i++) {
        expect(flat[i].rawText, startsWith('line $i '));
      }
      // 每段都不超过上限
      for (final seg in segs) {
        final ms = seg.turns
            .fold<int>(0, (a, t) => a + ClipBaker.estimateTurnMs(t));
        expect(ms, lessThanOrEqualTo(ClipBaker.maxClipMs));
      }
    });

    test('短尾段并入前一段而不是单独成片', () {
      // 20 轮长对话 + 1 轮极短 → 短尾段应并入前段
      final longLine = List.filled(15, 'word').join(' ');
      final turns = [
        ...List.generate(20, (i) => _turn('S$i', 'Backend', 'line $i $longLine')),
        _turn('Tail', 'QA', 'ok'),
      ];
      final segs = ClipBaker.segment(turns, '');
      expect(segs, hasLength(1));
      expect(segs.single.turns, hasLength(21));
    });

    test('空轮次列表不产出片段', () {
      expect(ClipBaker.segment(const [], ''), isEmpty);
    });
  });

  group('ClipBaker 烘焙', () {
    late Directory tmp;
    late Directory materialDir;
    late Directory cacheDir;
    late Uint8List fixture;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('clip_baker_test');
      materialDir = Directory(p.join(tmp.path, 'materials'));
      cacheDir = Directory(p.join(tmp.path, 'cache'));
      fixture = await _makeMp3Fixture(tmp);
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('产出音频与文稿清单，且轮次带时间戳', () async {
      final engine = _FakeEngine(fixture: fixture);
      final baker = ClipBaker(
          engine: engine, materialDir: materialDir, cacheDir: cacheDir);
      final dialogue = FetchedDialogue(
        scene: MeetingScene.standup,
        columnSlug: 'stand-up-meeting-dialogues',
        column: 'Stand-up Meeting Dialogues',
        pageUrl: 'https://coderslingo.com/exercises/listening/standup-dialogues/',
        blockIndex: 0,
        scenarioNote: 'Morning standup',
        turns: [
          _turn('Lena', 'Scrum Master', 'Good morning, let\'s keep it quick.'),
          _turn('Alex', 'Backend', 'Yesterday I finished the API endpoint.'),
        ],
      );

      final result = await baker.bakeDialogue(dialogue);
      expect(result.failures, isEmpty);
      expect(result.clips, hasLength(1));

      final clip = result.clips.single;
      expect(clip.turns, hasLength(2));
      expect(clip.turns.first.voice, isNotEmpty);
      // 时间戳单调递增
      expect(clip.turns[0].startMs, 0);
      expect(clip.turns[1].startMs, greaterThanOrEqualTo(clip.turns[0].endMs));
      // 音频与文稿都落盘
      expect(await File(p.join(materialDir.path, '${clip.id}.mp3')).exists(), isTrue);
      expect(await File(p.join(materialDir.path, '${clip.id}.json')).exists(), isTrue);
    });

    test('送入合成的文本是清洗后的副本（破折号变逗号）', () async {
      final engine = _FakeEngine(fixture: fixture);
      final baker = ClipBaker(
          engine: engine, materialDir: materialDir, cacheDir: cacheDir);
      final dialogue = FetchedDialogue(
        scene: MeetingScene.standup,
        columnSlug: 'c',
        column: 'C',
        pageUrl: 'u',
        blockIndex: 0,
        scenarioNote: '',
        turns: [
          _turn('Maria', 'Frontend',
              "Today I'll continue — but I'm blocked."),
        ],
      );
      await baker.bakeDialogue(dialogue);
      expect(engine.requestedTexts.single,
          "Today I'll continue, but I'm blocked.");
    });

    test('同一角色跨片段使用同一音色', () async {
      final engine = _FakeEngine(fixture: fixture);
      final baker = ClipBaker(
          engine: engine, materialDir: materialDir, cacheDir: cacheDir);
      FetchedDialogue mk(int i) => FetchedDialogue(
            scene: MeetingScene.standup,
            columnSlug: 'c',
            column: 'C',
            pageUrl: 'u',
            blockIndex: i,
            scenarioNote: '',
            turns: [_turn('Lena', 'Scrum Master', 'hello $i')],
          );
      final a = await baker.bakeDialogue(mk(0));
      final b = await baker.bakeDialogue(mk(1));
      expect(a.clips.single.turns.single.voice,
          b.clips.single.turns.single.voice);
    });

    test('单轮空音频会重试；仍失败则整个片段失败且不产出残缺文件', () async {
      // 第 1 次空、第 2 次成功 → 应成功
      final okEngine = _FakeEngine(emptyOnCalls: {1}, fixture: fixture);
      final baker = ClipBaker(
          engine: okEngine, materialDir: materialDir, cacheDir: cacheDir);
      final dialogue = FetchedDialogue(
        scene: MeetingScene.standup,
        columnSlug: 'c',
        column: 'C',
        pageUrl: 'u',
        blockIndex: 0,
        scenarioNote: '',
        turns: [_turn('A', 'QA', 'hello')],
      );
      final ok = await baker.bakeDialogue(dialogue);
      expect(ok.failures, isEmpty);
      expect(okEngine.calls, greaterThanOrEqualTo(2));

      // 全部失败 → 片段失败。用**独立目录**，以便断言"该次烘焙未产出任何 mp3"
      //（上面那次成功烘焙的文件仍在，属正常）。
      final badMaterialDir = Directory(p.join(tmp.path, 'materials_bad'));
      final badEngine =
          _FakeEngine(emptyOnCalls: {1, 2, 3, 4, 5}, fixture: fixture);
      final baker2 = ClipBaker(
          engine: badEngine,
          materialDir: badMaterialDir,
          cacheDir: Directory(p.join(tmp.path, 'cache_bad')));
      final bad = await baker2.bakeDialogue(dialogue);
      expect(bad.clips, isEmpty);
      expect(bad.failures, isNotEmpty);
      final produced = badMaterialDir.existsSync()
          ? badMaterialDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.mp3'))
          : <File>[];
      expect(produced, isEmpty);
    });

    test('文稿清单含来源与许可信息', () async {
      final engine = _FakeEngine(fixture: fixture);
      final baker = ClipBaker(
          engine: engine, materialDir: materialDir, cacheDir: cacheDir);
      final dialogue = FetchedDialogue(
        scene: MeetingScene.incident,
        columnSlug: 'live-incident-bridge-calls',
        column: 'Live Incident Bridge Calls',
        pageUrl: 'https://coderslingo.com/exercises/listening/incident-calls/',
        blockIndex: 0,
        scenarioNote: 'SEV-1',
        turns: [_turn('IC', 'Incident Commander', 'status update please')],
      );
      final result = await baker.bakeDialogue(dialogue);
      final clip = result.clips.single;
      expect(clip.source.site, 'CoderSlingo');
      expect(clip.source.pageUrl, contains('incident-calls'));
      expect(clip.source.license, 'CC BY 4.0');
      expect(clip.source.column, 'Live Incident Bridge Calls');
    });
  });
}
