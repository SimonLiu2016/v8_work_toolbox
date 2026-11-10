import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/models/recording_models.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/meeting_record_engine.dart';
import 'package:V8WorkToolbox/tools/meeting_recorder/services/recording_file_scanner.dart';

class _FakeAudioToolkit implements AudioToolkit {
  @override
  Future<void> concat(List<String> files, String outputPath) async {}

  @override
  Future<int> probeDurationMs(String filePath) async {
    final f = File(filePath);
    if (!f.existsSync()) return 0;
    // 模拟假时长
    return f.lengthSync() * 10;
  }

  @override
  Future<void> writeSilence(String path, int ms) async {}
}

void main() {
  group('FfmpegMeetingRecordEngine 设备列表解析', () {
    test('解析带 AVFoundation 前缀与声道的标准输出', () {
      const output = '''
[AVFoundation indev @ 0x7fa281005800] AVFoundation video devices:
[AVFoundation indev @ 0x7fa281005800] [0] FaceTime HD Camera
[AVFoundation indev @ 0x7fa281005800] AVFoundation audio devices:
[AVFoundation indev @ 0x7fa281005800] [0] MacBook Pro 麦克风 (1ch)
[AVFoundation indev @ 0x7fa281005800] [1] BlackHole 2ch (2ch)
[AVFoundation indev @ 0x7fa281005800] [2] 外置会议麦克风
''';

      final devices = FfmpegMeetingRecordEngine.parseDeviceList(output);
      expect(devices, hasLength(3));
      expect(devices[0].id, 0);
      expect(devices[0].name, 'MacBook Pro 麦克风 (1ch)');
      expect(devices[0].channels, 1);

      expect(devices[1].id, 1);
      expect(devices[1].name, 'BlackHole 2ch (2ch)');
      expect(devices[1].channels, 2);

      expect(devices[2].id, 2);
      expect(devices[2].name, '外置会议麦克风');
      expect(devices[2].channels, 2);
    });

    test('空音频区域返回空设备列表', () {
      const output = '''
[AVFoundation indev @ 0x123] AVFoundation video devices:
[AVFoundation indev @ 0x123] [0] Camera
Error opening input: Input/output error
''';
      final devices = FfmpegMeetingRecordEngine.parseDeviceList(output);
      expect(devices, isEmpty);
    });
  });

  group('RecordingFileScanner 扫描与管理', () {
    late Directory tempDir;
    late RecordingFileScanner scanner;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('recorder_scanner_test_');
      scanner = RecordingFileScanner(audioToolkit: _FakeAudioToolkit());
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('扫描并过滤非音频文件且按时间倒序排序', () async {
      final f1 = File('${tempDir.path}/rec_20261101.m4a');
      await f1.writeAsBytes(List.filled(100, 1));
      await f1.setLastModified(DateTime(2026, 11, 1));

      final f2 = File('${tempDir.path}/rec_20261105.mp3');
      await f2.writeAsBytes(List.filled(200, 1));
      await f2.setLastModified(DateTime(2026, 11, 5));

      final fDoc = File('${tempDir.path}/readme.txt');
      await fDoc.writeAsString('ignore me');

      final items = await scanner.scanDirectory(tempDir.path);
      expect(items, hasLength(2));
      // f2 最新，排在首位
      expect(items.first.fileName, 'rec_20261105.mp3');
      expect(items.first.durationMs, 2000);
      expect(items.last.fileName, 'rec_20261101.m4a');
      expect(items.last.durationMs, 1000);
    });

    test('重命名与删除录音文件', () async {
      final f = File('${tempDir.path}/temp_record.m4a');
      await f.writeAsBytes(List.filled(50, 1));

      final renamed = await scanner.renameRecording(f.path, '周例会_架构评审');
      expect(renamed, isNotNull);
      expect(renamed!.fileName, '周例会_架构评审.m4a');
      expect(File(renamed.filePath).existsSync(), isTrue);
      expect(f.existsSync(), isFalse);

      final deleted = await scanner.deleteRecording(renamed.filePath);
      expect(deleted, isTrue);
      expect(File(renamed.filePath).existsSync(), isFalse);
    });
  });

  group('FfmpegMeetingRecordEngine 音量电平与参数构建', () {
    test('buildArgs 包含 astats ametadata 实时电平滤镜与快启元数据', () {
      final args = FfmpegMeetingRecordEngine.buildArgs(
        deviceIndex: 1,
        outputPath: '/tmp/meeting.m4a',
      );

      expect(args, contains('-af'));
      final afIdx = args.indexOf('-af');
      expect(args[afIdx + 1], contains('lavfi.astats.Overall.RMS_level'));
      expect(args, containsAll(['-i', ':1', '-c:a', 'aac', '-movflags', '+faststart']));
      expect(args.last, '/tmp/meeting.m4a');
    });

    test('parseRmsLevelLine 能准确提取 FFmpeg stdout 中打印的分贝值', () {
      expect(
        FfmpegMeetingRecordEngine.parseRmsLevelLine('lavfi.astats.Overall.RMS_level=-21.083268'),
        closeTo(-21.083268, 0.0001),
      );
      expect(
        FfmpegMeetingRecordEngine.parseRmsLevelLine('lavfi.astats.Overall.RMS_level=-inf'),
        double.negativeInfinity,
      );
      expect(
        FfmpegMeetingRecordEngine.parseRmsLevelLine('lavfi.astats.Overall.RMS_level=nan'),
        double.negativeInfinity,
      );
      expect(
        FfmpegMeetingRecordEngine.parseRmsLevelLine('frame:0 pts:0 pts_time:0'),
        isNull,
      );
    });

    test('normalizeRmsDb 具备高信噪比静音门限并准确映射人声动态范围', () {
      // 静音、异常值或负无穷
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(null), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(double.nan), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(double.negativeInfinity), 0.0);

      // 环境物理底噪（风扇、室内空气流动 -40dB ~ -32dB）及门限 (-31dB) 均严格归零贴底
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-80.0), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-50.0), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-40.0), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-35.0), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-32.0), 0.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-31.0), 0.0);

      // 开口发声 / 轻声 (-25dB)
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-25.0), closeTo(0.44, 0.02));

      // 普通交谈音量 (-20dB)
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-20.0), closeTo(0.66, 0.02));

      // 洪亮/饱满发声 (-14dB)
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-14.0), closeTo(0.87, 0.02));

      // 峰值及大声音量 (-10dB 及以上)
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-10.0), 1.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(-5.0), 1.0);
      expect(FfmpegMeetingRecordEngine.normalizeRmsDb(0.0), 1.0);
    });
  });
}
