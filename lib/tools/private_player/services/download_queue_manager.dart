import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../services/proxy_settings.dart';
import '../../ai_video_studio/services/studio_asset_bridge.dart';
import 'private_storage_manager.dart';
import 'ytdlp_video_parser.dart';

enum DownloadStatus {
  queued('等待中'),
  downloading('下载中'),
  merging('合成中'),
  completed('已完成'),
  failed('失败'),
  cancelled('已取消');

  final String label;
  const DownloadStatus(this.label);
}

/// 下载任务条目模型
class DownloadTask extends ChangeNotifier {
  /// 完成后是否把文件复制进 AI 短视频工坊的当前集 `frames/`（spec 16.1/16.2）。
  ///
  /// 只是**复制**：yt-dlp 仍然写它自己的下载目录，用户原来的浏览习惯不变。
  bool importToStudio = false;

  final String id;
  final String url;
  String title;
  final String formatId;
  DownloadStatus status;
  double progress;
  String speed;
  String eta;
  String? outputPath;
  String? errorMessage;
  String? thumbnailUrl;
  final String triggeredBy; // 'manual' | 'browser'
  String? directStreamUrl;
  Process? _process;

  DownloadTask({
    required this.id,
    required this.url,
    required this.title,
    this.formatId = 'bestvideo+bestaudio/best',
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.speed = '',
    this.eta = '',
    this.outputPath,
    this.errorMessage,
    this.thumbnailUrl,
    this.triggeredBy = 'manual',
    this.directStreamUrl,
  });

  void update({
    String? newTitle,
    DownloadStatus? newStatus,
    double? newProgress,
    String? newSpeed,
    String? newEta,
    String? newOutputPath,
    String? newError,
    String? newThumbnailUrl,
  }) {
    if (newTitle != null) title = newTitle;
    if (newStatus != null) status = newStatus;
    if (newProgress != null) progress = newProgress;
    if (newSpeed != null) speed = newSpeed;
    if (newEta != null) eta = newEta;
    if (newOutputPath != null) outputPath = newOutputPath;
    if (newError != null) errorMessage = newError;
    if (newThumbnailUrl != null) thumbnailUrl = newThumbnailUrl;
    notifyListeners();
  }

  void cancel() {
    if (_process != null) {
      _process!.kill();
      _process = null;
    }
    update(newStatus: DownloadStatus.cancelled, newSpeed: '', newEta: '');
  }
}

/// 视频下载与批量排队管理器
class DownloadQueueManager extends ChangeNotifier {
  DownloadQueueManager._();
  static final DownloadQueueManager instance = DownloadQueueManager._();

  final List<DownloadTask> _tasks = [];
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int maxConcurrency = 2;
  int _activeCount = 0;

  static final RegExp _progressRegex = RegExp(
    r'\[download\]\s+(\d+\.?\d*)%\s+of\s+~?\s*([\d\.]+[A-Za-z]+)\s+at\s+([\d\.]+[A-Za-z/]+)\s+ETA\s+([\d:]+)',
  );

  /// 添加单项下载任务
  DownloadTask addTask(
    String url, {
    String? title,
    String? formatId,
    String? thumbnailUrl,
    String triggeredBy = 'manual',
    String? directStreamUrl,
    bool importToStudio = false,
  }) {
    final cleanUrl = url.trim();
    final existing = _tasks
        .where((t) =>
            t.url == cleanUrl &&
            (t.status == DownloadStatus.queued ||
                t.status == DownloadStatus.downloading))
        .firstOrNull;
    if (existing != null) {
      if (thumbnailUrl != null && existing.thumbnailUrl == null) {
        existing.thumbnailUrl = thumbnailUrl;
      }
      if (directStreamUrl != null && existing.directStreamUrl == null) {
        existing.directStreamUrl = directStreamUrl;
      }
      return existing;
    }

    final id = '${DateTime.now().millisecondsSinceEpoch}_${_tasks.length}';
    final task = DownloadTask(
      id: id,
      url: cleanUrl,
      title: title ?? cleanUrl,
      formatId: formatId ?? 'bestvideo+bestaudio/best',
      thumbnailUrl: thumbnailUrl,
      triggeredBy: triggeredBy,
      directStreamUrl: directStreamUrl,
    );
    task.importToStudio = importToStudio;

    _tasks.add(task);
    notifyListeners();
    _pumpQueue();
    return task;
  }

