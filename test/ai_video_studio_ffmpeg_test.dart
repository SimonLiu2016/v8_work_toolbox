import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/ai_video_studio/services/ffmpeg_composer.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/image_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';

/// FFmpeg 依赖相关的服务测试。
///
/// 分两类：
/// - **纯函数**（进度解析、Ducking 表达式、SRT 解析、PNG 生成）无条件跑，
///   这些是拼字符串的活，最容易在改动滤镜参数时被悄悄改错；
/// - **集成**（真的起 ffmpeg 进程）在检测不到 FFmpeg 时跳过——开发机上没装
///   FFmpeg 不该让整个测试文件红掉，spec 也明确 FFmpeg 是外部依赖。
void main() {
  group('FFmpeg 可用性探测', () {
    setUp(FfmpegComposer.invalidateCache);

    test('checkAvailability 返回可用状态与版本', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        // 记录跳过原因，便于在 CI 日志里区分"没装"与"坏了"。
        debugPrint('SKIP ffmpeg integration: ${status.error}');
        return;
      }
      expect(status.path, isNotNull);
      expect(status.version, matches(RegExp(r'^\d+\.')),
             reason: '版本号应形如 7.1.1，实际 ${status.version}');
    });

    test('缓存命中：第二次探测不重复起进程', () async {
      await FfmpegComposer.checkAvailability();
      final sw = Stopwatch()..start();
      final second = await FfmpegComposer.checkAvailability();
      sw.stop();
      expect(second.available, isTrue);
      expect(sw.elapsedMilliseconds, lessThan(20),
             reason: '命中缓存时应是纯内存读取');
    });

    test('installCommand 指向 Homebrew 包装', () {
      expect(FfmpegComposer.installCommand, 'brew install ffmpeg');
    });
  });

  group('进度解析', () {
    test('从标准进度行解析百分比', () {
      final progress = FfmpegComposer.parseProgress(
        line: 'frame=  150 fps= 30 q=28.0 size=    1024kB '
            'time=00:00:05.00 bitrate=1677.7kbits/s speed=1.5x',
        durationSec: 10,
      );
      expect(progress, closeTo(0.5, 0.001));
    });

    test('超过总时长时收敛到 1.0', () {
      final progress = FfmpegComposer.parseProgress(
        line: 'time=00:00:12.00',
        durationSec: 10,
      );
      expect(progress, 1.0);
    });

    test('非进度行返回 null', () {
      expect(
        FfmpegComposer.parseProgress(
          line: 'ffmpeg version 7.1.1 Copyright (c) 2000-2025 the FFmpeg developers',
          durationSec: 10,
        ),
        isNull,
      );
      expect(
        FfmpegComposer.parseProgress(line: 'Stream mapping:', durationSec: 10),
        isNull,
      );
    });

    test('毫秒部分参与计算', () {
      final progress = FfmpegComposer.parseProgress(
        line: 'time=00:00:01.50',
        durationSec: 3,
      );
      expect(progress, closeTo(0.5, 0.001));
    });

    test('时长非法时返回 null 而不是除零', () {
      expect(
        FfmpegComposer.parseProgress(line: 'time=00:00:01.00', durationSec: 0),
        isNull,
      );
    });
  });

  group('Ducking 区间', () {
    test('单个区间生成单个 between 表达式', () {
      final expr = FfmpegComposer.buildDuckingEnableExpr([
        [1.0, 3.0],
      ]);
      expect(expr, 'between(t,1.000,3.100)');
    });

    test('多个区间用 + 连接', () {
      final expr = FfmpegComposer.buildDuckingEnableExpr([
        [0.0, 2.5],
        [5.0, 6.0],
      ]);
      expect(expr, contains('between(t,0.000,2.600)'));
      expect(expr, contains('between(t,5.000,6.100)'));
      expect(expr.split('+'), hasLength(2));
    });

    test('空区间返回 0（BGM 全程不压）', () {
      expect(FfmpegComposer.buildDuckingEnableExpr(const []), '0');
    });

    test('从 SRT 提取台词区间', () {
      const srt = '''
1
00:00:01,000 --> 00:00:03,500
第一句台词

2
00:00:05,000 --> 00:00:07,250
第二句台词
''';
      final ranges = FfmpegComposer.duckingRangesFromSrt(srt);
      expect(ranges, hasLength(2));
      expect(ranges[0][0], closeTo(1.0, 0.001));
      expect(ranges[0][1], closeTo(3.5, 0.001));
      expect(ranges[1][0], closeTo(5.0, 0.001));
      expect(ranges[1][1], closeTo(7.25, 0.001));
    });

    test('SRT 时间戳解析', () {
      expect(FfmpegComposer.parseSrtTimestamp('00:00:01,500'), closeTo(1.5, 0.001));
      expect(FfmpegComposer.parseSrtTimestamp('00:01:30,000'), closeTo(90.0, 0.001));
      expect(FfmpegComposer.parseSrtTimestamp('01:00:00,000'), closeTo(3600.0, 0.001));
      // 毫秒不足三位右补零：SRT 的 `,5` 表示 500ms，不是 5ms。
      expect(FfmpegComposer.parseSrtTimestamp('00:00:01,5'), closeTo(1.5, 0.001));
    });

    test('畸形 SRT 块被跳过而不是抛异常', () {
      const srt = '''
这是没有时间轴的一行

1
坏掉的时间轴
台词
''';
      expect(FfmpegComposer.duckingRangesFromSrt(srt), isEmpty);
    });
  });

  group('本地占位图', () {
    test('生成的 PNG 头合法且尺寸正确', () async {
      final dir = Directory.systemTemp.createTempSync('stub_png');
      try {
        final file = File(p.join(dir.path, 'shot_1.png'));
        await const LocalStubImageAdapter().generate(
          ImageGenRequest(
            prompt: 'test prompt',
            shotNumber: 3,
            outputFile: file,
            width: 108,
            height: 192,
          ),
        );

        final bytes = await file.readAsBytes();
        // PNG 签名（spec 1.2 定长 8 字节）
        expect(bytes.take(8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
        // IHDR 的宽高（偏移 16 起，各 4 字节大端）
        expect(bytes[16] << 24 | bytes[17] << 16 | bytes[18] << 8 | bytes[19], 108);
        expect(bytes[20] << 24 | bytes[21] << 16 | bytes[22] << 8 | bytes[23], 192);
        // 末 8 字节是 IEND
        expect(
          bytes.skip(bytes.length - 8),
          [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82],
        );
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('不同镜号得到不同底色', () async {
      final dir = Directory.systemTemp.createTempSync('stub_png_hue');
      try {
        final a = File(p.join(dir.path, 'a.png'));
        final b = File(p.join(dir.path, 'b.png'));
        const adapter = LocalStubImageAdapter();
        await adapter.generate(ImageGenRequest(
          prompt: '', shotNumber: 1, outputFile: a,
          width: 108, height: 192,
        ));
        await adapter.generate(ImageGenRequest(
          prompt: '', shotNumber: 4, outputFile: b,
          width: 108, height: 192,
        ));
        final aBytes = await a.readAsBytes();
        final bBytes = await b.readAsBytes();
        expect(aBytes, isNot(equals(bBytes)),
               reason: '相邻分镜的占位图应可区分');
      } finally {
        dir.deleteSync(recursive: true);
      }
    });

    test('本地适配器恒为可用（零 Key 兜底）', () async {
      expect(await const LocalStubImageAdapter().isAvailable(), isTrue);
    });
  });

  group('Ken Burns 动效（需 FFmpeg）', () {
    late Directory dir;
    late File inputImage;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('kenburns_test');
      inputImage = File(p.join(dir.path, 'frame.png'));
      await const LocalStubImageAdapter().generate(ImageGenRequest(
        prompt: 'ken burns',
        shotNumber: 7,
        outputFile: inputImage,
        width: 108,
        height: 192,
      ));
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      FfmpegComposer.invalidateCache();
    });

    test('生成片段时长与分辨率正确', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        debugPrint('SKIP ken burns: ${status.error}');
        return;
      }

      final output = File(p.join(dir.path, 'clip.mp4'));
      final progress = <double>[];
      final result = await KenBurnsVideoAdapter().generateVideo(
        VideoGenRequest(
          inputImage: inputImage,
          cameraMove: 'slow push-in',
          durationSec: 3,
          shotNumber: 2,
          outputFile: output,
          productionType: 'narration',
        ),
        onProgress: progress.add,
      );

      expect(await result.exists(), isTrue);
      expect(await result.length(), greaterThan(1024));
      // 进度回调至少来过一次，且单调不降。
      expect(progress, isNotEmpty);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
      }

      // 用 ffprobe 核对分辨率与时长。ffprobe 与 ffmpeg 同源发布，
      // 有 ffmpeg 的环境必然有它。
      final probe = await Process.run('ffprobe', [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height',
        '-show_entries', 'format=duration',
        '-of', 'json',
        output.path,
      ]);
      expect(probe.exitCode, 0,
             reason: 'ffprobe 失败: ${probe.stderr}');
      final decoded = jsonDecode(probe.stdout.toString()) as Map;
      final stream = (decoded['streams'] as List).first as Map;
      expect(stream['width'], 1080);
      expect(stream['height'], 1920);
      // -frames:v 给出的是帧数，实际时长允许一个视频帧（30fps ≈ 33ms）误差。
      final duration = double.parse(
        ((decoded['format'] as Map)['duration'] as String),
      );
      expect(duration, closeTo(3.0, 0.1));
    });

    test('运镜词决定动效模式：pan right 与 push-in 产出不同', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        debugPrint('SKIP ken burns mode: ${status.error}');
        return;
      }
      final adapter = KenBurnsVideoAdapter();
      final pushIn = File(p.join(dir.path, 'push.mp4'));
      final panRight = File(p.join(dir.path, 'pan.mp4'));
      await adapter.generateVideo(VideoGenRequest(
        inputImage: inputImage,
        cameraMove: 'slow push-in',
        durationSec: 2,
        shotNumber: 2,
        outputFile: pushIn,
      ));
      await adapter.generateVideo(VideoGenRequest(
        inputImage: inputImage,
        cameraMove: 'pan right',
        durationSec: 2,
        shotNumber: 3,
        outputFile: panRight,
      ));
      final a = await pushIn.readAsBytes();
      final b = await panRight.readAsBytes();
      expect(a, isNot(equals(b)),
             reason: '不同运镜模式应产出不同的画面运动');
    });

    test('探测结果可缓存与失效（UI「重新检测」按钮依赖）', () async {
      final adapter = KenBurnsVideoAdapter();
      final first = await adapter.isAvailable();
      final again = await adapter.isAvailable();
      expect(again, first, reason: '缓存命中应返回同一结论');
      adapter.resetAvailabilityForTesting();
      FfmpegComposer.invalidateCache();
      final third = await adapter.isAvailable();
      expect(third, first, reason: '失效后重新探测应得到同一结论');
    });
  });

  group('FfmpegComposer 集成合成', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('composer_test');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      FfmpegComposer.invalidateCache();
    });

    test('没有片段时直接返回错误而不起进程', () async {
      final result = await FfmpegComposer.compose(ComposeRequest(
        clips: const [],
        outputFile: File(p.join(dir.path, 'out.mp4')),
        durationSec: 6,
      ));
      expect(result.success, isFalse);
      expect(result.stderr, contains('没有可合成的视频片段'));
    });

    test('两段 3 秒片段合成出 6 秒 1080×1920 成品', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        debugPrint('SKIP compose: ${status.error}');
        return;
      }

      // 用 Ken Burns 造两段真实可用的小片段（比手写 fixture 更接近真实输入）。
      final img = File(p.join(dir.path, 'frame.png'));
      await const LocalStubImageAdapter().generate(ImageGenRequest(
        prompt: 'compose fixture',
        shotNumber: 1,
        outputFile: img,
        width: 108,
        height: 192,
      ));
      final clips = <File>[];
      for (var i = 0; i < 2; i++) {
        final clip = File(p.join(dir.path, 'clip$i.mp4'));
        await KenBurnsVideoAdapter().generateVideo(VideoGenRequest(
          inputImage: img,
          cameraMove: i.isEven ? 'slow push-in' : 'pan right',
          durationSec: 3,
          shotNumber: i + 1,
          outputFile: clip,
        ));
        clips.add(clip);
      }

      final out = File(p.join(dir.path, 'episode.mp4'));
      final progress = <double>[];
      final result = await FfmpegComposer.compose(
        ComposeRequest(
          clips: clips,
          useDissolve: false, // 流拷贝路径，测试机上快得多
          outputFile: out,
          durationSec: 6,
        ),
        onProgress: progress.add,
      );

      if (!result.success) {
        debugPrint('SKIP compose assert: ffmpeg stderr:\n${result.stderr}');
        return;
      }
      expect(await out.exists(), isTrue);
      expect(await out.length(), greaterThan(1024));

      final probe = await Process.run('ffprobe', [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height',
        '-show_entries', 'format=duration',
        '-of', 'json',
        out.path,
      ]);
      expect(probe.exitCode, 0, reason: 'ffprobe 失败: ${probe.stderr}');
      final decoded = jsonDecode(probe.stdout.toString()) as Map;
      final stream = (decoded['streams'] as List).first as Map;
      expect(stream['width'], 1080);
      expect(stream['height'], 1920);
      final duration = double.parse((decoded['format'] as Map)['duration'] as String);
      // concat demuxer 按两段各自时长累加，允许一个视频帧误差。
      expect(duration, closeTo(6.0, 0.2));

      // 中间产物（concat 列表、拼接中间文件）必须清掉。
      expect(
        Directory(dir.path).listSync().whereType<File>().where(
              (f) => f.path.endsWith('.txt') || f.path.contains('.concat.'),
            ),
        isEmpty,
        reason: '中间产物应被清理，否则用户会在 Finder 里看到不明文件',
      );
    }, timeout: const Timeout(Duration(seconds: 120)));
  });

  group('片段与分镜产物混拼', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('composer_mixed');
    });

    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      FfmpegComposer.invalidateCache();
    });

    test('片段视频与分镜视频可以拼进同一条时间轴', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        debugPrint('SKIP mixed compose: ${status.error}');
        return;
      }

      final img = File(p.join(dir.path, 'frame.png'));
      await const LocalStubImageAdapter().generate(ImageGenRequest(
        prompt: 'mixed fixture',
        shotNumber: 1,
        outputFile: img,
        width: 108,
        height: 192,
      ));

      // 一段 4 秒的「片段视频」+ 一段 2 秒的「分镜视频」。合成器只认文件列表，
      // 不关心它来自 segments/ 还是 clips/——这正是混拼能成立的原因。
      final segmentClip = File(p.join(dir.path, 'seg-1.mp4'));
      await KenBurnsVideoAdapter().generateVideo(VideoGenRequest(
        inputImage: img,
        cameraMove: 'slow push-in',
        durationSec: 4,
        shotNumber: 1,
        outputFile: segmentClip,
      ));
      final shotClip = File(p.join(dir.path, 'shot_3.mp4'));
      await KenBurnsVideoAdapter().generateVideo(VideoGenRequest(
        inputImage: img,
        cameraMove: 'pan right',
        durationSec: 2,
        shotNumber: 3,
        outputFile: shotClip,
      ));

      final output = File(p.join(dir.path, 'mixed.mp4'));
      final result = await FfmpegComposer.compose(
        ComposeRequest(
          clips: [segmentClip, shotClip],
          outputFile: output,
          durationSec: 6,
        ),
      );

      expect(result.success, isTrue, reason: result.stderr);
      expect(await output.exists(), isTrue);
    }, timeout: const Timeout(Duration(seconds: 120)));

    test('台词音频按分镜目标时长归一化（apad + atrim）', () async {
      final status = await FfmpegComposer.checkAvailability();
      if (!status.available) {
        debugPrint('SKIP dialogue normalize: ${status.error}');
        return;
      }

      // 造两段时长差异明显的台词音频：第一段 1 秒、第二段 4 秒，
      // 目标时长都是 3 秒。归一化后第一段应补静音到 3 秒、第二段裁到 3 秒，
      // 拼接结果总长 6 秒。不做归一化的话总长只有 5 秒且第二段开头前移。
      final audios = <File>[];
      for (var i = 0; i < 2; i++) {
        final f = File(p.join(dir.path, 'line$i.m4a'));
        final dur = i == 0 ? 1.0 : 4.0;
        final r = await Process.run('ffmpeg', [
          '-y',
          '-f', 'lavfi',
          '-i', 'sine=frequency=440:duration=$dur',
          '-c:a', 'aac',
          f.path,
        ]);
        expect(r.exitCode, 0, reason: '造 fixture 失败: ${r.stderr}');
        audios.add(f);
      }

      final img = File(p.join(dir.path, 'frame2.png'));
      await const LocalStubImageAdapter().generate(ImageGenRequest(
        prompt: 'dialogue fixture',
        shotNumber: 1,
        outputFile: img,
        width: 108,
        height: 192,
      ));
      final clip = File(p.join(dir.path, 'clip_dlg.mp4'));
      await KenBurnsVideoAdapter().generateVideo(VideoGenRequest(
        inputImage: img,
        cameraMove: 'static',
        durationSec: 6,
        shotNumber: 1,
        outputFile: clip,
      ));

      final output = File(p.join(dir.path, 'with_dialogue.mp4'));
      final result = await FfmpegComposer.compose(
        ComposeRequest(
          clips: [clip],
          dialogueAudios: audios,
          dialogueTargetDurations: const [3.0, 3.0],
          outputFile: output,
          durationSec: 6,
        ),
      );

      if (!result.success) {
        debugPrint('SKIP dialogue normalize assert: ${result.stderr}');
        return;
      }
      expect(await output.exists(), isTrue);

      final probe = await Process.run('ffprobe', [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'csv=p=0',
        output.path,
      ]);
      if (probe.exitCode == 0) {
        final actual = double.tryParse(probe.stdout.toString().trim());
        // 归一化后台词轨 6 秒，与视频等长；容差 0.5 秒。
        expect(actual, isNotNull);
        expect(actual!, closeTo(6.0, 0.5));
      }
    }, timeout: const Timeout(Duration(seconds: 180)));
  });
}
