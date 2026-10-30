/// 素材烘焙管线。
///
/// 把抓取到的对话文本合成为可离线播放的音频：
///
///   对话块 → 清洗 → 角色映射音色 → 逐轮合成 → 拼接 → 落盘音频 + 文稿清单
///
/// **为什么逐轮合成**：实测端点一次请求内多段 SSML 只有第一段出音，单请求
/// 拿不到多角色对话。逐轮合成还带来三个额外好处：单轮失败可单独重试、
/// 轮次边界天然成为可定位的时间戳、每轮可独立选音色。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import '../models/listening_models.dart';
import 'clip_summarizer.dart';
import 'coderslingo_source.dart';
import 'listening_source.dart';
import 'role_voice_map.dart';
import 'text_sanitizer.dart';

/// 烘焙进度回调。
typedef BakeProgress = void Function(String clipId, int done, int total);

/// 烘焙结果。
class BakeResult {
  /// 成功烘焙的片段。
  final List<Clip> clips;

  /// 失败的片段与原因。
  final Map<String, String> failures;

  const BakeResult({this.clips = const [], this.failures = const {}});
}

/// 片段切分结果。
class ClipSegment {
  /// 该片段包含的轮次（原始顺序）。
  final List<SpeakerTurn> turns;

  /// 该片段包含的场景说明。
  final String scenarioNote;

  const ClipSegment(this.turns, this.scenarioNote);
}

/// 素材烘焙器。
class ClipBaker {
  /// 单轮合成的重试次数（不含首次尝试）。
  static const int turnRetries = 2;

  /// 配额耗尽时**不再重试**。
  ///
  /// 实测：连续批量烘焙会撞上上游配额上限（HTTP 402 quota_exceeded）。
  /// 配额错误重试多少次都一样——每次重试只是多打一次必然失败的请求，
  /// 徒延长时间并刷日志。识别到配额错误就立即放弃这一轮，让整条素材
  /// 标记失败，等配额恢复后重跑。
  static bool _isQuotaExhausted(Object error) {
    final text = error.toString();
    return text.contains('402') ||
        text.contains('quota_exceeded') ||
        text.contains('quota exceeded');
  }

  /// 单轮音频的最小有效时长（毫秒）。低于此值视为合成失败。
  static const int minTurnMs = 400;

  /// 送入 TTS 的单轮文本上限（字符）。
  ///
  /// 实测端点限制：input 必须 "characters less than 1000 and greater than 0"，
  /// 超过 1000 字返回 HTTP 400 `input_invalid`。
  static const int maxSynthesisChars = 900;

  /// 超长轮次的切分点（句子边界）。
  static final RegExp _sentenceEnd = RegExp(r'(?<=[.!?])\s+');

  /// 把超长的一轮切成若干可合成的子段。
  ///
  /// 实测有 7/34 块对话含超过 1000 字的单轮（架构评审的技术论证、
  /// 技术演讲的 ML 论述、面试的架构权衡回答）。端点对 input 长度有硬限制，
  /// 不切就整条素材丢失。
  ///
  /// 切分点优先取**句子边界**；单句本身就超长时，退化为按词切（宁可
  /// 断在词间，也不要让端点拒绝）。每段不超过 [maxSynthesisChars]。
  static List<String> splitLongTurn(String text, {int limit = maxSynthesisChars}) {
    if (text.length <= limit) return [text];

    final out = <String>[];
    var current = '';

    for (final sentence in text.split(_sentenceEnd)) {
      if (sentence.trim().isEmpty) continue;
      final candidate = current.isEmpty ? sentence : '$current $sentence';
      if (candidate.length <= limit) {
        current = candidate;
        continue;
      }
      // 当前段放不下了：先收尾，再看这句自己是否超长
      if (current.isNotEmpty) {
        out.add(current.trim());
        current = '';
      }
      if (sentence.length <= limit) {
        current = sentence;
        continue;
      }
      // 单句超长 → 按词硬切
      var chunk = '';
      for (final word in sentence.split(RegExp(r'\s+'))) {
        if (word.isEmpty) continue;
        final c = chunk.isEmpty ? word : '$chunk $word';
        if (c.length <= limit) {
          chunk = c;
        } else {
          if (chunk.isNotEmpty) out.add(chunk);
          chunk = word;
        }
      }
      current = chunk;
    }
    if (current.trim().isNotEmpty) out.add(current.trim());
    return out.isEmpty ? [text] : out;
  }

  /// 片段时长目标（毫秒）。
  static const int targetClipMs = 120000;

  /// 片段时长上限（毫秒）。
  static const int maxClipMs = 180000;

