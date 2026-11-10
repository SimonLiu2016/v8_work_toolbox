import 'dart:io';
import 'package:path/path.dart' as p;
import '../../it_meeting_listening/services/audio_toolkit.dart';
import '../models/recording_models.dart';

/// 录音目录扫描与文件管理服务
class RecordingFileScanner {
  final AudioToolkit _audioToolkit;

  RecordingFileScanner({AudioToolkit? audioToolkit})
      : _audioToolkit = audioToolkit ?? FfmpegAudioToolkit();

  static const supportedExtensions = {'.m4a', '.mp3', '.wav', '.aac'};

  /// 扫描指定目录下的录音文件，并按修改/创建时间倒序排列
  Future<List<MeetingRecordingItem>> scanDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final items = <MeetingRecordingItem>[];
    try {
      final entries = await dir.list().toList();
      for (final entry in entries) {
        if (entry is File) {
          final ext = p.extension(entry.path).toLowerCase();
          if (supportedExtensions.contains(ext)) {
            final stat = await entry.stat();
            if (stat.size <= 0) continue;

            var durationMs = 0;
            try {
              durationMs = await _audioToolkit.probeDurationMs(entry.path);
            } catch (_) {}

            items.add(MeetingRecordingItem(
              fileName: p.basename(entry.path),
              filePath: entry.path,
              createdAt: stat.modified,
              durationMs: durationMs,
              fileSizeBytes: stat.size,
            ));
          }
        }
      }
    } catch (_) {}

    // 按创建/修改时间从新到旧排序
    items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items;
  }

  /// 删除单个录音文件
  Future<bool> deleteRecording(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
        return true;
      } catch (_) {}
    }
    return false;
  }

  /// 重命名录音文件（保持原有扩展名不变）
  Future<MeetingRecordingItem?> renameRecording(
    String oldFilePath,
    String newBaseName,
  ) async {
    final file = File(oldFilePath);
    if (!await file.exists()) return null;

    final dir = file.parent.path;
    final ext = p.extension(oldFilePath);
    final sanitizedName = newBaseName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final newPath = p.join(dir, '$sanitizedName$ext');

    if (newPath == oldFilePath) return null;

    try {
      final renamed = await file.rename(newPath);
      final stat = await renamed.stat();
      var durationMs = 0;
      try {
        durationMs = await _audioToolkit.probeDurationMs(newPath);
      } catch (_) {}

      return MeetingRecordingItem(
        fileName: p.basename(newPath),
        filePath: newPath,
        createdAt: stat.modified,
        durationMs: durationMs,
        fileSizeBytes: stat.size,
      );
    } catch (_) {
      return null;
    }
  }
}
