import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_vocabulary_index.dart';

void main() {
  RealMeeting meeting(
    String id, {
    required List<String> texts,
    List<String> keywords = const [],
    String title = 'Meeting',
  }) =>
      RealMeeting(
        id: id,
        title: title,
        sourcePath: '/in/$id.md',
        fileName: '$id.md',
        contentHash: 'h',
        declaredDurationMs: 0,
        keywords: keywords,
        slots: const [SpeakerSlot(id: '发言人 1', turnCount: 1)],
        turns: [
          for (var i = 0; i < texts.length; i++)
            MeetingTurn(
                index: i,
                slotId: '发言人 1',
                timestampMs: i * 5000,
                text: texts[i]),
        ],
        importedAt: DateTime(2026, 10, 20),
      );

  group('分词与归一化', () {
    test('只取字母开头的词', () {
      expect(MeetingVocabularyIndex.tokenize('503s and 14:32 UTC'),
          ['s', 'and', 'UTC']);
    });

    test('保留内部连字符与缩写', () {
      expect(MeetingVocabularyIndex.tokenize('roll-back the end-to-end'),
          ['roll-back', 'the', 'end-to-end']);
    });

    test('所有格与大小写归一化', () {
      expect(MeetingVocabularyIndex.normalizeWord("Zest's"), 'zest');
      expect(MeetingVocabularyIndex.normalizeWord("Customer’s"), 'customer');
      // contractions 不是所有格，拆开就没意义了
      expect(MeetingVocabularyIndex.normalizeWord("they're"), "they're");
    });
  });

  group('词频累计', () {
    test('两场会的次数相加，分场明细可查', () {
      final index = MeetingVocabularyIndex.build([
        meeting('a', texts: ['governance here', 'governance again']),
        meeting('b', texts: ['governance once']),
      ]);
      final entry = index
          .entries()
          .firstWhere((e) => e.word == 'governance');
      expect(entry.count, 3);
      expect(entry.byMeeting, {'a': 2, 'b': 1});
    });

    test('停用词默认不占主列表，可切换显示', () {
      final index = MeetingVocabularyIndex.build([
        meeting('a', texts: ['the governance of the system']),
      ]);
      expect(index.entries().map((e) => e.word), isNot(contains('the')));
      expect(index.entries(includeStopwords: true).map((e) => e.word),
          contains('the'));
    });

    test('只出现一次且不在关键词段的词被折叠，但仍可查', () {
      final index = MeetingVocabularyIndex.build([
        meeting('a', texts: ['we discussed governance and aCRI today']),
      ]);
      final primary = index.entries().map((e) => e.word).toList();
      expect(primary, isNot(contains('acri')));

      final withNoisy = index.entries(includeNoisy: true);
      final noisy = withNoisy.firstWhere((e) => e.word == 'acri');
      expect(noisy.noisy, isTrue);
      expect(noisy.count, 1);

      // 折叠不影响查询
      expect(index.postingsFor('aCRI'), hasLength(1));
    });

    test('关键词段里的低频词不被折叠', () {
      final index = MeetingVocabularyIndex.build([
        meeting('a',
            texts: ['we use VPC for isolation'],
            keywords: const ['VPC']),
      ]);
      final vpc = index.entries().firstWhere((e) => e.word == 'vpc');
      expect(vpc.noisy, isFalse);
    });
  });

  group('反查', () {
    test('给出会议、说话人、句子与时间点', () {
      final index = MeetingVocabularyIndex.build([
        meeting('a', texts: ['first line', 'we talk about VPC', 'third'],
            keywords: const ['VPC']),
      ]);
      final hits = index.postingsFor('vpc');
      expect(hits, hasLength(1));
      expect(hits.single.meetingId, 'a');
      expect(hits.single.turnIndex, 1);
      expect(hits.single.slotId, '发言人 1');
      expect(hits.single.timestampMs, 5000);
      expect(hits.single.sentence, 'we talk about VPC');
    });

    test('跨会议结果按会议标题与轮次排序', () {
      final index = MeetingVocabularyIndex.build([
        meeting('b', texts: ['VPC here'], title: 'Zeta', keywords: const ['VPC']),
        meeting('a', texts: ['VPC here'], title: 'Alpha', keywords: const ['VPC']),
      ]);
      expect(index.postingsFor('vpc').map((p) => p.meetingTitle),
          ['Alpha', 'Zeta']);
    });
  });

  group('增量维护与全量重建一致', () {
    final m1 = meeting('a', texts: ['governance first', 'second governance']);
    final m2 = meeting('b', texts: ['governance third', 'noise token']);

    test('加会议的结果与全量构建一致', () {
      final incremental = MeetingVocabularyIndex.build([m1]).addMeeting(m2);
      final full = MeetingVocabularyIndex.build([m1, m2]);
      expect(incremental.postingsFor('governance').length,
          full.postingsFor('governance').length);
      expect(incremental.perMeeting, full.perMeeting);
    });

    test('删会议后次数扣减且反查清空', () {
      final both = MeetingVocabularyIndex.build([m1, m2]);
      expect(both.entries(includeStopwords: true)
          .firstWhere((e) => e.word == 'governance').count, 3);

      final onlyA = both.removeMeeting('b');
      final g = onlyA.entries(includeStopwords: true)
          .firstWhere((e) => e.word == 'governance');
      expect(g.count, 2);
      expect(onlyA.postingsFor('governance').map((p) => p.meetingId).toSet(),
          {'a'});
    });

    test('重新导入同一场会不翻倍', () {
      final once = MeetingVocabularyIndex.build([m1]);
      final twice = once.addMeeting(m1);
      expect(twice.entries(includeStopwords: true)
          .firstWhere((e) => e.word == 'governance').count, 2);
    });
  });

  group('落盘', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('vocab_index_test');
      AppPaths.overrideRootForTesting(tmp);
    });

    tearDown(() async {
      AppPaths.resetForTesting();
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('保存后可读回，查询结果不变', () async {
      final store = MeetingVocabularyStore();
      final index = MeetingVocabularyIndex.build([
        meeting('a', texts: ['we talk about VPC']),
      ]);
      await store.save(index);

      final loaded = (await store.load())!;
      expect(loaded.postingsFor('vpc'), hasLength(1));
      expect(loaded.entries(includeStopwords: true).length,
          index.entries(includeStopwords: true).length);
    });

    test('索引缺失时返回 null 而不是抛异常', () async {
      expect(await MeetingVocabularyStore().load(), isNull);
    });

    test('损坏的索引返回 null（调用方据此重建）', () async {
      await AppPaths.meetingVocabularyIndexFile.parent.create(recursive: true);
      await AppPaths.meetingVocabularyIndexFile.writeAsString('{broken');
      expect(await MeetingVocabularyStore().load(), isNull);
    });
  });
}
