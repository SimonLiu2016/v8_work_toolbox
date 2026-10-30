import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// 用**本机真实损坏的数据**验证自愈路径。
///
/// 场景：某场会议的 115 个逐组音频齐备，但整篇 mp3 从未被拼出来（历史 bug）。
/// 断言：用真实 ffmpeg 重建后 mp3 出现，且**一次 TTS 都没有调用**。
///
/// TTS 用"一调就炸"的假实现——重建若试图重合成，测试会直接失败并指出位置。
class _ExplosiveTts implements TtsEngine {
  int calls = 0;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    calls++;
    throw StateError('重建不应调用 TTS（第 $calls 次）: ${text.substring(0, text.length.clamp(0, 40))}');
  }

  @override
  Future<bool> isAvailable() async => true;
}

void main() {
  test('真实损坏数据：重建整篇音频且不重合成', () async {
    final home = Platform.environment['HOME'] ?? '';
    final realRoot = Directory(p.join(home,
        'Library/Application Support/V8WorkToolbox/it_meeting_listening'));
    final realMeetings = Directory(p.join(realRoot.path, 'real_meetings'));

    if (!realMeetings.existsSync()) {
      markTestSkipped('本机没有真实会议数据：${realMeetings.path}');
      return;
    }
    final meetingFiles = Directory(p.join(realMeetings.path, 'meetings'))
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList();
    if (meetingFiles.isEmpty) {
      markTestSkipped('没有已导入的真实会议');
      return;
    }

    // 复制到临时根目录，避免动用户的真实数据。
    final tmp = await Directory.systemTemp.createTemp('selfheal');
    AppPaths.overrideRootForTesting(tmp);
    final store = RealMeetingStore();

    var tested = 0;
    try {
      for (final f in meetingFiles) {
        final id = p.basenameWithoutExtension(f.path);
        // 只挑"逐组音频在、整篇 mp3 不在"的那种损坏状态
        final srcTurns = Directory(p.join(realMeetings.path, 'turns', id));
        if (!srcTurns.existsSync()) continue;
        final srcGroups = srcTurns
            .listSync()
            .whereType<File>()
            .where((g) => g.path.endsWith('.mp3'))
            .toList();
        if (srcGroups.isEmpty) continue;
        final srcMp3 = File(p.join(realMeetings.path, 'audio', '$id.mp3'));
        if (srcMp3.existsSync()) continue;

        // 复制原稿、状态与逐组音频
        await Directory(p.join(tmp.path, 'it_meeting_listening/real_meetings/meetings'))
            .create(recursive: true);
        await f.copy(p.join(tmp.path,
            'it_meeting_listening/real_meetings/meetings/${p.basename(f.path)}'));
        final srcState =
            File(p.join(realMeetings.path, 'audio', '$id.json'));
        if (srcState.existsSync()) {
          final dst = Directory(p.join(tmp.path,
              'it_meeting_listening/real_meetings/audio'));
          await dst.create(recursive: true);
          await srcState.copy(p.join(dst.path, '$id.json'));
        }
        final dstTurns = Directory(p.join(
            tmp.path, 'it_meeting_listening/real_meetings/turns/$id'));
        await dstTurns.create(recursive: true);
        for (final g in srcGroups) {
          await g.copy(p.join(dstTurns.path, p.basename(g.path)));
        }

        final meeting = (await store.loadMeeting(id))!;
        final tts = _ExplosiveTts();
        final baker = RealMeetingBaker(
          engine: tts,
          store: store,
          audio: FfmpegAudioToolkit(),
        );

        final result = await baker.bake(
          meeting,
          // 说话人设定为空 → 走默认显示名与散列音色；重建不关心具体是谁
          speakers: const {},
        );

        final mp3 = File(p.join(
            tmp.path, 'it_meeting_listening/real_meetings/audio/$id.mp3'));
        expect(mp3.existsSync(), isTrue,
            reason: '重建后整篇音频必须真的落盘');
        expect(mp3.lengthSync(), greaterThan(1000),
            reason: '整篇音频不该是空文件');
        expect(result.hasPlayableAudio, isTrue);
        expect(tts.calls, 0,
            reason: '115 个逐组音频都在，重建不该重新合成任何一组');

        tested++;
      }
    } finally {
      AppPaths.resetForTesting();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    }

    if (tested == 0) {
      markTestSkipped('本机没有处于"逐组齐全但整篇缺失"状态的会议');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
