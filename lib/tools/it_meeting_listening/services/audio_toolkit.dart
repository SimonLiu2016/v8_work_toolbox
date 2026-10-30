/// 音频处理工具（拼接 / 时长探测 / 静音占位）。
///
/// **为什么要抽接口**：整篇重建的核心逻辑是"按顺序拼文件 → 逐段探时长 →
/// 累加出每轮时间戳"。这段逻辑的正确性（插入后时间戳整体后移、删除后复原）
/// 是本功能最容易出错的地方，但它依赖 ffmpeg 这个外部进程——不抽出来就只能
/// 靠真实合成几十轮来验，慢且不稳定。
///
/// 抽成接口后，测试注入一个按"字节数 ↔ 时长"推算的假实现，时间戳逻辑就能
/// 被精确断言；生产实现仍是原来的 ffmpeg 调用。
library;

import 'dart:io';

/// 音频工具接口。
///
/// **刻意没有 `isAvailable`**：曾经有过一个同步布尔属性表示"ffmpeg 是否可用"，
/// 而它背后是惰性解析的路径——结果是调用点看到 `false` 就跳过拼接，而"解析
/// ffmpeg 路径"这件事本身恰恰只在拼接里发生，形成自锁，整篇音频永远拼不出来。
/// 能力查询在这里没有价值：拼接失败时 [concat] 会自己抛错，调用点需要的是
/// "失败就失败"，不是事先问一句再决定要不要做。
abstract class AudioToolkit {
  /// 按顺序拼接为一个文件。
  Future<void> concat(List<String> files, String outputPath);

  /// 探测文件时长（毫秒）。
  Future<int> probeDurationMs(String filePath);

  /// 写一段静音（失败轮次的时间轴占位）。
  Future<void> writeSilence(String path, int ms);
}

/// 生产实现：调 ffmpeg / ffprobe。
class FfmpegAudioToolkit implements AudioToolkit {
  String? _ffmpegPath;
  String? _ffprobePath;

  /// 预热（只探测一次）。
  Future<String?> resolveFfmpeg() async {
    if (_ffmpegPath != null) return _ffmpegPath;
    for (final c in const ['/usr/local/bin/ffmpeg', '/opt/homebrew/bin/ffmpeg', 'ffmpeg']) {
      try {
        final r = await Process.run(c, ['-version']);
        if (r.exitCode == 0) {
          _ffmpegPath = c;
          return c;
        }
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _resolveFfprobe() async {
    if (_ffprobePath != null) return _ffprobePath;
    for (final c in const ['/usr/local/bin/ffprobe', '/opt/homebrew/bin/ffprobe', 'ffprobe']) {
      try {
        final r = await Process.run(c, ['-version']);
        if (r.exitCode == 0) {
          _ffprobePath = c;
          return c;
        }
      } catch (_) {}
    }
    return null;
  }

  @override
  Future<void> concat(List<String> files, String outputPath) async {
    final ffmpeg = await resolveFfmpeg();
    if (ffmpeg == null) {
      throw StateError('未检测到 ffmpeg，无法拼接音频');
    }
    final listFile = File('$outputPath.concat.txt');
    await listFile.writeAsString(
        files.map((f) => "file '${_escape(f)}'").join('\n'));
    try {
      final r = await Process.run(ffmpeg, [
        '-y', '-loglevel', 'error',
        '-f', 'concat', '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        outputPath,
      ]);
      if (r.exitCode != 0) {
        throw StateError('ffmpeg 拼接失败: ${r.stderr}');
      }
    } finally {
      if (await listFile.exists()) await listFile.delete();
    }
  }

  @override
  Future<int> probeDurationMs(String filePath) async {
    final probe = await _resolveFfprobe();
    if (probe != null) {
      final r = await Process.run(probe, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'csv=p=0',
        filePath,
      ]);
      final value = double.tryParse(r.stdout.toString().trim());
      if (value != null && value > 0) return (value * 1000).round();
    }
    // ffprobe 缺失时按 128kbps 从字节数估算：定位有小偏差，但不会崩。
    final file = File(filePath);
    if (await file.exists()) {
      final bytes = await file.length();
      return ((bytes * 8 / 128000) * 1000).round();
    }
    return 0;
  }

  @override
  Future<void> writeSilence(String path, int ms) async {
    final ffmpeg = await resolveFfmpeg();
    if (ffmpeg != null) {
      final r = await Process.run(ffmpeg, [
        '-y', '-loglevel', 'error',
        '-f', 'lavfi',
        '-i', 'anullsrc=r=24000:cl=mono',
        '-t', '${ms / 1000}',
        '-q:a', '9',
        path,
      ]);
      if (r.exitCode == 0) return;
    }
    // 没有 ffmpeg：写空文件。时长会被估成接近 0，定位有偏差但流程不中断。
    await File(path).writeAsBytes(const [], flush: true);
  }

  static String _escape(String path) =>
      path.replaceAll("'", r"'\''").replaceAll('\n', '');
}

/// 逐轮音频的命名工具（集中一处，避免拼错文件名）。
String groupAudioFileName(int groupIndex) => 'g$groupIndex.mp3';
