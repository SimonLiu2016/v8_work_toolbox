import 'dart:io';

/// 录音条目数据模型
class MeetingRecordingItem {
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int durationMs;
  final int fileSizeBytes;

  const MeetingRecordingItem({
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    required this.fileSizeBytes,
  });

  String get formattedDuration {
    final d = Duration(milliseconds: durationMs);
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String get formattedSize {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) {
      return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  File get file => File(filePath);

  MeetingRecordingItem copyWith({
    String? fileName,
    String? filePath,
    DateTime? createdAt,
    int? durationMs,
    int? fileSizeBytes,
  }) =>
      MeetingRecordingItem(
        fileName: fileName ?? this.fileName,
        filePath: filePath ?? this.filePath,
        createdAt: createdAt ?? this.createdAt,
        durationMs: durationMs ?? this.durationMs,
        fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      );
}

/// 录音配置数据模型
class MeetingRecorderConfig {
  final String outputDirectory;
  final int selectedDeviceId;
  final String selectedDeviceName;
  final double playbackRate;

  const MeetingRecorderConfig({
    required this.outputDirectory,
    this.selectedDeviceId = -1,
    this.selectedDeviceName = '',
    this.playbackRate = 1.0,
  });

  MeetingRecorderConfig copyWith({
    String? outputDirectory,
    int? selectedDeviceId,
    String? selectedDeviceName,
    double? playbackRate,
  }) =>
      MeetingRecorderConfig(
        outputDirectory: outputDirectory ?? this.outputDirectory,
        selectedDeviceId: selectedDeviceId ?? this.selectedDeviceId,
        selectedDeviceName: selectedDeviceName ?? this.selectedDeviceName,
        playbackRate: playbackRate ?? this.playbackRate,
      );

  Map<String, dynamic> toJson() => {
        'outputDirectory': outputDirectory,
        'selectedDeviceId': selectedDeviceId,
        'selectedDeviceName': selectedDeviceName,
        'playbackRate': playbackRate,
      };

  factory MeetingRecorderConfig.fromJson(Map<String, dynamic> json) =>
      MeetingRecorderConfig(
        outputDirectory: json['outputDirectory'] as String? ?? '',
        selectedDeviceId: (json['selectedDeviceId'] as num?)?.toInt() ?? -1,
        selectedDeviceName: json['selectedDeviceName'] as String? ?? '',
        playbackRate: (json['playbackRate'] as num?)?.toDouble() ?? 1.0,
      );
}

/// 音频捕获输入设备模型
class RecordingAudioDevice {
  final int id;
  final String name;
  final int channels;

  const RecordingAudioDevice({
    required this.id,
    required this.name,
    this.channels = 2,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecordingAudioDevice &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}

/// 录制状态枚举
enum MeetingRecordState {
  idle,
  recording,
  paused,
  stopping,
}
