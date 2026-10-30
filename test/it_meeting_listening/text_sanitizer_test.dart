import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/text_sanitizer.dart';

void main() {
  group('sanitizeForSynthesis 破折号处理', () {
    test('em dash 替换为逗号并保留语义停顿', () {
      expect(
        sanitizeForSynthesis("Today I'll continue — but I'm blocked."),
        "Today I'll continue, but I'm blocked.",
      );
    });

    test('en dash 同样替换', () {
      expect(
        sanitizeForSynthesis("Theory one – a config change – is likely."),
        "Theory one, a config change, is likely.",
      );
    });

    test('行首行尾的双连字符替换为逗号', () {
      expect(
        sanitizeForSynthesis("-- I think we should roll back."),
        ", I think we should roll back.",
      );
    });

    test('两侧有空白的双连字符替换为逗号', () {
      expect(
        sanitizeForSynthesis("the retry logic -- it keeps failing -- is broken."),
        "the retry logic, it keeps failing, is broken.",
      );
    });

    test('替换后不留下重复逗号', () {
      expect(
        sanitizeForSynthesis("a — b"),
        "a, b",
      );
    });
  });

  group('sanitizeForSynthesis 不改动术语与数字', () {
    test('HTTP 状态码保持不变', () {
      expect(
        sanitizeForSynthesis("The service is returning 503s across all regions."),
        "The service is returning 503s across all regions.",
      );
    });

    test('带千分位的数量保持不变', () {
      expect(
        sanitizeForSynthesis(
            "The service processes roughly 1,200 transactions per minute normally."),
        "The service processes roughly 1,200 transactions per minute normally.",
      );
    });

    test('UTC 时间戳保持不变', () {
      expect(
        sanitizeForSynthesis("Started at 14:32 UTC."),
        "Started at 14:32 UTC.",
      );
    });

    test('工单号保持不变', () {
      expect(
        sanitizeForSynthesis("Ticket JIRA-4821 is a P1 blocker."),
        "Ticket JIRA-4821 is a P1 blocker.",
      );
    });

    test('IT 术语保持不变', () {
      const terms = [
        'rollback',
        'hotfix',
        'blocker',
        'scope creep',
        'trade-off',
        'idempotent',
        'circuit breaker',
        'upstream payment provider',
      ];
      for (final t in terms) {
        expect(sanitizeForSynthesis(t), t, reason: '术语 "$t" 不应被改动');
      }
    });
  });

  group('sanitizeForSynthesis 空白与引号', () {
    test('连续空白折叠为单个空格', () {
      expect(
        sanitizeForSynthesis("No   blockers. \n\n  Noted."),
        "No blockers. Noted.",
      );
    });

    test('剥除首尾成对的直引号', () {
      expect(
        sanitizeForSynthesis('"Okay, let\'s get a status update."'),
        "Okay, let's get a status update.",
      );
    });

    test('剥除首尾成对的弯引号', () {
      expect(
        sanitizeForSynthesis('“Okay, let\'s get a status update.”'),
        "Okay, let's get a status update.",
      );
    });

    test('句内引号保留', () {
      expect(
        sanitizeForSynthesis('He said "that is the blocker" yesterday.'),
        'He said "that is the blocker" yesterday.',
      );
    });

    test('空串与纯空白返回空串', () {
      expect(sanitizeForSynthesis(''), '');
      expect(sanitizeForSynthesis('   \n  '), '');
    });
  });

  group('sanitizeForSynthesis 保留填充词', () {
    test('逗号分隔的填充词完整保留', () {
      expect(
        sanitizeForSynthesis("Um, uh, yeah, I mean, the test is still failing."),
        "Um, uh, yeah, I mean, the test is still failing.",
      );
    });

    test('句号分隔的填充词完整保留', () {
      expect(
        sanitizeForSynthesis("Uh. I think. Um. We should roll back."),
        "Uh. I think. Um. We should roll back.",
      );
    });
  });
}
