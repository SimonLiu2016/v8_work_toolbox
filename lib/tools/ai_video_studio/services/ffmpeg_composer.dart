/// FFmpeg 封装：可用性探测、原生命令、成片合成。
///
/// 设计要点（design.md D5）：
/// - **不内置打包 FFmpeg**。静态编译包约 80-100 MB，而绝大多数创作者机器上
///   已有 FFmpeg；所以这里只探测本机已安装的二进制，探测路径覆盖 Homebrew
///   的 Intel/Apple Silicon 两个前缀。
/// - **GUI 应用的 PATH 不可信**。Flutter 打包后的进程 PATH 通常只有
///   `/usr/bin:/bin`，直接用裸名 `ffmpeg` 会稳定 "command not found"，而错误
///   信息读起来像"没装"。所以先按清单找绝对路径，找不到再回落裸名，让上层
///   拿到的是真实的可用性结论。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// FFmpeg 可用性探测结果。
class FfmpegStatus {
  final bool available;

  /// 解析到的绝对路径（不可用时为 null）。
  final String? path;

  /// 版本号（从 `ffmpeg -version` 首行解析，如 `7.1.1`）。
  final String? version;

  final String? error;

  const FfmpegStatus({
    required this.available,
    this.path,
    this.version,
    this.error,
  });

  const FfmpegStatus.unavailable(String message)
    : available = false,
      path = null,
      version = null,
      error = message;
}

/// 合成参数：一集的所有素材与开关。
class ComposeRequest {
  /// 分镜视频片段，按分镜顺序排列。
  final List<File> clips;

  /// 台词音频轨（可为空）。
  final List<File> dialogueAudios;

  /// BGM 文件（可为空）。
  final File? bgm;

  /// SRT 字幕文件（可为空）。
  final File? subtitle;

  /// 是否在片段之间加 dissolve 转场（spec 默认开，可关）。
  final bool useDissolve;

  /// Ducking 降音量（dB）。台词时段 BGM 降到这个量。
  final double duckingDb;

  /// 输出文件（.mp4）。
  final File outputFile;

  /// 目标总时长（秒），用于进度百分比计算。
  final double durationSec;

  /// 每段台词音频对应的分镜时长（秒），与 [dialogueAudios] 一一对应。
  ///
  /// 空列表表示不归一化（旧行为）。传入后每段台词会被 `apad` + `atrim` 到
  /// 对应分镜时长——TTS 念白往往短于分镜时长，不补齐的话后续片段一拼，
  /// 台词全会往前挪，字幕与口型全错位（spec: 台词音频按分镜游标落位）。
  final List<double> dialogueTargetDurations;

  const ComposeRequest({
    required this.clips,
    this.dialogueAudios = const [],
    this.bgm,
    this.subtitle,
    this.useDissolve = true,
    this.duckingDb = 10,
    required this.outputFile,
    required this.durationSec,
    this.dialogueTargetDurations = const [],
  });
}

/// FFmpeg 进程执行结果。
class FfmpegRunResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool cancelled;

  const FfmpegRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.cancelled = false,
  });

  bool get success => !cancelled && exitCode == 0;
}

/// 一条 SRT 字幕。
class SrtEntry {
  final double start;
  final double end;
  final String text;

  const SrtEntry({
    required this.start,
    required this.end,
    required this.text,
  });
}

abstract final class FfmpegComposer {
  static final List<String> _candidatePaths = [
    '/opt/homebrew/bin/ffmpeg',
    '/usr/local/bin/ffmpeg',
    '/usr/bin/ffmpeg',
    '/opt/local/bin/ffmpeg',
  ];

  static String? _cachedPath;
  static String? _cachedVersion;