  /// 片段时长下限（毫秒）。低于此值的尾段并入前一片段。
  static const int minClipMs = 45000;

  final TtsEngine _engine;
  final Directory _materialDir;
  final Directory _cacheDir;

  /// 摘要生成器。为 null 时不生成摘要（摘要失败不阻塞烘焙）。
  final ClipSummarizer? _summarizer;

  ClipBaker({
    required TtsEngine engine,
    required Directory materialDir,
    required Directory cacheDir,
    ClipSummarizer? summarizer,
  })  : _engine = engine,
        _materialDir = materialDir,
        _cacheDir = cacheDir,
        _summarizer = summarizer;

  /// 按说话人轮次边界切分一个对话块。
  ///
  /// 切分点必须落在**完整轮次**边界上——切断一句话会让用户听到半句，
  /// 那不是听力材料，是噪音。
  /// 单轮的估算时长（毫秒）。
  ///
  /// 切分发生在合成**之前**，那时还不知道真实时长，只能估。英语会议语速约
  /// 150 wpm，即每词约 400ms；加上起停的固定开销。
  static int estimateTurnMs(SpeakerTurn turn) {
    final words = turn.rawText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    if (words == 0) return 800;
    return (words * 400 + 600).clamp(800, 30000);
  }

  /// 按说话人轮次边界切分一个对话块。
  ///
  /// 切分点必须落在**完整轮次**边界上——切断一句话会让用户听到半句，
  /// 那不是听力材料，是噪音。
  ///
  /// 尾段过短时**只在并入后仍不超过上限时**才并入上一段：否则会出现一个
  /// 几秒的碎片（用户听不出什么），或一个超长片段（违反时长上限）。
  static List<ClipSegment> segment(List<SpeakerTurn> turns, String note) {
    if (turns.isEmpty) return const [];
    final segments = <ClipSegment>[];
    var current = <SpeakerTurn>[];
    var currentMs = 0;

    for (final turn in turns) {
      final turnMs = estimateTurnMs(turn);
      if (currentMs + turnMs > maxClipMs && current.isNotEmpty) {
        segments.add(ClipSegment(current, note));
        current = <SpeakerTurn>[];
        currentMs = 0;
      }
      current.add(turn);
      currentMs += turnMs;
    }
    if (current.isNotEmpty) {
      final tailMs = currentMs;
      if (segments.isNotEmpty && tailMs < minClipMs) {
        final prev = segments.removeLast();
        final prevMs = prev.turns.fold<int>(0, (a, t) => a + estimateTurnMs(t));
        if (prevMs + tailMs <= maxClipMs) {
          segments.add(ClipSegment([...prev.turns, ...current], note));
        } else {
          // 并入会超上限：宁可留一个短尾段，也不产出超长片段。
          segments.add(ClipSegment(prev.turns, note));
          segments.add(ClipSegment(current, note));
        }
      } else {
        segments.add(ClipSegment(current, note));
      }
    }
    return segments;
  }

  /// 烘焙一个对话块。
  ///
  /// 返回烘焙成功的片段；失败时通过 [BakeResult.failures] 报告原因。
  Future<BakeResult> bakeDialogue(
    FetchedDialogue dialogue, {
    BakeProgress? onProgress,
  }) async {
    return bakeSourceDialogue(
      SourceDialogue(
        column: SourceColumn(
          sourceId: CoderSlingoSource.sourceIdentifier,
          slug: dialogue.columnSlug,
          displayName: dialogue.column,
          scene: dialogue.scene,
          pageUrl: dialogue.pageUrl,
        ),
        pageUrl: dialogue.pageUrl,
        blockIndex: dialogue.blockIndex,
        scenarioNote: dialogue.scenarioNote,
        turns: dialogue.turns,
      ),
      onProgress: onProgress,
    );
  }

  /// 抽象层形态的烘焙入口。
  Future<BakeResult> bakeSourceDialogue(
    SourceDialogue dialogue, {
    BakeProgress? onProgress,
  }) async {
    final segments = segment(dialogue.turns, dialogue.scenarioNote);
    final clips = <Clip>[];
    final failures = <String, String>{};

    for (var i = 0; i < segments.length; i++) {
      final clipId = '${dialogue.clipId}_s$i';
      onProgress?.call(clipId, i, segments.length);
      try {
        final clip = await _bakeSegment(clipId, dialogue, segments[i]);
        clips.add(clip);
      } catch (e) {
        failures[clipId] = '$e';
      }
    }
    onProgress?.call(dialogue.clipId, segments.length, segments.length);
    return BakeResult(clips: clips, failures: failures);
  }

