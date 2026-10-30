/// 排练会议的语音烘焙器。
///
/// 把剧本逐回合合成、拼接为一条连续整场音频，并把每轮的起止时间回填到剧本里
/// （design D3 / D4）。
///
/// **为什么不复用 [ClipBaker]**：它的切分逻辑（3 分钟上限、尾段合并）是为
/// 1-3 分钟碎片设计的，会把 30 分钟会议切成 10 段——违背"整场"的需求
/// （design D5）。但它的**合成防线**是与端点斗出来的经验，必须照搬：
///
/// | 防线 | 触发条件 | 行为 |
/// |---|---|---|
/// | 空音频重试 | 端点返回 0 字节 | 重试 2 次 |
/// | 内容审查降级 | HTTP 451 censorship_blocked | 切到 120 字碎片重试 |
/// | 配额 fast-fail | HTTP 402 quota_exceeded | 立即放弃，不重试 |
/// | 超长切分 | input > 900 字 | 按句子边界切，单句超长按词硬切 |
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import '../models/listening_models.dart';
import '../models/rehearsal_models.dart';
import 'clip_baker.dart';
import 'rehearsal_voices.dart';
import 'text_sanitizer.dart';

/// 烘焙进度回调：`(已完成轮数, 总轮数, 当前角色)`。
typedef RehearsalBakeProgress = void Function(int done, int total, String role);

/// 讲稿一节的烘焙结果。
class DraftSectionResult {
  /// 节标题。
  final String title;

  /// 节正文（原始文本）。
  final String text;

  /// 音频相对路径（相对素材目录）。失败节为空串。
  final String audioPath;

  /// 该节音频时长（毫秒）。
  final int durationMs;

  /// 是否合成失败。
  final bool failed;

  const DraftSectionResult({
    required this.title,
    required this.text,
    required this.audioPath,
    required this.durationMs,
    required this.failed,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'text': text,
        'audioPath': audioPath,
        'durationMs': durationMs,
        'failed': failed,
      };

  factory DraftSectionResult.fromJson(Map<String, dynamic> json) =>
      DraftSectionResult(
        title: json['title'] as String? ?? '',
        text: json['text'] as String? ?? '',
        audioPath: json['audioPath'] as String? ?? '',
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        failed: (json['failed'] as bool?) ?? false,
      );
}

/// 讲稿烘焙结果（按节，一个音频文件一节）。
class DraftBakeResult {
  /// 来源材料标识。
  final String materialId;

  /// 讲稿标识。
  final String draftId;

  /// Simon 使用的音色（固定）。
  final String voice;

  /// 各节结果（顺序与讲稿一致）。
  final List<DraftSectionResult> sections;

  /// 失败的节下标与原因。
  final Map<int, String> failures;

  const DraftBakeResult({
    this.materialId = '',
    this.draftId = '',
    this.voice = '',
    this.sections = const [],
    this.failures = const {},
  });

  /// 成功合成语音的节数。
  int get bakedCount => sections.where((s) => !s.failed).length;

  /// 讲稿语音总时长（毫秒）。
  int get totalMs => sections.fold<int>(0, (a, s) => a + s.durationMs);

  /// 是否有任何一节成功。
  bool get hasAudio => bakedCount > 0;
}

/// 整场烘焙结果。
class RehearsalBakeResult {
  /// 落盘后的素材（audioPath 为空表示整场失败）。
  final Clip? clip;

  /// 带时间戳的轮次（写回剧本用）。
  final List<ScriptTurn> turns;

  /// 失败的轮次下标与原因。
  final Map<int, String> failures;

  const RehearsalBakeResult({
    this.clip,
    this.turns = const [],
    this.failures = const {},
  });

  bool get hasAudio => clip != null && clip!.audioPath.isNotEmpty;
}

/// 排练会议烘焙器。
class RehearsalBaker {
  /// 单轮重试次数（不含首次）。
  static const int turnRetries = 2;

  /// 送入 TTS 的单轮文本上限（字符）——与 [ClipBaker.maxSynthesisChars] 一致。
  static const int maxSynthesisChars = ClipBaker.maxSynthesisChars;

  final TtsEngine _engine;
  final Directory _materialDir;
  final Directory _cacheDir;

  RehearsalBaker({
    required TtsEngine engine,
    required Directory materialDir,
    required Directory cacheDir,
  })  : _engine = engine,
        _materialDir = materialDir,
        _cacheDir = cacheDir;