  /// 探测本机 FFmpeg。
  ///
  /// 结果缓存：一次探测要起一个进程，而 FFmpeg 不会在会话中途凭白消失。
  /// UI 上"重新检测"按钮通过 [invalidateCache] 强制重查。
  static Future<FfmpegStatus> checkAvailability({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedPath != null) {
      return FfmpegStatus(
        available: true,
        path: _cachedPath,
        version: _cachedVersion,
      );
    }

    for (final candidate in _candidatePaths) {
      if (File(candidate).existsSync()) {
        final version = await _probeVersion(candidate);
        _cachedPath = candidate;
        _cachedVersion = version;
        return FfmpegStatus(
          available: true,
          path: candidate,
          version: version,
        );
      }
    }

    // 清单里没有时再试 PATH：用户可能装在别处（nix、asdf、conda）。
    try {
      final result = await Process.run('ffmpeg', [
        '-version',
      ], workingDirectory: Directory.systemTemp.path);
      if (result.exitCode == 0) {
        _cachedPath = 'ffmpeg';
        _cachedVersion = _parseVersion(result.stdout.toString());
        return FfmpegStatus(
          available: true,
          path: 'ffmpeg',
          version: _cachedVersion,
        );
      }
    } catch (_) {
      // 不在 PATH 上，落到下方统一报错。
    }

    return const FfmpegStatus.unavailable(
      '未在本机检测到 FFmpeg。请通过 Homebrew 安装：brew install ffmpeg',
    );
  }

  /// 安装引导命令（UI 横幅一键复制用）。
  static const String installCommand = 'brew install ffmpeg';

  /// 清除探测缓存。
  static void invalidateCache() {
    _cachedPath = null;
    _cachedVersion = null;
  }

  static Future<String?> _probeVersion(String executable) async {
    try {
      final result = await Process.run(executable, [
        '-version',
      ], workingDirectory: Directory.systemTemp.path);
      if (result.exitCode == 0) {
        return _parseVersion(result.stdout.toString());
      }
    } catch (_) {}
    return null;
  }

  static String? _parseVersion(String output) {
    final match = RegExp(r'ffmpeg version (\S+)').firstMatch(output);
    return match?.group(1);
  }

