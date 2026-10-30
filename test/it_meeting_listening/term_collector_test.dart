import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/listening_term_collector.dart';

void main() {
  group('ListeningTermSource 解析', () {
    test('解析本工具写入的 sourceContext', () {
      const source = ListeningTermSource(
        clipId: 'standup_1_s0',
        sceneId: 'standup',
        clipTitle: 'Morning standup',
        sentence: 'The rollback is blocked.',
        startMs: 12000,
        endMs: 18000,
      );
      final parsed =
          ListeningTermSource.fromSourceContext(_encode(source.toJson()));
      expect(parsed, isNotNull);
      expect(parsed!.clipId, 'standup_1_s0');
      expect(parsed.sceneId, 'standup');
      expect(parsed.sentence, 'The rollback is blocked.');
      expect(parsed.startMs, 12000);
      expect(parsed.endMs, 18000);
    });

    test('非本工具的 sourceContext（纯文本）解析为 null，不报错', () {
      expect(ListeningTermSource.fromSourceContext('来自划词查词'), isNull);
    });

    test('null / 空串解析为 null', () {
      expect(ListeningTermSource.fromSourceContext(null), isNull);
      expect(ListeningTermSource.fromSourceContext(''), isNull);
    });

    test('非法 JSON 解析为 null，不抛异常', () {
      expect(ListeningTermSource.fromSourceContext('{ 这不是 json'), isNull);
    });

    test('tool 字段不匹配时解析为 null', () {
      expect(
        ListeningTermSource.fromSourceContext('{"tool":"other","clipId":"x"}'),
        isNull,
      );
    });

    test('缺 clipId 时解析为 null', () {
      expect(
        ListeningTermSource.fromSourceContext('{"tool":"it-meeting-listening"}'),
        isNull,
      );
    });
  });
}

String _encode(Map<String, dynamic> json) {
  // 避免为测试引入 dart:convert 的依赖写法错误——直接手写最简 JSON。
  return '{"tool":"${json['tool']}","clipId":"${json['clipId']}",'
      '"sceneId":"${json['sceneId']}","clipTitle":"${json['clipTitle']}",'
      '"sentence":"${json['sentence']}","startMs":${json['startMs']},'
      '"endMs":${json['endMs']}}';
}
