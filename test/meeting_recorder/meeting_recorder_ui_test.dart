import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/models/recording_models.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_playback_controller.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_record_engine.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_recorder_store.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/recording_file_scanner.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/ui/live_waveform_meter.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/ui/meeting_recorder_page.dart';

class _MockEngine implements MeetingRecordEngine {
  MeetingRecordState _state = MeetingRecordState.idle;
  final _stateController = StreamController<MeetingRecordState>.broadcast();
  final _elapsedController = StreamController<int>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();
  int _currentElapsed = 0;
  double _currentAudioLevel = 0.0;
  String? _path;

  @override
  MeetingRecordState get state => _state;

  @override
  Stream<MeetingRecordState> get stateStream => _stateController.stream;

  @override
  Stream<int> get elapsedMsStream => _elapsedController.stream;

  @override
  int get currentElapsedMs => _currentElapsed;

  @override
  String? get currentRecordingPath => _path;

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  double get currentAudioLevel => _currentAudioLevel;

  void emitAudioLevel(double level) {
    _currentAudioLevel = level;
    _audioLevelController.add(level);
  }

  @override
  Future<List<RecordingAudioDevice>> listDevices() async {
    return const [
      RecordingAudioDevice(id: 0, name: 'MacBook Pro 麦克风 (1ch)', channels: 1),
      RecordingAudioDevice(id: 1, name: 'BlackHole 2ch (2ch)', channels: 2),
    ];
  }

  @override
  Future<void> start({required int deviceIndex, required String outputPath}) async {
    _state = MeetingRecordState.recording;
    _path = outputPath;
    _stateController.add(_state);
  }

  @override
  Future<void> pause() async {
    _state = MeetingRecordState.paused;
    _stateController.add(_state);
  }

  @override
  Future<void> resume() async {
    _state = MeetingRecordState.recording;
    _stateController.add(_state);
  }

  @override
  Future<void> stop() async {
    _state = MeetingRecordState.idle;
    _path = null;
    _stateController.add(_state);
  }
}

class _MockStore extends MeetingRecorderStore {
  MeetingRecorderConfig _mockConfig = const MeetingRecorderConfig(
    outputDirectory: '/mock/recordings',
    selectedDeviceId: 0,
    selectedDeviceName: 'MacBook Pro 麦克风 (1ch)',
  );

  @override
  Future<MeetingRecorderConfig> loadConfig() async => _mockConfig;

  @override
  Future<void> saveConfig(MeetingRecorderConfig config) async {
    _mockConfig = config;
  }
}

class _MockScanner extends RecordingFileScanner {
  final List<MeetingRecordingItem> mockItems;

  _MockScanner(this.mockItems);

  @override
  Future<List<MeetingRecordingItem>> scanDirectory(String dirPath) async {
    return mockItems;
  }

  @override
  Future<bool> deleteRecording(String filePath) async => true;
}

class _FakeMeetingAudioPlayer implements MeetingAudioPlayer {
  final posController = StreamController<Duration>.broadcast();
  final durController = StreamController<Duration>.broadcast();
  final completeController = StreamController<void>.broadcast();
  final stateController = StreamController<PlayerState>.broadcast();

  @override
  Stream<Duration> get onPositionChanged => posController.stream;

  @override
  Stream<Duration> get onDurationChanged => durController.stream;

  @override
  Stream<void> get onPlayerComplete => completeController.stream;

  @override
  Stream<PlayerState> get onPlayerStateChanged => stateController.stream;

  @override
  Future<void> playFile(String path) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> setPlaybackRate(double rate) async {}

  @override
  Future<void> release() async {}
}

void main() {
  testWidgets('MeetingRecorderPage 完整渲染与基础交互', (tester) async {
    final engine = _MockEngine();
    final store = _MockStore();
    final mockRecordings = [
      MeetingRecordingItem(
        fileName: '周例会_20261105.m4a',
        filePath: '/mock/recordings/周例会_20261105.m4a',
        createdAt: DateTime(2026, 11, 5, 10, 30),
        durationMs: 125000,
        fileSizeBytes: 2048576,
      ),
    ];
    final scanner = _MockScanner(mockRecordings);
    final playback = MeetingPlaybackController(player: _FakeMeetingAudioPlayer());

    await tester.pumpWidget(
      MaterialApp(
        home: MeetingRecorderPage(
          engine: engine,
          store: store,
          scanner: scanner,
          playbackController: playback,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 标题
    expect(find.text('会议录音'), findsOneWidget);
    expect(find.text('00:00:00'), findsOneWidget);
    expect(find.text('开始录音'), findsOneWidget);

    // 设备下拉匹配与内录声卡标签
    expect(find.text('MacBook Pro 麦克风 (1ch)'), findsOneWidget);

    // 历史列表
    expect(find.text('历史录音 (1)'), findsOneWidget);
    expect(find.text('周例会_20261105.m4a'), findsOneWidget);

    // 点击开始录音 → 状态变更为录制中
    await tester.tap(find.text('开始录音'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('正在录音中...'), findsOneWidget);
    expect(find.text('停止并保存'), findsOneWidget);
    expect(find.text('暂停'), findsOneWidget);

    // 点击暂停
    await tester.tap(find.text('暂停'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('已暂停'), findsOneWidget);
    expect(find.text('继续录音'), findsOneWidget);

    // 验证实时动态声波组件存在
    expect(find.byType(LiveWaveformMeter), findsOneWidget);

    // 点击停止
    await tester.tap(find.text('停止保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('就绪'), findsOneWidget);
    expect(find.text('开始录音'), findsOneWidget);
  });

  testWidgets('LiveWaveformMeter 在自适应宽度与不同电平状态下的表现', (tester) async {
    // 谐波权重算法测试
    expect(LiveWaveformMeter.calculateHarmonicWeight(0, 40), greaterThanOrEqualTo(0.2));
    expect(LiveWaveformMeter.calculateHarmonicWeight(20, 40), closeTo(1.0, 0.15));

    // 1. 未录音状态（自适应宽度 320px）：自动产生 40 根贴底柱条
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: LiveWaveformMeter(
                level: 0.8,
                isRecording: false,
                height: 64.0,
                barWidth: 4.0,
                barSpacing: 4.0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final containersIdle = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(LiveWaveformMeter),
        matching: find.byType(AnimatedContainer),
      ),
    );
    // 320 / (4 + 4) = 40
    expect(containersIdle.length, 40);

    // 2. 录音中但处于静音/底噪状态 (level: 0.0)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: LiveWaveformMeter(
                level: 0.0,
                isRecording: true,
                height: 64.0,
                barWidth: 4.0,
                barSpacing: 4.0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final containersSilent = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(LiveWaveformMeter),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(containersSilent.length, 40);
    // 静音/底噪时所有柱条严格贴底 3.0，无伪动画起伏
    for (final c in containersSilent) {
      expect(c.constraints?.maxHeight ?? 3.0, 3.0);
    }

    // 3. 录音中且有声音输入状态 (全屏自适应 400px，高度 64.0)
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: LiveWaveformMeter(
                level: 0.85,
                isRecording: true,
                height: 64.0,
                barWidth: 4.0,
                barSpacing: 4.0,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final containersActive = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(LiveWaveformMeter),
        matching: find.byType(AnimatedContainer),
      ),
    );
    // 400 / 8 = 50 根柱条
    expect(containersActive.length, 50);

    // 中心附近柱条高度应充分拉伸，明显高于静音基线 (3px)
    final centerContainer = containersActive.elementAt(25);
    expect(centerContainer.constraints?.maxHeight ?? 64.0, greaterThan(35.0));
  });
}