  /// 烘焙一场会议。
  ///
  /// [script] 里的轮次会被打上时间戳与失败标记后随结果返回（调用方负责写回
  /// 磁盘）。单轮失败不毁整场：失败的轮次在音频里留一段静音占位，其余轮次
  /// 照常拼接——用户听到的是"某个人没说话"，而不是"会议断了"。
  Future<RehearsalBakeResult> bake(
    MeetingScript script, {
    RehearsalBakeProgress? onProgress,
    String? clipId,
  }) async {
    if (script.turns.isEmpty) {
      return const RehearsalBakeResult();
    }
    await _materialDir.create(recursive: true);
    await _cacheDir.create(recursive: true);

    final id = clipId ?? _clipIdFor(script);
    final turnFiles = <String>[];
    final turns = <ScriptTurn>[];
    final failures = <int, String>{};
    // 每轮对应的音频文件数（合成时记录，回填时间戳时按它切分 turnFiles）。
    final turnFileCounts = <int>[];

    for (var i = 0; i < script.turns.length; i++) {
      final turn = script.turns[i];
      onProgress?.call(i, script.turns.length, turn.role.speaker);

      final voice = RehearsalVoices.voiceFor(turn.role.id);
      final text = sanitizeForSynthesis(turn.text);
      if (text.isEmpty) {
        failures[i] = '台词为空';
        turns.add(turn.copyWith(failed: true));
        continue;
      }

      final files = <String>[];
      for (final part in ClipBaker.splitLongTurn(text)) {
        final segs = await _synthesize(part, voice, '${id}_t$i');
        if (segs == null) {
          failures[i] = '合成失败';
          break;
        }
        for (final seg in segs) {
          final f = File(p.join(
              _cacheDir.path, '${id}_t${i}_s${files.length}.mp3'));
          await f.writeAsBytes(seg, flush: true);
          files.add(f.path);
        }
      }

      // 静音占位：失败轮次也占用时间轴，后续轮次的 startMs 才与音频对得上。
      if (failures.containsKey(i)) {
        files.add(await _writeSilence('${id}_t${i}_gap.mp3', 1200));
      }
      if (files.isEmpty) {
        turns.add(turn.copyWith(failed: true));
        continue;
      }
      turnFiles.addAll(files);
      // 每轮的音频文件下标区间——回填时间戳时按它取时长，**不靠文件名猜**
      // （猜错会让某一轮吃掉下一轮的音频，按回合定位整体错位）。
      turnFileCounts.add(files.length);
      turns.add(failures.containsKey(i) ? turn.copyWith(failed: true) : turn);
    }

    onProgress?.call(script.turns.length, script.turns.length, '');

    // 全部轮次都失败时**不产出素材**：一条纯静音的 mp3 进了索引，用户点开会
    // 以为会议生成好了。失败信息已经在 [failures] 里，交给界面提示重试。
    if (turnFiles.isEmpty || failures.length == turns.length) {
      return RehearsalBakeResult(turns: turns, failures: failures);
    }

    final audioPath = '$id.mp3';
    await _concat(turnFiles, p.join(_materialDir.path, audioPath));

    // 各轮起止时间由实际音频时长累加得出。
    //
    // 用合成时记下的 [turnFileCounts] 切分文件列表，而不是从文件名反推轮次——
    // 反推在"某轮超长被切成多段"和"某轮失败带静音占位"两种情况下都会错位。
    final withTimes = <ScriptTurn>[];
    var cursor = 0;
    var fileIndex = 0;
    for (var i = 0; i < turns.length; i++) {
      final count = i < turnFileCounts.length ? turnFileCounts[i] : 0;
      var ms = 0;
      for (var k = 0; k < count && fileIndex < turnFiles.length; k++) {
        ms += await _probeDurationMs(turnFiles[fileIndex]);
        fileIndex++;
      }
      withTimes.add(turns[i].copyWith(startMs: cursor, endMs: cursor + ms));
      cursor += ms;
    }

    final clip = Clip(
      id: id,
      scene: MeetingScene.rehearsal,
      title: script.title,
      audioPath: audioPath,
      durationMs: cursor,
      turns: [
        for (final t in withTimes)
          SpeakerTurn(
            speaker: t.role.speaker,
            role: t.role.note,
            rawText: t.text,
            synthesisText: sanitizeForSynthesis(t.text),
            voice: RehearsalVoices.voiceFor(t.role.id),
            startMs: t.startMs,
            endMs: t.endMs,
          ),
      ],
      source: ClipSource(
        sourceId: 'rehearsal',
        site: '排练会议',
        pageUrl: '',
        column: script.title,
        license: '本地生成',
      ),
      summary: '${script.turns.length} 轮 · ${withTimes.length} 个角色发言 · '
          '目标 ${script.targetMinutes} 分钟',
    );

    return RehearsalBakeResult(clip: clip, turns: withTimes, failures: failures);
  }

