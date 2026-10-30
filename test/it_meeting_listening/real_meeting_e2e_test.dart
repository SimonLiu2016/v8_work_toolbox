import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_library.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_service.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 端到端验收：用**真实样例文稿**跑完整条链路（解析 → 合成 → 词表 → 查词 →
/// 插入回答 → 播放重建 → 删除），TTS 用假引擎。
///
/// **为什么值得单独一条**：前面的单元测试各自验证一层，但这条链最容易断在
/// 层与层之间的契约上（轮次下标、音频路径、索引覆盖写）。样例不在本机时跳过。
class _FakeTts implements TtsEngine {
  int calls = 0;
  final Map<String, int> callsByText = {};

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    calls++;
    callsByText[text] = (callsByText[text] ?? 0) + 1;
    return Uint8List(text.length * 16);
  }

  @override
  Future<bool> isAvailable() async => true;
}

class _FakeAudio implements AudioToolkit {
  final Map<String, int> durations = {};


  int _of(String path) {
    final cached = durations[path];
    if (cached != null) return cached;
    final f = File(path);
    if (!f.existsSync()) return 0;
    return ((f.lengthSync() * 8 / 128000) * 1000).round();
  }

  @override
  Future<void> concat(List<String> files, String outputPath) async {
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

const samplePath = '/Users/simon/Downloads/'
    'sea-doc-main-3962826157dbab79e85ee5b1f17b1ca1cd87cd32/'
    'communications/20261020-ai-agent-security-review/'
    '逐字稿_原文_20261020.md';

void main() {
  late Directory tmp;
  late RealMeetingStore store;
  late _FakeTts tts;
  late RealMeetingService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('real_meeting_e2e');
    AppPaths.overrideRootForTesting(tmp);
    store = RealMeetingStore();
    tts = _FakeTts();
    service = RealMeetingService(
      store: store,
      baker: RealMeetingBaker(engine: tts, store: store, audio: _FakeAudio()),
      library: ClipLibrary(AppPaths.itMeetingListeningDir),
    );
  });

  tearDown(() async {
    AppPaths.resetForTesting();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('真实样例全链路', () async {
    if (!File(samplePath).existsSync()) {
      markTestSkipped('真实样例不在本机：$samplePath');
      return;
    }

    // ① 导入
    final outcome = await service.importFile(samplePath);
    final meeting = outcome.meeting;
    expect(meeting.turns, hasLength(152));
    expect(meeting.slots, hasLength(6));
    expect(meeting.keywords, contains('governance'));

    // ② 素材进了索引
    var index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
    final clip = index.byId(meeting.id);
    expect(clip, isNotNull);
    expect(clip!.scene.id, 'real-meeting');
    expect(clip.turns.length, lessThanOrEqualTo(meeting.turns.length),
        reason: '续句合并后组内各轮仍逐条保留，不会凭空多出轮次');
    expect(clip.durationMs, greaterThan(0));

    // ③ 说话人改名只改展示
    await service.renameSpeaker(meeting.id, '发言人 1', 'Alice');
    index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
    expect(index.byId(meeting.id)!.turns.first.speaker, 'Alice');
    expect((await store.loadMeeting(meeting.id))!.turns.first.slotId,
        '发言人 1');

    // ④ 词汇表与反查
    final vocabStore = MeetingVocabularyStore();
    final vocab = await vocabStore.rebuild([meeting]);
    final governance =
        vocab.entries(includeStopwords: true).firstWhere((e) => e.word == 'governance');
    expect(governance.count, greaterThan(1));
    final hits = vocab.postingsFor('VPC');
    if (hits.isNotEmpty) {
      expect(hits.first.sentence.toLowerCase(), contains('vpc'));
      expect(hits.first.meetingId, meeting.id);
    }

    // ⑤ 插入回答
    final callsAfterBake = tts.calls;
    final answer = await service.insertAnswer(
      meetingId: meeting.id,
      questionTurnIndex: 5,
      textEn: 'We route the agent through the internal gateway.',
      textZh: '我们通过内部网关访问。',
    );
    expect(answer, isNotNull);
    index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
    final withAnswer = index.byId(meeting.id)!;
    expect(withAnswer.turns.where((t) => t.role == InsertedAnswer.roleMarker),
        hasLength(1));
    // 只合成了新增那一段
    expect(tts.calls - callsAfterBake, lessThanOrEqualTo(1));

    // ⑥ 清缓存后插入不回退到整场重合成（design D4 的关键约束）
    if (await AppPaths.itMeetingListeningCacheDir.exists()) {
      await AppPaths.itMeetingListeningCacheDir.delete(recursive: true);
    }
    final before = tts.calls;
    await service.insertAnswer(
      meetingId: meeting.id,
      questionTurnIndex: 10,
      textEn: 'That is tracked in the same backlog.',
    );
    expect(tts.calls - before, lessThanOrEqualTo(1),
        reason: '清缓存后既有的 152 轮不该被重新合成');

    // ⑦ 删除回答后复原
    await service.deleteAnswer(meeting.id, answer!.id);
    index = await ClipLibrary(AppPaths.itMeetingListeningDir).loadIndex();
    final restored = index.byId(meeting.id)!;
    expect(
        restored.turns.where((t) => t.role == InsertedAnswer.roleMarker),
        hasLength(1),
        reason: '只删了一条，另一条仍在');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
