import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/html_to_markdown.dart';
import 'package:V8WorkToolbox/tools/lookup_panel/services/dictionary_service.dart';
import 'package:V8WorkToolbox/tools/vocab_book/models/vocab_entry.dart';

void main() {
  group('HTML to Markdown Converter Tests', () {
    test('converts headings and paragraphs', () {
      const html = '<h1>Title 1</h1><p>First paragraph with <strong>bold</strong> text.</p><h2>Subtitle</h2>';
      final md = htmlToMarkdown(html);
      expect(md, contains('# Title 1'));
      expect(md, contains('First paragraph with **bold** text.'));
      expect(md, contains('## Subtitle'));
    });

    test('converts links and images', () {
      const html = '<p><a href="https://example.com">Example Link</a></p><img src="https://example.com/pic.png" alt="Test Pic" />';
      final md = htmlToMarkdown(html);
      expect(md, contains('[Example Link](https://example.com)'));
      expect(md, contains('![Test Pic](https://example.com/pic.png)'));
    });

    test('converts unordered and ordered lists', () {
      const html = '<ul><li>Item A</li><li>Item B</li></ul><ol><li>First</li><li>Second</li></ol>';
      final md = htmlToMarkdown(html);
      expect(md, contains('- Item A'));
      expect(md, contains('- Item B'));
      expect(md, contains('1. First'));
      expect(md, contains('2. Second'));
    });

    test('converts tables properly', () {
      const html = '''
<table>
  <thead>
    <tr><th>Word</th><th>Meaning</th></tr>
  </thead>
  <tbody>
    <tr><td>ephemeral</td><td>lasting short time</td></tr>
  </tbody>
</table>
''';
      final md = htmlToMarkdown(html);
      expect(md, contains('| **Word** | **Meaning** |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| ephemeral | lasting short time |'));
    });

    test('decodes HTML entities and strips unwanted tags', () {
      const html = '<p>Tom &amp; Jerry &gt; Mickey &lt; Mouse &quot;Quotes&quot;</p><script>alert("hack")</script>';
      final md = htmlToMarkdown(html);
      expect(md, equals('Tom & Jerry > Mickey < Mouse "Quotes"'));
      expect(md, isNot(contains('alert')));
    });
  });

  group('Dictionary and Vocab Models Tests', () {
    test('DictionaryResult parses and exposes helpers', () {
      final res = DictionaryResult(
        word: 'test',
        phonetic: '/test/',
        audioUrl: 'https://example.com/audio.mp3',
        meanings: [
          const DictionaryMeaning(
            partOfSpeech: 'noun',
            definitions: ['A procedure intended to establish quality.'],
            examples: ['This is a test.'],
          ),
          const DictionaryMeaning(
            partOfSpeech: 'verb',
            definitions: ['Take measures to check the quality.'],
            examples: [],
          ),
        ],
      );

      expect(res.primaryPartOfSpeech, equals('noun'));
      expect(res.allDefinitions.length, equals(2));
      expect(res.allExamples.length, equals(1));
    });

    test('VocabEntryModel handles mastery levels and colors', () {
      final entry = VocabEntryModel(
        id: '123',
        word: 'serendipity',
        definitions: ['Fortunate happenstance'],
        examples: ['Finding this was pure serendipity.'],
        masteryLevel: 4,
        addedAt: DateTime.now(),
      );

      expect(entry.masteryLevel, equals(4));
      expect(VocabEntryModel.masteryLabels[4], equals('熟悉'));
      expect(VocabEntryModel.masteryColors.length, equals(6));
    });
  });
}