  /// 批量添加多个视频链接下载
  List<DownloadTask> addBatch(List<String> urls, {String? formatId}) {
    final added = <DownloadTask>[];
    for (final u in urls) {
      final trimmed = u.trim();
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        added.add(addTask(trimmed, formatId: formatId));
      }
    }
    return added;
  }

  /// 取消指定任务
  void cancelTask(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      task.cancel();
      _pumpQueue();
    }
  }

  /// 重试失败或已取消任务
  void retryTask(String id) {
    final task = _tasks.where((t) => t.id == id).firstOrNull;
    if (task != null) {
      task.update(
        newStatus: DownloadStatus.queued,
        newProgress: 0.0,
        newSpeed: '',
        newEta: '',
        newError: '',
      );
      _pumpQueue();
    }
  }

  /// 清空已完成或失败任务
  void clearFinished() {
    _tasks.removeWhere((t) =>
        t.status == DownloadStatus.completed ||
        t.status == DownloadStatus.cancelled ||
        t.status == DownloadStatus.failed);
    notifyListeners();
  }

  /// 清空所有任务并取消正在运行的进程
  void clearAll() {
    for (final t in _tasks) {
      t.cancel();
    }
    _tasks.clear();
    notifyListeners();
  }

  void _pumpQueue() {
    if (_activeCount >= maxConcurrency) return;

    final pending = _tasks.where((t) => t.status == DownloadStatus.queued).toList();
    if (pending.isEmpty) return;

    final availableSlots = maxConcurrency - _activeCount;
    final toRun = pending.take(availableSlots);

    for (final task in toRun) {
      _startTask(task);
    }
  }

  /// 下载完成后按需把文件复制进工坊素材目录（spec 16.2）。
  ///
  /// 复制失败不影响下载本身的状态：文件已经好好躺在下载目录里了，工坊那份
  /// 是附加价值，为它把「已完成」改成「失败」会让用户以为视频没了。
  Future<void> _maybeImportToStudio(DownloadTask task, String path) async {
    if (!task.importToStudio || path.isEmpty) return;
    final result = await StudioAssetImporter.importDownloadedFile(
      downloadedFilePath: path,
    );
    if (result.ok) {
      task.update(newEta: '已复制到工坊素材目录');
    } else {
      task.update(newEta: '复制到工坊失败：${result.error}');
    }
  }

  Future<void> _startTask(DownloadTask task) async {
    _activeCount++;
    task.update(newStatus: DownloadStatus.downloading);

    final ytdlp = await YtdlpVideoParser.instance.resolveYtdlpPath();
    final ffmpeg = await YtdlpVideoParser.instance.resolveFfmpegPath();

    if (ytdlp == null) {
      task.update(
        newStatus: DownloadStatus.failed,
        newError: '未检测到 yt-dlp 工具，请先安装',
      );
      _activeCount--;
      _pumpQueue();
      return;
    }

    final outDir = PrivateStorageManager.instance.downloadsDir.path;
    final outTemplate = p.join(outDir, '%(title).80s.%(ext)s');

    final platform = YtdlpVideoParser.instance.detectPlatform(task.url);
    final proxy = ProxySettings.instance;

    final args = <String>[
      '--newline',
      '--no-playlist',
      '--no-warnings',
      '--no-check-certificates',
      '-f', task.formatId,
      '--merge-output-format', 'mp4',
      '-o', outTemplate,
      '--user-agent',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    ];

    if (proxy.isConfigured) {
      args.addAll(['--proxy', 'http://${proxy.host}:${proxy.port}']);
    }

    if (ffmpeg != null) {
      args.addAll(['--ffmpeg-location', ffmpeg]);
    }

    if (platform == 'YouTube') {
      args.addAll(['--remote-components', 'ejs:npm']);
    } else if (platform == 'MissAV' || platform == 'PornLulu') {
      args.addAll([
        '--force-generic-extractor',
        '--extractor-args',
        'generic:impersonate',
        '--force-ipv4',
      ]);
    } else if (platform == 'PornHub' || task.url.contains('pornhub')) {
      args.addAll([
        '--add-header', 'Referer:https://www.pornhub.com/',
        '--add-header', 'Cookie:age_verified=1; platform=pc',
      ]);
    }

    args.add(task.url);

    try {
      final process = await Process.start(ytdlp, args);
      task._process = process;

      String lastDownloadedPath = '';

      process.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
        final match = _progressRegex.firstMatch(line);
        if (match != null) {
          final pct = double.tryParse(match.group(1) ?? '0') ?? 0.0;
          final spd = match.group(3) ?? '';
          final eta = match.group(4) ?? '';
          task.update(
            newProgress: (pct / 100.0).clamp(0.0, 1.0),
            newSpeed: spd,
            newEta: eta,
          );
        } else if (line.contains('[Merger]') || line.contains('[ffmpeg]')) {
          task.update(newStatus: DownloadStatus.merging, newSpeed: '', newEta: '合成中');
        } else if (line.contains('Destination:')) {
          final dest = line.split('Destination:').last.trim();
          if (dest.isNotEmpty) lastDownloadedPath = dest;
        }
      });

      final exitCode = await process.exitCode;
      task._process = null;

      if (exitCode == 0) {
        task.update(
          newStatus: DownloadStatus.completed,
          newProgress: 1.0,
          newSpeed: '',
          newEta: '已完成',
          newOutputPath: lastDownloadedPath.isNotEmpty ? lastDownloadedPath : null,
        );
        await _maybeImportToStudio(task, lastDownloadedPath);
      } else {
        // 双轨回退机制：当主页面解析遇到反爬或 410 报错时，若有已嗅探到的有效媒体流直链，自动回退下载
        if (task.status != DownloadStatus.cancelled &&
            task.directStreamUrl != null &&
            task.directStreamUrl!.isNotEmpty &&
            task.directStreamUrl != task.url &&
            !task.directStreamUrl!.startsWith('blob:') &&
            !isSuspectAdUrl(task.directStreamUrl!)) {
          task.update(
            newStatus: DownloadStatus.downloading,
            newSpeed: '',
            newEta: '切换直链下载中',
          );

          final fallbackArgs = <String>[
            '--newline',
            '--no-playlist',
            '--no-warnings',
            '--no-check-certificates',
            '--merge-output-format', 'mp4',
            '-o', outTemplate,
            '--user-agent',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
            '--add-header', 'Referer:${task.url}',
            '--add-header', 'Cookie:age_verified=1; platform=pc',
          ];

          if (proxy.isConfigured) {
            fallbackArgs.addAll(['--proxy', 'http://${proxy.host}:${proxy.port}']);
          }
          if (ffmpeg != null) {
            fallbackArgs.addAll(['--ffmpeg-location', ffmpeg]);
          }
          fallbackArgs.add(task.directStreamUrl!);

          final fallbackProcess = await Process.start(ytdlp, fallbackArgs);
          task._process = fallbackProcess;

          fallbackProcess.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
            final match = _progressRegex.firstMatch(line);
            if (match != null) {
              final pct = double.tryParse(match.group(1) ?? '0') ?? 0.0;
              final spd = match.group(3) ?? '';
              final eta = match.group(4) ?? '';
              task.update(
                newProgress: (pct / 100.0).clamp(0.0, 1.0),
                newSpeed: spd,
                newEta: eta,
              );
            } else if (line.contains('[Merger]') || line.contains('[ffmpeg]')) {
              task.update(newStatus: DownloadStatus.merging, newSpeed: '', newEta: '合成中');
            } else if (line.contains('Destination:')) {
              final dest = line.split('Destination:').last.trim();
              if (dest.isNotEmpty) lastDownloadedPath = dest;
            }
          });

          final fallbackExitCode = await fallbackProcess.exitCode;
          task._process = null;

          if (fallbackExitCode == 0) {
            task.update(
              newStatus: DownloadStatus.completed,
              newProgress: 1.0,
              newSpeed: '',
              newEta: '已完成',
              newOutputPath: lastDownloadedPath.isNotEmpty ? lastDownloadedPath : null,
            );
            return;
          }
        }

        if (task.status != DownloadStatus.cancelled) {
          task.update(
            newStatus: DownloadStatus.failed,
            newError: '下载进程退出码: $exitCode',
          );
        }
      }
    } catch (e) {
      task.update(
        newStatus: DownloadStatus.failed,
        newError: e.toString(),
      );
    } finally {
      _activeCount--;
      _pumpQueue();
    }
  }

  /// 校验 URL 是否疑似广告流地址（排除广告商域名、贴片广告标记与广告路径）
  static bool isSuspectAdUrl(String url) {
    final lower = url.toLowerCase();
    const adKeywords = [
      'trafficjunky', 'doubleclick', 'googlesyndication', 'adzerk',
      'scorecardresearch', 'spotx', '/ads/', '/ad/', '_ad.', '-ad.',
      'preroll', 'vast', 'vmap', 'delivery', 'adcontent', 'ad_video',
      'advertisement', 'adnxs', 'exponential', 'adservice', 'commercial',
    ];
    return adKeywords.any((k) => lower.contains(k));
  }
}
