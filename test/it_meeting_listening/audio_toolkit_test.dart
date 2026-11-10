import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';

void main() {
  late Directory tmp;
  late FfmpegAudioToolkit toolkit;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('audio_toolkit_test');
    toolkit = FfmpegAudioToolkit();
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  test('FfmpegAudioToolkit.concat 在 PCM WAV 输入合并为 MP3 时自动回退重编码并成功', () async {
    final ffmpeg = await toolkit.resolveFfmpeg();
    if (ffmpeg == null) {
      // 机器未安装 ffmpeg 则跳过
      return;
    }

    // 生成两个测试 PCM WAV 文件
    final wav1 = File('${tmp.path}/part1.wav');
    final wav2 = File('${tmp.path}/part2.wav');
    await Process.run(ffmpeg, [
      '-y', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono',
      '-t', '0.5', wav1.path,
    ]);
    await Process.run(ffmpeg, [
      '-y', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono',
      '-t', '0.5', wav2.path,
    ]);

    expect(wav1.existsSync(), isTrue);
    expect(wav2.existsSync(), isTrue);

    // 拼接成 .mp3 目标文件
    final outputMp3 = File('${tmp.path}/output.mp3');
    await toolkit.concat([wav1.path, wav2.path], outputMp3.path);

    expect(outputMp3.existsSync(), isTrue);
    expect(outputMp3.lengthSync(), greaterThan(0));

    // 探测时长：两段各 0.5s，合并后应约为 1000ms
    final dur = await toolkit.probeDurationMs(outputMp3.path);
    expect(dur, greaterThanOrEqualTo(800));
    expect(dur, lessThanOrEqualTo(1200));
  });

  test('FfmpegAudioToolkit.concat 在 WAV 与 MP3 混流输入时仍能成功拼接', () async {
    final ffmpeg = await toolkit.resolveFfmpeg();
    if (ffmpeg == null) return;

    final wavFile = File('${tmp.path}/sample.wav');
    final mp3File = File('${tmp.path}/silence.mp3');

    await Process.run(ffmpeg, [
      '-y', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono',
      '-t', '0.5', wavFile.path,
    ]);
    await toolkit.writeSilence(mp3File.path, 1200);

    final merged = File('${tmp.path}/merged.mp3');
    await toolkit.concat([wavFile.path, mp3File.path], merged.path);

    expect(merged.existsSync(), isTrue);
    expect(merged.lengthSync(), greaterThan(0));
  });

  test('FfmpegAudioToolkit.concat 在输出路径包含 .mp3 但有其他后缀（如 .new）时仍能指定容器并成功', () async {
    final ffmpeg = await toolkit.resolveFfmpeg();
    if (ffmpeg == null) return;

    final wavFile = File('${tmp.path}/part.wav');
    await Process.run(ffmpeg, [
      '-y', '-f', 'lavfi', '-i', 'anullsrc=r=24000:cl=mono',
      '-t', '0.5', wavFile.path,
    ]);

    final outputWithNew = File('${tmp.path}/g39.mp3.new');
    await toolkit.concat([wavFile.path], outputWithNew.path);

    expect(outputWithNew.existsSync(), isTrue);
    expect(outputWithNew.lengthSync(), greaterThan(0));

    final dur = await toolkit.probeDurationMs(outputWithNew.path);
    expect(dur, greaterThanOrEqualTo(400));
  });
}
