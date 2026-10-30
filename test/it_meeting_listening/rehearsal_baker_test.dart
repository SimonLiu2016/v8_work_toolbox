import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_voices.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 假引擎：返回真实 mp3 固件，并记录收到的文本与音色。
///
/// 必须是真 mp3——烘焙管线用 ffmpeg concat 拼音频，喂假字节测的就是 ffmpeg 的
/// 报错而不是管线。
class _FakeEngine implements TtsEngine {
  final List<String> texts = [];
  final List<String> voices = [];
  final Uint8List fixture;

  /// 这些调用抛异常（模拟配额/审查失败）。
  final Map<int, Object> throwOnCalls;

  int _calls = 0;

  _FakeEngine({required this.fixture, this.throwOnCalls = const {}});

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    _calls++;
    texts.add(text);
    voices.add(config.effectiveVoiceId);
    final err = throwOnCalls[_calls];
    if (err != null) throw err;
    return fixture;
  }
}

Future<Uint8List> _makeMp3Fixture(Directory dir) async {
  final out = p.join(dir.path, 'fixture.mp3');
  final r = await Process.run('ffmpeg', [
    '-y',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'anullsrc=r=24000:cl=mono',
    '-t',
    '0.5',
    '-b:a',
    '128k',
    out,
  ]);
  if (r.exitCode != 0) {
    throw StateError('无法生成测试固件（需要 ffmpeg）: ${r.stderr}');
  }
  return Uint8List.fromList(await File(out).readAsBytes());
}

/// 探测音频时长（毫秒）。
Future<int> _probe(String path) async {
  final r = await Process.run('ffprobe', [
    '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path,
  ]);
  return ((double.tryParse(r.stdout.toString().trim()) ?? 0) * 1000).round();
}

MeetingScript _script({int turns = 4}) => MeetingScript(
      id: 'script_mat_x',
      materialId: 'mat_x',
      draftId: 'draft_mat_x',
      title: 'Q4 评审 · 模拟会议',
      targetMinutes: 30,
      generatedAt: DateTime(2026, 10, 22),
      turns: [
        for (var i = 0; i < turns; i++)
          ScriptTurn(
            role: RehearsalRole.values[i % RehearsalRole.values.length],
            text: 'Turn number $i about capacity and latency.',
            phase: ScriptPhase.topics,
          ),
      ],
    );

