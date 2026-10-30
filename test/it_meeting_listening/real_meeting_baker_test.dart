import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/speaker_profile_resolver.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 假 TTS：产出与文本长度成比例的字节，使时长可精确预期。
///
/// 字节数 = 字数 × 16 → 按 128kbps 估算时长 = 字数 × 1ms。
/// 这样"第 N 轮在第几毫秒"可以在测试里手算。
class _FakeTts implements TtsEngine {
  int calls = 0;

  /// 返回 true 的文本模拟合成失败。
  bool Function(String text)? failWhen;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    calls++;
    if (failWhen?.call(text) ?? false) {
      throw StateError('boom');
    }
    return Uint8List(text.length * 16);
  }

  @override
  Future<bool> isAvailable() async => true;
}

/// 假音频工具：拼接 = 时长相加；时长 = 字节数 × 8 / 128000。
class _FakeAudio implements AudioToolkit {
  int concatCount = 0;

  /// 模拟拼接失败（ffmpeg 缺失 / 进程出错）。
  bool failConcat = false;

  final Map<String, int> _durations = {};


  int _fromBytes(String path) {
    final f = File(path);
    if (!f.existsSync()) return 0;
    return ((f.lengthSync() * 8 / 128000) * 1000).round();
  }

  int durationOf(String path) => _durations[path] ?? _fromBytes(path);

  @override
  Future<void> concat(List<String> files, String outputPath) async {
    concatCount++;
    // 模拟 ffmpeg 缺失/拼接失败：调用点必须让失败可见，而不是静默留一段。
    if (failConcat) throw StateError('未检测到 ffmpeg，无法拼接音频');
    _durations[outputPath] = files.fold(0, (a, f) => a + durationOf(f));
    await File(outputPath).writeAsBytes(List.filled(1, 0));
  }

  @override
  Future<int> probeDurationMs(String filePath) async => durationOf(filePath);

  @override
  Future<void> writeSilence(String path, int ms) async {
    _durations[path] = ms;
    await File(path).writeAsBytes(const [0]);
  }
}

