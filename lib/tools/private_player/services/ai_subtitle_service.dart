import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../services/ai_config_store.dart';
import '../../../services/ai_logger.dart';
import '../../../services/keychain_service.dart';
import 'private_player_controller.dart';
import 'private_storage_manager.dart';
import 'ytdlp_video_parser.dart';

/// 集成全局 AI 语音识别槽位的字幕生成服务
class AiSubtitleService {
  AiSubtitleService._();
  static final AiSubtitleService instance = AiSubtitleService._();

  /// 检查是否有可用的 STT 语音识别供应商
  Future<bool> hasAvailableSttProvider() async {
    final candidates = AiConfigStore.instance.slotBindings['stt'] ?? [];
    if (candidates.isEmpty) {
      // 检查是否有任何 provider 带有 stt 模型
      return AiConfigStore.instance.providers.any((p) => p.enabled && p.sttModels.isNotEmpty);
    }
    return true;
  }

  /// 提取轻量化单声道 MP3 音频切片 (16kHz, 64kbps)
  Future<File> extractAudio({
    required String videoPathOrUrl,
    Duration? start,
    Duration? duration,
    String? outputFileName,
  }) async {
    final ffmpeg = await YtdlpVideoParser.instance.resolveFfmpegPath();
    if (ffmpeg == null) {
      throw Exception('系统未检测到 ffmpeg 工具，无法抽取音频');
    }

    final tempDir = PrivateStorageManager.instance.tempAudioDir;
    final name = outputFileName ?? 'audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final targetFile = File(p.join(tempDir.path, name));
    if (targetFile.existsSync()) targetFile.deleteSync();

    final args = <String>['-y'];

    if (start != null && start > Duration.zero) {
      args.addAll(['-ss', _formatFfmpegDuration(start)]);
    }

    args.addAll(['-i', videoPathOrUrl]);

    if (duration != null && duration > Duration.zero) {
      args.addAll(['-t', _formatFfmpegDuration(duration)]);
    }

    args.addAll([
      '-vn',
      '-ar', '16000',
      '-ac', '1',
      '-b:a', '64k',
      '-f', 'mp3',
      targetFile.path,
    ]);

    final res = await Process.run(ffmpeg, args);
    if (res.exitCode != 0 || !targetFile.existsSync()) {
      throw Exception('音频提取失败: ${res.stderr}');
    }

    return targetFile;
  }

