import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/recording_models.dart';

/// 录音引擎抽象接口
abstract class MeetingRecordEngine {
  MeetingRecordState get state;
  Stream<MeetingRecordState> get stateStream;
  Stream<int> get elapsedMsStream;
  int get currentElapsedMs;
  String? get currentRecordingPath;

  /// 实时输入音量电平流 (0.0 ~ 1.0)
  Stream<double> get audioLevelStream;

  /// 当前瞬时电平 (0.0 ~ 1.0)
  double get currentAudioLevel;

  /// 开始录制
  Future<void> start({
    required int deviceIndex,
    required String outputPath,
  });

  /// 暂停录制
  Future<void> pause();

  /// 恢复录制
  Future<void> resume();

  /// 停止录制并完成落盘
  Future<void> stop();

  /// 枚举可用系统音频输入设备
  Future<List<RecordingAudioDevice>> listDevices();
}

/// 基于 FFmpeg avfoundation 的生产级录音引擎
class FfmpegMeetingRecordEngine implements MeetingRecordEngine {
  String? _ffmpegPath;
  Process? _process;
  MeetingRecordState _state = MeetingRecordState.idle;
  String? _currentRecordingPath;
  double _currentAudioLevel = 0.0;

  final _stateController = StreamController<MeetingRecordState>.broadcast();
  final _elapsedController = StreamController<int>.broadcast();
  final _audioLevelController = StreamController<double>.broadcast();

  StreamSubscription<String>? _stdoutSubscription;
  Timer? _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  int _accumulatedMs = 0;

  static final _rmsLevelRegex = RegExp(
    r'lavfi\.astats\.Overall\.RMS_level=(-?inf|nan|[-+]?[\d.]+)',
    caseSensitive: false,
  );

  FfmpegMeetingRecordEngine({String? ffmpegPath}) : _ffmpegPath = ffmpegPath;

  @override
  MeetingRecordState get state => _state;

  @override
  Stream<MeetingRecordState> get stateStream => _stateController.stream;

  @override
  Stream<int> get elapsedMsStream => _elapsedController.stream;

  @override
  int get currentElapsedMs => _accumulatedMs + _stopwatch.elapsedMilliseconds;

  @override
  String? get currentRecordingPath => _currentRecordingPath;

  @override
  Stream<double> get audioLevelStream => _audioLevelController.stream;

  @override
  double get currentAudioLevel => _currentAudioLevel;

  /// 解析 FFmpeg 可执行文件路径
  Future<String?> resolveFfmpeg() async {
    if (_ffmpegPath != null) return _ffmpegPath;
    for (final candidate in const [
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      'ffmpeg',
    ]) {
      try {
        final r = await Process.run(candidate, ['-version']);
        if (r.exitCode == 0) {
          _ffmpegPath = candidate;
          return candidate;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<List<RecordingAudioDevice>> listDevices() async {
    final ffmpeg = await resolveFfmpeg();
    if (ffmpeg == null) return [];

    try {
      final result = await Process.run(ffmpeg, [
        '-f', 'avfoundation',
        '-list_devices', 'true',
        '-i', '',
      ]);
      // avfoundation 设备列表输出在 stderr
      return parseDeviceList('${result.stderr}');
    } catch (_) {
      return [];
    }
  }

  /// 从 FFmpeg avfoundation 报错信息中解析设备列表
  @visibleForTesting
  static List<RecordingAudioDevice> parseDeviceList(String output) {
    final devices = <RecordingAudioDevice>[];
    final lines = output.split(RegExp(r'\r?\n'));
    bool inAudioSection = false;

    final deviceLineRe = RegExp(r'(?:\]\s+|^)\[(\d+)\]\s+(.+?)\s*$');
    final channelRe = RegExp(r'\((\d+)ch\)');

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.contains('AVFoundation audio devices:')) {
        inAudioSection = true;
        continue;
      }

      if (inAudioSection) {
        if (line.contains('AVFoundation video devices:') ||
            line.startsWith('Error opening') ||
            line.contains('[in#')) {
          break;
        }

        final m = deviceLineRe.firstMatch(line);
        if (m != null) {
          final index = int.tryParse(m.group(1)!);
          if (index != null) {
            final name = m.group(2)!.trim();
            final chMatch = channelRe.firstMatch(name);
            final channels = chMatch != null ? int.parse(chMatch.group(1)!) : 2;
            devices.add(RecordingAudioDevice(
              id: index,
              name: name,
              channels: channels,
            ));
          }
        }
      }
    }
    return devices;
  }

  @override
  Future<void> start({
    required int deviceIndex,
    required String outputPath,
  }) async {
    if (_state != MeetingRecordState.idle) {
      throw StateError('当前录音引擎处于 ${_state.name} 状态，无法开始新录音');
    }

    final ffmpeg = await resolveFfmpeg();
    if (ffmpeg == null) {
      throw StateError('未检测到 FFmpeg，请检查系统环境或安装 ffmpeg');
    }

    final targetFile = File(outputPath);
    if (!await targetFile.parent.exists()) {
      await targetFile.parent.create(recursive: true);
    }

    _currentRecordingPath = outputPath;

    final args = buildArgs(deviceIndex: deviceIndex, outputPath: outputPath);

    try {
      _process = await Process.start(ffmpeg, args);
    } catch (e) {
      _currentRecordingPath = null;
      throw StateError('启动 FFmpeg 录音进程失败: $e');
    }

    _listenStdout(_process!);

    _accumulatedMs = 0;
    _stopwatch
      ..reset()
      ..start();

    _startTicker();
    _updateState(MeetingRecordState.recording);

    // 监听意外退出
    _process!.exitCode.then((code) {
      if (_state == MeetingRecordState.recording ||
          _state == MeetingRecordState.paused) {
        debugPrint('[FfmpegMeetingRecordEngine] 进程非预期退出: $code');
        _cleanupTimer();
        _stdoutSubscription?.cancel();
        _stdoutSubscription = null;
        _updateAudioLevel(0.0);
        _updateState(MeetingRecordState.idle);
      }
    });
  }

  /// 构建用于录音的 FFmpeg 命令行参数
  @visibleForTesting
  static List<String> buildArgs({
    required int deviceIndex,
    required String outputPath,
  }) {
    return [
      '-y',
      '-f', 'avfoundation',
      '-i', ':$deviceIndex',
      '-af', 'astats=metadata=1:reset=1,ametadata=print:key=lavfi.astats.Overall.RMS_level:file=-',
      '-c:a', 'aac',
      '-b:a', '192k',
      '-ar', '44100',
      '-movflags', '+faststart',
      outputPath,
    ];
  }

  /// 解析 FFmpeg stdout 中打印的实时 RMS 电平
  @visibleForTesting
  static double? parseRmsLevelLine(String line) {
    final m = _rmsLevelRegex.firstMatch(line);
    if (m == null) return null;
    final valStr = m.group(1);
    if (valStr == null) return null;
    final lower = valStr.toLowerCase();
    if (lower == '-inf' || lower == 'nan') {
      return double.negativeInfinity;
    }
    return double.tryParse(valStr);
  }

  /// 将 RMS 电平 (dB) 归一化为 0.0 ~ 1.0 的人声感知音量幅度
  ///
  /// 引入高信噪比静音门限 (Noise Gate -31dB) 过滤环境物理底噪 (风扇、室内空气流动 -40dB ~ -32dB)。
  /// 有效人声动态区间设为 -31dB 至 -10dB，并应用非线性感知曲线 (t^0.65)，
  /// 确保不说话时绝对静止贴底 (0.0)，开口发声时灵敏爆发饱满的动态波形。
  @visibleForTesting
  static double normalizeRmsDb(double? db) {
    const minDb = -31.0;
    const maxDb = -10.0;
    if (db == null || db.isNaN || db.isInfinite || db <= minDb) {
      return 0.0;
    }
    if (db >= maxDb) {
      return 1.0;
    }
    final t = (db - minDb) / (maxDb - minDb);
    return math.pow(t.clamp(0.0, 1.0), 0.65).toDouble();
  }

  void _listenStdout(Process process) {
    _stdoutSubscription?.cancel();
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) {
            if (_state != MeetingRecordState.recording) return;
            final db = parseRmsLevelLine(line);
            if (db != null) {
              final level = normalizeRmsDb(db);
              _updateAudioLevel(level);
            }
          },
          onError: (_) {},
          cancelOnError: false,
        );
  }

