import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_llm.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_markdown_exporter.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/vocabulary_study_store.dart';
import 'package:V8WorkToolbox/tools/lookup_panel/services/dictionary_service.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

import 'dart:typed_data';

class _FakeTextGenerator implements RehearsalTextGenerator {
  final String Function(String prompt) handler;
  _FakeTextGenerator(this.handler);

  @override
  Future<String> generate(String prompt) async => handler(prompt);
}

class _FakeTtsEngine implements TtsEngine {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async =>
      Uint8List.fromList([0x49, 0x44, 0x33, ...text.codeUnits]);
}

RealMeeting _meeting({
  required String id,
  required String title,
  required List<MeetingTurn> turns,
  List<String> keywords = const [],
}) {
  return RealMeeting(
    id: id,
    title: title,
    sourcePath: '/tmp/$id.md',
    fileName: '$id.md',
    contentHash: 'hash-$id',
    declaredDurationMs: 60000,
    importedAt: DateTime.utc(2026, 10, 24),
    keywords: keywords,
    slots: const [SpeakerSlot(id: 'Host', turnCount: 1)],
    turns: turns,
  );
}

MeetingTurn _turn(int index, String slotId, int ts, String text) =>
    MeetingTurn(index: index, slotId: slotId, timestampMs: ts, text: text);

void main() {
  group('VocabularyMarkdownExporter', () {
    late Directory tempDir;
    late VocabularyStudyStore store;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vocab_export_test_');
      store = VocabularyStudyStore(
        baseDir: tempDir,
        dictionaryLookup: (word) async => DictionaryResult(
          word: word,
          phonetic: '/ˈtest/',
          meanings: const [
            DictionaryMeaning(
              partOfSpeech: 'n.',
              definitions: ['测试释义'],
              examples: [],
            ),
          ],
        ),
        textGenerator: _FakeTextGenerator((_) => '测试中文翻译。'),
        ttsEngine: _FakeTtsEngine(),
      );
    });

    tearDown(() {
      store.dispose();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('有重点词时导出包含元数据、音标、词性、释义与全部去重例句', () async {
      final index = MeetingVocabularyIndex.build([
        _meeting(
          id: 'm1',
          title: 'Architecture Sync',
          keywords: ['latency'],
          turns: [
            _turn(0, 'Host', 12000, 'We are seeing high P99 latency.'),
            _turn(1, 'Host', 45000, 'How does caching affect latency?'),
          ],
        ),
      ]);

      store.toggleFocus(
        'latency',
        sentences: const [
          'We are seeing high P99 latency.',
          'How does caching affect latency?',
        ],
      );
      await store.ensureWordProfile('latency');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final md = VocabularyMarkdownExporter.build(
        index: index,
        studyStore: store,
        now: DateTime(2026, 11, 1, 16, 50),
      );

      expect(md, contains('# 听力练习重点关注词汇表'));
      expect(md, contains('导出时间**: 2026-11-01 16:50'));
      expect(md, contains('词汇总量**: 1 个重点词'));
      expect(md, contains('## latency'));
      expect(md, contains('音标'));
      expect(md, contains('词性'));
      expect(md, contains('释义'));
      expect(md, contains('全语料频次**: 2 次'));
      expect(md, contains('1. We are seeing high P99 latency.'));
      expect(md, contains('2. How does caching affect latency?'));
      expect(md, contains('出处**: *Architecture Sync*'));
    });

    test('同一原句重复出现时只导出一次', () async {
      final index = MeetingVocabularyIndex.build([
        _meeting(
          id: 'm1',
          title: 'Architecture Sync',
          keywords: ['latency'],
          turns: [
            // 同一句中 latency 出现两次，索引会生成两条 posting。
            _turn(0, 'Host', 12000, 'Latency is latency, period.'),
          ],
        ),
      ]);

      store.toggleFocus(
        'latency',
        sentences: const ['Latency is latency, period.'],
      );

      final md = VocabularyMarkdownExporter.build(
        index: index,
        studyStore: store,
        now: DateTime(2026, 11, 1),
      );

      final occurrences = RegExp('Latency is latency, period.').allMatches(md).length;
      expect(occurrences, 1);
      expect(md, contains('共 1 句'));
    });

    test('缺失助学字段时自然省略、不输出 null 或占位符', () async {
      final index = MeetingVocabularyIndex.build([
        _meeting(
          id: 'm1',
          title: 'Architecture Sync',
          keywords: ['opaque'],
          turns: [
            _turn(0, 'Host', 12000, 'The opaque pointer is unsafe.'),
          ],
        ),
      ]);

      // 标记但不等待任何助学补全，确保 profile / translation 均缺失。
      store.toggleFocus('opaque', autoEnrich: false);

      final md = VocabularyMarkdownExporter.build(
        index: index,
        studyStore: store,
        now: DateTime(2026, 11, 1),
      );

      expect(md, contains('## opaque'));
      expect(md, contains('1. The opaque pointer is unsafe.'));
      expect(md, isNot(contains('null')));
      expect(md, isNot(contains('暂无')));
      // 无音标/词性/释义/翻译，只有频次与例句。
      expect(md, isNot(contains('**音标**')));
      expect(md, isNot(contains('**词性**')));
      expect(md, isNot(contains('**释义**')));
      expect(md, isNot(contains('**中文**')));
    });

    test('无重点词时导出仅含头部与零总量', () async {
      final index = MeetingVocabularyIndex.build([
        _meeting(
          id: 'm1',
          title: 'Architecture Sync',
          turns: [_turn(0, 'Host', 0, 'Nothing focused here.')],
        ),
      ]);

      final md = VocabularyMarkdownExporter.build(
        index: index,
        studyStore: store,
        now: DateTime(2026, 11, 1),
      );

      expect(md, contains('词汇总量**: 0 个重点词'));
      expect(md, isNot(contains('## ')));
    });

    test('例句翻译命中缓存时附带中文翻译与出处', () async {
      final index = MeetingVocabularyIndex.build([
        _meeting(
          id: 'm1',
          title: 'Tech Talks',
          keywords: ['cache'],
          turns: [
            _turn(0, 'Speaker', 9000, 'The cache is warm.'),
          ],
        ),
      ]);

      store.toggleFocus(
        'cache',
        sentences: const ['The cache is warm.'],
        autoEnrich: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final md = VocabularyMarkdownExporter.build(
        index: index,
        studyStore: store,
        now: DateTime(2026, 11, 1),
      );

      expect(md, contains('1. The cache is warm.'));
      expect(md, contains('**中文**: 测试中文翻译。'));
      expect(md, contains('**出处**: *Tech Talks* (轮次 0 · Speaker · 00:09)'));
    });
  });
}