void main() {
  late Directory tmp;
  late RealMeetingStore store;
  late _FakeTts tts;
  late _FakeAudio audio;
  late RealMeetingBaker baker;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('real_meeting_baker_test');
    AppPaths.overrideRootForTesting(tmp);
    store = RealMeetingStore();
    tts = _FakeTts();
    audio = _FakeAudio();
    baker = RealMeetingBaker(engine: tts, store: store, audio: audio);
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RealMeeting meeting(List<(String slot, String text)> turns) => RealMeeting(
        id: 'rm_test',
        title: 'Test Meeting',
        sourcePath: '/in/test.md',
        fileName: 'test.md',
        contentHash: 'h',
        declaredDurationMs: 0,
        keywords: const [],
        slots: [
          for (final s in turns.map((t) => t.$1).toSet())
            SpeakerSlot(id: s, turnCount: 0),
        ],
        turns: [
          for (var i = 0; i < turns.length; i++)
            MeetingTurn(
              index: i,
              slotId: turns[i].$1,
              timestampMs: i * 1000,
              text: turns[i].$2,
            ),
        ],
        importedAt: DateTime(2026, 10, 20),
      );

  final speakers = {
    '发言人 1': const ResolvedSpeaker(
        slotId: '发言人 1', displayName: 'Simon', voiceId: 'v1', isMe: false),
    '发言人 2': const ResolvedSpeaker(
        slotId: '发言人 2', displayName: 'Deepan', voiceId: 'v2', isMe: false),
  };

  group('合成', () {
    test('逐组合成落盘，时间戳按实际音频累加', () async {
      final m = meeting([
        ('发言人 1', 'hello.'),
        ('发言人 2', 'world.'),
      ]);
      final result = await baker.bake(m, speakers: speakers);
      expect(result.hasAudio, isTrue);

      final turnsDir = store.turnsDir(m.id);
      expect(File('${turnsDir.path}/g0.mp3').existsSync(), isTrue);
      expect(File('${turnsDir.path}/g1.mp3').existsSync(), isTrue);

      final clip = result.clip!;
      expect(clip.turns, hasLength(2));
      expect(clip.turns.first.speaker, 'Simon');
      expect(clip.turns.last.speaker, 'Deepan');
      // "hello." 6 字 → 6ms；"world." 6 字 → 6ms
      expect(clip.turns.first.startMs, 0);
      expect(clip.turns.first.endMs, 6);
      expect(clip.turns.last.startMs, 6);
      expect(clip.durationMs, 12);
      expect(clip.scene.id, 'real-meeting');
    });

    test('续句被合成成一组，组内各轮共享起止时间', () async {
      final m = meeting([
        ('发言人 1', 'we need to'),
        ('发言人 2', 'check it.'),
      ]);
      final result = await baker.bake(m, speakers: speakers);
      final clip = result.clip!;
      // 两轮并成一组，但仍然显示两轮——展示层的说话人归属保持原样
      expect(clip.turns, hasLength(2));
      expect(clip.turns.first.startMs, clip.turns.last.startMs);
      expect(clip.turns.first.endMs, clip.turns.last.endMs);
      expect(clip.turns.first.speaker, 'Simon');
      expect(clip.turns.last.speaker, 'Deepan');
      // 但整组是 Simon 的音色念的，两轮的 voice 都必须记成 v1
      expect(clip.turns.first.voice, 'v1');
      expect(clip.turns.last.voice, 'v1');
      expect(tts.calls, 1);
    });

    test('失败组写静音占位，后续组时间不漏', () async {
      tts.failWhen = (t) => t.contains('BROKEN');
      final m = meeting([
        ('发言人 1', 'ok one.'),
        ('发言人 2', 'BROKEN part'),
        ('发言人 1', 'ok two.'),
      ]);
      final result = await baker.bake(m, speakers: speakers);

      expect(result.failures.keys, contains(1));
      final clip = result.clip!;
      // "ok one."(7字) → 7ms，失败组 1200ms 静音，"ok two."(7字) → 7ms
      expect(clip.turns[0].startMs, 0);
      // "BROKEN part" 无句末标点，"ok two." 小写开头 → 并成同一组，
      // 两轮共享 1200ms 静音占位的跨度（这就是续句合并的时间戳语义）。
      expect(result.state.groups, hasLength(2));
      expect(result.state.groups.last.turnIndices, [1, 2]);
      expect(clip.turns[1].startMs, 7);
      expect(clip.turns[1].endMs, 7 + 1200);
      expect(clip.turns[2].startMs, 7);
      expect(clip.durationMs, 7 + 1200);
    });

    test('续跑不重复合成已完成的组', () async {
      final m = meeting([
        ('发言人 1', 'hello.'),
        ('发言人 2', 'world.'),
      ]);
      await baker.bake(m, speakers: speakers);
      final firstCalls = tts.calls;
      expect(firstCalls, 2);

      await baker.bake(m, speakers: speakers);
      expect(tts.calls, firstCalls, reason: '续跑不该再请求 TTS');
    });

    test('上次失败的组在续跑时重新合成', () async {
      tts.failWhen = (t) => t.contains('BROKEN');
      final m = meeting([
        ('发言人 1', 'ok one.'),
        ('发言人 2', 'BROKEN part'),
      ]);
      await baker.bake(m, speakers: speakers);

      tts.failWhen = null;
      final result = await baker.bake(m, speakers: speakers);
      expect(result.failures, isEmpty);
      expect(result.state.isComplete, isTrue);
    });
  });

  group('插入回答与重建', () {
    Future<RealMeeting> baked() async {
      final m = meeting([
        ('发言人 1', 'question here.'),
        ('发言人 2', 'answer here.'),
      ]);
      await baker.bake(m, speakers: speakers);
      return m;
    }

    test('插入回答后它出现在锚点轮之后，后续时间戳后移', () async {
      final m = await baked();
      final before = (await baker.rebuildAudio(m, speakers: speakers)).$1!;
      final beforeSecondStart = before.turns[1].startMs;

      final answer = InsertedAnswer(
        id: 'ans_1',
        anchorTurnIndex: 0,
        questionTurnIndex: 0,
        speakerName: '我',
        voiceId: 'vme',
        textEn: 'my reply.',
      );
      final fileName = await baker.bakeAnswer(
        meetingId: m.id,
        textEn: answer.textEn,
        voiceId: answer.voiceId,
        fileName: 'ans_1.mp3',
      );
      expect(fileName, 'ans_1.mp3');
      await store.saveAnswers(m.id, [answer.copyWith(audioFile: fileName!)]);

      final (clip, state) = await baker.rebuildAudio(m, speakers: speakers);
      expect(clip!.turns, hasLength(3));
      expect(clip.turns[1].role, InsertedAnswer.roleMarker);
      expect(clip.turns[1].speaker, '我');
      // "my reply." 9 字 → 9ms
      expect(clip.turns[2].startMs, beforeSecondStart + 9);
      expect(state.totalMs, before.durationMs + 9);
      expect(audio.concatCount, greaterThanOrEqualTo(2));
    });

    test('删除回答后时间戳复原', () async {
      final m = await baked();
      final (before, _) = await baker.rebuildAudio(m, speakers: speakers);

      final fileName = await baker.bakeAnswer(
        meetingId: m.id,
        textEn: 'my reply.',
        voiceId: 'vme',
        fileName: 'ans_1.mp3',
      );
      await store.saveAnswers(m.id, [
        InsertedAnswer(
          id: 'ans_1',
          anchorTurnIndex: 0,
          questionTurnIndex: 0,
          speakerName: '我',
          voiceId: 'vme',
          textEn: 'my reply.',
          audioFile: fileName!,
        ),
      ]);
      await baker.rebuildAudio(m, speakers: speakers);

      await store.saveAnswers(m.id, const []);
      final (after, state) = await baker.rebuildAudio(m, speakers: speakers);

      expect(after!.turns, hasLength(2));
      expect(after.turns[1].startMs, before!.turns[1].startMs);
      expect(after.durationMs, before.durationMs);
      expect(state.totalMs, before.durationMs);
    });

    test('锚点越界的回答不进音频、不崩，摘要里点名失效', () async {
      final m = await baked();
      final fileName = await baker.bakeAnswer(
        meetingId: m.id,
        textEn: 'orphan.',
        voiceId: 'vme',
        fileName: 'ans_x.mp3',
      );
      await store.saveAnswers(m.id, [
        InsertedAnswer(
          id: 'ans_x',
          anchorTurnIndex: 99,
          questionTurnIndex: 99,
          speakerName: '我',
          voiceId: 'vme',
          textEn: 'orphan.',
          audioFile: fileName!,
        ),
      ]);

      final (clip, _) = await baker.rebuildAudio(m, speakers: speakers);
      expect(clip!.turns, hasLength(2));
      expect(clip.summary, contains('锚点失效'));
    });

    test('回答音频缺失时不参与拼接，也不留下长度为 0 的轮次', () async {
      final m = await baked();
      await store.saveAnswers(m.id, const [
        InsertedAnswer(
          id: 'ans_no_audio',
          anchorTurnIndex: 0,
          questionTurnIndex: 0,
          speakerName: '我',
          voiceId: 'vme',
          textEn: 'not baked yet',
          audioFile: '',
        ),
      ]);
      final (clip, _) = await baker.rebuildAudio(m, speakers: speakers);
      expect(clip!.turns, hasLength(2));
    });
  });

  group('拼接失败不产出假素材', () {
    test('整篇拼接失败时素材以占位形态返回，而不是播不了的记录', () async {
      final m = meeting([
        ('发言人 1', 'hello.'),
        ('发言人 2', 'world.'),
      ]);
      audio.failConcat = true;

      final result = await baker.bake(m, speakers: speakers);
      expect(result.clip, isNotNull);
      expect(result.clip!.isPlaceholder, isTrue,
          reason: '没有可播音频就必须是占位，否则索引在撒谎');
      expect(result.clip!.audioPath, isEmpty);
      expect(result.hasPlayableAudio, isFalse);
      expect(result.clip!.summary, contains('尚未生成'));
      // 逐组音频仍然落盘——修好后重建不必重新合成
      expect(File('${store.turnsDir(m.id).path}/g0.mp3').existsSync(), isTrue);
    });

    test('修好后重建即可发布，且不重复合成', () async {
      final m = meeting([
        ('发言人 1', 'hello.'),
        ('发言人 2', 'world.'),
      ]);
      audio.failConcat = true;
      await baker.bake(m, speakers: speakers);
      final callsWhenBroken = tts.calls;

      audio.failConcat = false;
      final (clip, _) = await baker.rebuildAudio(m, speakers: speakers);

      expect(clip!.isPlaceholder, isFalse);
      expect(clip.audioPath, isNotEmpty);
      expect(tts.calls, callsWhenBroken, reason: '重建不该重新合成逐组音频');
    });

    test('多段拼接失败时该组标记失败，不产出被截断的音频', () async {
      // 超过 900 字会被切成多段，走拼接分支
      final long = List.filled(400, 'word').join(' ');
      final m = meeting([('发言人 1', '$long.')]);
      audio.failConcat = true;

      final result = await baker.bake(m, speakers: speakers);
      expect(result.failures.keys, contains(0));
      expect(result.state.groups.single.failed, isTrue);
    });
  });

  group('强制重烘与取消', () {
    Map<String, ResolvedSpeaker> withVoice(String slot, String voice) => {
          for (final e in speakers.entries)
            e.key: e.key == slot
                ? ResolvedSpeaker(
                    slotId: e.value.slotId,
                    displayName: e.value.displayName,
                    voiceId: voice,
                    isMe: e.value.isMe)
                : e.value,
        };

    test('强制重烘成功后替换音频并更新记录的音色', () async {
      final m = meeting([('发言人 1', 'hello.')]);
      final first = await baker.bake(m, speakers: speakers);
      expect(first.state.groups.single.voiceId, 'v1');

      final second = await baker.bake(
        m,
        speakers: withVoice('发言人 1', 'v9'),
        forceGroups: {0},
      );
      expect(second.state.groups.single.voiceId, 'v9');
      expect(second.failures, isEmpty);
      // 新文件确实写出来了（内容长度随文本，换音色不改文本，这里只看存在与非空）
      final f = File('${store.turnsDir(m.id).path}/g0.mp3');
      expect(f.existsSync() && f.lengthSync() > 0, isTrue);
      // 临时文件不该残留
      expect(File('${f.path}.new').existsSync(), isFalse);
    });

    test('强制重烘失败：保留旧音频与旧音色记录', () async {
      final m = meeting([('发言人 1', 'hello.')]);
      await baker.bake(m, speakers: speakers);
      final file = File('${store.turnsDir(m.id).path}/g0.mp3');
      final before = file.readAsBytesSync();

      tts.failWhen = (_) => true;
      final result = await baker.bake(
        m,
        speakers: withVoice('发言人 1', 'v9'),
        forceGroups: {0},
      );

      expect(result.failures.keys, contains(0));
      expect(file.readAsBytesSync(), before,
          reason: '失败不能覆盖旧音频——那是用户还能听的那一份');
      expect(result.state.groups.single.voiceId, 'v1',
          reason: '记录仍是实际在放的那段音频的音色');
      expect(File('${file.path}.new').existsSync(), isFalse);
    });

    test('取消在组边界生效：已完成的组更新，其余保持原样', () async {
      final m = meeting([
        ('发言人 1', 'one.'),
        ('发言人 2', 'two.'),
        ('发言人 1', 'three.'),
      ]);
      await baker.bake(m, speakers: speakers);

      var checks = 0;
      final result = await baker.bake(
        m,
        speakers: withVoice('发言人 1', 'v9'),
        forceGroups: {0, 2},
        shouldCancel: () => checks++ >= 1, // 处理完第一组后取消
      );

      expect(result.cancelled, isTrue);
      // 组 0 已更新
      expect(result.state.groups[0].voiceId, 'v9');
      // 组 2 还没轮到，仍是旧音色
      expect(result.state.groups[2].voiceId, 'v1');
    });
  });

  group('空与边界', () {
    test('没有合成状态时重建返回空 Clip 而不是抛异常', () async {
      final m = meeting([('发言人 1', 'x.')]);
      final (clip, state) = await baker.rebuildAudio(m, speakers: speakers);
      expect(clip, isNull);
      expect(state.groups, isEmpty);
    });
  });
}
