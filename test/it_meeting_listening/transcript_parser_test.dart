import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/services/transcript_parser.dart';

/// 逐字稿解析的关键断言。
///
/// **为什么用合成文稿而不是把样例提交进仓库**：样例是用户的真实会议内容，
/// 不该躺在测试固件里。这里按同样形态合成一份（NBSP 分隔、152 轮、6 个槽位、
/// 中英混排），断言的是解析器的行为，不是那份文稿。
///
/// 另外留了一条：如果本机存在真实样例，就顺带校验一次真实形态（不存在则跳过）。
void main() {
  /// 生成一份形态与会议记录系统一致的文稿。
  ///
  /// 关键点：**分隔符是不间断空格**。这是实测最容易踩的坑。
  String buildTranscript({
    int turnCount = 152,
    int slotCount = 6,
    bool useNbsp = true,
    List<(int, int)>? timestamps,
  }) {
    final nbsp = useNbsp ? ' ' : ' ';
    final b = StringBuffer()
      ..writeln('# 10-20 AI Agent Security and Governance Review')
      ..writeln()
      ..writeln('>${nbsp}创建时间:${nbsp}2026-10-20${nbsp}15:02')
      ..writeln()
      ..writeln('>${nbsp}转写时长:${nbsp}20分6秒')
      ..writeln()
      ..writeln('## 关键词')
      ..writeln()
      ..writeln('${nbsp}AI${nbsp}${nbsp}${nbsp}${nbsp}governance'
          '${nbsp}${nbsp}${nbsp}${nbsp}isolated${nbsp}${nbsp}${nbsp}${nbsp}VPC')
      ..writeln()
      ..writeln('## 转文字');

    for (var i = 0; i < turnCount; i++) {
      final slot = (i % slotCount) + 1;
      final sec = timestamps != null
          ? timestamps[i % timestamps.length].$1
          : i * 2;
      final mm = sec ~/ 60;
      final ss = sec % 60;
      final ts = '00:${mm.toString().padLeft(2, '0')}:'
          '${ss.toString().padLeft(2, '0')}';
      b
        ..writeln()
        ..writeln('发言人$nbsp$slot$nbsp$ts')
        ..writeln()
        ..writeln('This is turn $i from speaker $slot.');
    }
    return b.toString();
  }

  group('形态解析', () {
    test('NBSP 分隔的说话人行能解析出全部轮次与槽位', () {
      final parsed = TranscriptParser.parse(buildTranscript());
      expect(parsed.turns, hasLength(152));
      expect(parsed.slots, hasLength(6));
      expect(parsed.slots.map((s) => s.id).first, '发言人 1');
    });

    test('普通空格的分隔同样能解析（不依赖 NBSP 这一种形态）', () {
      final parsed = TranscriptParser.parse(buildTranscript(useNbsp: false));
      expect(parsed.turns, hasLength(152));
    });

    test('标题、转写时长、关键词都被提取', () {
      final parsed = TranscriptParser.parse(buildTranscript());
      expect(parsed.title, contains('AI Agent Security'));
      expect(parsed.declaredDurationMs, 20 * 60 * 1000 + 6 * 1000);
      expect(parsed.keywords, containsAll(['AI', 'governance', 'VPC']));
      // 关键词去重且保序
      expect(parsed.keywords, ['AI', 'governance', 'isolated', 'VPC']);
    });

    test('轮次下标连续、时间戳按原文保留', () {
      final parsed = TranscriptParser.parse(buildTranscript());
      for (var i = 0; i < parsed.turns.length; i++) {
        expect(parsed.turns[i].index, i);
      }
      expect(parsed.turns.first.timestampMs, 0);
      expect(parsed.turns[1].timestampMs, 2000);
    });

    test('多行正文合并为一段', () {
      const raw = '''
# t
## 转文字

发言人 1 00:00:01

first line
second line

发言人 2 00:00:05

ok
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns.first.text, 'first line second line');
    });

    test('两段式时间戳 MM:SS 也接受', () {
      const raw = '''
# t
## 转文字

发言人 1 00:01

hi
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns.first.timestampMs, 1000);
    });

    test('标题里的 Markdown 转义下划线被还原', () {
      const raw = '''
# 纪要\\_10-20 AI Agent Security

## 转文字

发言人 1 00:00:01

hi
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.title, '纪要_10-20 AI Agent Security');
    });
  });

  group('校验与失败', () {
    test('时间戳倒序时报出行号', () {
      final raw = '''
# t
## 转文字

发言人 1 00:00:10

a

发言人 2 00:00:05

b
''';
      expect(
        () => TranscriptParser.parse(raw),
        throwsA(isA<TranscriptParseException>()
            .having((e) => e.lineNumber, 'lineNumber', 8)),
      );
    });

    test('没有轮次时报出可操作的提示', () {
      const raw = '# t\n## 转文字\n\n没有说话人行\n';
      expect(
        () => TranscriptParser.parse(raw),
        throwsA(isA<TranscriptParseException>().having(
            (e) => e.message, 'message', contains('发言人 1 00:00:01'))),
      );
    });

    test('时间戳格式不认识时报错而不是静默归零', () {
      const raw = '''
# t
## 转文字

发言人 1 00:xx:01

hi
''';
      // 说话人行正则不匹配，于是整段没有任何轮次
      expect(() => TranscriptParser.parse(raw),
          throwsA(isA<TranscriptParseException>()));
    });
  });

  group('标识与内容哈希', () {
    test('同一路径恒得同一标识', () {
      expect(TranscriptParser.meetingIdFor('/a/b.md'),
          TranscriptParser.meetingIdFor('/a/b.md'));
      expect(TranscriptParser.meetingIdFor('/a/b.md'),
          isNot(TranscriptParser.meetingIdFor('/a/c.md')));
    });

    test('只差换行符与 NBSP 不算内容变化', () {
      expect(
        TranscriptParser.contentHashOf('a b\r\nc'),
        TranscriptParser.contentHashOf('a b\nc'),
      );
    });

    test('改了一个字就算内容变化', () {
      expect(TranscriptParser.contentHashOf('hello world'),
          isNot(TranscriptParser.contentHashOf('hello worlds')));
    });
  });

  group('多平台形态', () {
    test('豆包：无二级标题 + @说话人 + MM:SS', () {
      const raw = '''
# 智能纪要：新录音 2026年10月8日

录音时间：2026\\-10\\-08 15:10 \\- 2026\\-10\\-08 16:07

@说话人 1  00:00
yes.ok, going to.

@说话人 1  00:15
the software image list, need to install on the platform, right?

@说话人 2  00:20
do they have the list?
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns, hasLength(3));
      expect(parsed.slots.map((s) => s.id).toList(), ['说话人 1', '说话人 2']);
      expect(parsed.declaredDurationMs, 57 * 60 * 1000);
      expect(parsed.keywordsMissing, isTrue);
      expect(parsed.isProcessedDocument, isFalse);
      expect(parsed.turns.first.text, 'yes.ok, going to.');
    });

    test('真实姓名槽位', () {
      const raw = '''
# 海庭项目沟通

## 转文字

李嘉成 00:00:03

嗯，有人打个招呼吗？

许怿 00:00:44

哎，你跟力哥同步一下呗。
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns, hasLength(2));
      expect(parsed.slots.map((s) => s.id).toList(), ['李嘉成', '许怿']);
      expect(parsed.turns.last.text, '哎，你跟力哥同步一下呗。');
      expect(parsed.isProcessedDocument, isFalse);
    });

    test('归档件：跳过说明表格、代码块与附录', () {
      const raw = '''
# 项目周例会（中英对照）

## 说明

| 项 | 内容 |
|----|------|
| 时间 | 2026-10-22，39 分 57 秒 |
| 平台 | Microsoft Teams |

## 原文（导出件一字未改）

导出件自带的关键词行（原样）：

```
 Cloud    Code    AVD
```

发言人 1 00:00:05

RightLet me pick my colleagues.

> 【译】好，我把同事拉进来。

发言人 2 00:00:45

呃。Jocelyn today and see

> 【译】呃……Jocelyn 今天……再看吧。

## 附录：转写噪音
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.isProcessedDocument, isTrue);
      expect(parsed.turns, hasLength(2));
      // 译文不能混进正文
      expect(parsed.turns.first.text, 'RightLet me pick my colleagues.');
      expect(parsed.turns.first.text, isNot(contains('【译】')));
      expect(parsed.turns.last.text, '呃。Jocelyn today and see');
      // 表格行与代码块里的内容都不该变成轮次
      expect(parsed.turns.any((t) => t.text.contains('Microsoft Teams')), isFalse);
      expect(parsed.turns.any((t) => t.text.contains('Cloud    Code')), isFalse);
    });

    test('普通句子独占一行不会被当成说话人', () {
      const raw = '''
# t

## 转文字

发言人 1 00:00:01

Meeting at 10:30

see you at 10:30 tomorrow

发言人 2 00:00:05

ok.
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns, hasLength(2));
      expect(parsed.turns.first.text, contains('Meeting at 10:30'));
      expect(parsed.turns.first.text, contains('see you at 10:30 tomorrow'));
    });

    test('代码块里的假说话人行不被识别', () {
      const raw = '''
# t

## 转文字

```
发言人 1 00:00:01
```

发言人 1 00:00:10

real.
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns, hasLength(1));
      expect(parsed.turns.single.text, 'real.');
    });

    test('表格行里的时间不被识别为说话人', () {
      const raw = '''
# t

| 发言人 1 | 00:00:01 |

## 转文字

发言人 1 00:00:10

real.
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.turns, hasLength(1));
    });

    test('关键词段缺失被标记但不阻断', () {
      const raw = '''
# t

## 转文字

发言人 1 00:00:01

hello.
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.keywordsMissing, isTrue);
      expect(parsed.turns, hasLength(1));
    });

    test('关键词被逗号分隔时也能拆开', () {
      const raw = '''
# t

## 关键词

 governance，VPC、isolated

## 转文字

发言人 1 00:00:01

hi.
''';
      final parsed = TranscriptParser.parse(raw);
      expect(parsed.keywords, containsAll(['governance', 'VPC', 'isolated']));
    });
  });

  group('真实语料的多种形态（本机存在时才跑）', () {
    const base = '/Users/simon/Downloads/'
        'sea-doc-main-3962826157dbab79e85ee5b1f17b1ca1cd87cd32';

    /// 文件 → 最少轮次数（按实测，留一点余量）。
    const cases = {
      '$base/communications/20261015-weekly-customer/附件/钉钉原始-逐字稿_20261015.md': 400,
      '$base/communications/20261022-项目周例会-客户沟通/逐字稿_原文_EN_20261022.md': 250,
      '$base/communications/20261022-项目周例会-客户沟通/逐字稿_中英对照_20261022.md': 250,
      '$base/communications/20261008-weekly-customer/附件/豆包原始-逐字稿_20261008.md': 100,
      '$base/communications/20261015-weekly-customer/附件/豆包原始-逐字稿_20261015.md': 50,
      '$base/communications/20261015-项目周例会-内部会后/海庭内部总结.md': 700,
      '$base/tech/solutions/20260807-私有化部署DSV4论证/会议/海庭项目·华为云大模型私有化部署事宜沟通 20260807.md': 100,
    };

    for (final entry in cases.entries) {
      final name = entry.key.split('/').last;
      test('解析 $name', () async {
        if (!File(entry.key).existsSync()) {
          markTestSkipped('样例不在本机：${entry.key}');
          return;
        }
        final parsed = await TranscriptParser.parseFile(entry.key);
        expect(parsed.turns.length, greaterThanOrEqualTo(entry.value));
        expect(parsed.slots, isNotEmpty);
        // 时间戳单调（解析器已保证，这里再断言一次产物）
        for (var i = 1; i < parsed.turns.length; i++) {
          expect(parsed.turns[i].timestampMs,
              greaterThanOrEqualTo(parsed.turns[i - 1].timestampMs));
        }
        // 译文引用块不该出现在任何一轮里
        expect(parsed.turns.any((t) => t.text.contains('【译】')), isFalse);
      });
    }
  });

  group('真实样例（本机存在时才跑）', () {
    const sample = '/Users/simon/Downloads/'
        'sea-doc-main-3962826157dbab79e85ee5b1f17b1ca1cd87cd32/'
        'communications/20261020-ai-agent-security-review/'
        '逐字稿_原文_20261020.md';

    test('解析出 152 轮 / 6 个槽位', () async {
      if (!File(sample).existsSync()) {
        // 样例不在本机（其它机器 / CI）——跳过而不是失败。
        markTestSkipped('真实样例不在本机：$sample');
        return;
      }
      final parsed = await TranscriptParser.parseFile(sample);
      expect(parsed.turns, hasLength(152));
      expect(parsed.slots.map((s) => s.id).toList(),
          ['发言人 1', '发言人 2', '发言人 3', '发言人 4', '发言人 5', '发言人 6']);
      expect(parsed.declaredDurationMs, 20 * 60 * 1000 + 6 * 1000);
      expect(parsed.keywords, contains('governance'));
      // 39% 的轮次是跨说话人断句——这是后续续句合并要处理的对象。
      final lowercaseStarts =
          parsed.turns.where((t) => t.text.isNotEmpty && t.text[0] == t.text[0].toLowerCase() && RegExp(r'[a-z]').hasMatch(t.text[0])).length;
      expect(lowercaseStarts, greaterThan(50));
    });
  });
}
