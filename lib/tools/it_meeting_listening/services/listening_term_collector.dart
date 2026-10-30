/// 术语收藏：把 IT 会议听力里的术语/句子存入既有术语本。
///
/// **不新增表、不做迁移**（design 决策）：来源信息用既有字段承载——
/// - `sourceContext` 存 JSON：来源工具、片段 id、场景、句子文本、起止毫秒
/// - `audioUrl` 存该句的读音音频路径
/// - `phrases` 存上下文句子
///
/// 复用 `VocabEntries` 既有列是刻意的：术语本已经是「跨工具的词条仓库」，
/// 为一个新工具加表会让同一份词条散在两处。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../vocab_book/models/vocab_entry.dart';
import '../../vocab_book/services/vocab_store.dart';
import '../models/listening_models.dart';

/// 术语条目的来源信息。
class ListeningTermSource {
  /// 来源工具标识。
  static const String toolId = 'it-meeting-listening';

  /// 片段 id。
  final String clipId;

  /// 来源标识（如 "coderslingo"）。
  ///
  /// 多来源下分辨出处用。旧条目缺这个字段时读回为 `coderslingo`（首版唯一来源）。
  final String sourceId;

  /// 场景 id。
  final String sceneId;

  /// 片段标题。
  final String clipTitle;

  /// 所在句子的文本。
  final String sentence;

  /// 句子在音频中的起始毫秒。
  final int startMs;

  /// 句子在音频中的结束毫秒。
  final int endMs;

  const ListeningTermSource({
    required this.clipId,
    this.sourceId = 'coderslingo',
    required this.sceneId,
    required this.clipTitle,
    required this.sentence,
    required this.startMs,
    required this.endMs,
  });

  Map<String, dynamic> toJson() => {
        'tool': toolId,
        'sourceId': sourceId,
        'clipId': clipId,
        'sceneId': sceneId,
        'clipTitle': clipTitle,
        'sentence': sentence,
        'startMs': startMs,
        'endMs': endMs,
      };

  /// 从 `sourceContext` 解析来源信息。
  ///
  /// 不是本工具写入的词条（划词查词加入的）解析不出这些字段，返回 null——
  /// UI 侧据此判断"这条没有来源"，不报错。
  static ListeningTermSource? fromSourceContext(String? sourceContext) {
    if (sourceContext == null || sourceContext.isEmpty) return null;
    try {
      final decoded = jsonDecode(sourceContext);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['tool'] != toolId) return null;
      final clipId = map['clipId'] as String? ?? '';
      if (clipId.isEmpty) return null;
      return ListeningTermSource(
        clipId: clipId,
        // 旧条目（首版收藏的）没有 sourceId —— 缺省 coderslingo。
        sourceId: map['sourceId'] as String? ?? 'coderslingo',
        sceneId: map['sceneId'] as String? ?? '',
        clipTitle: map['clipTitle'] as String? ?? '',
        sentence: map['sentence'] as String? ?? '',
        startMs: (map['startMs'] as num?)?.toInt() ?? 0,
        endMs: (map['endMs'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// 术语收藏服务。
class ListeningTermCollector {
  static const _uuid = Uuid();

  /// 收藏一个术语。
  ///
  /// [turn] 是术语所在的那一轮，[clip] 是它所属的片段。收藏时会裁出该轮的
  /// 音频片段存到术语音频目录，术语本里就能直接重听这个词的发音。
  Future<String> collect({
    required Clip clip,
    required SpeakerTurn turn,
    required String term,
    required Directory materialDir,
    required Directory termAudioDir,
  }) async {
    final source = ListeningTermSource(
      clipId: clip.id,
      sourceId: clip.source.sourceId,
      sceneId: clip.scene.id,
      clipTitle: clip.title,
      sentence: turn.rawText,
      startMs: turn.startMs,
      endMs: turn.endMs,
    );

    // 裁出该轮的音频（术语本里可直接重听这个词的发音）
    String? audioUrl;
    try {
      await termAudioDir.create(recursive: true);
      final srcFile = File(p.join(materialDir.path, clip.audioPath));
      if (await srcFile.exists() && turn.endMs > turn.startMs) {
        final outFile =
            File(p.join(termAudioDir.path, '${_uuid.v4()}.mp3'));
        final ok = await _cutAudio(srcFile, outFile, turn.startMs, turn.endMs);
        if (ok) audioUrl = outFile.path;
      }
    } catch (_) {
      // 裁剪失败不影响收藏本身——词条文本与来源仍然有效。
      audioUrl = null;
    }

    return VocabStore.instance.insertEntry(VocabEntryModel(
      id: _uuid.v4(),
      word: term,
      audioUrl: audioUrl,
      definitions: const [],
      examples: const [],
      phrases: [turn.rawText],
      sourceContext: jsonEncode(source.toJson()),
      masteryLevel: 0,
      tags: ['it-meeting', clip.scene.id],
      addedAt: DateTime.now(),
    ));
  }

  /// 用 ffmpeg 裁出 [startMs]~[endMs] 的音频。
  Future<bool> _cutAudio(
      File src, File out, int startMs, int endMs) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) return false;
    final start = (startMs / 1000).toStringAsFixed(3);
    final duration = ((endMs - startMs) / 1000).toStringAsFixed(3);
    final r = await Process.run(ffmpeg, [
      '-y', '-loglevel', 'error',
      '-ss', start, '-t', duration, '-i', src.path,
      '-c:a', 'libmp3lame', '-b:a', '96k', out.path,
    ]);
    return r.exitCode == 0 && await out.exists();
  }

  String? _ffmpegPath;

  Future<String?> _resolveFfmpeg() async {
    if (_ffmpegPath != null) return _ffmpegPath;
    const candidates = [
      '/usr/local/bin/ffmpeg',
      '/opt/homebrew/bin/ffmpeg',
      'ffmpeg',
    ];
    for (final c in candidates) {
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
}