void main() {
  late Directory tmp;
  late Uint8List fixture;

  setUp(() async {
    await AppPaths.init();
    tmp = await Directory.systemTemp.createTemp('rehearsal_bake_test');
    fixture = await _makeMp3Fixture(tmp);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RehearsalBaker baker(TtsEngine e) => RehearsalBaker(
        engine: e,
        materialDir: Directory(p.join(tmp.path, 'materials')),
        cacheDir: Directory(p.join(tmp.path, 'cache')),
      );

  group('逐回合合成', () {
    test('轮次顺序保持，音色按角色分配', () async {
      final engine = _FakeEngine(fixture: fixture);
      final result = await baker(engine).bake(_script());

      expect(result.hasAudio, isTrue);
      expect(result.failures, isEmpty);
      // 每轮一次合成请求，顺序不变
      expect(engine.texts, hasLength(4));
      expect(engine.texts.first, contains('Turn number 0'));
      // 音色按角色来（第 0 轮 Simon、第 1 轮 xiaofeng…）
      expect(engine.voices[0], RehearsalVoices.voiceFor('simon'));
      expect(engine.voices[1], RehearsalVoices.voiceFor('xiaofeng'));
      // 落盘的 Clip 用排练场景与 rehearsal 来源
      expect(result.clip!.scene, MeetingScene.rehearsal);
      expect(result.clip!.source.sourceId, 'rehearsal');
      // 每轮起止时间累加且单调
      var prev = 0;
      for (final t in result.turns) {
        expect(t.startMs, prev);
        expect(t.endMs - t.startMs, greaterThanOrEqualTo(500));
        prev = t.endMs;
      }
      expect(result.clip!.durationMs, prev);
      // SpeakerTurn 也带上了时间戳（播放器按它定位）
      expect(result.clip!.turns, hasLength(4));
      expect(result.clip!.turns.first.speaker, 'Simon');
    });

    test('5 角色音色互不相同', () {
      final voices =
          RehearsalRole.values.map((r) => RehearsalVoices.voiceFor(r.id)).toSet();
      expect(voices, hasLength(5));
    });

    test('整场音频落盘为一条 mp3', () async {
      final result = await baker(_FakeEngine(fixture: fixture)).bake(_script());
      final audio =
          File(p.join(tmp.path, 'materials', '${result.clip!.id}.mp3'));
      expect(await audio.exists(), isTrue);
      // 音频长度等于各轮时长之和（真拼起来了，不是只写了第一个文件）
      final probed = await _probe(audio.path);
      expect(probed, greaterThanOrEqualTo(1900));
    });
  });

  group('失败处理', () {
    test('配额 fast-fail：不重试，直接放弃该轮', () async {
      final engine = _FakeEngine(
        fixture: fixture,
        throwOnCalls: {2: Exception('HTTP 402 quota_exceeded')},
      );
      final result = await baker(engine).bake(_script(turns: 3));

      // 第 2 轮失败，其余 2 轮成功——整场没毁
      expect(result.failures, hasLength(1));
      expect(result.failures.containsKey(1), isTrue);
      expect(result.turns.where((t) => !t.failed), hasLength(2));
      expect(result.hasAudio, isTrue);
      // 402 不重试：3 轮各一次请求
      expect(engine.texts, hasLength(3));
      // 失败轮次被标记
      expect(result.turns[1].failed, isTrue);
      // 失败轮次仍占时间轴（静音占位），后续轮次定位不错位
      expect(result.turns[2].startMs, result.turns[1].endMs);
    });

    test('内容审查失败后降级到更细切分重试', () async {
      final engine = _FakeEngine(
        fixture: fixture,
        throwOnCalls: {1: Exception('HTTP 451 censorship_blocked')},
      );
      // 台词长到能切成多个 120 字碎片——否则没有降级空间。
      final long = MeetingScript(
        id: 'script_mat_c',
        materialId: 'mat_c',
        draftId: 'd',
        title: 'censor',
        targetMinutes: 30,
        generatedAt: DateTime(2026, 10, 22),
        turns: [
          ScriptTurn(
            role: RehearsalRole.simon,
            text: List.filled(30, 'We need to discuss the VPN password policy.')
                .join(' '),
          ),
        ],
      );
      final result = await baker(engine).bake(long);

      // 首段被拒后切成碎片逐段合成，整轮最终成功
      expect(result.failures, isEmpty);
      expect(result.hasAudio, isTrue);
      expect(engine.texts.length, greaterThan(1));
    });

    test('空音频算失败并重试', () async {
      final engine = _AlwaysEmptyEngine();
      final result = await baker(engine).bake(_script(turns: 1));
      // 1 次首发 + 2 次重试
      expect(engine.calls, 3);
      expect(result.failures, hasLength(1));
      // 唯一一轮失败 → 没有任何音频可拼
      expect(result.hasAudio, isFalse);
      expect(result.clip, isNull);
    });

    test('超长轮次按句子边界切分合成', () async {
      final engine = _FakeEngine(fixture: fixture);
      final long = MeetingScript(
        id: 'script_mat_long',
        materialId: 'mat_long',
        draftId: 'd',
        title: 'long',
        targetMinutes: 30,
        generatedAt: DateTime(2026, 10, 22),
        turns: [
          ScriptTurn(
            role: RehearsalRole.simon,
            text: List.filled(60, 'This is a fairly long sentence about latency.')
                .join(' '),
          ),
        ],
      );
      final result = await baker(engine).bake(long);
      expect(result.hasAudio, isTrue);
      // 超长文本被切成多段，每段独立合成
      expect(engine.texts.length, greaterThan(1));
      for (final t in engine.texts) {
        expect(t.length, lessThanOrEqualTo(RehearsalBaker.maxSynthesisChars));
      }
    });
  });

  group('讲稿语音', () {
    SpeechDraft _draft() => SpeechDraft(
          id: 'draft_mat_x',
          materialId: 'mat_x',
          title: 'Q4 评审 · 汇报讲稿',
          generatedAt: DateTime(2026, 10, 22),
          sections: const [
            DraftSection(title: '容量现状', body: 'We run 72 nodes today.'),
            DraftSection(title: '扩容计划', body: 'We scale to 96 nodes.'),
            DraftSection(title: '风险', body: 'The 503 rate is 0.4 percent.'),
          ],
        );

    test('按节合成，每节一个音频文件，Simon 固定音色', () async {
      final engine = _FakeEngine(fixture: fixture);
      final result = await baker(engine).bakeDraft(_draft());

      expect(result.hasAudio, isTrue);
      expect(result.sections, hasLength(3));
      expect(result.failures, isEmpty);
      // 每节一个 mp3，路径各不相同
      final paths = result.sections.map((s) => s.audioPath).toSet();
      expect(paths, hasLength(3));
      for (final s in result.sections) {
        expect(
          await File(p.join(tmp.path, 'materials', s.audioPath)).exists(),
          isTrue,
        );
        expect(s.durationMs, greaterThan(0));
        expect(s.failed, isFalse);
      }
      // 全部用 Simon 的音色
      expect(result.voice, RehearsalVoices.voiceFor('simon'));
      expect(engine.voices.toSet(), {RehearsalVoices.voiceFor('simon')});
    });

    test('节标题与讲稿一一对应', () async {
      final result =
          await baker(_FakeEngine(fixture: fixture)).bakeDraft(_draft());
      expect(result.sections.map((s) => s.title).toList(),
          ['容量现状', '扩容计划', '风险']);
    });

    test('单节失败被标记，其它节不受影响', () async {
      final engine = _FakeEngine(
        fixture: fixture,
        throwOnCalls: {2: Exception('HTTP 402 quota_exceeded')},
      );
      final result = await baker(engine).bakeDraft(_draft());

      expect(result.failures, hasLength(1));
      expect(result.failures.containsKey(1), isTrue);
      expect(result.sections[1].failed, isTrue);
      expect(result.sections[1].audioPath, isEmpty);
      // 其余两节照常产出
      expect(result.bakedCount, 2);
      expect(result.sections[0].audioPath, isNotEmpty);
      expect(result.sections[2].audioPath, isNotEmpty);
    });

    test('总时长等于各节之和', () async {
      final result =
          await baker(_FakeEngine(fixture: fixture)).bakeDraft(_draft());
      final sum = result.sections.fold<int>(0, (a, s) => a + s.durationMs);
      expect(result.totalMs, sum);
    });

    test('正文为空的节被标记失败', () async {
      final draft = SpeechDraft(
        id: 'd',
        materialId: 'mat_x',
        title: 't',
        generatedAt: DateTime(2026, 10, 22),
        sections: const [
          DraftSection(title: '空节', body: '   '),
          DraftSection(title: '正常节', body: 'Hello there.'),
        ],
      );
      final result = await baker(_FakeEngine(fixture: fixture)).bakeDraft(draft);
      expect(result.failures.containsKey(0), isTrue);
      expect(result.sections[0].failed, isTrue);
      expect(result.bakedCount, 1);
    });
  });

  group('素材 id', () {
    test('带 rehearsal 前缀，与 CoderSlingo 形态不撞', () async {
      final result = await baker(_FakeEngine(fixture: fixture)).bake(_script());
      expect(result.clip!.id, startsWith('rehearsal_'));
    });
  });
}

class _AlwaysEmptyEngine implements TtsEngine {
  int calls = 0;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    calls++;
    return Uint8List(0);
  }
}