  Future<Clip> _bakeSegment(
    String clipId,
    SourceDialogue dialogue,
    ClipSegment segment,
  ) async {
    await _materialDir.create(recursive: true);
    final turnFiles = <String>[];
    final turns = <SpeakerTurn>[];

    for (var i = 0; i < segment.turns.length; i++) {
      final turn = segment.turns[i];
      final voice = RoleVoiceMap.voiceFor(turn.speaker, turn.role);
      final synthesisText = sanitizeForSynthesis(turn.rawText);
      if (synthesisText.isEmpty) continue;

      // 超长的一轮拆成多段合成——端点对 input 长度有硬限制（<1000 字）。
      // 拆出的段落共用同一音色，听感上是同一个人连续说，只是中间多了个停顿。
      final parts = splitLongTurn(synthesisText);
      var segIndex = 0;
      for (var pi = 0; pi < parts.length; pi++) {
        final segs = await _synthesizeTurn(
            parts[pi], voice, '${clipId}_turn${i}_p$pi');
        if (segs == null || segs.isEmpty) {
          throw StateError('第 ${i + 1} 轮（${turn.speaker}）'
              '${parts.length > 1 ? " 第 ${pi + 1} 段" : ""}合成失败');
        }
        for (final seg in segs) {
          final file = File(
              p.join(_cacheDir.path, '${clipId}_turn${i}_s$segIndex.mp3'));
          await file.parent.create(recursive: true);
          await file.writeAsBytes(seg, flush: true);
          turnFiles.add(file.path);
          segIndex++;
        }
      }

      turns.add(turn.copyWith(
        synthesisText: synthesisText,
        voice: voice,
      ));
    }
    if (turnFiles.isEmpty) {
      throw StateError('该片段没有可合成的轮次');
    }

    // 拼接成单条音频
    final audioFile = File(p.join(_materialDir.path, '$clipId.mp3'));
    await _concat(turnFiles, audioFile.path);

    // 各轮起止时间由实际音频时长累加得出
    final withTimes = <SpeakerTurn>[];
    var cursor = 0;
    for (var i = 0; i < turns.length; i++) {
      final ms = await _probeDurationMs(turnFiles[i]);
      withTimes.add(turns[i].copyWith(startMs: cursor, endMs: cursor + ms));
      cursor += ms;
    }

    final clip = Clip(
      id: clipId,
      scene: dialogue.column.scene,
      title: _titleFor(dialogue, segment),
      audioPath: p.basename(audioFile.path),
      durationMs: cursor,
      turns: withTimes,
      source: ClipSource(
        sourceId: dialogue.column.sourceId,
        site: dialogue.column.sourceId == CoderSlingoSource.sourceIdentifier
            ? CoderSlingoSource.siteName
            : dialogue.column.sourceId,
        pageUrl: dialogue.pageUrl,
        column: dialogue.column.displayName,
        license: CoderSlingoSource.licenseId,
      ),
    );

    // 摘要：只为长片段生成，且失败不阻塞烘焙（音频才是主体）。
    var finalClip = clip;
    final summarizer = _summarizer;
    if (summarizer != null) {
      final summary = await summarizer.summarize(clip);
      if (summary != null && summary.isNotEmpty) {
        finalClip = clip.copyWith(summary: summary);
      }
    }

    // 文稿清单与音频同目录配对
    await File(p.join(_materialDir.path, '$clipId.json')).writeAsString(
      const JsonEncoder.withIndent('  ').convert(finalClip.toJson()),
      flush: true,
    );
    return finalClip;
  }

