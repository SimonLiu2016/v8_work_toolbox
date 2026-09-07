import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'private_storage_manager.dart';
import 'ytdlp_video_parser.dart';

/// 缩略图下载与本地视频帧截图提取管理器
class ThumbnailManager {
  ThumbnailManager._();
  static final ThumbnailManager instance = ThumbnailManager._();

  final Map<String, String> _cachedPaths = {};

  /// 获取或生成本地缩略图路径（在线图片下载至本地隐私目录，或从本地视频截图）
  Future<String?> getOrCreateThumbnail(
    String urlOrPath, {
    String? remoteThumbnailUrl,
  }) async {
    if (urlOrPath.trim().isEmpty) return null;

    final cached = _cachedPaths[urlOrPath];
    if (cached != null && File(cached).existsSync()) {
      return cached;
    }

    final hash = getThumbnailFileName(urlOrPath);
    final targetFile = File(p.join(PrivateStorageManager.instance.thumbnailsDir.path, hash));

    if (targetFile.existsSync() && targetFile.lengthSync() > 100) {
      _cachedPaths[urlOrPath] = targetFile.path;
      return targetFile.path;
    }

    // 1. 若提供了远程在线封面 URL，优先下载落盘
    final posterUrl = remoteThumbnailUrl ?? (urlOrPath.startsWith('http') ? null : null);
    if (posterUrl != null && (posterUrl.startsWith('http://') || posterUrl.startsWith('https://'))) {
      try {
        final res = await http.get(Uri.parse(posterUrl)).timeout(const Duration(seconds: 15));
        if (res.statusCode == 200 && res.bodyBytes.length > 200) {
          await targetFile.writeAsBytes(res.bodyBytes, flush: true);
          _cachedPaths[urlOrPath] = targetFile.path;
          return targetFile.path;
        }
      } catch (e) {
        debugPrint('下载远程视频封面失败: $e');
      }
    }

    // 2. 若为本地视频文件，使用 ffmpeg 截取第 2 秒画面作为高清缩略图
    final isOnline = urlOrPath.startsWith('http://') || urlOrPath.startsWith('https://');
    if (!isOnline && File(urlOrPath).existsSync()) {
      final ok = await captureVideoFrame(urlOrPath, targetFile.path);
      if (ok && targetFile.existsSync()) {
        _cachedPaths[urlOrPath] = targetFile.path;
        return targetFile.path;
      }
    }

    return null;
  }

  /// 计算指定媒体链接或本地路径对应的缩略图文件名
  static String getThumbnailFileName(String urlOrPath) {
    final hash = md5.convert(utf8.encode(urlOrPath)).toString().substring(0, 16);
    return 'thumb_$hash.jpg';
  }

  /// 构建 ffmpeg 截图参数列表
  static List<String> buildFfmpegArgs(String videoPath, String outImagePath, {int atSecond = 2}) {
    final timeStr = '00:00:0${atSecond.clamp(0, 9)}';
    return [
      '-y',
      '-ss', timeStr,
      '-i', videoPath,
      '-vframes', '1',
      '-q:v', '2',
      '-f', 'image2',
      outImagePath,
    ];
  }

  /// 构建 ffmpeg 兜底截图参数列表 (0.5秒)
  static List<String> buildFallbackFfmpegArgs(String videoPath, String outImagePath) {
    return [
      '-y',
      '-ss', '00:00:00.5',
      '-i', videoPath,
      '-vframes', '1',
      '-q:v', '2',
      '-f', 'image2',
      outImagePath,
    ];
  }

  /// 使用 ffmpeg 毫秒级提取视频关键帧截图
  Future<bool> captureVideoFrame(String videoPath, String outImagePath, {int atSecond = 2}) async {
    final ffmpeg = await YtdlpVideoParser.instance.resolveFfmpegPath();
    if (ffmpeg == null) return false;

    final parentDir = File(outImagePath).parent;
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final args = buildFfmpegArgs(videoPath, outImagePath, atSecond: atSecond);

    try {
      final res = await Process.run(ffmpeg, args).timeout(const Duration(seconds: 5));
      if (res.exitCode == 0 && File(outImagePath).existsSync()) {
        return true;
      }
    } catch (_) {}

    // 兜底：若视频较短，从 0.5 秒位置截取
    try {
      final fallbackArgs = buildFallbackFfmpegArgs(videoPath, outImagePath);
      final res = await Process.run(ffmpeg, fallbackArgs).timeout(const Duration(seconds: 5));
      return res.exitCode == 0 && File(outImagePath).existsSync();
    } catch (_) {
      return false;
    }
  }
}
