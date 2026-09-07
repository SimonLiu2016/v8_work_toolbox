import 'dart:convert';
import 'dart:io';

/// 视频画质与格式选项
class VideoFormatOption {
  final String formatId;
  final String resolution;
  final String ext;
  final int? filesize;
  final String? note;
  final String? url;
  final bool hasVideo;
  final bool hasAudio;

  const VideoFormatOption({
    required this.formatId,
    required this.resolution,
    required this.ext,
    this.filesize,
    this.note,
    this.url,
    this.hasVideo = true,
    this.hasAudio = true,
  });

  String get displayName {
    final res = resolution.isNotEmpty ? resolution : (note ?? '默认画质');
    final sz = filesize != null ? ' (${(filesize! / 1024 / 1024).toStringAsFixed(1)} MB)' : '';
    return '$res [$ext]$sz';
  }
}

/// 在线解析返回的视频详情元数据
class ParsedVideoInfo {
  final String title;
  final String? author;
  final Duration duration;
  final String? thumbnailUrl;
  final String originalUrl;
  final String platform;
  final String? directStreamUrl;
  final Map<String, String>? httpHeaders;
  final List<VideoFormatOption> formats;

  const ParsedVideoInfo({
    required this.title,
    this.author,
    required this.duration,
    this.thumbnailUrl,
    required this.originalUrl,
    required this.platform,
    this.directStreamUrl,
    this.httpHeaders,
    required this.formats,
  });
}

/// 基于系统 yt-dlp 的跨平台流媒体解析器
class YtdlpVideoParser {
  YtdlpVideoParser._();
  static final YtdlpVideoParser instance = YtdlpVideoParser._();

  String? _cachedYtdlpPath;
  String? _cachedFfmpegPath;