  /// 烘焙讲稿语音：按节合成，Simon 固定音色。
  ///
  /// 与会议剧本分开成两个入口而不是塞进 [bake]：讲稿是单人口述（一个音色、
  /// 按节分文件），会议是五人对话（五音色、按轮分文件、要拼成一整条）。两者的
  /// 产物形态不同，硬合到一个方法里只会多出一堆 if 分支。
  ///
  /// 每节一个音频文件（不拼成一整条）：用户要"按节试听"，独立文件点哪节听哪节，
  /// 不需要 seek。起止时间仍然累加记录——界面按进度高亮当前节。
  Future<DraftBakeResult> bakeDraft(
    SpeechDraft draft, {
    RehearsalBakeProgress? onProgress,
    String? clipId,
  }) async {
    if (draft.sections.isEmpty) {
      return const DraftBakeResult();
    }
    await _materialDir.create(recursive: true);
    await _cacheDir.create(recursive: true);

    final id = clipId ?? 'draft_${draft.materialId}';
    final voice = RehearsalVoices.voiceFor('simon');
    final sections = <DraftSectionResult>[];
    final failures = <int, String>{};

    for (var i = 0; i < draft.sections.length; i++) {
      final section = draft.sections[i];
      onProgress?.call(i, draft.sections.length, 'Simon');

      final text = sanitizeForSynthesis(section.body);
      if (text.isEmpty) {
        failures[i] = '该节正文为空';
        sections.add(DraftSectionResult(
          title: section.title,
          text: section.body,
          audioPath: '',
          durationMs: 0,
          failed: true,
        ));
        continue;
      }

      // 一节的音频可能是多个文件（超长切分 / 审查降级）——按节拼成一条。
      final files = <String>[];
      for (final part in ClipBaker.splitLongTurn(text)) {
        final segs = await _synthesize(part, voice, '${id}_s$i');
        if (segs == null) {
          failures[i] = '合成失败';
          break;
        }
        for (final seg in segs) {
          final f = File(p.join(
              _cacheDir.path, '${id}_s${i}_p${files.length}.mp3'));
          await f.writeAsBytes(seg, flush: true);
          files.add(f.path);
        }
      }

      if (files.isEmpty) {
        sections.add(DraftSectionResult(
          title: section.title,
          text: section.body,
          audioPath: '',
          durationMs: 0,
          failed: true,
        ));
        continue;
      }

      final audioPath = '${id}_s$i.mp3';
      await _concat(files, p.join(_materialDir.path, audioPath));
      var ms = 0;
      for (final f in files) {
        ms += await _probeDurationMs(f);
      }
      sections.add(DraftSectionResult(
        title: section.title,
        text: section.body,
        audioPath: audioPath,
        durationMs: ms,
        failed: false,
      ));
    }

    onProgress?.call(draft.sections.length, draft.sections.length, '');

    return DraftBakeResult(
      materialId: draft.materialId,
      draftId: draft.id,
      voice: voice,
      sections: sections,
      failures: failures,
    );
  }

  /// 素材 id：`rehearsal_<materialId>`。
  ///
  /// 带 `rehearsal_` 前缀与来源标识，与 CoderSlingo 的
  /// `{sourceId}_{scene}_{column}_{block}` 形态区分开，不会撞 id。
  static String clipIdForMaterialId(String materialId) =>
      RehearsalStatusInfo.clipIdFor(materialId);

  static String _clipIdFor(MeetingScript script) =>
      clipIdForMaterialId(script.materialId);

  /// 合成一段文本，失败时重试（防线与 [ClipBaker] 一致）。
  ///
  /// 返回多个片段的情况：内容审查拒绝了整段，降级到更细切分后每段单独合成。
  Future<List<List<int>>?> _synthesize(
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
        if (_isQuotaExhausted(e)) {
          debugPrint('[RehearsalBaker] "$tag" 配额耗尽，跳过重试: $e');
          return null;
        }
        if (_isCensorshipRejection(e)) {
          final finer = _splitFiner(text);
          if (finer.length > 1) {
            debugPrint('[RehearsalBaker] "$tag" 被内容审查拒绝，改用更细切分重试');
            final parts = <List<int>>[];
            var ok = true;
            for (var i = 0; i < finer.length; i++) {
              final sub = await _synthesize(finer[i], voice, '${tag}_f$i');
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
    debugPrint('[RehearsalBaker] "$tag" 合成失败: $lastError');
    return null;
  }

  static bool _isQuotaExhausted(Object error) {
    final text = error.toString();
    return text.contains('402') ||
        text.contains('quota_exceeded') ||
        text.contains('quota exceeded');
  }

  static bool _isCensorshipRejection(Object error) {
    final text = error.toString();
    return text.contains('451') || text.contains('censorship');
  }

  /// 更细的切分：按词切成小块（比按句子更碎），用于绕开整段内容审查。
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

  /// 生成一段静音 mp3（失败轮次的时间轴占位）。
  ///
  /// 没有静音占位的话，失败轮次之后的所有轮次 startMs 都会前移，用户点第 N 轮
  /// 会跳到错误的音频位置——按回合定位是整个功能的入口，不能错。
  Future<String> _writeSilence(String name, int ms) async {
    final file = File(p.join(_cacheDir.path, name));
    final ffmpeg = await _resolveFfmpeg();
    if (ffmpeg != null) {
      final r = await Process.run(ffmpeg, [
        '-y',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        'anullsrc=r=24000:cl=mono',
        '-t',
        '${ms / 1000}',
        '-q:a',
        '9',
        file.path,
      ]);
      if (r.exitCode == 0) return file.path;
    }
    // ffmpeg 缺失时退回写一个空文件：探测会按 128kbps 估出接近 0 的时长，
    // 定位有小偏差但不会崩。
    await file.writeAsBytes(const [], flush: true);
    return file.path;
  }

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

  Future<int> _probeDurationMs(String filePath) async {
    final ffmpeg = await _resolveFfmpeg();
    final probe = ffmpeg == null ? null : await _resolveFfprobe();
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
}