  /// 合成一轮，失败时重试。
  ///
  /// 端点在批量调用时偶发返回空音频（不抛异常），所以"空结果"也算失败，
  /// 必须重试——否则会产出半截的句子。
  /// 合成一段文本，返回**一个或多个**音频片段。
  ///
  /// 返回多个片段的情况：内容审查拒绝了整段，降级到更细切分后每段单独
  /// 合成（审查是按整段做的，段越小越不容易命中）。调用方把每个片段写成
  /// 独立文件再交给 ffmpeg 拼接——**不能把 mp3 字节直接相加**。
  Future<List<List<int>>?> _synthesizeTurn(
      String text, String voice, String tag) async {
    Object? lastError;
    for (var attempt = 0; attempt <= turnRetries; attempt++) {
      try {
        final bytes = await _engine.synthesize(
          text,
          const TtsSynthesisConfig(
            mode: TtsMode.customAi,
            useSystemAiConfig: true,
          ).copyWith(customVoiceId: voice),
        );
        if (bytes.isNotEmpty) return [bytes];
        lastError = '返回空音频';
      } catch (e) {
        lastError = e;
        // 配额耗尽：重试无用，立即放弃。
        if (_isQuotaExhausted(e)) {
          debugPrint('[ClipBaker] 轮次 "$tag" 配额耗尽，跳过重试: $e');
          return null;
        }
        // 端点的**内容审查**对某些段落会误判（实测：讲 VPN 密码被锁的
        // 一轮话被判 451 censorship_blocked）。审查是按整段文本做的，
        // 拆成更小的段落后往往就过了——所以失败时降级到更细的切分再试。
        if (_isCensorshipRejection(e)) {
          final finer = _splitFiner(text);
          if (finer.length > 1) {
            debugPrint('[ClipBaker] 轮次 "$tag" 被内容审查拒绝，改用更细切分（'
                '${finer.length} 段）重试');
            final parts = <List<int>>[];
            var ok = true;
            for (var i = 0; i < finer.length; i++) {
              final sub = await _synthesizeTurn(finer[i], voice, '${tag}_f$i');
              if (sub == null || sub.isEmpty) {
                ok = false;
                break;
              }
              parts.addAll(sub);
            }
            if (ok) return parts;
            lastError = '内容审查拒绝，细分后仍失败';
          }
        }
      }
      if (attempt < turnRetries) {
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
    debugPrint('[ClipBaker] 轮次 "$tag" 合成失败: $lastError');
    return null;
  }

  /// 判断异常是否是端点的内容审查拒绝（HTTP 451）。
  static bool _isCensorshipRejection(Object error) {
    final text = error.toString();
    return text.contains('451') || text.contains('censorship');
  }

  /// 更细的切分：按词切成小块（比按句子更碎）。
  ///
  /// 用于绕开端点的整段内容审查——审查粒度是整段，段越小越不容易命中。
  static List<String> _splitFiner(String text, {int limit = 120}) {
    if (text.length <= limit) return [text];
    final out = <String>[];
    var chunk = '';
    for (final word in text.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      final candidate = chunk.isEmpty ? word : '$chunk $word';
      if (candidate.length <= limit) {
        chunk = candidate;
      } else {
        if (chunk.isNotEmpty) out.add(chunk);
        chunk = word;
      }
    }
    if (chunk.isNotEmpty) out.add(chunk);
    return out.isEmpty ? [text] : out;
  }

  /// ffmpeg concat 拼接。
  Future<void> _concat(List<String> files, String outputPath) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg == null) {
      throw StateError('未检测到 ffmpeg，无法拼接音频');
    }
    final listFile = File('$outputPath.concat.txt');
    await listFile.writeAsString(
        files.map((f) => "file '${_escapeConcatPath(f)}'").join('\n'));
    try {
      final result = await Process.run(ffmpeg, [
        '-y',
        '-loglevel',
        'error',
        '-f',
        'concat',
        '-safe',
        '0',
        '-i',
        listFile.path,
        '-c',
        'copy',
        outputPath,
      ]);
      if (result.exitCode != 0) {
        throw StateError('ffmpeg 拼接失败: ${result.stderr}');
      }
    } finally {
      if (await listFile.exists()) await listFile.delete();
    }
  }

  static String _escapeConcatPath(String path) =>
      path.replaceAll("'", r"'\''").replaceAll('\n', '');

  /// 探测音频时长（毫秒）。
  Future<int> _probeDurationMs(String filePath) async {
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg != null) {
      final probe = await _resolveFfprobe();
      if (probe != null) {
        final r = await Process.run(probe, [
          '-v',
          'error',
          '-show_entries',
          'format=duration',
          '-of',
          'csv=p=0',
          filePath,
        ]);
        final value = double.tryParse(r.stdout.toString().trim());
        if (value != null && value > 0) return (value * 1000).round();
      }
    }
    // 兜底：按 128kbps 估算
    final file = File(filePath);
    if (await file.exists()) {
      final bytes = await file.length();
      return ((bytes * 8 / 128000) * 1000).round();
    }
    return 0;
  }

  String? _ffmpegPath;
  String? _ffprobePath;

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

  Future<String?> _resolveFfprobe() async {
    if (_ffprobePath != null) return _ffprobePath;
    const candidates = [
      '/usr/local/bin/ffprobe',
      '/opt/homebrew/bin/ffprobe',
      'ffprobe',
    ];
    for (final c in candidates) {
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

  String _titleFor(SourceDialogue dialogue, ClipSegment segment) {
    final note = dialogue.scenarioNote;
    if (note.isNotEmpty) {
      final cleaned = note.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (cleaned.length > 60) {
        return '${cleaned.substring(0, 60)}…';
      }
      return cleaned;
    }
    return '${dialogue.column} #${dialogue.blockIndex}';
  }
}
