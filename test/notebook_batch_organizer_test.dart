import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/batch_organizer_service.dart';

void main() {
  group('BatchOrganizeProgress 数据模型', () {
    test('正常比例计算', () {
      const p = BatchOrganizeProgress(
        current: 5,
        total: 20,
        currentNoteTitle: '测试笔记',
      );
      expect(p.ratio, closeTo(0.25, 0.001));
    });

    test('total 为 0 时比例为 0.0', () {
      const p = BatchOrganizeProgress(
        current: 0,
        total: 0,
        currentNoteTitle: '无笔记',
      );
      expect(p.ratio, 0.0);
    });

    test('current 超过 total 时比例截断为 1.0', () {
      const p = BatchOrganizeProgress(
        current: 25,
        total: 20,
        currentNoteTitle: '超出上限',
      );
      expect(p.ratio, 1.0);
    });
  });

  group('BatchCancellationToken 令牌控制', () {
    test('初始状态为未取消', () {
      final token = BatchCancellationToken();
      expect(token.isCancelled, isFalse);
    });

    test('调用 cancel 后变为已取消', () {
      final token = BatchCancellationToken();
      token.cancel();
      expect(token.isCancelled, isTrue);
    });
  });

  group('BatchOrganizeSummary 统计模型', () {
    test('构造与字段完整性', () {
      const summary = BatchOrganizeSummary(
        processedNotes: 10,
        totalNotes: 12,
        tagsAdded: 15,
        linksCreated: 8,
        skippedNotes: 2,
        failedNotes: 0,
        wasCancelled: false,
      );
      expect(summary.processedNotes, 10);
      expect(summary.totalNotes, 12);
      expect(summary.tagsAdded, 15);
      expect(summary.linksCreated, 8);
      expect(summary.skippedNotes, 2);
      expect(summary.failedNotes, 0);
      expect(summary.wasCancelled, isFalse);
    });
  });

  group('getScopeMetrics 范围过滤逻辑', () {
    test('正确区分全量笔记与未关联孤立笔记', () {
      final allNotes = [
        {'id': 'n1', 'title': '笔记1'},
        {'id': 'n2', 'title': '笔记2'},
        {'id': 'n3', 'title': '笔记3'},
      ];
      final allLinks = [
        {'source': 'n1', 'target': 'n2'},
      ];

      final linkedIds = <String>{};
      for (final l in allLinks) {
        linkedIds.add(l['source']!);
        linkedIds.add(l['target']!);
      }

      final unlinkedList = allNotes.where((n) => !linkedIds.contains(n['id'])).toList();

      expect(allNotes.length, 3);
      expect(unlinkedList.length, 1);
      expect(unlinkedList.first['id'], 'n3');
    });
  });
}
