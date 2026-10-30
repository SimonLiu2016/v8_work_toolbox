import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'recording_audio_backend.dart';

/// 词汇表发音播放链路：合成 / 播放两阶段、缓存与实时两条路径、失败语义与步进。
///
/// 这些用例的价值在于：它们替换的是**设备后端**而不是播放逻辑，所以
/// "停止 → 播放 → 等待完成（带超时上限）"与失败处理这些真正会抛错的行，
/// 在测试里与生产走的是同一段代码（此前 `audioPlayerFn` 把整段逻辑替换掉，
/// 生产分支从未被测试执行）。
class _RecordingTtsEngine implements TtsEngine {
  final List<String> synthesized = [];
  Object? synthError;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    final err = synthError;
    if (err != null) throw err;
    synthesized.add(text);
    return Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
  }
}

RealMeeting _meeting() => RealMeeting(
      id: 'm1',
      title: 'Architecture Sync',
      sourcePath: '/tmp/m1.md',
      fileName: 'm1.md',
      contentHash: 'hash123',
      declaredDurationMs: 60000,
      importedAt: DateTime.utc(2026, 10, 24),
      keywords: const ['governance', 'idempotent'],
      slots: const [
        SpeakerSlot(id: 'Host', turnCount: 1),
        SpeakerSlot(id: 'CTO', turnCount: 1),
      ],
      turns: const [
        MeetingTurn(
          index: 0,
          slotId: 'Host',
          timestampMs: 12000,
          text: 'We need stronger data Governance before scaling.',
        ),
        MeetingTurn(
          index: 1,
          slotId: 'CTO',
          timestampMs: 45000,
          text: "Cloud governance's overhead should not block idempotent jobs.",
        ),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late _RecordingTtsEngine engine;
  late VocabularyStudyStore store;
  late MeetingVocabularyIndex index;

  // 真实 dart:io I/O 必须放在 setUp：testWidgets 体跑在 FakeAsync 区里，
  // 真实异步 I/O 在那里永不完成。
  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vocab_pipeline_');
    engine = _RecordingTtsEngine();
    store = VocabularyStudyStore(baseDir: tempDir, ttsEngine: engine);
    index = MeetingVocabularyIndex.build([_meeting()]);
  });

  tearDown(() async {
    store.dispose();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 预置缓存：复刻生产"音频已缓存"条件（合成不发请求）。
  void prewarmCache() {
    final cacheDir = Directory('${tempDir.path}/vocab_tts_cache')
      ..createSync(recursive: true);
    for (final e in index.entries()) {
      File('${cacheDir.path}/${VocabularyStudyStore.ttsCacheKey(e.word)}.mp3')
          .writeAsBytesSync(Uint8List.fromList([0x49, 0x44, 0x33, 1, 2, 3]));
    }
  }

  Future<void> pumpDialog(
    WidgetTester tester,
    RecordingAudioBackend backend,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VocabularyBrowserDialog(
            index: index,
            studyStore: store,
            audioBackend: backend,
            onJump: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> tapPlay(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey('vocab-continuous-play-pause-btn')),
    );
    await tester.pump();
  }

  /// 只抓「失败」文案（避开"单词发音/句子发音"这类按钮标签）。
  String? failureText(WidgetTester tester) {
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final s = t.data;
      if (s != null && s.contains('发音') && s.contains('失败：')) return s;
    }
    return null;
  }

  group('播放编排（真实执行，不替换播放逻辑）', () {
    testWidgets('缓存命中：不触发合成，编排的 stop→play 仍真实执行', (tester) async {
      prewarmCache();
      final backend = RecordingAudioBackend();
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.synthesized, isEmpty, reason: '缓存命中不应再合成');
      expect(backend.stopCount, greaterThanOrEqualTo(1),
          reason: '编排里的 stop 必须被执行，而不是被替身整段绕过');
      expect(backend.played.length, 1);
      expect(failureText(tester), isNull);
    });

    testWidgets('无缓存：先生成再播放，两条路径都走到同一个编排', (tester) async {
      final backend = RecordingAudioBackend();
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(engine.synthesized, isNotEmpty, reason: '无缓存时应触发合成');
      expect(backend.stopCount, greaterThanOrEqualTo(1));
      expect(backend.played.length, 1);
      expect(failureText(tester), isNull);
    });
  });

  group('失败语义（按阶段可区分、可定位）', () {
    testWidgets('播放阶段失败：文案含阶段、异常类型与消息', (tester) async {
      prewarmCache();
      final backend = RecordingAudioBackend(
        playError: StateError('boom-play-42'),
      );
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final msg = failureText(tester);
      expect(msg, isNotNull);
      expect(msg, contains('发音播放失败'), reason: '必须标明失败发生在播放阶段');
      expect(msg, contains('StateError'), reason: '必须给出异常运行时类型');
      expect(msg, contains('boom-play-42'), reason: '必须给出异常消息');
      expect(msg, isNot(contains('发音生成失败')));
    });

    testWidgets('合成阶段失败：归因到生成而非播放', (tester) async {
      engine.synthError = StateError('boom-synth-7');
      final backend = RecordingAudioBackend();
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));

      final msg = failureText(tester);
      expect(msg, isNotNull);
      expect(msg, contains('发音生成失败'));
      expect(msg, contains('StateError'));
      expect(msg, contains('boom-synth-7'));
      expect(backend.played, isEmpty, reason: '合成失败不应进入播放');
    });
  });

  group('连续磨耳朵的步进保证', () {
    testWidgets('单个词播放失败不中断连播', (tester) async {
      prewarmCache();
      final backend = RecordingAudioBackend(
        playError: StateError('always-fail'),
      );
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(milliseconds: 100));
      // 失败后 1.5s 应步进到下一个词
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 100));

      expect(backend.played.length, greaterThanOrEqualTo(2),
          reason: '单词级失败不得中断连播');
      expect(failureText(tester), contains('发音播放失败'));
      // spec：该词被标记为失败（列表项旁的红色警标），而不只是一行全局文案。
      expect(
        find.byIcon(Icons.error_outline_rounded),
        findsWidgets,
        reason: '失败词应被逐词标记',
      );
    });

    testWidgets('播放完成不返回时，等待有上限、不卡死连播', (tester) async {
      prewarmCache();
      final backend = RecordingAudioBackend(completesImmediately: false);
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(seconds: 5)); // 越过 4s 上限
      await tester.pump(const Duration(milliseconds: 1700)); // 越过 1.5s 间隔
      await tester.pump(const Duration(milliseconds: 100));

      expect(backend.played.length, greaterThanOrEqualTo(2),
          reason: '超时后应放行并步进，而不是无限阻塞');
      expect(failureText(tester), isNull);

      // 收尾：停掉连播并让在途的 4s 上限等待自然结束。
      await tester.tap(
        find.byKey(const ValueKey('vocab-continuous-stop-btn')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('底层返回协变的 Stream<AudioEvent/Object> 时，超时不抛 TypeError', (tester) async {
      prewarmCache();
      // 模拟生产 audioplayers: 内部为 Stream<AudioEvent>，协变赋值给 Stream<void>。
      // 若上层直接用 .first.timeout(..., onTimeout: () {})，Dart 会抛出：
      // type '() => Null' is not a subtype of type '(() => FutureOr<AudioEvent>)?' of 'onTimeout'。
      // 显式 Completer<void> 阻断后，即使超时也能平滑放行。
      final controller = StreamController<Object>.broadcast();
      final backend = RecordingAudioBackend(
        customCompleteStream: controller.stream,
      );
      await pumpDialog(tester, backend);

      await tapPlay(tester);
      await tester.pump(const Duration(seconds: 5)); // 越过 4s 上限
      await tester.pump(const Duration(milliseconds: 1700)); // 越过 1.5s 间隔
      await tester.pump(const Duration(milliseconds: 100));

      expect(failureText(tester), isNull,
          reason: '不得抛出 () => Null is not subtype of ...');
      expect(backend.played.length, greaterThanOrEqualTo(2),
          reason: '超时后应安全步进');

      await tester.tap(
        find.byKey(const ValueKey('vocab-continuous-stop-btn')),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await controller.close();
    });
  });
}