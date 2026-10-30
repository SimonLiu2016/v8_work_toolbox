import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_library.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

class _FakeTts implements TtsEngine {
  int calls = 0;
  final List<String> synthesized = [];

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    calls++;
    synthesized.add(text);
    return Uint8List(text.length * 16);
  }

  @override
  Future<bool> isAvailable() async => true;
}

class _FakeAudio implements AudioToolkit {
  final Map<String, int> durations = {};

  /// 模拟拼接失败（ffmpeg 不可用）。
  bool failConcat = false;


  int _fromBytes(String path) {
    final f = File(path);
    if (!f.existsSync()) return 0;
    return ((f.lengthSync() * 8 / 128000) * 1000).round();
  }

  int _of(String path) => durations[path] ?? _fromBytes(path);

  @override
  Future<void> concat(List<String> files, String outputPath) async {
    if (failConcat) throw StateError('未检测到 ffmpeg，无法拼接音频');
    durations[outputPath] = files.fold(0, (a, f) => a + _of(f));
    await File(outputPath).writeAsBytes(const [0]);
  }

  @override
  Future<int> probeDurationMs(String filePath) async => _of(filePath);

  @override
  Future<void> writeSilence(String path, int ms) async {
    durations[path] = ms;
    await File(path).writeAsBytes(const [0]);
  }
}