  /// 模式一：按当前播放进度区间按需分段生成（例如前后 10 分钟）
  Future<List<SubtitleSegment>> generateIntervalSubtitles({
    required String videoPathOrUrl,
    required Duration currentPosition,
    Duration intervalDuration = const Duration(minutes: 10),
    void Function(String status)? onStatus,
  }) async {
    onStatus?.call('正在提取音频切片...');
    final startOffset = currentPosition > const Duration(minutes: 2)
        ? currentPosition - const Duration(minutes: 2)
        : Duration.zero;

    final audioFile = await extractAudio(
      videoPathOrUrl: videoPathOrUrl,
      start: startOffset,
      duration: intervalDuration,
    );

    try {
      onStatus?.call('正在请求 AI 语音识别 (STT)...');
      final rawSegments = await _transcribeAudioFile(audioFile);

      // 将分段的相对时间换算为视频全局时间轴
      final result = <SubtitleSegment>[];
      for (int i = 0; i < rawSegments.length; i++) {
        final seg = rawSegments[i];
        final globalStart = startOffset + seg.start;
        final globalEnd = startOffset + seg.end;
        result.add(SubtitleSegment(
          id: i + 1,
          start: globalStart,
          end: globalEnd,
          text: seg.text,
        ));
      }
      return result;
    } finally {
      if (audioFile.existsSync()) {
        try {
          audioFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// 模式二：全量后台分片转录并合并完整字幕
  Future<List<SubtitleSegment>> generateFullSubtitles({
    required String videoPathOrUrl,
    required Duration totalDuration,
    void Function(double progress, String status)? onProgress,
  }) async {
    onProgress?.call(0.05, '正在抽取全量音频...');

    final audioFile = await extractAudio(videoPathOrUrl: videoPathOrUrl);

    try {
      const chunkMinutes = 10;
      final totalSeconds = totalDuration.inSeconds > 0 ? totalDuration.inSeconds : 600;
      final chunkCount = (totalSeconds / (chunkMinutes * 60)).ceil();

      final allSegments = <SubtitleSegment>[];

      if (chunkCount <= 1) {
        onProgress?.call(0.3, '正在发送 AI 语音识别...');
        final segs = await _transcribeAudioFile(audioFile);
        allSegments.addAll(segs);
      } else {
        // 多片段拆解转录
        for (int i = 0; i < chunkCount; i++) {
          final start = Duration(minutes: i * chunkMinutes);
          final progressPct = 0.1 + (i / chunkCount) * 0.8;
          onProgress?.call(progressPct, '正在识别第 ${i + 1}/$chunkCount 分段 (${i * 10}~${(i + 1) * 10} 分钟)...');

          final chunkAudio = await extractAudio(
            videoPathOrUrl: audioFile.path,
            start: start,
            duration: const Duration(minutes: chunkMinutes),
            outputFileName: 'chunk_${i}_${DateTime.now().millisecondsSinceEpoch}.mp3',
          );

          try {
            final chunkSegs = await _transcribeAudioFile(chunkAudio);
            for (final seg in chunkSegs) {
              allSegments.add(SubtitleSegment(
                id: allSegments.length + 1,
                start: start + seg.start,
                end: start + seg.end,
                text: seg.text,
              ));
            }
          } finally {
            if (chunkAudio.existsSync()) {
              try {
                chunkAudio.deleteSync();
              } catch (_) {}
            }
          }
        }
      }

      onProgress?.call(1.0, '字幕生成完成');
      return allSegments;
    } finally {
      if (audioFile.existsSync()) {
        try {
          audioFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// 调用商业 AI 语音识别接口 (兼容 OpenAI Whisper /v1/audio/transcriptions 规范)
  Future<List<SubtitleSegment>> _transcribeAudioFile(File audioFile) async {
    final (provider, model, apiKey) = await _resolveSttProvider();

    String endpoint = provider.baseUrl.trim();
    if (endpoint.endsWith('/audio/transcriptions')) {
      // 已完整
    } else if (endpoint.endsWith('/v1')) {
      endpoint = '$endpoint/audio/transcriptions';
    } else {
      endpoint = '$endpoint/v1/audio/transcriptions';
    }

    final uri = Uri.parse(endpoint);
    final request = http.MultipartRequest('POST', uri);

    if (apiKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $apiKey';
    }

    request.fields['model'] = model;
    request.fields['response_format'] = 'verbose_json';
    request.fields['timestamp_granularities[]'] = 'segment';
    request.fields['temperature'] = '0.0';

    request.files.add(
      await http.MultipartFile.fromPath('file', audioFile.path),
    );

    final stopwatch = Stopwatch()..start();
    AiLogger.logRequest(
      providerName: provider.name,
      protocol: 'openai-stt',
      model: model,
      endpoint: endpoint,
      promptSummary: 'STT 语音转写: ${audioFile.path.split('/').last} (${(audioFile.lengthSync() / 1024).toStringAsFixed(1)} KB)',
    );

    final streamedResponse = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamedResponse);
    stopwatch.stop();

    AiLogger.logResponse(
      providerName: provider.name,
      statusCode: response.statusCode,
      durationMs: stopwatch.elapsedMilliseconds,
      bodyPreview: 'STT 响应完成: ${response.statusCode}',
    );

    if (response.statusCode != 200) {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      AiLogger.logError('STT 识别失败 (HTTP ${response.statusCode}): $body', providerName: provider.name);
      throw Exception('语音识别接口请求失败 (HTTP ${response.statusCode}): $body');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw Exception('STT 响应数据结构异常');
    }

    final segments = decoded['segments'] as List?;
    final result = <SubtitleSegment>[];

    if (segments != null && segments.isNotEmpty) {
      for (int i = 0; i < segments.length; i++) {
        final s = segments[i] as Map;
        final startSec = (s['start'] as num?)?.toDouble() ?? 0.0;
        final endSec = (s['end'] as num?)?.toDouble() ?? 0.0;
        final text = (s['text'] as String?)?.trim() ?? '';
        if (text.isNotEmpty) {
          result.add(SubtitleSegment(
            id: i + 1,
            start: Duration(milliseconds: (startSec * 1000).round()),
            end: Duration(milliseconds: (endSec * 1000).round()),
            text: text,
          ));
        }
      }
    } else {
      // 兜底：若仅有 text 字段无 segment 时间戳
      final text = (decoded['text'] as String?)?.trim() ?? '';
      if (text.isNotEmpty) {
        result.add(SubtitleSegment(
          id: 1,
          start: Duration.zero,
          end: const Duration(seconds: 10),
          text: text,
        ));
      }
    }

    return result;
  }

  /// 解析 STT 槽位与凭证
  Future<(AiProviderConfig, String, String)> _resolveSttProvider() async {
    final candidates = AiConfigStore.instance.slotBindings['stt'] ?? [];
    AiProviderConfig? targetProvider;
    String targetModel = '';

    for (final cand in candidates) {
      final p = AiConfigStore.instance.providers
          .where((e) => e.id == cand.providerId)
          .firstOrNull;
      if (p != null && p.enabled) {
        targetProvider = p;
        targetModel = cand.model.trim();
        break;
      }
    }

    targetProvider ??= AiConfigStore.instance.providers
        .where((p) => p.enabled && (p.sttModels.isNotEmpty || p.protocol == AiProtocolType.openai))
        .firstOrNull;

    if (targetProvider == null) {
      throw Exception('未找到可用的语音识别 (STT) 供应商，请先在"AI 能力配置"中绑定 STT 槽位');
    }

    if (targetModel.isEmpty) {
      targetModel = targetProvider.sttModels.firstOrNull ?? 'whisper-1';
    }

    final apiKey = await KeychainService.instance.readSecret(targetProvider.keychainKeyId) ?? '';

    return (targetProvider, targetModel, apiKey);
  }

  /// 将字幕片段导出为标准 SRT 纯文本字符串
  static String exportAsSrt(List<SubtitleSegment> segments) {
    final buffer = StringBuffer();
    for (int i = 0; i < segments.length; i++) {
      final seg = segments[i];
      buffer.writeln('${i + 1}');
      buffer.writeln('${_formatSrtTimestamp(seg.start)} --> ${_formatSrtTimestamp(seg.end)}');
      buffer.writeln(seg.text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// 保存字幕至私密存储或目标文件
  Future<File> saveSubtitleFile({
    required String title,
    required List<SubtitleSegment> segments,
    String? customPath,
  }) async {
    final srtContent = exportAsSrt(segments);
    File target;

    if (customPath != null) {
      target = File(customPath);
    } else {
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final dir = PrivateStorageManager.instance.subtitlesDir;
      target = File(p.join(dir.path, '$safeTitle.srt'));
    }

    await target.writeAsString(srtContent, flush: true);
    return target;
  }

  static String _formatSrtTimestamp(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final millis = d.inMilliseconds.remainder(1000).toString().padLeft(3, '0');
    return '$hours:$minutes:$seconds,$millis';
  }

  static String _formatFfmpegDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds.remainder(60) + (d.inMilliseconds.remainder(1000) / 1000.0)).toStringAsFixed(2).padLeft(5, '0');
    return '$hours:$minutes:$seconds';
  }

  /// 解析标准 SRT 或 WebVTT 格式字符串为字幕片段列表
  static List<SubtitleSegment> parseSrtOrVtt(String rawContent) {
    final cleanContent = rawContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = cleanContent.split('\n');
    final segments = <SubtitleSegment>[];

    final timeRegex = RegExp(
      r'(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,.](\d{3})\s*-->\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})[,.](\d{3})',
    );

    Duration? currentStart;
    Duration? currentEnd;
    final textBuffer = StringBuffer();

    void flushSegment() {
      if (currentStart != null && currentEnd != null) {
        final text = textBuffer.toString().trim();
        if (text.isNotEmpty) {
          segments.add(SubtitleSegment(
            id: segments.length + 1,
            start: currentStart!,
            end: currentEnd!,
            text: text,
          ));
        }
      }
      currentStart = null;
      currentEnd = null;
      textBuffer.clear();
    }

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      // 忽略 WebVTT 头部或备注行
      if (line == 'WEBVTT' || line.startsWith('NOTE') || line.startsWith('STYLE')) {
        continue;
      }

      final match = timeRegex.firstMatch(line);
      if (match != null) {
        flushSegment();

        final startH = match.group(1) != null ? int.parse(match.group(1)!) : 0;
        final startM = int.parse(match.group(2)!);
        final startS = int.parse(match.group(3)!);
        final startMs = int.parse(match.group(4)!);
        currentStart = Duration(hours: startH, minutes: startM, seconds: startS, milliseconds: startMs);

        final endH = match.group(5) != null ? int.parse(match.group(5)!) : 0;
        final endM = int.parse(match.group(6)!);
        final endS = int.parse(match.group(7)!);
        final endMs = int.parse(match.group(8)!);
        currentEnd = Duration(hours: endH, minutes: endM, seconds: endS, milliseconds: endMs);
      } else if (currentStart != null) {
        if (line.isEmpty) {
          flushSegment();
        } else {
          if (textBuffer.isEmpty && RegExp(r'^\d+$').hasMatch(line)) {
            continue;
          }
          final cleanText = line.replaceAll(RegExp(r'<[^>]+>'), '').trim();
          if (cleanText.isNotEmpty) {
            if (textBuffer.isNotEmpty) textBuffer.write('\n');
            textBuffer.write(cleanText);
          }
        }
      }
    }

    flushSegment();
    return segments;
  }

  /// 抽取超轻量化单声道 MP3 (16kHz, 32kbps，用于极速单文件全量转写)
  Future<File> extractAudioFast({
    required String videoPathOrUrl,
  }) async {
    final ffmpeg = await YtdlpVideoParser.instance.resolveFfmpegPath();
    if (ffmpeg == null) {
      throw Exception('系统未检测到 ffmpeg 工具，无法抽取音频');
    }

    final tempDir = PrivateStorageManager.instance.tempAudioDir;
    final name = 'fast_audio_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final targetFile = File(p.join(tempDir.path, name));
    if (targetFile.existsSync()) targetFile.deleteSync();

    final args = <String>[
      '-y',
      '-i', videoPathOrUrl,
      '-vn',
      '-ar', '16000',
      '-ac', '1',
      '-b:a', '32k',
      '-f', 'mp3',
      targetFile.path,
    ];

    final res = await Process.run(ffmpeg, args);
    if (res.exitCode != 0 || !targetFile.existsSync()) {
      throw Exception('快速音频提取失败: ${res.stderr}');
    }

    return targetFile;
  }

  /// 极速生成/提取全部字幕（三级阶梯策略）
  /// Tier 1: 在线视频 - yt-dlp 秒级直取原生/自动字幕 (1~2秒)
  /// Tier 2: 本地视频 - ffmpeg 瞬间导出内嵌软字幕轨 (<1秒)
  /// Tier 3: 极致单文件压缩 (32kbps) 快速全量转写
  Future<List<SubtitleSegment>> fastGenerateSubtitles({
    required String videoPathOrUrl,
    required String title,
    Duration? duration,
    void Function(String status, double? progress)? onProgress,
  }) async {
    final isOnline = videoPathOrUrl.startsWith('http://') || videoPathOrUrl.startsWith('https://');

    // Tier 1: 在线视频原生字幕提取
    if (isOnline) {
      onProgress?.call('正在检查源站原生字幕 (Tier 1)...', 0.15);
      try {
        final onlineSubs = await _extractOnlineNativeSubtitles(videoPathOrUrl);
        if (onlineSubs.isNotEmpty) {
          onProgress?.call('成功提取源站原生字幕！', 1.0);
          await saveSubtitleFile(title: title, segments: onlineSubs);
          return onlineSubs;
        }
      } catch (e) {
        debugPrint('Tier 1 在线原生字幕直取失败: $e');
      }
    }

    // Tier 2: 本地视频内嵌软字幕轨提取
    if (!isOnline && File(videoPathOrUrl).existsSync()) {
      onProgress?.call('正在检查内嵌字幕轨 (Tier 2)...', 0.2);
      try {
        final embeddedSubs = await _extractEmbeddedSubtitles(videoPathOrUrl);
        if (embeddedSubs.isNotEmpty) {
          onProgress?.call('成功提取视频内嵌字幕！', 1.0);
          await saveSubtitleFile(title: title, segments: embeddedSubs);
          return embeddedSubs;
        }
      } catch (e) {
        debugPrint('Tier 2 内嵌字幕流提取失败: $e');
      }
    }

    // Tier 3: 极速全量语音转录
    onProgress?.call('正在抽取轻量音频轨 (Tier 3)...', 0.3);
    final audioFile = await extractAudioFast(videoPathOrUrl: videoPathOrUrl);

    try {
      onProgress?.call('正在快速转写音频...', 0.65);
      final segments = await _transcribeAudioFile(audioFile);
      if (segments.isNotEmpty) {
        await saveSubtitleFile(title: title, segments: segments);
      }
      onProgress?.call('字幕生成完成！', 1.0);
      return segments;
    } finally {
      if (audioFile.existsSync()) {
        try {
          audioFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  Future<List<SubtitleSegment>> _extractOnlineNativeSubtitles(String url) async {
    final ytdlp = await YtdlpVideoParser.instance.resolveYtdlpPath();
    if (ytdlp == null) return [];

    final tempDir = PrivateStorageManager.instance.tempAudioDir;
    final prefix = 'online_sub_${DateTime.now().millisecondsSinceEpoch}';
    final outTemplate = p.join(tempDir.path, '$prefix.%(ext)s');

    final args = [
      '--write-subs',
      '--write-auto-subs',
      '--sub-lang', 'zh-Hans,zh-CN,zh,zh-Hant,en',
      '--skip-download',
      '--sub-format', 'srt/vtt/best',
      '-o', outTemplate,
      '--no-playlist',
      '--no-warnings',
    ];

    final customFlags = YtdlpVideoParser.instance.getCustomFlagsForUrl(url);
    args.addAll(customFlags);
    args.add(url);

    final res = await Process.run(ytdlp, args).timeout(const Duration(seconds: 20));
    if (res.exitCode != 0) return [];

    final files = tempDir.listSync().whereType<File>().where((f) {
      final base = p.basename(f.path);
      return base.startsWith(prefix) && (base.endsWith('.srt') || base.endsWith('.vtt'));
    }).toList();

    if (files.isEmpty) return [];

    final targetFile = files.first;
    try {
      final content = await targetFile.readAsString();
      return parseSrtOrVtt(content);
    } finally {
      for (final f in files) {
        try { f.deleteSync(); } catch (_) {}
      }
    }
  }

  Future<List<SubtitleSegment>> _extractEmbeddedSubtitles(String localVideoPath) async {
    final ffmpeg = await YtdlpVideoParser.instance.resolveFfmpegPath();
    if (ffmpeg == null) return [];

    final tempDir = PrivateStorageManager.instance.tempAudioDir;
    final outSrt = File(p.join(tempDir.path, 'embed_${DateTime.now().millisecondsSinceEpoch}.srt'));

    final args = [
      '-y',
      '-i', localVideoPath,
      '-map', '0:s:0',
      outSrt.path,
    ];

    final res = await Process.run(ffmpeg, args).timeout(const Duration(seconds: 10));
    if (res.exitCode != 0 || !outSrt.existsSync() || outSrt.lengthSync() < 10) {
      if (outSrt.existsSync()) outSrt.deleteSync();
      return [];
    }

    try {
      final content = await outSrt.readAsString();
      return parseSrtOrVtt(content);
    } finally {
      if (outSrt.existsSync()) outSrt.deleteSync();
    }
  }
}