  /// 检测 yt-dlp 是否可用并获取路径
  Future<String?> resolveYtdlpPath() async {
    if (_cachedYtdlpPath != null) return _cachedYtdlpPath;

    const candidates = [
      '/usr/local/Caskroom/miniconda/base/bin/yt-dlp',
      '/usr/local/bin/yt-dlp',
      '/opt/homebrew/bin/yt-dlp',
      'yt-dlp',
    ];

    for (final path in candidates) {
      try {
        final res = await Process.run(path, ['--version']);
        if (res.exitCode == 0) {
          _cachedYtdlpPath = path;
          return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 检测 ffmpeg 是否可用并获取路径
  Future<String?> resolveFfmpegPath() async {
    if (_cachedFfmpegPath != null) return _cachedFfmpegPath;

    const candidates = [
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      'ffmpeg',
    ];

    for (final path in candidates) {
      try {
        final res = await Process.run(path, ['-version']);
        if (res.exitCode == 0) {
          _cachedFfmpegPath = path;
          return path;
        }
      } catch (_) {}
    }
    return null;
  }

  /// 识别目标网址平台类型
  String detectPlatform(String url) {
    final u = url.toLowerCase();
    if (u.contains('bilibili.com') || u.contains('b23.tv')) return 'Bilibili';
    if (u.contains('youtube.com') || u.contains('youtu.be')) return 'YouTube';
    if (u.contains('pornhub.com')) return 'Pornhub';
    if (u.contains('pornlulu.com')) return 'PornLulu';
    if (u.contains('missav.')) return 'MissAV';
    return 'Generic';
  }

  /// 获取针对特定平台的额外优化参数
  List<String> getCustomFlagsForUrl(String url) {
    final platform = detectPlatform(url);
    if (platform == 'YouTube') {
      return ['--remote-components', 'ejs:npm'];
    } else if (platform == 'MissAV' || platform == 'PornLulu') {
      return [
        '--force-generic-extractor',
        '--extractor-args',
        'generic:impersonate',
        '--force-ipv4',
      ];
    }
    return [];
  }

  /// 执行解析并获取视频元数据
  Future<ParsedVideoInfo> parseUrl(String url, {String? cookiePath, String? cookiesFromBrowser}) async {
    final ytdlp = await resolveYtdlpPath();
    if (ytdlp == null) {
      throw Exception('系统未检测到 yt-dlp 工具，请通过 brew install yt-dlp 安装');
    }

    final platform = detectPlatform(url);
    final args = <String>[
      '--dump-json',
      '--no-playlist',
      '--no-warnings',
      '--no-check-certificates',
    ];

    // 平台专项优化参数
    if (platform == 'YouTube') {
      args.addAll(['--remote-components', 'ejs:npm']);
    } else if (platform == 'MissAV' || platform == 'PornLulu') {
      args.addAll([
        '--force-generic-extractor',
        '--extractor-args',
        'generic:impersonate',
        '--force-ipv4',
      ]);
    }

    if (cookiePath != null && cookiePath.isNotEmpty) {
      args.addAll(['--cookies', cookiePath]);
    } else if (cookiesFromBrowser != null && cookiesFromBrowser.isNotEmpty) {
      args.addAll(['--cookies-from-browser', cookiesFromBrowser]);
    }

    args.add(url);

    final processResult = await Process.run(
      ytdlp,
      args,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (processResult.exitCode != 0) {
      final err = processResult.stderr.toString().trim();
      throw Exception('解析失败: ${err.isNotEmpty ? err : "未知错误"}');
    }

    final rawJson = jsonDecode(processResult.stdout.toString());
    if (rawJson is! Map<String, dynamic>) {
      throw Exception('yt-dlp 返回数据格式异常');
    }

    final title = rawJson['title'] as String? ?? '未命名视频';
    final author = rawJson['uploader'] as String? ?? rawJson['channel'] as String?;
    final durationSec = (rawJson['duration'] as num?)?.toInt() ?? 0;
    final thumbnail = rawJson['thumbnail'] as String?;

    // 提取格式选项
    final formatList = <VideoFormatOption>[];
    String? bestStreamUrl;
    Map<String, String>? headers;

    if (rawJson['http_headers'] is Map) {
      headers = Map<String, String>.from(
        (rawJson['http_headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        ),
      );
    }

    final rawFormats = rawJson['formats'] as List?;
    if (rawFormats != null && rawFormats.isNotEmpty) {
      for (final f in rawFormats) {
        if (f is Map<String, dynamic>) {
          final fId = f['format_id']?.toString() ?? '';
          final ext = f['ext']?.toString() ?? '';
          final height = f['height'] as num?;
          final width = f['width'] as num?;
          final vcodec = f['vcodec']?.toString();
          final acodec = f['acodec']?.toString();
          final hasV = vcodec != null && vcodec != 'none';
          final hasA = acodec != null && acodec != 'none';
          final resolution = height != null ? '${height}p' : (width != null ? '${width}x' : '');
          final fUrl = f['url']?.toString();

          formatList.add(VideoFormatOption(
            formatId: fId,
            resolution: resolution,
            ext: ext,
            filesize: (f['filesize'] ?? f['filesize_approx']) as int?,
            note: f['format_note']?.toString(),
            url: fUrl,
            hasVideo: hasV,
            hasAudio: hasA,
          ));

          // 寻找最佳单一完整流 (带视频和音频) 或 m3u8 用于直接播放
          if (bestStreamUrl == null && (fUrl != null && fUrl.contains('.m3u8') || (hasV && hasA))) {
            bestStreamUrl = fUrl;
          }
        }
      }
    }

    bestStreamUrl ??= rawJson['url'] as String?;

    return ParsedVideoInfo(
      title: title,
      author: author,
      duration: Duration(seconds: durationSec),
      thumbnailUrl: thumbnail,
      originalUrl: url,
      platform: platform,
      directStreamUrl: bestStreamUrl,
      httpHeaders: headers,
      formats: formatList.reversed.toList(),
    );
  }
}
