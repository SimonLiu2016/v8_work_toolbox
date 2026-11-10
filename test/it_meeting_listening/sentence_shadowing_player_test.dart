import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_audio_player.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_progress_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/resume_recorder.dart';

class _FakePlayer implements ListeningAudioPlayer {
  final StreamController<Duration> pos = StreamController<Duration>.broadcast();
  final StreamController<Duration> dur = StreamController<Duration>.broadcast();
  final StreamController<void> complete = StreamController<void>.broadcast();
  final StreamController<PlayerState> state =
      StreamController<PlayerState>.broadcast();

  Duration? lastSeek;
  double? lastRate;
  bool isPlaying = false;

  @override
  Stream<Duration> get onPositionChanged => pos.stream;
  @override
  Stream<Duration> get onDurationChanged => dur.stream;
  @override
  Stream<void> get onPlayerComplete => complete.stream;
  @override
  Stream<PlayerState> get onPlayerStateChanged => state.stream;

  @override
  Future<void> playFile(String path) async {
    isPlaying = true;
    state.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    isPlaying = false;
    state.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    state.add(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    isPlaying = false;
    state.add(PlayerState.stopped);
  }

  @override
  Future<void> seek(Duration position) async {
    lastSeek = position;
    pos.add(position);
  }

  @override
  Future<void> setPlaybackRate(double rate) async {
    lastRate = rate;
  }

  @override
  Future<void> release() async {}
}

Clip _createTestClip() {
  return const Clip(
    id: 'shadowing_test_clip',
    scene: MeetingScene.realMeeting,
    title: 'Shadowing Test Meeting',
    audioPath: 'test.mp3',
    durationMs: 30000,
    turns: [
      SpeakerTurn(
        speaker: 'Alice',
        role: 'PM',
        rawText: 'Welcome everyone to our sprint review.',
        synthesisText: 'Welcome everyone to our sprint review.',
        voice: 'en-US-JennyNeural',
        startMs: 0,
        endMs: 5000,
      ),
      SpeakerTurn(
        speaker: 'Bob',
        role: 'Dev',
        rawText: 'I have completed the backend migration and database index optimizations.',
        synthesisText: 'I have completed the backend migration and database index optimizations.',
        voice: 'en-US-GuyNeural',
        startMs: 5000,
        endMs: 12000,
      ),
      SpeakerTurn(
        speaker: 'Charlie',
        role: 'QA',
        rawText: 'That sounds great, let us look at the monitoring dashboard.',
        synthesisText: 'That sounds great, let us look at the monitoring dashboard.',
        voice: 'en-US-AriaNeural',
        startMs: 12000,
        endMs: 20000,
      ),
    ],
    source: ClipSource(
      sourceId: 'real-meeting',
      site: 'Local',
      pageUrl: '',
      column: '',
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ListeningProgressStore store;
  late _FakePlayer fakePlayer;
  late ListeningPlayerController controller;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('sentence_shadowing_test');
    store = ListeningProgressStore(File(p.join(tmp.path, 'progress.json')));
    fakePlayer = _FakePlayer();
    controller = ListeningPlayerController(
      player: fakePlayer,
      recorder: ResumeRecorder(store: store),
    );
    await controller.recorder.init();
  });

  tearDown(() async {
    await controller.flushProgress();
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    try {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    } catch (_) {}
  });

  group('ListeningPlayerController - 影子跟读与变速', () {
    test('toggleQuickSpeed: 1.0x ↔ 0.8x 瞬时切换，并自适应记忆自定义速度', () async {
      final clip = _createTestClip();
      await controller.play(clip, filePath: '/tmp/test.mp3');

      expect(controller.speed, 1.0);
      expect(controller.lastCustomSpeed, 0.8);

      // 切换到慢速
      await controller.toggleQuickSpeed();
      expect(controller.speed, 0.8);
      expect(fakePlayer.lastRate, 0.8);

      // 再次切换回到 1.0x
      await controller.toggleQuickSpeed();
      expect(controller.speed, 1.0);
      expect(fakePlayer.lastRate, 1.0);

      // 用户主动设为 0.75x
      await controller.setSpeed(0.75);
      expect(controller.speed, 0.75);
      expect(controller.lastCustomSpeed, 0.75);

      // 此时快速切换应回 1.0x，再按应回 0.75x
      await controller.toggleQuickSpeed();
      expect(controller.speed, 1.0);
      await controller.toggleQuickSpeed();
      expect(controller.speed, 0.75);
    });

    test('单句 A-B 循环：设置循环轮次，播放超出边界时自动 seek 回开头', () async {
      final clip = _createTestClip();
      await controller.play(clip, filePath: '/tmp/test.mp3');

      // 开启第 1 轮（Bob: 5000ms - 12000ms）单句循环
      controller.setLoopingTurn(1);
      expect(controller.isLoopingTurn, isTrue);
      expect(controller.loopingTurnIndex, 1);
      // 由于之前在 0ms，设置后自动定位到 turn 1 开头 5000ms
      expect(fakePlayer.lastSeek, const Duration(milliseconds: 5000));

      // 模拟音频播放流推进到 11000ms（未超出）
      fakePlayer.pos.add(const Duration(milliseconds: 11000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(controller.position.inMilliseconds, 11000);

      // 推进到 12050ms（已到达 turn 1 结束边界），控制器应自动循环回 5000ms
      fakePlayer.pos.add(const Duration(milliseconds: 12050));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(fakePlayer.lastSeek, const Duration(milliseconds: 5000));

      // 再次点击同一下标取消循环
      controller.toggleLoopingTurn(1);
      expect(controller.isLoopingTurn, isFalse);
      expect(controller.loopingTurnIndex, isNull);
    });

    test('句间自动停顿（Auto-Pause）：句末自动暂停，恢复后定位下一句', () async {
      final clip = _createTestClip();
      await controller.play(clip, filePath: '/tmp/test.mp3');

      controller.setAutoPause(true);
      expect(controller.isAutoPause, isTrue);

      // 当前在第 0 轮（0ms - 5000ms），播放推进到 5100ms
      fakePlayer.pos.add(const Duration(milliseconds: 5100));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // 应当自动暂停
      expect(controller.state, ListeningPlaybackState.paused);

      // 用户按 resume 后，自动定位至第 1 轮起点 5000ms
      await controller.resume();
      expect(controller.state, ListeningPlaybackState.playing);
      expect(fakePlayer.lastSeek, const Duration(milliseconds: 5000));
    });
  });
}
