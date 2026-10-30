import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_list_player_controller.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'recording_audio_backend.dart';

/// 词汇列表播放编排：顺序步进、循环、失败上报、停止/上一词/下一词与超时兜底。
///
/// 与词汇表对话框的编排一致（停止 → 合成(磁盘缓存) → 播放 → 等待完成(4s 超时)
/// → 1.5s 缓冲 → 步进）；替换的是**设备后端**，编排本身在测试里被真实执行。
class _FakeTtsEngine implements TtsEngine {
  Object? synthError;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    final err = synthError;
    if (err != null) throw err;
    return Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
  }
}

void main() {
  late Directory tempDir;
  late _FakeTtsEngine engine;
  late VocabularyStudyStore store;
  late RecordingAudioBackend backend;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('vocab_list_player_');
    engine = _FakeTtsEngine();
    store = VocabularyStudyStore(
      baseDir: tempDir,
      dictionaryLookup: (_) async => null,
      ttsEngine: engine,
    );
    backend = RecordingAudioBackend();
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  VocabularyListPlayerController build() =>
      VocabularyListPlayerController(studyStore: store, backend: backend);

  test('顺序步进：从第一个词开始，播毕停顿后步进到下一个', () async {
    final ctrl = build();
    ctrl.setWords(['governance', 'idempotent']);
    await ctrl.start();

    expect(ctrl.wordIndex, 0);
    expect(ctrl.currentWord, 'governance');
    expect(ctrl.isPlaying, isTrue);
    expect(backend.played, hasLength(1));

    // 播毕停顿缓冲 1.5s 后步进到第二个词。
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.wordIndex, 1);
    expect(ctrl.currentWord, 'idempotent');
    expect(backend.played, hasLength(2));
  });

  test('不循环：到末尾后停止', () async {
    final ctrl = build();
    ctrl.setLoop(false);
    ctrl.setWords(['alpha']);
    await ctrl.start();

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    // 只剩一个词，播完不循环 → 停止。
    expect(ctrl.isPlaying, isFalse);
  });

  test('循环：到末尾后回到第一个词', () async {
    final ctrl = build();
    ctrl.setLoop(true);
    ctrl.setWords(['alpha', 'beta']);
    await ctrl.start();

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.wordIndex, 1);
    // 到末尾后循环回 0，继续播。
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.wordIndex, 0);
    expect(ctrl.isPlaying, isTrue);
  });

  test('合成失败：标记失败但不中断步进', () async {
    final ctrl = build();
    ctrl.setWords(['governance', 'idempotent']);
    engine.synthError = StateError('TTS 模型返回了空音频');
    await ctrl.start();

    expect(ctrl.failedWords, contains('governance'));
    // 清空错误后，步进到第二个词应正常（失败不中断步进）。
    engine.synthError = null;
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.wordIndex, 1);
    expect(ctrl.failedWords, isNot(contains('idempotent')));
  });

  test('播放失败：标记失败但不中断步进', () async {
    final failing = RecordingAudioBackend(playError: StateError('设备播放失败'));
    final ctrl2 = VocabularyListPlayerController(studyStore: store, backend: failing);
    ctrl2.setWords(['alpha', 'beta']);
    await ctrl2.start();

    expect(ctrl2.failedWords, contains('alpha'));
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl2.wordIndex, 1);
  });

  test('上一词/下一词', () async {
    final ctrl = build();
    ctrl.setWords(['alpha', 'beta', 'gamma']);
    await ctrl.start();
    expect(ctrl.wordIndex, 0);

    await ctrl.next();
    expect(ctrl.wordIndex, 1);

    await ctrl.previous();
    expect(ctrl.wordIndex, 0);
  });

  test('停止：复位播放态并停掉后端', () async {
    final ctrl = build();
    ctrl.setWords(['alpha']);
    await ctrl.start();
    expect(ctrl.isPlaying, isTrue);

    await ctrl.stop();
    expect(ctrl.isPlaying, isFalse);
    expect(backend.stopCount, greaterThan(0));
  });

  test('播放永不完成时 4s 超时兜底放行（不卡死）', () async {
    final backend = RecordingAudioBackend(completesImmediately: false);
    final ctrl = VocabularyListPlayerController(studyStore: store, backend: backend);
    ctrl.setWords(['alpha', 'beta']);
    await ctrl.start();

    // 第一个词永不播完 → 4s 超时后仍步进，而非卡死。
    await Future<void>.delayed(const Duration(milliseconds: 4200));
    expect(ctrl.isPlaying, isTrue); // 仍处于播放状态（等待下一词缓冲）
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    expect(ctrl.wordIndex, 1);
  });
}
