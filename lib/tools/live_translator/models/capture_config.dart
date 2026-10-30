/// 捕获配置模型
///
/// 内录捕获的可调参数：选定设备、采样率、块长、重叠、能量阈值（design D2）。
/// 阈值默认值待实测标定（design Open Question），故暴露为可调项。
library;

/// 音频捕获设备信息。
class AudioCaptureDevice {
  AudioCaptureDevice({
    required this.name,
    required this.channels,
    required this.deviceIndex,
  });

  /// 设备名（如 "Soundflower (2ch)"）。
  final String name;

  /// 通道数。
  final int channels;

  /// avfoundation 设备索引（传给 FFmpeg `:index`）。
  final int deviceIndex;
}

/// 捕获配置。
class CaptureConfig {
  CaptureConfig({
    this.deviceName = 'Soundflower (2ch)',
    this.deviceIndex = -1,
    this.deviceChannels = 2,
    this.sampleRate = 16000,
    this.channels = 1,
    this.bitsPerSample = 16,
    this.chunkSeconds = 2,
    this.overlapSeconds = 0.5,
    this.energyThreshold = 50.0,
  });

  /// 选定设备名。
  String deviceName;

  /// 选定设备的 avfoundation 索引；-1 表示未解析。
  int deviceIndex;

  /// 设备硬件通道数（如 2 或 64）。
  int deviceChannels;

  /// 采样率（Hz）。
  int sampleRate;

  /// 通道数（内录固定单声道）。
  int channels;

  /// 位深。
  int bitsPerSample;

  /// 语音块时长（秒）。
  double chunkSeconds;

  /// 相邻块重叠时长（秒）。
  double overlapSeconds;

  /// VAD 能量阈值（RMS）。待实测标定，暴露为可调。
  double energyThreshold;

  /// 每块采样点数（16-bit 单声道 = 2 字节/采样）。
  int get chunkSamples => (sampleRate * chunkSeconds).round();

  /// 每块字节数。
  int get chunkBytes => chunkSamples * 2;

  /// 重叠区采样点数。
  int get overlapSamples => (sampleRate * overlapSeconds).round();

  /// 重叠区字节数。
  int get overlapBytes => overlapSamples * 2;

  CaptureConfig copyWith({
    String? deviceName,
    int? deviceIndex,
    int? deviceChannels,
    double? chunkSeconds,
    double? overlapSeconds,
    double? energyThreshold,
  }) {
    return CaptureConfig(
      deviceName: deviceName ?? this.deviceName,
      deviceIndex: deviceIndex ?? this.deviceIndex,
      deviceChannels: deviceChannels ?? this.deviceChannels,
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      chunkSeconds: chunkSeconds ?? this.chunkSeconds,
      overlapSeconds: overlapSeconds ?? this.overlapSeconds,
      energyThreshold: energyThreshold ?? this.energyThreshold,
    );
  }
}

/// 一个带时间基准的音频块。
class AudioChunk {
  AudioChunk({
    required this.data,
    required this.startMs,
  });

  /// PCM 16-bit 单声道数据。
  final List<int> data;

  /// 该块在捕获时间基准中的起始毫秒（用于去重与时间轴）。
  final int startMs;
}
