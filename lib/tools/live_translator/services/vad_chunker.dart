/// VAD + 分块器
///
/// 对连续 PCM 流做能量阈值静音检测（design D2），仅在语音段产出固定时长
/// （约 2s）、带重叠（约 0.5s）的音频块。静音段不产出，降低无效请求与成本
/// （spec: live-audio-capture / 静音检测与语音分块）。
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../models/capture_config.dart';

/// VAD + 分块器。
///
/// 输入原始 PCM 字节流，输出带时间基准的 [AudioChunk]。时间基准以第一个
/// 到达的字节为 0，暂停期间不调用（调用方控制），故时间轴天然不含暂停段。
class VadChunker {
  VadChunker(this._config);

  final CaptureConfig _config;

  final _chunkController = StreamController<AudioChunk>.broadcast();

  /// 待处理字节缓冲。
  final List<int> _buffer = [];

  /// 已处理的总字节数（用于计算时间基准）。
  int _processedBytes = 0;

  /// 当前语音段是否已开始（用于重叠与切块）。
  bool _inSpeech = false;

  /// 上一块保留的重叠字节（拼到下一块头部）。
  List<int> _carryOverlap = [];

  Stream<AudioChunk> get chunkStream => _chunkController.stream;

  /// 喂入一段原始 PCM 数据。
  void addPcm(Uint8List data) {
    _buffer.addAll(data);
    _tryEmitChunks();
  }

  /// 计算一段 PCM 的 RMS 能量。
  ///
  /// PCM 为 16-bit 有符号小端。返回 0..32768 范围的 RMS。
  static double computeRms(List<int> pcm) {
    if (pcm.length < 2) return 0;
    double sum = 0;
    var count = 0;
    for (var i = 0; i + 1 < pcm.length; i += 2) {
      final sample = (pcm[i] & 0xFF) | ((pcm[i + 1] & 0xFF) << 8);
      // 转成有符号 16-bit。
      final signed = sample >= 32768 ? sample - 65536 : sample;
      sum += signed * signed;
      count++;
    }
    if (count == 0) return 0;
    return sqrt(sum / count);
  }

  void _tryEmitChunks() {
    // 每帧 20ms 做一次 VAD 判定。
    final frameBytes = (_config.sampleRate * 0.02).round() * 2; // 16-bit
    while (_buffer.length >= frameBytes) {
      final frame = _buffer.sublist(0, frameBytes);
      _buffer.removeRange(0, frameBytes);
      final rms = computeRms(frame);
      final isSpeech = rms >= _config.energyThreshold;

      if (isSpeech && !_inSpeech) {
        _inSpeech = true;
      }

      if (_inSpeech) {
        // 语音段内累积到块长即切块。
        if (_frameAccumulator.length + frame.length >= _config.chunkBytes) {
          _emitChunk();
        }
        _frameAccumulator.addAll(frame);
      }
      // 静音且不在语音段：丢弃（不产出）。
      // 注：语音段内部的短暂静音帧也会被累积，避免切断词（由上层重叠去重兜底）。
    }
  }

  final List<int> _frameAccumulator = [];

  void _emitChunk() {
    if (_frameAccumulator.isEmpty) return;
    // 头部拼上上一块的重叠区。
    final payload = <int>[..._carryOverlap, ..._frameAccumulator];
    final startMs =
        ((_processedBytes) / (_config.sampleRate * 2) * 1000).round();

    _chunkController.add(AudioChunk(
      data: payload,
      startMs: startMs,
    ));

    // 保留尾部 overlap 作为下一块的重叠。
    final overlapLen =
        min(_config.overlapBytes, _frameAccumulator.length);
    _carryOverlap =
        _frameAccumulator.sublist(_frameAccumulator.length - overlapLen);

    _processedBytes += _frameAccumulator.length;
    _frameAccumulator.clear();
    _inSpeech = false;
  }

  /// 冲刷剩余缓冲（停止时调用，产出不足一块的尾部语音）。
  void flush() {
    if (_frameAccumulator.isNotEmpty) {
      _emitChunk();
    }
    _frameAccumulator.clear();
    _carryOverlap = [];
    _buffer.clear();
    _inSpeech = false;
  }

  /// 重置时间基准（暂停恢复时可选用；默认时间基准连续，无需重置）。
  void reset() {
    _processedBytes = 0;
    _frameAccumulator.clear();
    _carryOverlap = [];
    _buffer.clear();
    _inSpeech = false;
  }

  Future<void> dispose() async {
    await _chunkController.close();
  }
}
