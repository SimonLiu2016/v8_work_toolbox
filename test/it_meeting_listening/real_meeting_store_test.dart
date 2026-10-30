import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/speaker_profile_resolver.dart';

void main() {
  late Directory tmp;
  late RealMeetingStore store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('real_meeting_store_test');
    AppPaths.overrideRootForTesting(tmp);
    store = RealMeetingStore();
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  RealMeeting meeting(String id, {String path = '/in/a.md'}) => RealMeeting(
        id: id,
        title: 'AI Agent Security Review',
        sourcePath: path,
        fileName: 'a.md',
        contentHash: 'deadbeefdeadbeef',
        declaredDurationMs: 1206000,
        keywords: const ['governance', 'VPC'],
        slots: const [
          SpeakerSlot(id: '发言人 1', turnCount: 54),
          SpeakerSlot(id: '发言人 2', turnCount: 55),
        ],
        turns: const [
          MeetingTurn(
              index: 0, slotId: '发言人 1', timestampMs: 1000, text: 'hello'),
          MeetingTurn(
              index: 1, slotId: '发言人 2', timestampMs: 21000, text: 'hi'),
        ],
        importedAt: DateTime(2026, 10, 20, 15, 2),
      );

  group('四层各自独立落盘', () {
    test('原稿、设定、回答、合成状态分别存取', () async {
      await store.saveMeeting(meeting('rm_1'));
      await store.saveSettings(
        'rm_1',
        const MeetingSpeakerSettings(bySlot: {
          '发言人 1': SpeakerSetting(displayName: 'Simon'),
        }),
      );
      await store.saveAnswers('rm_1', const [
        InsertedAnswer(
          id: 'ans_1',
          anchorTurnIndex: 0,
          questionTurnIndex: 0,
          speakerName: '我',
          voiceId: 'boyinnansheng',
          textEn: 'We already have a gateway.',
          textZh: '我们已经有网关了。',
          audioFile: 'ans_1.mp3',
        ),
      ]);
      await store.saveBakeState(
        'rm_1',
        const MeetingBakeState(
          groups: [
            TurnGroupAudio(turnIndices: [0, 1], fileName: 'g0.mp3'),
          ],
          audioFile: 'rm_1.mp3',
          totalMs: 4100,
        ),
      );

      expect((await store.loadMeeting('rm_1'))!.turns, hasLength(2));
      expect((await store.loadSettings('rm_1')).of('发言人 1').displayName,
          'Simon');
      expect((await store.loadAnswers('rm_1')).single.textZh, '我们已经有网关了。');
      final bake = (await store.loadBakeState('rm_1'))!;
      expect(bake.groups.single.turnIndices, [0, 1]);
      expect(bake.totalMs, 4100);
    });

    test('改设定不动原稿与回答', () async {
      await store.saveMeeting(meeting('rm_1'));
      await store.saveAnswers('rm_1', const [
        InsertedAnswer(
          id: 'ans_1',
          anchorTurnIndex: 0,
          questionTurnIndex: 0,
          speakerName: '我',
          voiceId: 'v',
          textEn: 'x',
        ),
      ]);

      await store.saveSettings(
        'rm_1',
        const MeetingSpeakerSettings(bySlot: {
          '发言人 2': SpeakerSetting(displayName: 'Deepan'),
        }),
      );

      expect((await store.loadMeeting('rm_1'))!.turns.first.slotId, '发言人 1');
      expect((await store.loadAnswers('rm_1')), hasLength(1));
    });

    test('删除覆盖层回落为空设定', () async {
      await store.saveSettings(
        'rm_1',
        const MeetingSpeakerSettings(bySlot: {
          '发言人 1': SpeakerSetting(displayName: 'Simon'),
        }),
      );
      await store.deleteSettings('rm_1');
      expect((await store.loadSettings('rm_1')).isEmpty, isTrue);
    });
  });

  group('会议列表与查找', () {
    test('按导入时间倒序', () async {
      await store.saveMeeting(meeting('old'));
      await store.saveMeeting(RealMeeting(
        id: 'new',
        title: 't',
        sourcePath: '/in/b.md',
        fileName: 'b.md',
        contentHash: 'h2',
        declaredDurationMs: 0,
        keywords: const [],
        slots: const [],
        turns: const [],
        importedAt: DateTime(2026, 10, 22),
      ));
      expect((await store.listMeetings()).map((m) => m.id), ['new', 'old']);
    });

    test('按来源路径找到同一场会', () async {
      await store.saveMeeting(meeting('rm_1', path: '/in/a.md'));
      expect((await store.findBySourcePath('/in/a.md'))!.id, 'rm_1');
      expect(await store.findBySourcePath('/in/none.md'), isNull);
    });

    test('删除会议清空全部层与逐轮音频', () async {
      await store.saveMeeting(meeting('rm_1'));
      await store.saveSettings(
          'rm_1', const MeetingSpeakerSettings(bySlot: {'发言人 1': SpeakerSetting(displayName: 'A')}));
      await store.saveAnswers('rm_1', const []);
      await store.saveBakeState('rm_1', const MeetingBakeState());
      final turns = store.turnsDir('rm_1');
      await turns.create(recursive: true);
      await File('${turns.path}/g0.mp3').writeAsBytes([1, 2, 3]);
      await store.audioFile('rm_1').writeAsBytes([1, 2, 3]);

      await store.deleteMeeting('rm_1');

      expect(await store.loadMeeting('rm_1'), isNull);
      expect(await store.loadBakeState('rm_1'), isNull);
      expect(await turns.exists(), isFalse);
      expect(await store.audioFile('rm_1').exists(), isFalse);
    });
  });

  group('我的身份', () {
    test('未配置时返回默认值', () async {
      final id = await store.loadMyIdentity();
      expect(id.name, MyIdentity.defaultName);
      expect(id.voiceId, MyIdentity.defaultVoiceId);
      expect(id.voiceId, 'boyinnansheng');
    });

    test('存取往返', () async {
      await store.saveMyIdentity(const MyIdentity(name: 'Simon', voiceId: 'v1'));
      final id = await store.loadMyIdentity();
      expect(id.name, 'Simon');
      expect(id.voiceId, 'v1');
    });

    test('配置文件被改坏时回落默认', () async {
      await AppPaths.listeningMyIdentityFile.parent.create(recursive: true);
      await AppPaths.listeningMyIdentityFile
          .writeAsString('{"name": "", "voiceId": ""}');
      final id = await store.loadMyIdentity();
      expect(id.name, MyIdentity.defaultName);
      expect(id.voiceId, MyIdentity.defaultVoiceId);
    });
  });

  group('降级', () {
    test('缺失文件返回空而不是抛异常', () async {
      expect(await store.loadMeeting('nope'), isNull);
      expect(await store.loadBakeState('nope'), isNull);
      expect(await store.loadAnswers('nope'), isEmpty);
      expect((await store.loadSettings('nope')).isEmpty, isTrue);
    });

    test('损坏的原稿不影响列表其余部分', () async {
      await store.saveMeeting(meeting('good'));
      await AppPaths.realMeetingMeetingsDir.create(recursive: true);
      await File('${AppPaths.realMeetingMeetingsDir.path}/bad.json')
          .writeAsString('{not json');
      expect((await store.listMeetings()).map((m) => m.id), ['good']);
    });
  });

  group('说话人设定解析', () {
    const identity = MyIdentity(name: '我', voiceId: 'boyinnansheng');

    test('未设定时名字回落槽位、音色由槽位散列决定', () {
      final a = SpeakerProfileResolver.resolve(
        slotId: '发言人 1',
        setting: const SpeakerSetting(),
        identity: identity,
      );
      final b = SpeakerProfileResolver.resolve(
        slotId: '发言人 1',
        setting: const SpeakerSetting(),
        identity: identity,
      );
      expect(a.displayName, '发言人 1');
      // 纯函数：同一槽位两次解析必须是同一音色
      expect(a.voiceId, b.voiceId);
    });

    test('不同槽位大概率不同音色', () {
      final ids = ['发言人 1', '发言人 2', '发言人 3', '发言人 4', '发言人 5']
          .map((s) => SpeakerProfileResolver.resolve(
                slotId: s,
                setting: const SpeakerSetting(),
                identity: identity,
              ).voiceId)
          .toSet();
      expect(ids.length, greaterThan(1));
    });

    test('标记为我在任何设定下都用我的身份', () {
      final r = SpeakerProfileResolver.resolve(
        slotId: '发言人 3',
        setting: const SpeakerSetting(
            displayName: '别人', voiceId: 'other', isMe: true),
        identity: identity,
      );
      expect(r.displayName, '我');
      expect(r.voiceId, 'boyinnansheng');
      expect(r.isMe, isTrue);
      expect(r.label, '我（我）');
    });

    test('覆盖层的名字与音色优先', () {
      final r = SpeakerProfileResolver.resolve(
        slotId: '发言人 2',
        setting: const SpeakerSetting(displayName: 'Deepan', voiceId: 'v9'),
        identity: identity,
      );
      expect(r.displayName, 'Deepan');
      expect(r.voiceId, 'v9');
      expect(r.isMe, isFalse);
    });
  });
}