  /// 原样执行一条 FFmpeg 命令（Ken Burns 等子动作用）。
  static Future<FfmpegRunResult> runRaw({
    required List<String> args,
    void Function(String line)? onStderrLine,
    void Function(String line)? onStdoutLine,
    Duration? timeout,
  }) async {
    final executable = _cachedPath ??= (await checkAvailability()).path;
    if (executable == null) {
      return const FfmpegRunResult(
        exitCode: -1,
        stdout: '',
        stderr: 'FFmpeg 不可用',
      );
    }

    final started = await Process.start(
      executable,
      args,
      workingDirectory: Directory.systemTemp.path,
      includeParentEnvironment: true,
    );

    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    final stdoutDone = started.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stdoutBuf.writeln(line);
          onStdoutLine?.call(line);
        })
        .asFuture<void>();
    final stderrDone = started.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrBuf.writeln(line);
          onStderrLine?.call(line);
        })
        .asFuture<void>();

    var timedOut = false;
    final exitCode = await started.exitCode.timeout(
      timeout ?? const Duration(minutes: 10),
      onTimeout: () {
        timedOut = true;
        started.kill(ProcessSignal.sigkill);
        return -1;
      },
    );

    // **必须先等流结束再返回。** 进程退出时 stdout/stderr 管道里可能还有未读完
    // 的缓冲；直接返回会让调用方读到截断的输出，也会让后续对同一目录的清理
    // 与文件读取撞上「进程已退但内容未完」的窗口。
    //
    // 这里不能用 `Future.wait(...).timeout()` 那种写法：`.asFuture()` 只在流
    // **正常关闭**时才完成，而超时信号里 kill 掉的进程可能让管道永不关闭——
    // 那样整个 wait 会挂住，表现就是调用方无限期等待。所以改成手动 await
    // 流各自的 done，并给总的等待加一个硬上限。
    if (!timedOut) {
      await Future.wait([stdoutDone, stderrDone]).timeout(
        const Duration(seconds: 30),
        onTimeout: () => <void>[],
      );
    }

    return FfmpegRunResult(
      exitCode: timedOut ? -1 : exitCode,
      stdout: stdoutBuf.toString(),
      stderr: stderrBuf.toString(),
    );
  }

  // ---------------------------------------------------------------------------
  // 进度解析
  // ---------------------------------------------------------------------------

  /// 从 stderr 的一行里解析进度百分比。
  ///
  /// FFmpeg 的进度行长这样：
  /// `frame= 150 fps= 30 q=28.0 size=    1024kB time=00:00:05.00 bitrate=...`
  /// `time=` 是当前编码到的时间点。返回 null 表示这行没有进度信息（版本信息、
  /// Stream mapping 等），调用方据此忽略。
  static double? parseProgress({
    required String line,
    required double durationSec,
  }) {
    if (durationSec <= 0) return null;
    final match = RegExp(r'time=(\d+):(\d+):(\d+)\.(\d+)').firstMatch(line);
    if (match == null) return null;
    // 毫秒可能是 `00`（两位不到）也可能是 `00`，FFmpeg 有时只输出两位小数；
    // 按十进制小数补足，别用 int.parse 拼字符串。
    final fraction = match.group(4)!.padRight(3, '0');
    final seconds =
        int.parse(match.group(1)!) * 3600 +
        int.parse(match.group(2)!) * 60 +
        int.parse(match.group(3)!) +
        int.parse(fraction) / 1000;
    if (seconds <= 0) return null;
    final progress = seconds / durationSec;
    return progress.clamp(0.0, 1.0);
  }

  // ---------------------------------------------------------------------------
  // Ducking
  // ---------------------------------------------------------------------------

  /// 把 `[[start, end], ...]`（秒）列表转成 FFmpeg volume 滤镜的时间段参数。
  ///
  /// `volume` 的 `enable` 表达式写法是
  /// `between(t,a,b)+between(t,c,d)+...`——每加一个区间就是一个 `between`，
  /// 全部相加即"落在任一时间段内"为真。
  static String buildDuckingEnableExpr(List<List<double>> ranges) {
    if (ranges.isEmpty) return '0';
    final parts = ranges.map((r) {
      final start = r[0].clamp(0, double.infinity);
      final end = r[1];
      // 末尾留 100ms 呼吸，防止台词刚结束 BGM 立刻弹回造成的突兀感。
      return 'between(t,${start.toStringAsFixed(3)},${(end + 0.1).toStringAsFixed(3)})';
    });
    return parts.join('+');
  }

  /// 解析 SRT 为带文本的区间列表。
  ///
  /// 剪映字幕轨要文本，Ducking 只要数字——两者共用同一个解析实现，避免
  /// 两处正则各自漂移后字幕和压混时段对不上。
  static List<SrtEntry> parseSrt(String srtText) {
    final entries = <SrtEntry>[];
    final blocks = srtText.split(RegExp(r'\r?\n\r?\n'));
    for (final block in blocks) {
      final lines =
          block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.length < 2) continue;
      final timeline = lines[1].trim();
      if (!timeline.contains('-->')) continue;
      final parts = timeline.split('-->');
      if (parts.length != 2) continue;
      final start = parseSrtTimestamp(parts[0]);
      final end = parseSrtTimestamp(parts[1]);
      if (start == null || end == null) continue;
      final text = lines.skip(2).join('\n').trim();
      entries.add(SrtEntry(start: start, end: end, text: text));
    }
    return entries;
  }

  /// 由 SRT 时间轴计算 Ducking 区间（台词起止时间对）。
  ///
  /// spec 要求台词时段 BGM 降 8-14 dB；这里默认 10 dB，落在区间中段——
  /// 低了听不清台词，高了 BGM 像被切断。
  static List<List<double>> duckingRangesFromSrt(String srtText) {
    return parseSrt(srtText)
        .map((e) => <double>[e.start, e.end])
        .toList();
  }

  /// 解析 SRT 时间戳 `HH:MM:SS,mmm` → 秒。
  static double? parseSrtTimestamp(String value) {
    final match = RegExp(
      r'(\d+):(\d+):(\d+)[,.](\d+)',
    ).firstMatch(value.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) * 3600 +
        int.parse(match.group(2)!) * 60 +
        int.parse(match.group(3)!) +
        int.parse(match.group(4)!.padRight(3, '0')) / 1000;
  }

  // ---------------------------------------------------------------------------
  // 成片合成
  // ---------------------------------------------------------------------------

  /// 合成一集 MP4：拼接片段 + 混音 + Ducking + 字幕。
  ///
  /// 实现分三段，而不是一条巨型 filter_complex：
  /// 1. **拼接**。有转场用 xfade 链，无转场用 concat demuxer（后者不需要
  ///    重编码视频流，快一个数量级）。
  /// 2. **混音**。台词与 BGM 用 amix 混合，BGM 那一路先按 Ducking 区间压。
  /// 3. **字幕**。subtitles 滤镜把 SRT 烧进画面。
  ///
  /// 分段是为了每步的失败能精确定位：拼接失败不会和混音失败混成一句
  /// "FFmpeg 报错"。
  static Future<FfmpegRunResult> compose(
    ComposeRequest request, {
    void Function(double progress)? onProgress,
  }) async {
    final status = await checkAvailability();
    if (!status.available) {
      return FfmpegRunResult(
        exitCode: -1,
        stdout: '',
        stderr: status.error ?? 'FFmpeg 不可用',
      );
    }
    if (request.clips.isEmpty) {
      return const FfmpegRunResult(
        exitCode: -1,
        stdout: '',
        stderr: '没有可合成的视频片段',
      );
    }

    await request.outputFile.parent.create(recursive: true);

    // --- 1. 拼接 -----------------------------------------------------------
    final concatFile = File('${request.outputFile.path}.concat.mp4');
    final concatResult = request.useDissolve && request.clips.length > 1
        ? await _composeWithDissolve(
            clips: request.clips,
            outputFile: concatFile,
            durationSec: request.durationSec,
            onProgress: onProgress,
          )
        : await _composeConcat(
            clips: request.clips,
            outputFile: concatFile,
            durationSec: request.durationSec,
            onProgress: onProgress,
          );
    if (!concatResult.success) return concatResult;

    // --- 2. 混音 -----------------------------------------------------------
    final hasDialogue = request.dialogueAudios.isNotEmpty;
    final hasBgm = request.bgm != null && request.bgm!.existsSync();
    File? mixedAudio;
    if (hasDialogue && hasBgm) {
      final srtFile = request.subtitle;
      final duckingRanges = srtFile != null && srtFile.existsSync()
          ? duckingRangesFromSrt(srtFile.readAsStringSync())
          : <List<double>>[];
      mixedAudio = await _mixAudio(
        dialogues: request.dialogueAudios,
        bgm: request.bgm!,
        outputFile: File('${request.outputFile.path}.mixed.m4a'),
        duckingRanges: duckingRanges,
        duckingDb: request.duckingDb,
        targetDurations: request.dialogueTargetDurations,
      );
    } else if (hasDialogue) {
      mixedAudio = await _concatAudio(
        audios: request.dialogueAudios,
        outputFile: File('${request.outputFile.path}.dialogue.m4a'),
        targetDurations: request.dialogueTargetDurations,
      );
    }

    // --- 3. 成品 -----------------------------------------------------------
    // 字幕在最后一段烧进去：烧进成品而不是拼接产物，能与最终音轨一起核对。
    final srtFile = (request.subtitle != null && request.subtitle!.existsSync())
        ? request.subtitle
        : null;

    final args = <String>[
      '-y',
      '-i', concatFile.path,
      if (mixedAudio != null) ...['-i', mixedAudio.path],
      if (srtFile != null) ...[
        // 字幕文件名里的 `:` 和 `,` 会破坏 filter 语法，须转义。
        '-vf', "subtitles='${_escapeSubtitlePath(srtFile.path)}'",
      ],
      '-c:v', 'libx264',
      '-preset', 'medium',
      '-crf', '20',
      '-pix_fmt', 'yuv420p',
      '-r', '30',
      if (mixedAudio != null) ...[
        '-map', '0:v:0',
        '-map', '1:a:0',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-shortest',
      ],
      '-movflags', '+faststart',
      request.outputFile.path,
    ];

    final finalResult = await runRaw(
      args: args,
      onStderrLine: (line) {
        final progress = parseProgress(
          line: line,
          durationSec: request.durationSec,
        );
        if (progress != null) onProgress?.call(progress);
      },
    );

    // 中间产物清掉：留着用户会在 Finder 里看到一堆不知道能不能删的文件。
    await _deleteQuietly(concatFile);
    if (mixedAudio != null) await _deleteQuietly(mixedAudio);

    return finalResult;
  }

  /// 无转场：concat demuxer + 流拷贝（视频不重编码）。
  static Future<FfmpegRunResult> _composeConcat({
    required List<File> clips,
    required File outputFile,
    required double durationSec,
    void Function(double)? onProgress,
  }) async {
    final listFile = File('${outputFile.path}.txt');
    final buffer = StringBuffer();
    for (final clip in clips) {
      buffer.writeln("file '${clip.path.replaceAll("'", "'\\''")}'");
    }
    await listFile.writeAsString(buffer.toString(), flush: true);

    final result = await runRaw(
      args: [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c', 'copy',
        outputFile.path,
      ],
      onStderrLine: (line) {
        final progress = parseProgress(line: line, durationSec: durationSec);
        if (progress != null) onProgress?.call(progress);
      },
    );
    await _deleteQuietly(listFile);
    return result;
  }

  /// 有转场：xfade 链。相邻片段重叠 0.4 秒做淡入淡出。
  ///
  /// xfade 要求两路输入的帧率与分辨率一致，所以在链首统一 scale + fps；
  /// 不一致时 FFmpeg 报的是 "First input link ... parameters do not match"，
  /// 这种错误信息对用户毫无意义，所以直接在源头消掉它。
  static Future<FfmpegRunResult> _composeWithDissolve({
    required List<File> clips,
    required File outputFile,
    required double durationSec,
    void Function(double)? onProgress,
  }) async {
    final transition = 0.4;
    final normalized = <File>[];
    for (var i = 0; i < clips.length; i++) {
      // concat demuxer 的拷贝产物不能直接进 xfade 链（时间戳可能不连续），
      // 逐个片段先重编码到统一参数最稳。
      final target = File('${outputFile.parent.path}/_norm_$i.mp4');
      final normed = await runRaw(
        args: [
          '-y',
          '-i', clips[i].path,
          '-vf', 'scale=1080:1920:force_original_aspect_ratio=decrease,'
              'pad=1080:1920:(ow-iw)/2:(oh-ih)/2,fps=30',
          '-c:v', 'libx264',
          '-preset', 'veryfast',
          '-crf', '23',
          '-pix_fmt', 'yuv420p',
          target.path,
        ],
      );
      if (!normed.success) {
        for (final f in normalized) {
          await _deleteQuietly(f);
        }
        return normed;
      }
      normalized.add(target);
    }

    final args = <String>['-y'];
    for (final f in normalized) {
      args.addAll(['-i', f.path]);
    }
    // xfade 链：每加一段，偏移量是「已拼长度 - transition」。
    final filters = <String>[];
    var offset = 0.0;
    var label = '[0:v]';
    for (var i = 1; i < normalized.length; i++) {
      offset += durationSec / normalized.length - transition;
      final nextLabel = i == normalized.length - 1 ? '[vout]' : '[x$i]';
      filters.add(
        '$label[$i:v]xfade=transition=fade:'
        'duration=$transition:offset=${offset.toStringAsFixed(3)}$nextLabel',
      );
      label = nextLabel;
    }
    args.addAll([
      '-filter_complex', filters.join(';'),
      '-map', '[vout]',
      '-c:v', 'libx264',
      '-preset', 'medium',
      '-crf', '20',
      '-pix_fmt', 'yuv420p',
      outputFile.path,
    ]);

    final result = await runRaw(
      args: args,
      onStderrLine: (line) {
        final progress = parseProgress(line: line, durationSec: durationSec);
        if (progress != null) onProgress?.call(progress);
      },
    );
    for (final f in normalized) {
      await _deleteQuietly(f);
    }
    return result;
  }

  /// 台词与 BGM 混音，BGM 按 Ducking 区间降压。
  static Future<File> _mixAudio({
    required List<File> dialogues,
    required File bgm,
    required File outputFile,
    required List<List<double>> duckingRanges,
    required double duckingDb,
    List<double> targetDurations = const [],
  }) async {
    final dialogueTrack = await _concatAudio(
      audios: dialogues,
      outputFile: File('${outputFile.path}.dialogue.m4a'),
      targetDurations: targetDurations,
    );
    if (!await dialogueTrack.exists()) {
      return dialogueTrack;
    }

    // BGM 先循环到与台词等长再压音量。用 -stream_loop -1 而不是 aloop 滤镜：
    // 前者在输入侧循环，输出时长由 -shortest 决定，参数更直观。
    final duckingExpr = buildDuckingEnableExpr(duckingRanges);
    final bgmVolume =
        duckingRanges.isEmpty ? 1.0 : null; // 无台词区间时无需压
    final args = <String>[
      '-y',
      '-i', dialogueTrack.path,
      '-stream_loop', '-1',
      '-i', bgm.path,
      '-filter_complex',
      bgmVolume != null
          ? '[0:a][1:a]amix=inputs=2:duration=first:dropout_transition=0[aout]'
          : '[1:a]volume='
                '${(-duckingDb).toStringAsFixed(1)}dB:'
                "enable='$duckingExpr'[bgm];"
                '[0:a][bgm]amix=inputs=2:duration=first:'
                'dropout_transition=0[aout]',
      '-map', '[aout]',
      '-c:a', 'aac',
      '-b:a', '192k',
      outputFile.path,
    ];

    final result = await runRaw(args: args);
    await _deleteQuietly(dialogueTrack);
    if (!result.success) {
      // 混音失败不该让整集白合成：退回只用台词轨。
      return dialogueTrack;
    }
    await _deleteQuietly(dialogueTrack);
    return outputFile;
  }

  /// 拼接台词音频（逐段对齐分镜时长）。
  ///
  /// 每段台词都 `apad` + `atrim` 到该分镜的目标时长——TTS 实际念白往往短于
  /// 分镜时长，不补齐的话后续片段一拼，台词全会往前挪，字幕与口型全错位。
  ///
  /// 有 [targetDurations] 时走滤镜路径：concat demuxer 的 `duration` 指令只写
  /// 元数据、不改实际采样，长度归一必须在滤镜层做。没有则退回 demuxer 流拷贝
  /// （旧行为，也更快）。
  static Future<File> _concatAudio({
    required List<File> audios,
    required File outputFile,
    List<double>? targetDurations,
  }) async {
    final hasTargets = targetDurations != null &&
        targetDurations.length == audios.length &&
        audios.length > 1;

    if (hasTargets) {
      return _concatAudioNormalized(
        audios: audios,
        outputFile: outputFile,
        targetDurations: targetDurations,
      );
    }

    final listFile = File('${outputFile.path}.txt');
    final buffer = StringBuffer();
    for (var i = 0; i < audios.length; i++) {
      final path = audios[i].path.replaceAll("'", "'\\''");
      buffer.writeln("file '$path'");
    }
    await listFile.writeAsString(buffer.toString(), flush: true);
    final result = await runRaw(
      args: [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', listFile.path,
        '-c:a', 'aac',
        '-b:a', '192k',
        outputFile.path,
      ],
    );
    await _deleteQuietly(listFile);
    if (!result.success) {
      // 拼接失败时退回第一段，至少成品有声音。
      if (audios.isNotEmpty && await audios.first.exists()) {
        return audios.first;
      }
    }
    return outputFile;
  }

  /// 滤镜路径：逐段 `apad` 补静音 + `atrim` 裁到目标时长，再 `concatn` 拼接。
  ///
  /// 与 [StudioSrtWriter] 的游标模型（`cursorMs += holdMs`）天然对齐：每段
  /// 自包含到目标长度，concat 后第 N 段的起点就是前 N-1 段时长之和。用
  /// `adelay` 反而要手算每段的绝对偏移，段数一变全部重算。
  static Future<File> _concatAudioNormalized({
    required List<File> audios,
    required File outputFile,
    required List<double> targetDurations,
  }) async {
    final inputs = <String>[];
    final filters = <String>[];
    final labels = <String>[];
    for (var i = 0; i < audios.length; i++) {
      inputs.addAll(['-i', audios[i].path]);
      final target = targetDurations[i] > 0 ? targetDurations[i] : 0.0;
      final label = 'a$i';
      labels.add('[$label]');
      // apad 把短于目标的段补上静音；atrim 再把超过目标的段裁掉。
      // whole_dur 参数直接给目标秒数，不必先探测原时长。
      filters.add(
        '[$i:a]apad=whole_dur=$target,atrim=0:$target,asetpts=N/SR/TB[$label]',
      );
    }
    filters.add('${labels.join('')}concat=n=${audios.length}:v=0:a=1[out]');

    final result = await runRaw(
      args: [
        '-y',
        ...inputs,
        '-filter_complex', filters.join(';'),
        '-map', '[out]',
        '-c:a', 'aac',
        '-b:a', '192k',
        outputFile.path,
      ],
    );
    if (!result.success) {
      // 滤镜拼接失败不该让整集白合成：退回 demuxer 直拼（旧行为），
      // 最坏情况是音频前移，但至少有声音。
      final fallback = await _concatAudio(
        audios: audios,
        outputFile: outputFile,
        targetDurations: null,
      );
      return fallback;
    }
    return outputFile;
  }

  /// 从文件路径提取基名（导出器复用）。
  static String basenameOf(String path) => p.basename(path);

  /// 转义 subtitles 滤镜里的路径分隔符。
  static String _escapeSubtitlePath(String path) {
    return path
        .replaceAll('\\', '\\\\')
        .replaceAll(':', '\\:')
        .replaceAll("'", "\\'");
  }

  /// 从视频中抽取最后一帧作为静态图像。
  ///
  /// 用于首尾帧接力：将前一个镜头的末尾帧抽取出来，作为下一个同场景镜头的首帧
  /// [first_frame]，确保镜头切接时的画面空间与角色状态无缝连续。
  static Future<File?> extractLastFrame({
    required File videoFile,
    required File outputFile,
  }) async {
    if (!await videoFile.exists()) return null;
    await outputFile.parent.create(recursive: true);
    final result = await runRaw(
      args: [
        '-y',
        '-sseof', '-0.1',
        '-i', videoFile.path,
        '-frames:v', '1',
        '-q:v', '2',
        outputFile.path,
      ],
    );
    if (result.success && await outputFile.exists()) {
      return outputFile;
    }
    // 若 -sseof -0.1 失败，尝试倒数一秒抽帧
    final fallback = await runRaw(
      args: [
        '-y',
        '-sseof', '-1',
        '-i', videoFile.path,
        '-update', '1',
        '-q:v', '2',
        outputFile.path,
      ],
    );
    if (fallback.success && await outputFile.exists()) {
      return outputFile;
    }
    return null;
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 中间产物清理失败不影响合成结果，不向上抛。
    }
  }
}
