import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_llm.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/vocabulary_browser_dialog.dart';
import 'package:V8WorkToolbox/tools/lookup_panel/services/dictionary_service.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'recording_audio_backend.dart';

class _FakeTextGenerator implements RehearsalTextGenerator {
  final List<String> prompts = [];
  final String Function(String prompt) handler;

  _FakeTextGenerator(this.handler);

  @override
  Future<String> generate(String prompt) async {
    prompts.add(prompt);
    return handler(prompt);
  }
}

class _FakeTtsEngine implements TtsEngine {
  final List<String> synthesizedTexts = [];

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    synthesizedTexts.add(text);
    return Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
  }
}

RealMeeting _sampleMeeting() {
  return RealMeeting(
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
}

void main() {
  group('findWordHighlightRanges & buildHighlightedSentenceSpans', () {
    test('highlights target word case-insensitively and with possessive suffix', () {
      const sentence =
          "Cloud Governance's overhead should not block daily governance or governor.";
      final ranges = findWordHighlightRanges(sentence, 'governance');
      final matched = [
        for (final r in ranges) sentence.substring(r.start, r.end),
      ];
      expect(matched, equals(["Governance's", 'governance']));
    });

    test('buildHighlightedSentenceSpans applies highlightStyle only to target tokens', () {
      const sentence = 'We need Governance now.';
      const normal = TextStyle(color: Colors.black);
      const highlight = TextStyle(
        color: Colors.blue,
        fontWeight: FontWeight.w700,
      );
      final spans = buildHighlightedSentenceSpans(
        sentence,
        'governance',
        normalStyle: normal,
        highlightStyle: highlight,
      );
      expect(spans.length, 3);
      final s0 = spans[0] as TextSpan;
      final s1 = spans[1] as TextSpan;
      final s2 = spans[2] as TextSpan;
      expect(s0.text, 'We need ');
      expect(s0.style, normal);
      expect(s1.text, 'Governance');
      expect(s1.style, highlight);
      expect(s2.text, ' now.');
      expect(s2.style, normal);
    });
  });

  group('VocabularyStudyStore', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vocab_study_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('persists focused words, word profiles, and sentence translations across rebuilds', () async {
      final fakeLlm = _FakeTextGenerator((prompt) {
        if (prompt.contains('JSON 字符串数组')) {
          return '["在扩展之前我们需要更强的数据治理。", "云治理的开销不应阻塞幂等任务。"]';
        }
        return '在扩展之前我们需要更强的数据治理。';
      });
      final fakeTts = _FakeTtsEngine();

      final store = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (word) async => DictionaryResult(
          word: word,
          phonetic: '/ˈɡʌvənəns/',
          meanings: const [
            DictionaryMeaning(
              partOfSpeech: 'n.',
              definitions: ['治理；管理机制'],
              examples: [],
            ),
          ],
        ),
        textGenerator: fakeLlm,
        ttsEngine: fakeTts,
      );

      final focused = store.toggleFocus(
        'Governance',
        sentences: const [
          'We need stronger data Governance before scaling.',
          "Cloud governance's overhead should not block idempotent jobs.",
        ],
      );
      expect(focused, isTrue);
      expect(store.isFocused('governance'), isTrue);

      // 等待后台自动补全释义与句子翻译完成
      await store.ensureWordProfile('governance');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final profile = store.profileFor('governance');
      expect(profile, isNotNull);
      expect(profile!.phonetic, '/ˈɡʌvənəns/');
      expect(profile.partOfSpeech, 'n.');
      expect(profile.definitionZh, contains('治理'));

      expect(
        store.translationForSentence(
          'We need stronger data Governance before scaling.',
        ),
        '在扩展之前我们需要更强的数据治理。',
      );
      expect(
        store.translationForSentence(
          "Cloud governance's overhead should not block idempotent jobs.",
        ),
        '云治理的开销不应阻塞幂等任务。',
      );

      // 重新实例化 VocabularyStudyStore，验证磁盘持久化生效
      final reloaded = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (_) async => null,
        textGenerator: fakeLlm,
        ttsEngine: fakeTts,
      );
      expect(reloaded.isFocused('governance'), isTrue);
      expect(reloaded.profileFor('governance')?.definitionZh, contains('治理'));
      expect(
        reloaded.translationForSentence(
          'We need stronger data Governance before scaling.',
        ),
        '在扩展之前我们需要更强的数据治理。',
      );
    });

    test('falls back to LLM when dictionary lookup returns no Chinese definition', () async {
      final fakeLlm = _FakeTextGenerator(
        (_) =>
            '{"phonetic": "/aɪˈdempətənt/", "partOfSpeech": "adj.", "definitionZh": "adj. 幂等的（多次执行结果一致）"}',
      );
      final store = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (_) async => null,
        textGenerator: fakeLlm,
        ttsEngine: _FakeTtsEngine(),
      );

      final profile = await store.ensureWordProfile('idempotent');
      expect(profile, isNotNull);
      expect(profile!.phonetic, '/aɪˈdempətənt/');
      expect(profile.partOfSpeech, 'adj.');
      expect(profile.definitionZh, contains('幂等的'));
      expect(fakeLlm.prompts.length, 1);
    });

    test('synthesizes TTS audio on demand and reuses local cache on subsequent calls', () async {
      final fakeTts = _FakeTtsEngine();
      final store = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (_) async => null,
        textGenerator: _FakeTextGenerator((_) => ''),
        ttsEngine: fakeTts,
      );

      final file1 = await store.synthesizeOrGetTtsFile('governance');
      expect(file1.existsSync(), isTrue);
      expect(fakeTts.synthesizedTexts, equals(['governance']));

      // 第二次请求同一单词发音：命中本地缓存，不再调用 TTS
      final file2 = await store.synthesizeOrGetTtsFile('governance');
      expect(file2.path, equals(file1.path));
      expect(fakeTts.synthesizedTexts.length, 1);
    });
  });

  group('VocabularyBrowserDialog widget tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vocab_dialog_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    testWidgets('highlights word in expanded sentence, supports focus filter, auto translations, and TTS playback', (tester) async {
      final index = MeetingVocabularyIndex.build([_sampleMeeting()]);
      final fakeLlm = _FakeTextGenerator((prompt) {
        if (prompt.contains('JSON 字符串数组')) {
          return '["在扩展之前我们需要更强的数据治理。", "云治理的开销不应阻塞幂等任务。"]';
        }
        return '云治理的开销不应阻塞幂等任务。';
      });
      final fakeTts = _FakeTtsEngine();
      final playedFiles = <String>[];

      final studyStore = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (word) async => DictionaryResult(
          word: word,
          phonetic: word == 'governance' ? '/ˈɡʌvənəns/' : '/aɪˈdempətənt/',
          meanings: [
            DictionaryMeaning(
              partOfSpeech: word == 'governance' ? 'n.' : 'adj.',
              definitions: [
                word == 'governance' ? '治理；管控机制' : '幂等的',
              ],
              examples: const [],
            ),
          ],
        ),
        textGenerator: fakeLlm,
        ttsEngine: fakeTts,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VocabularyBrowserDialog(
              index: index,
              studyStore: studyStore,
              audioBackend: RecordingAudioBackend(played: playedFiles),
              onJump: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 展开单词 governance：自动查词典展示音标、词性与中文解释，且原句中 Governance 高亮
      await tester.tap(find.text('Governance'));
      await tester.pumpAndSettle();

      expect(find.text('/ˈɡʌvənəns/'), findsWidgets);
      expect(find.textContaining('治理；管控机制'), findsWidgets);

      final richFinder = find.byKey(
        const ValueKey('vocab-sentence-rich-governance-0'),
      );
      expect(richFinder, findsOneWidget);
      final richWidget = tester.widget<Text>(richFinder);
      final rootSpan = richWidget.textSpan! as TextSpan;
      final highlightedTexts = <String>[
        for (final child in rootSpan.children ?? const <InlineSpan>[])
          if (child is TextSpan && child.style?.fontWeight == FontWeight.w700)
            child.text ?? '',
      ];
      expect(highlightedTexts, equals(['Governance']));

      // 2. 点击「单词发音」与「句子发音」：调用 TTS 临时合成并播放
      await tester.tap(find.byKey(const ValueKey('vocab-word-tts-governance')));
      await tester.pumpAndSettle();
      expect(fakeTts.synthesizedTexts, contains('governance'));
      expect(playedFiles.length, 1);

      await tester.tap(
        find.byKey(const ValueKey('vocab-sentence-tts-governance-0')),
      );
      await tester.pumpAndSettle();
      expect(
        fakeTts.synthesizedTexts,
        contains('We need stronger data Governance before scaling.'),
      );
      expect(playedFiles.length, 2);

      // 3. 点击 ☆ 标记 governance 为「重点关注」：自动生成所属原句的中文意思，且可切到「重点关注」列表单独查看
      await tester.tap(
        find.byKey(const ValueKey('vocab-focus-btn-governance')),
      );
      await tester.pumpAndSettle();

      expect(find.text('重点关注 (1)'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('vocab-sentence-zh-governance-0')),
        findsOneWidget,
      );
      expect(
        find.textContaining('在扩展之前我们需要更强的数据治理。'),
        findsOneWidget,
      );

      // 切换到「重点关注 (1)」视图，只展示已标记重点关注的单词
      await tester.tap(find.byKey(const ValueKey('vocab-tab-focused')));
      await tester.pumpAndSettle();

      expect(find.text('Governance'), findsWidgets);
      expect(find.text('idempotent'), findsNothing);
    });
  });
}
