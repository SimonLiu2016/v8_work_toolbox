import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/scheduled_news_service.dart';

/// 快报来源的序列化（capability: `ai-news-assistant` 的 Briefing sources）。
///
/// 重点是旧条目的兼容：`sources` 是新增字段，历史快报里没有它。反序列化必须
/// 悄悄降级为空列表，而不是抛异常——否则老用户一打开快报历史就崩。
void main() {
  group('BriefingSource serialization', () {
    test('round-trips through json', () {
      const source = BriefingSource(title: '某篇报道', url: 'https://example.com/a');

      final restored = BriefingSource.fromJson(
        jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>,
      );

      expect(restored.title, '某篇报道');
      expect(restored.url, 'https://example.com/a');
    });
  });

  group('NewsBriefingItem sources', () {
    test('round-trips sources through json', () {
      final item = NewsBriefingItem(
        id: 'b1',
        taskId: 't1',
        taskTitle: '追踪某发布',
        content: '摘要',
        sources: const [
          BriefingSource(title: '报道 A', url: 'https://example.com/a'),
          BriefingSource(title: '报道 B', url: 'https://example.com/b'),
        ],
      );

      final json = jsonDecode(jsonEncode(item.toJson())) as Map<String, dynamic>;
      final restored = NewsBriefingItem.fromJson(json);

      expect(restored.sources.length, 2);
      expect(restored.sources.first.title, '报道 A');
      expect(restored.sources.first.url, 'https://example.com/a');
    });

    test('legacy entry without sources deserializes to an empty list', () {
      // 历史条目：sources 字段入库前生成，json 里根本没有这个键。
      final legacy = <String, dynamic>{
        'id': 'old',
        'taskId': 't1',
        'taskTitle': '旧任务',
        'content': '旧摘要',
        'timestamp': '2026-01-01T00:00:00.000',
        'isRead': true,
      };

      final item = NewsBriefingItem.fromJson(legacy);

      expect(item.sources, isEmpty);
      expect(item.content, '旧摘要');
      expect(item.isRead, isTrue);
    });

    test('null sources entry deserializes to an empty list', () {
      final withNull = <String, dynamic>{
        'id': 'n',
        'taskId': 't',
        'taskTitle': '题',
        'content': '文',
        'timestamp': '2026-01-01T00:00:00.000',
        'sources': null,
      };

      expect(NewsBriefingItem.fromJson(withNull).sources, isEmpty);
    });

    test('malformed source entries are skipped, not fatal', () {
      final messy = <String, dynamic>{
        'id': 'm',
        'taskId': 't',
        'taskTitle': '题',
        'content': '文',
        'timestamp': '2026-01-01T00:00:00.000',
        'sources': [
          {'title': '好的', 'url': 'https://example.com/ok'},
          '不是 map',
          <String, dynamic>{'title': '缺 url'},
        ],
      };

      final item = NewsBriefingItem.fromJson(messy);

      expect(item.sources.length, 2);
      expect(item.sources.first.url, 'https://example.com/ok');
      expect(item.sources.last.url, '', reason: '缺 url 的条目降级为空串，不丢弃整条');
    });
  });
}