  void _updateAudioLevel(double level) {
    _currentAudioLevel = level;
    if (!_audioLevelController.isClosed) {
      _audioLevelController.add(level);
    }
  }

  @override
  Future<void> pause() async {
    if (_state != MeetingRecordState.recording) return;

    final p = _process;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigstop);
      } catch (e) {
        debugPrint('[FfmpegMeetingRecordEngine] 暂停发送 sigstop 失败: $e');
      }
    }

    _accumulatedMs += _stopwatch.elapsedMilliseconds;
    _stopwatch.reset();
    _stopwatch.stop();

    _updateAudioLevel(0.0);
    _updateState(MeetingRecordState.paused);
  }

  @override
  Future<void> resume() async {
    if (_state != MeetingRecordState.paused) return;

    final p = _process;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigcont);
      } catch (e) {
        debugPrint('[FfmpegMeetingRecordEngine] 恢复发送 sigcont 失败: $e');
      }
    }

    _stopwatch
      ..reset()
      ..start();

    _updateState(MeetingRecordState.recording);
  }

  @override
  Future<void> stop() async {
    if (_state == MeetingRecordState.idle) return;

    _updateState(MeetingRecordState.stopping);
    _cleanupTimer();
    _stdoutSubscription?.cancel();
    _stdoutSubscription = null;
    _updateAudioLevel(0.0);

    final p = _process;
    if (p != null) {
      try {
        // 如果处于暂停状态，先继续以接收退出指令
        p.kill(ProcessSignal.sigcont);
      } catch (_) {}

      try {
        // 向 stdin 写入 'q\n' 促使 FFmpeg 优雅终止并写完 moov atom
        p.stdin.write('q\n');
        await p.stdin.flush();
        await p.stdin.close();
      } catch (_) {}

      try {
        await p.exitCode.timeout(const Duration(seconds: 3), onTimeout: () {
          p.kill(ProcessSignal.sigint);
          return -1;
        });
      } catch (_) {}
    }

    _process = null;
    _accumulatedMs = 0;
    _stopwatch.reset();
    _currentRecordingPath = null;
    _updateState(MeetingRecordState.idle);
  }

  void _startTicker() {
    _cleanupTimer();
    _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (_state == MeetingRecordState.recording) {
        _elapsedController.add(currentElapsedMs);
      }
    });
  }

  void _cleanupTimer() {
    _ticker?.cancel();
    _ticker = null;
    _stopwatch.stop();
  }

  void _updateState(MeetingRecordState next) {
    if (_state != next) {
      _state = next;
      _stateController.add(next);
    }
  }

  void dispose() {
    _cleanupTimer();
    _stdoutSubscription?.cancel();
    _stateController.close();
    _elapsedController.close();
    _audioLevelController.close();
  }
}
