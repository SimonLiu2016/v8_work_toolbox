import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_audio_player.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_host.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_progress_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/resume_recorder.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_list_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'recording_audio_backend.dart';

/// 片段播放器的假实现（真实 AudioPlayer 在测试环境无平台实现，会挂起）。
class _FakeClipPlayer implements ListeningAudioPlayer {
  final pos = StreamController<Duration>.broadcast();
  final dur = StreamController<Duration>.broadcast();
  final done = StreamController<void>.broadcast();
  final state = StreamController<PlayerState>.broadcast();

  @override
  Stream<Duration> get onPositionChanged => pos.stream;
  @override
  Stream<Duration> get onDurationChanged => dur.stream;
  @override
  Stream<void> get onPlayerComplete => done.stream;
  @override
  Stream<PlayerState> get onPlayerStateChanged => state.stream;

  @override
  Future<void> playFile(String path) async => state.add(PlayerState.playing);
  @override
  Future<void> pause() async => state.add(PlayerState.paused);
  @override
  Future<void> resume() async => state.add(PlayerState.playing);
  @override
  Future<void> stop() async => state.add(PlayerState.stopped);
  @override
  Future<void> seek(Duration position) async => pos.add(position);
  @override
  Future<void> setPlaybackRate(double rate) async {}
  @override
  Future<void> release() async {}
}

/// ListeningHost 词汇模式路由与互斥测试。
///
/// 验证：
/// - `openMiniWindowWithVocab` 先暂停片段播放（互斥），并进入 vocab 模式；
/// - vocab 模式下指令 `toggle/previous/next/toggleContinuous/close` 分流到词汇控制器；
/// - 片段播放动作激活时先停词汇播放；
/// - `close` 在 vocab 模式停播并回退 clip 模式。
class _FakeTtsEngine implements TtsEngine {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async =>
      Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late ListeningProgressStore progressStore;
  late ListeningPlayerController clipController;
  late VocabularyStudyStore studyStore;
  late RecordingAudioBackend vocabBackend;
  late VocabularyListPlayerController vocabCtrl;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('host_vocab_test');
    progressStore = ListeningProgressStore(File('${tmp.path}/progress.json'));
    clipController = ListeningPlayerController(
      player: _FakeClipPlayer(),
      recorder: ResumeRecorder(store: progressStore),
      defaultFilePathFor: (_) => '/tmp/x.mp3',
    );
    await clipController.recorder.init();
    ListeningHost.instance.setControllerForTesting(clipController);

    studyStore = VocabularyStudyStore(
      baseDir: tmp,
      dictionaryLookup: (_) async => null,
      ttsEngine: _FakeTtsEngine(),
    );
    vocabBackend = RecordingAudioBackend();
    vocabCtrl = VocabularyListPlayerController(
      studyStore: studyStore,
      backend: vocabBackend,
    );
    ListeningHost.instance.setVocabPlayerForTesting(vocabCtrl);
  });

  tearDown(() async {
    ListeningHost.instance.setControllerForTesting(null);
    ListeningHost.instance.setVocabPlayerForTesting(null);
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('openMiniWindowWithVocab 进入 vocab 模式并载入词列表', () async {
    await ListeningHost.instance
        .openMiniWindowWithVocab(['governance', 'idempotent'], autoplay: false);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.vocab);
    expect(vocabCtrl.words, ['governance', 'idempotent']);
  });

  test('vocab 模式指令分流：toggle/next/toggleContinuous', () async {
    await ListeningHost.instance
        .openMiniWindowWithVocab(['alpha', 'beta'], autoplay: false);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.vocab);

    await ListeningHost.instance.handleMiniCommand('toggle');
    expect(vocabCtrl.isPlaying, isTrue);
    expect(vocabCtrl.currentWord, 'alpha');

    await ListeningHost.instance.handleMiniCommand('next');
    expect(vocabCtrl.currentWord, 'beta');

    await ListeningHost.instance.handleMiniCommand('toggleContinuous');
    expect(vocabCtrl.isLooping, isTrue);
  });

  test('vocab 模式 close 停播并回退 clip 模式', () async {
    await ListeningHost.instance
        .openMiniWindowWithVocab(['alpha'], autoplay: true);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.vocab);
    expect(vocabCtrl.isPlaying, isTrue);

    await ListeningHost.instance.handleMiniCommand('close');
    expect(vocabCtrl.isPlaying, isFalse);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.clip);
  });

  test('openMiniWindowWithVocab 暂停正在播放的片段（互斥）', () async {
    // 先播一个片段（filePath 走默认解析）。
    await clipController.play(
      const Clip(
        id: 'x',
        scene: MeetingScene.realMeeting,
        title: 'x',
        audioPath: 'x.mp3',
        durationMs: 100000,
        turns: [],
        source: ClipSource(
          sourceId: 'rehearsal',
          site: 'Local',
          pageUrl: '',
          column: 'Rehearsal',
        ),
      ),
      filePath: '/tmp/x.mp3',
    );
    expect(clipController.isPlaying, isTrue);

    await ListeningHost.instance
        .openMiniWindowWithVocab(['alpha'], autoplay: false);
    expect(clipController.isPlaying, isFalse);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.vocab);
  });

  test('词汇播放中从控制器启动片段 → 词汇停止（反向互斥）', () async {
    await ListeningHost.instance
        .openMiniWindowWithVocab(['alpha', 'beta'], autoplay: true);
    expect(vocabCtrl.isPlaying, isTrue);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.vocab);

    // 模拟主窗口直接调 controller.play（不经迷你窗指令/热键）。
    await clipController.play(
      const Clip(
        id: 'y',
        scene: MeetingScene.realMeeting,
        title: 'y',
        audioPath: 'y.mp3',
        durationMs: 100000,
        turns: [],
        source: ClipSource(
          sourceId: 'rehearsal',
          site: 'Local',
          pageUrl: '',
          column: 'Rehearsal',
        ),
      ),
      filePath: '/tmp/y.mp3',
    );
    // 控制器监听已把词汇停掉并回退 clip 模式。
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(vocabCtrl.isPlaying, isFalse);
    expect(ListeningHost.instance.playbackMode, MiniPlaybackMode.clip);
    expect(clipController.isPlaying, isTrue);
  });
}
