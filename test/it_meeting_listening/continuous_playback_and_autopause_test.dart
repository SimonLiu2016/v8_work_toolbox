import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_audio_player.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_progress_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/resume_recorder.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/workspace_player_bar.dart';

class _FakePlayer implements ListeningAudioPlayer {
  final StreamController<Duration> pos = StreamController<Duration>.broadcast();
  final StreamController<Duration> dur = StreamController<Duration>.broadcast();
  final StreamController<void> complete = StreamController<void>.broadcast();
  final StreamController<PlayerState> state =
      StreamController<PlayerState>.broadcast();

  Duration? lastSeek;
  int pauseCallCount = 0;
  int resumeCallCount = 0;
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
    pauseCallCount++;
    state.add(PlayerState.paused);
  }

  @override
  Future<void> resume() async {
    isPlaying = true;
    resumeCallCount++;
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
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> release() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late _FakePlayer fakePlayer;
  late ListeningProgressStore store;
  late ResumeRecorder recorder;
  late ListeningPlayerController controller;

  final clipA = Clip(
    id: 'clip-a',
    title: 'Standup Clip A',
    audioPath: 'dummy.mp3',
    scene: MeetingScene.standup,
    source: const ClipSource(
      sourceId: 'public-material',
      site: 'Local',
      pageUrl: '',
      column: '',
    ),
    durationMs: 10000,
    turns: const [
      SpeakerTurn(
        speaker: 'Alice',
        role: 'PM',
        voice: 'en-US-JennyNeural',
        rawText: 'First sentence here.',
        synthesisText: 'First sentence here.',
        startMs: 0,
        endMs: 3000,
      ),
      SpeakerTurn(
        speaker: 'Bob',
        role: 'Dev',
        voice: 'en-US-GuyNeural',
        rawText: 'Second sentence follows.',
        synthesisText: 'Second sentence follows.',
        startMs: 3000,
        endMs: 7000,
      ),
    ],
  );

  final clipB = Clip(
    id: 'clip-b',
    title: 'Retrospective Clip B',
    audioPath: 'dummy.mp3',
    scene: MeetingScene.incident,
    source: const ClipSource(
      sourceId: 'real-meeting',
      site: 'Local',
      pageUrl: '',
      column: '',
    ),
    durationMs: 12000,
    turns: const [
      SpeakerTurn(
        speaker: 'Carol',
        role: 'QA',
        voice: 'en-US-AriaNeural',
        rawText: 'Carol statement.',
        synthesisText: 'Carol statement.',
        startMs: 0,
        endMs: 4000,
      ),
    ],
  );

  setUp(() async {
    tmpDir = await Directory.systemTemp.createTemp('v8_continuous_test_');
    final dummyFile = File(p.join(tmpDir.path, 'dummy.mp3'));
    await dummyFile.writeAsBytes([0, 1, 2, 3]);

    fakePlayer = _FakePlayer();
    store = ListeningProgressStore(File(p.join(tmpDir.path, 'progress.json')));
    recorder = ResumeRecorder(store: store);
    controller = ListeningPlayerController(
      player: fakePlayer,
      recorder: recorder,
      defaultFilePathFor: (_) => dummyFile.path,
    );
    await controller.recorder.init();
  });

  tearDown(() async {
    await controller.flushProgress();
    controller.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      if (tmpDir.existsSync()) {
        await tmpDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('切换音频素材时自动清除 _autoPause 句末停顿状态，防止后续音频误暂停', () async {
    await controller.play(clipA);
    controller.setAutoPause(true);
    expect(controller.isAutoPause, isTrue);

    // 播放 clipA 第一句结束，应触发暂停
    fakePlayer.pos.add(const Duration(milliseconds: 3050));
    await pumpEventQueue();
    expect(fakePlayer.pauseCallCount, 1);

    // 切换到 clipB 播放
    await controller.play(clipB);
    expect(controller.isAutoPause, isFalse, reason: '切换素材后 autoPause 必须被自动重置为 false');

    // 播放 clipB 第一句结束，不应再次触发 pause
    fakePlayer.pos.add(const Duration(milliseconds: 4050));
    await pumpEventQueue();
    expect(fakePlayer.pauseCallCount, 1, reason: '由于 autoPause 已重置，不应在句子结尾再次强行暂停');
  });

  test('ListeningLoopMode 三态流转与单篇循环、顺序停止逻辑', () async {
    await controller.play(clipA);

    // 默认单篇播放
    expect(controller.loopMode, ListeningLoopMode.orderOnce);
    expect(controller.isContinuous, isFalse);

    // 轮转为列表连播
    controller.cycleLoopMode();
    expect(controller.loopMode, ListeningLoopMode.listLoop);
    expect(controller.isContinuous, isTrue);

    // 轮转为单篇循环
    controller.cycleLoopMode();
    expect(controller.loopMode, ListeningLoopMode.singleLoop);
    expect(controller.isContinuous, isFalse);

    // 触发完成事件：单篇循环应 seek(0) 并继续播放
    fakePlayer.complete.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(fakePlayer.lastSeek, Duration.zero);

    // 再次轮转回到单篇播放
    controller.cycleLoopMode();
    expect(controller.loopMode, ListeningLoopMode.orderOnce);

    // 单篇播放播完后停止
    fakePlayer.complete.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(controller.state, ListeningPlaybackState.stopped);
  });

  testWidgets('句级跟读模式胶囊可在畅听与逐句跟读间自由切换', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    controller.preparePaused(clipA, offsetMs: 0);
    expect(controller.isAutoPause, isFalse);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => WorkspacePlayerBar(
              player: controller,
              fallbackClip: clipA,
              transcriptOpen: false,
              onToggleTranscript: () {},
              onTogglePlay: () => controller.togglePlay(),
              onPrevious: () {},
              onNext: () {},
              onJumpToClip: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 默认展示畅听胶囊
    final toggleFinder = find.byKey(const ValueKey('player-bar-autopause-toggle'));
    expect(toggleFinder, findsOneWidget);
    expect(find.text('畅听'), findsOneWidget);

    // 点击畅听胶囊，切换为逐句跟读
    await tester.tap(toggleFinder);
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.isAutoPause, isTrue);
    final indicatorFinder = find.byKey(const ValueKey('player-bar-autopause-indicator'));
    expect(indicatorFinder, findsOneWidget);
    expect(find.text('逐句跟读'), findsOneWidget);

    // 点击逐句跟读胶囊，切换回畅听并自动恢复播放
    await tester.tap(indicatorFinder);
    await tester.pump(const Duration(milliseconds: 50));

    expect(controller.isAutoPause, isFalse);
    expect(fakePlayer.resumeCallCount, greaterThanOrEqualTo(1));
    expect(find.text('畅听'), findsOneWidget);
  });

  testWidgets('篇级播放模式三态按钮（单篇 ➔ 列表 ➔ 单曲循环）轮转触发', (tester) async {
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    controller.preparePaused(clipA, offsetMs: 0);
    expect(controller.loopMode, ListeningLoopMode.orderOnce);

    ListeningLoopMode? notifiedMode;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => WorkspacePlayerBar(
              player: controller,
              fallbackClip: clipA,
              transcriptOpen: false,
              onToggleTranscript: () {},
              onTogglePlay: () {},
              onPrevious: () {},
              onNext: () {},
              onJumpToClip: (_) {},
              onLoopModeChanged: (m) => notifiedMode = m,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final loopModeBtn = find.byKey(const ValueKey('player-bar-loop-mode-btn'));
    expect(loopModeBtn, findsOneWidget);

    // 点击第 1 次：单篇播放 ➔ 列表连播
    await tester.tap(loopModeBtn);
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.loopMode, ListeningLoopMode.listLoop);
    expect(notifiedMode, ListeningLoopMode.listLoop);

    // 点击第 2 次：列表连播 ➔ 单篇循环
    await tester.tap(loopModeBtn);
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.loopMode, ListeningLoopMode.singleLoop);
    expect(notifiedMode, ListeningLoopMode.singleLoop);

    // 点击第 3 次：单篇循环 ➔ 单篇播放
    await tester.tap(loopModeBtn);
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.loopMode, ListeningLoopMode.orderOnce);
    expect(notifiedMode, ListeningLoopMode.orderOnce);
  });
}