void main() {
  late Directory tmp;
  late RealMeetingStore store;
  late _FakeTts tts;
  late _FakeAudio audio;
  late RealMeetingService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('real_meeting_service_test');
    AppPaths.overrideRootForTesting(tmp);
    store = RealMeetingStore();
    tts = _FakeTts();
    audio = _FakeAudio();
    service = RealMeetingService(
      store: store,
      baker: RealMeetingBaker(engine: tts, store: store, audio: audio),
      library: ClipLibrary(AppPaths.itMeetingListeningDir),
    );
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<String> writeTranscript(String name, {String tail = 'bye.'}) async {
    final file = File('${tmp.path}/$name');
    await file.writeAsString('''
# Test Meeting

## 关键词

 governance    VPC

## 转文字

发言人 1 00:00:01

question here.

发言人 2 00:00:05

$tail
''');
    return file.path;
  }

  group('导入', () {
    test('导入后会议、音频、索引三处都有', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);

      expect(outcome.unchanged, isFalse);
      expect(outcome.meeting.turns, hasLength(2));
      expect(outcome.meeting.keywords, ['governance', 'VPC']);
      expect(outcome.bake!.hasAudio, isTrue);

      final index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
      expect(index.byId(outcome.meeting.id)?.scene.id, 'real-meeting');
    });

    test('内容未变的重复导入什么都不做', () async {
      final path = await writeTranscript('a.md');
      await service.importFile(path);
      final callsAfterFirst = tts.calls;

      final second = await service.importFile(path);
      expect(second.unchanged, isTrue);
      expect(tts.calls, callsAfterFirst, reason: '内容未变不该重新合成');
    });

    test('文稿更新后重建音频，回答保留并标记越界', () async {
      final path = await writeTranscript('a.md');
      final first = await service.importFile(path);
      await service.insertAnswer(
        meetingId: first.meeting.id,
        questionTurnIndex: 1,
        textEn: 'my reply.',
      );

      // 改稿：少了一轮 → 锚在第 1 轮的回答越界
      await File(path).writeAsString('''
# Test Meeting

## 转文字

发言人 1 00:00:01

question here.
''');
      final second = await service.importFile(path);

      expect(second.unchanged, isFalse);
      final answers = await store.loadAnswers(first.meeting.id);
      expect(answers, hasLength(1), reason: '回答不该被静默删除');
      expect(answers.single.stale, isTrue);
    });
  });

  group('说话人设定', () {
    test('改名只重建素材，不重新合成', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final callsBefore = tts.calls;

      final clip = await service.renameSpeaker(
          outcome.meeting.id, '发言人 1', 'Simon');
      expect(clip!.turns.first.speaker, 'Simon');
      expect(tts.calls, callsBefore);
      expect(outcome.meeting.turns.first.slotId, '发言人 1',
          reason: '原稿的槽位标识不该被改名影响');
    });

    test('改音色不触发合成，只标记待更新', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final callsBefore = tts.calls;

      final clip =
          await service.setSpeakerVoice(outcome.meeting.id, '发言人 1', 'newvoice');
      // 设定是声明，不是执行：一次 TTS 都不该发生
      expect(tts.calls, callsBefore);

      // 磁盘上的音频仍是旧音色，Clip 必须如实记录"实际"音色
      expect(clip!.turns.first.voice, isNot('newvoice'));

      // 但该槽位的组被标记为待更新
      final pending = await service.pendingGroups(outcome.meeting);
      expect(pending, isNotEmpty);

      // 显式重烘之后才会真的变声
      await service.rebakeGroups(outcome.meeting, pending.toSet());
      final after = await service.refresh(outcome.meeting);
      expect(after!.turns.first.voice, 'newvoice');
      expect(await service.pendingGroups(outcome.meeting), isEmpty);
    });

    test('标记为「我」立即改名，音色待重烘后才变', () async {
      await store.saveMyIdentity(const MyIdentity(name: 'Simon', voiceId: 'me_voice'));
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);

      final clip = await service.markSlotAsMe(outcome.meeting.id, '发言人 2');
      // 名字立刻生效
      expect(clip!.turns.last.speaker, 'Simon');
      // 音频还是旧音色，直到显式重烘
      expect(clip.turns.last.voice, isNot('me_voice'));

      final pending = await service.pendingGroups(outcome.meeting);
      await service.rebakeGroups(outcome.meeting, pending.toSet());
      final after = await service.refresh(outcome.meeting);
      expect(after!.turns.last.voice, 'me_voice');
    });
  });

  group('解析预览', () {
    test('预览不写文件、不合成', () async {
      final path = await writeTranscript('a.md');
      final preview = await service.parseFile(path);

      expect(preview.turnCount, 2);
      expect(preview.slotIds, ['发言人 1', '发言人 2']);
      expect(preview.samples, hasLength(2));
      expect(preview.samples.first.slot, '发言人 1');
      expect(preview.contentUnchanged, isFalse);
      expect(preview.isProcessedDocument, isFalse);

      expect(await store.listMeetings(), isEmpty);
      expect(tts.calls, 0);
    });

    test('确认后才落盘与合成', () async {
      final path = await writeTranscript('a.md');
      final preview = await service.parseFile(path);
      expect(tts.calls, 0);

      final outcome = await service.commitImport(preview);
      expect(outcome.unchanged, isFalse);
      expect(await store.listMeetings(), hasLength(1));
      expect(tts.calls, greaterThan(0));
    });

    test('内容未变时预览标出、确认也不触发合成', () async {
      final path = await writeTranscript('a.md');
      await service.commitImport(await service.parseFile(path));
      final callsAfterFirst = tts.calls;

      final preview = await service.parseFile(path);
      expect(preview.contentUnchanged, isTrue);

      final outcome = await service.commitImport(preview);
      expect(outcome.unchanged, isTrue);
      expect(tts.calls, callsAfterFirst);
    });

    test('归档件与缺失关键词在预览里被标出', () async {
      final file = File('${tmp.path}/wrapped.md');
      await file.writeAsString('''
# 项目周例会

## 说明

| 项 | 内容 |
|----|------|
| 时间 | 2026-10-22 |

## 原文（导出件一字未改）

李嘉成 00:00:03

你好。

> 【译】hello.
''');
      final preview = await service.parseFile(file.path);
      expect(preview.isProcessedDocument, isTrue);
      expect(preview.keywordsMissing, isTrue);
      expect(preview.slotIds, ['李嘉成']);
      expect(preview.samples.first.text, '你好。');
    });
  });

  group('槽位合并', () {
    test('合并后名字与音色统一，原稿槽位标识不变', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      final before = await service.refresh(outcome.meeting);
      expect(before!.turns.last.speaker, '发言人 2');

      final clip = await service.mergeSpeakers(id, '发言人 2', '发言人 1');
      // 名字立刻统一；音色要等重烘（这里只断言展示层）
      expect(clip!.turns.last.speaker, '发言人 1');
      expect(await service.pendingGroups(outcome.meeting), isNotEmpty);

      // 原稿没变
      final meeting = (await store.loadMeeting(id))!;
      expect(meeting.turns.last.slotId, '发言人 2');
    });

    test('合并后改名对两个槽位同时生效', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      await service.mergeSpeakers(id, '发言人 2', '发言人 1');
      final clip = await service.renameSpeaker(id, '发言人 1', 'Alice');
      expect(clip!.turns.map((t) => t.speaker).toSet(), {'Alice'});
    });

    test('取消合并恢复原状', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      await service.mergeSpeakers(id, '发言人 2', '发言人 1');
      final clip = await service.unmergeSpeaker(id, '发言人 2');
      expect(clip!.turns.last.speaker, '发言人 2');
      final settings = await store.loadSettings(id);
      expect(settings.mergeInto, isEmpty);
    });

    test('合并本身不触发合成', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final callsBefore = tts.calls;

      await service.mergeSpeakers(outcome.meeting.id, '发言人 2', '发言人 1');
      expect(tts.calls, callsBefore, reason: '设定变更不该烧 TTS');
    });

    test('合并后的重烘只动被合并槽位的组', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final pending = await service.pendingGroups(outcome.meeting);
      final callsBefore = tts.calls;

      await service.rebakeGroups(outcome.meeting, pending.toSet());
      // 合并只影响发言人 2 的组（一场 2 轮会议里就是 1 组）
      expect(tts.calls - callsBefore, pending.length);
    });
  });

  group('真实语料走预览（本机存在时才跑）', () {
    const base = '/Users/simon/Downloads/'
        'sea-doc-main-3962826157dbab79e85ee5b1f17b1ca1cd87cd32';

    const files = [
      '$base/communications/20261008-weekly-customer/附件/豆包原始-逐字稿_20261008.md',
      '$base/communications/20261015-weekly-customer/附件/豆包原始-逐字稿_20261015.md',
      '$base/communications/20261015-项目周例会-内部会后/海庭内部总结.md',
      '$base/communications/20261022-项目周例会-客户沟通/逐字稿_中英对照_20261022.md',
      '$base/communications/20261020-ai-agent-security-review/逐字稿_原文_20261020.md',
    ];

    for (final path in files) {
      final name = path.split('/').last;
      test('预览 $name', () async {
        if (!File(path).existsSync()) {
          markTestSkipped('样例不在本机：$path');
          return;
        }
        final preview = await service.parseFile(path);
        expect(preview.turnCount, greaterThan(0));
        expect(preview.slotIds, isNotEmpty);
        expect(preview.samples, isNotEmpty);
        expect(preview.samples.length, lessThanOrEqualTo(5));
        // 译文不能出现在样例里（TTS 会把中英都念一遍）
        for (final s in preview.samples) {
          expect(s.text.contains('【译】'), isFalse);
          expect(s.text.trim(), isNotEmpty);
        }
        // 预览阶段不做任何落盘
        expect(await store.listMeetings(), isEmpty);
        expect(tts.calls, 0);
      });
    }
  });

  group('会议显示名', () {
    test('改名只动展示，原稿标题不变', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      final renamed = await service.renameMeeting(id, '10-08 客户周会');
      expect(renamed!.title, '10-08 客户周会');

      final index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
      expect(index.byId(id)!.title, '10-08 客户周会');
      expect((await store.loadMeeting(id))!.title, 'Test Meeting');
    });

    test('清空后回落到文稿标题', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      await service.renameMeeting(id, '临时名');
      final cleared = await service.renameMeeting(id, '   ');
      expect(cleared!.title, 'Test Meeting');
    });

    test('重新导入（内容未变）不丢自定义名字', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      await service.renameMeeting(outcome.meeting.id, '10-08 客户周会');

      await service.importFile(path);
      final index =
          await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
      expect(index.byId(outcome.meeting.id)!.title, '10-08 客户周会');
    });
  });

  group('音频缺失时的自愈', () {
    test('拼接失败时以占位入库，修好后重建可播且不重合成', () async {
      final path = await writeTranscript('a.md');
      audio.failConcat = true;
      final broken = await service.importFile(path);

      var index =
          await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
      final placeholder = index.byId(broken.meeting.id)!;
      expect(placeholder.isPlaceholder, isTrue,
          reason: '播不了的素材必须是占位，不能带音频路径');
      expect(await service.bake(broken.meeting, onProgress: null),
          isA<RealMeetingBakeResult>());

      // 修好 ffmpeg 后重建
      audio.failConcat = false;
      final callsBefore = tts.calls;
      final meeting = (await store.loadMeeting(broken.meeting.id))!;
      final fixed = await service.bake(meeting);

      expect(fixed.hasPlayableAudio, isTrue);
      index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
      expect(index.byId(broken.meeting.id)!.isPlaceholder, isFalse);
      expect(tts.calls, callsBefore, reason: '重建应复用逐组音频，不重新合成');
    });
  });

  group('待更新判定', () {
    test('旧数据没有音色记录时不当作待更新', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      // 模拟旧版本写出的状态：组里有音频，但没有 voiceId
      final state = (await store.loadBakeState(id))!;
      await store.saveBakeState(
        id,
        MeetingBakeState(
          groups: [
            for (final g in state.groups)
              TurnGroupAudio(
                turnIndices: g.turnIndices,
                fileName: g.fileName,
                startMs: g.startMs,
                endMs: g.endMs,
              ),
          ],
          audioFile: state.audioFile,
          totalMs: state.totalMs,
        ),
      );

      // 什么都没改 → 不该提示待更新
      expect(await service.pendingGroups(outcome.meeting), isEmpty);

      // 改了音色之后，旧组（无记录）依然不参与判定——不知道当时用的什么
      await service.setSpeakerVoice(id, '发言人 1', 'newvoice');
      expect(await service.pendingGroups(outcome.meeting), isEmpty);
    });
  });

  group('回答层', () {
    test('插入 / 改文本 / 删除都可逆', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final id = outcome.meeting.id;

      final answer = await service.insertAnswer(
        meetingId: id,
        questionTurnIndex: 0,
        textEn: 'first reply.',
        textZh: '第一版回答。',
      );
      expect(answer, isNotNull);
      var clip = await service.refresh(outcome.meeting);
      expect(clip!.turns, hasLength(3));
      expect(clip.turns[1].role, InsertedAnswer.roleMarker);

      await service.updateAnswerText(id, answer!.id, 'second reply.');
      clip = await service.refresh(outcome.meeting);
      expect(clip!.turns[1].rawText, 'second reply.');
      expect((await store.loadAnswers(id)).single.textZh, '第一版回答。');

      await service.deleteAnswer(id, answer.id);
      clip = await service.refresh(outcome.meeting);
      expect(clip!.turns, hasLength(2));
      expect(await store.loadAnswers(id), isEmpty);
      // 音频文件也一并删掉
      expect(store.turnAudioFile(id, answer.audioFile).existsSync(), isFalse);
    });

    test('空回答不产生音频也不落盘', () async {
      final path = await writeTranscript('a.md');
      final outcome = await service.importFile(path);
      final answer = await service.insertAnswer(
        meetingId: outcome.meeting.id,
        questionTurnIndex: 0,
        textEn: '   ',
      );
      expect(answer, isNull);
      expect(await store.loadAnswers(outcome.meeting.id), isEmpty);
    });
  });
}
