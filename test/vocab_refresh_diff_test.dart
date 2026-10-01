import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/vocab_book/models/vocab_entry.dart';
import 'package:V8WorkToolbox/tools/vocab_book/ui/vocab_book_page.dart';

/// 生词本聚焦刷新的比对逻辑（capability: `vocab-book-fresh-on-focus`）。
///
/// 这条比对是"刷新必须静默"的唯一保障：无变化时 rebuild 一次，用户就看到
/// 一次闪烁。所以它的每一个判定都要钉住。
///
/// 字段范围刻意**不是**全字段：列表只展示 word / partOfSpeech /
/// definitions.first / mastery / tags（以及筛选栏的 mastery 与 tag 计数）。
/// `phrases`、`examples`、`audioUrl`、`addedAt` 不在列表里，它们变了却
/// 重建就是白闪一次。
void main() {
  VocabEntryModel entry({
    String id = 'e1',
    String word = 'hello',
    String? partOfSpeech,
    String def = '喂，你好',
    int mastery = 0,
    List<String> tags = const [],
  }) {
    return VocabEntryModel(
      id: id,
      word: word,
      partOfSpeech: partOfSpeech,
      definitions: def.isEmpty ? const [] : [def],
      examples: const [],
      addedAt: DateTime(2026),
      masteryLevel: mastery,
      tags: tags,
    );
  }

  group('vocabListChanged', () {
    test('identical lists report no change', () {
      final before = [entry(id: 'a'), entry(id: 'b')];
      final after = [entry(id: 'a'), entry(id: 'b')];
      expect(vocabListChanged(before, after), isFalse);
    });

    test('both empty report no change', () {
      expect(vocabListChanged(const [], const []), isFalse);
    });

    test('an added entry is a change', () {
      final before = [entry(id: 'a')];
      final after = [entry(id: 'a'), entry(id: 'b')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a removed entry is a change', () {
      final before = [entry(id: 'a'), entry(id: 'b')];
      final after = [entry(id: 'a')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a mastery-only change IS a change', () {
      // 这条最关键：mastery 不在 word 里，只比重数或只比 word 会漏掉它。
      // 从别处（浮窗、另一个窗口）改了掌握程度，用户回来必须看到。
      final before = [entry(id: 'a', mastery: 0)];
      final after = [entry(id: 'a', mastery: 3)];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a tag-only change IS a change', () {
      final before = [entry(id: 'a')];
      final after = [entry(id: 'a', tags: const ['考研'])];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('definitions going from empty to non-empty IS a change', () {
      // 从浏览器深链加进来的词条本来没有释义；之后补上了，列表必须反映。
      final before = [entry(id: 'a', def: '')];
      final after = [entry(id: 'a', def: 'n. 问候')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a definition edit is a change', () {
      final before = [entry(id: 'a', def: '喂')];
      final after = [entry(id: 'a', def: '你好')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a word typo fix is a change', () {
      final before = [entry(id: 'a', word: 'helo')];
      final after = [entry(id: 'a', word: 'hello')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('partOfSpeech appearing is a change', () {
      final before = [entry(id: 'a')];
      final after = [entry(id: 'a', partOfSpeech: 'int.')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a second definition being appended is NOT a change', () {
      // 列表只显示 definitions.first。第二条释义进来，列表看起来一模一样，
      // 不该为它闪一次。
      final before = [entry(id: 'a', def: '喂')];
      final after = [
        VocabEntryModel(
          id: 'a',
          word: 'hello',
          definitions: const ['喂', '你好'],
          examples: const [],
          addedAt: DateTime(2026),
        ),
      ];
      expect(vocabListChanged(before, after), isFalse);
    });

    test('an examples-only change is NOT a change', () {
      final before = [entry(id: 'a')];
      final after = [
        VocabEntryModel(
          id: 'a',
          word: 'hello',
          definitions: const ['喂，你好'],
          examples: const ['Hello, world.'],
          addedAt: DateTime(2026),
        ),
      ];
      expect(vocabListChanged(before, after), isFalse);
    });

    test('order matters', () {
      // 列表按序展示；同样的两条换个顺序，选中项/滚动位置都会错位。
      final before = [entry(id: 'a'), entry(id: 'b')];
      final after = [entry(id: 'b'), entry(id: 'a')];
      expect(vocabListChanged(before, after), isTrue);
    });

    test('a different id with identical display is a change', () {
      // id 是选中项跟踪的凭据；id 变了即使显示一样也要重建，否则选中会漂。
      final before = [entry(id: 'a')];
      final after = [entry(id: 'b')];
      expect(vocabListChanged(before, after), isTrue);
    });
  });

  group('vocabEntrySignature', () {
    test('same display fields produce the same signature', () {
      final a = entry(id: 'a');
      final b = entry(id: 'a', def: '喂，你好');
      expect(vocabEntrySignature(a), vocabEntrySignature(b));
    });

    test('the signature covers exactly the displayed fields', () {
      // 逐个字段改一遍，签名必须跟着变——这条守住"覆盖范围"本身。
      final base = entry(id: 'a');
      expect(vocabEntrySignature(base.copyWith(word: 'other')),
          isNot(vocabEntrySignature(base)));
      expect(vocabEntrySignature(base.copyWith(definitions: const ['别的'])),
          isNot(vocabEntrySignature(base)));
      expect(vocabEntrySignature(base.copyWith(masteryLevel: 2)),
          isNot(vocabEntrySignature(base)));
      expect(vocabEntrySignature(base.copyWith(tags: const ['x'])),
          isNot(vocabEntrySignature(base)));
      expect(vocabEntrySignature(base.copyWith(partOfSpeech: 'n.')),
          isNot(vocabEntrySignature(base)));
      expect(vocabEntrySignature(base.copyWith(id: 'zzz')),
          isNot(vocabEntrySignature(base)));
    });
  });
}
