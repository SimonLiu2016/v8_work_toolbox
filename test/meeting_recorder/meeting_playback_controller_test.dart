import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_playback_controller.dart';

class _FakeMeetingAudioPlayer implements MeetingAudioPlayer {
  final posController = StreamController<Duration>.broadcast();
  final durController = StreamController<Duration>.broadcast();
  final completeController = StreamController<void>.broadcast();
  final stateController = StreamController<PlayerState>.broadcast();

  String? playedPath;
  Duration? seekPos;
  double rate = 1.0;
  bool isStopped = false;
  bool isPaused = false;
  bool isReleased = false;

  @override
  Stream<Duration> get onPositionChanged => posController.stream;

  @override
  Stream<Duration> get onDurationChanged => durController.stream;

  @override
  Stream<void> get onPlayerComplete => completeController.stream;

  @override
  Stream<PlayerState> get onPlayerStateChanged => stateController.stream;

  @override
  Future<void> playFile(String path) async {
    playedPath = path;
    isStopped = false;
    isPaused = false;
    stateController.add(PlayerState.playing);
  }

  @override
  Future<void> pause() async {
    isPaused = true;
    stateController.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    isPaused = false;
    stateController.add(PlayerState.playing);
  }

  @override
  Future<void> stop() async {
    isStopped = true;
    stateController.add(PlayerState.stopped);
  }

  @override
  Future<void> seek(Duration position) async {
    seekPos = position;
  }

  @override
  Future<void> setPlaybackRate(double r) async {
    rate = r;
  }

  @override
  Future<void> release() async {
    isReleased = true;
  }
}

void main() {
  late _FakeMeetingAudioPlayer fakePlayer;
  late MeetingPlaybackController controller;

  setUp(() {
    fakePlayer = _FakeMeetingAudioPlayer();
    controller = MeetingPlaybackController(player: fakePlayer);
  });

  tearDown(() {
    controller.dispose();
  });

  test('播放、暂停、继续与停止状态流转', () async {
    expect(controller.isPlaying, isFalse);
    expect(controller.currentPlayingPath, isNull);

    await controller.play('/tmp/test_rec.m4a', fallbackDurationMs: 60000);
    expect(controller.isPlaying, isTrue);
    expect(controller.currentPlayingPath, '/tmp/test_rec.m4a');
    expect(controller.duration.inMilliseconds, 60000);
    expect(fakePlayer.playedPath, '/tmp/test_rec.m4a');

    await controller.pause();
    expect(controller.isPlaying, isFalse);

    await controller.resume();
    expect(controller.isPlaying, isTrue);

    await controller.stop();
    expect(controller.isPlaying, isFalse);
    expect(controller.currentPlayingPath, isNull);
  });

  test('togglePlay 在同文件下切换暂停/播放，不同文件下切歌', () async {
    await controller.togglePlay('/tmp/a.m4a');
    expect(controller.currentPlayingPath, '/tmp/a.m4a');
    expect(controller.isPlaying, isTrue);

    // 再次点击同一文件 → 暂停
    await controller.togglePlay('/tmp/a.m4a');
    expect(controller.isPlaying, isFalse);
    expect(fakePlayer.isPaused, isTrue);

    // 点击不同文件 → 播放新文件
    await controller.togglePlay('/tmp/b.m4a');
    expect(controller.currentPlayingPath, '/tmp/b.m4a');
    expect(controller.isPlaying, isTrue);
  });

  test('进度与播放倍速变更能触发通知', () async {
    await controller.play('/tmp/a.m4a');

    fakePlayer.posController.add(const Duration(seconds: 15));
    fakePlayer.durController.add(const Duration(seconds: 45));
    await pumpEventQueue();

    expect(controller.position.inSeconds, 15);
    expect(controller.duration.inSeconds, 45);

    await controller.setPlaybackRate(1.5);
    expect(controller.playbackRate, 1.5);
    expect(fakePlayer.rate, 1.5);

    await controller.seek(const Duration(seconds: 30));
    expect(controller.position.inSeconds, 30);
    expect(fakePlayer.seekPos?.inSeconds, 30);
  });

  test('播放完成事件自动重置播放状态', () async {
    await controller.play('/tmp/a.m4a');
    expect(controller.isPlaying, isTrue);

    fakePlayer.completeController.add(null);
    await pumpEventQueue();

    expect(controller.isPlaying, isFalse);
    expect(controller.position, Duration.zero);
  });
}
