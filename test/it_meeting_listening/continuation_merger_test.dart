import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/continuation_merger.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/transcript_parser.dart';

void main() {
  MeetingTurn turn(int index, String slot, String text, {int ts = 0}) =>
      MeetingTurn(index: index, slotId: slot, timestampMs: ts, text: text);

  group('合并规则', () {
    test('上一轮无句末标点、下一轮小写开头 → 合并', () {
      final turns = [
        turn(0, '发言人 1',
            'In ABD, in a zoo, right? And sorry, I should be a second that people and they need to install a clock, also took on the client book, uh, during'),
        turn(1, '发言人 2', 'the...I can take the command, command line tool, like, okay,'),
      ];
      final groups = ContinuationMerger.group(turns);
      expect(groups, hasLength(1));
      expect(groups.single.turnIndices, [0, 1]);
      // 整组用组首的说话人音色
      expect(groups.single.slotId, '发言人 1');
    });

    test('上一轮有句末标点 → 不合并', () {
      final turns = [
        turn(0, '发言人 1', "Okay, that's the plan."),
        turn(1, '发言人 2', 'next topic, anyone?'),
      ];
      final groups = ContinuationMerger.group(turns);
      expect(groups, hasLength(2));
    });

    test('问号与感叹号同样终止一句', () {
      for (final tail in ['really?', 'wow!']) {
        final groups = ContinuationMerger.group([
          turn(0, '发言人 1', tail),
          turn(1, '发言人 2', 'lowercase start'),
        ]);
        expect(groups, hasLength(2), reason: '结尾是 "$tail" 时不该合并');
      }
    });

    test('中文开头不合并——它不是续句信号', () {
      final turns = [
        turn(0, '发言人 1', 'and then we shipped it without'),
        turn(1, '发言人 2', '我们下周再谈这个'),
      ];
      expect(ContinuationMerger.group(turns), hasLength(2));
    });

    test('数字或引号开头不合并', () {
      final turns = [
        turn(0, '发言人 1', 'we counted'),
        turn(1, '发言人 2', '3 of them'),
      ];
      expect(ContinuationMerger.group(turns), hasLength(2));
    });

    test('首轮永远自成一组', () {
      final groups = ContinuationMerger.group([turn(0, '发言人 1', 'lowercase opener')]);
      expect(groups.single.turnIndices, [0]);
    });

    test('连续三轮续句并成一组', () {
      final turns = [
        turn(0, '发言人 1', 'we need to'),
        turn(1, '发言人 2', 'check the'),
        turn(2, '发言人 3', 'gateway logs'),
      ];
      final groups = ContinuationMerger.group(turns);
      expect(groups, hasLength(1));
      expect(groups.single.turnIndices, [0, 1, 2]);
      expect(groups.single.isMerged, isTrue);
    });

    test('每个轮次恰好属于一个组', () {
      final turns = [
        turn(0, 'a', 'one.'),
        turn(1, 'b', 'two'),
        turn(2, 'c', 'three.'),
        turn(3, 'd', 'four'),
      ];
      final groups = ContinuationMerger.group(turns);
      final covered = groups.expand((g) => g.turnIndices).toList()..sort();
      expect(covered, [0, 1, 2, 3]);
    });

    test('空列表返回空组', () {
      expect(ContinuationMerger.group(const []), isEmpty);
    });
  });

  group('合成文本', () {
    test('组内各轮用空格接上', () {
      final turns = [
        turn(0, 'a', 'we need to'),
        turn(1, 'b', 'check the'),
      ];
      final g = ContinuationMerger.group(turns).single;
      expect(ContinuationMerger.synthesisText(turns, g), 'we need to check the');
    });
  });

  group('真实样例（本机存在时才跑）', () {
    const sample = '/Users/simon/Downloads/'
        'sea-doc-main-3962826157dbab79e85ee5b1f17b1ca1cd87cd32/'
        'communications/20261020-ai-agent-security-review/'
        '逐字稿_原文_20261020.md';

    test('合并后组数明显少于轮数，且没有组跨句末标点', () async {
      if (!File(sample).existsSync()) {
        markTestSkipped('真实样例不在本机：$sample');
        return;
      }
      final parsed = await TranscriptParser.parseFile(sample);
      final groups = ContinuationMerger.group(parsed.turns);

      expect(groups.length, lessThan(parsed.turns.length));
      // 合并掉的轮次，正是那些"被切断"的轮次
      final mergedTurns =
          groups.where((g) => g.isMerged).fold<int>(0, (a, g) => a + g.length - 1);
      expect(mergedTurns, greaterThan(30));

      // 合成文本不该把两句完整的话黏在一起
      for (final g in groups.where((g) => g.isMerged)) {
        final text = ContinuationMerger.synthesisText(parsed.turns, g);
        expect(text.trim(), isNotEmpty);
      }
    });
  });
}
