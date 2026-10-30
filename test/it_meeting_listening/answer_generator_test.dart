import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/answer_generator.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_llm.dart';

class _FakeLlm implements RehearsalTextGenerator {
  _FakeLlm(this.output);

  String output;
  final List<String> prompts = [];

  @override
  Future<String> generate(String prompt) async {
    prompts.add(prompt);
    if (output == '__throw__') throw StateError('llm down');
    return output;
  }
}

void main() {
  RealMeeting meeting({
    List<String> texts = const [
      'we reviewed the gateway yesterday.',
      'can you explain how the agent reaches the model?',
      'sure, next topic.',
    ],
    List<String> keywords = const ['gateway', 'VPC'],
  }) =>
      RealMeeting(
        id: 'rm',
        title: 'AI Agent Security Review',
        sourcePath: '/in/a.md',
        fileName: 'a.md',
        contentHash: 'h',
        declaredDurationMs: 0,
        keywords: keywords,
        slots: const [SpeakerSlot(id: '发言人 1', turnCount: 3)],
        turns: [
          for (var i = 0; i < texts.length; i++)
            MeetingTurn(
                index: i,
                slotId: '发言人 1',
                timestampMs: i * 1000,
                text: texts[i]),
        ],
        importedAt: DateTime(2026, 10, 20),
      );

  group('AI 直接回答', () {
    test('提示词带上会议标题、关键词、前文与目标轮', () async {
      final llm = _FakeLlm('We route through the gateway.');
      final gen = AnswerGenerator(llm);
      final draft = await gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1);

      final prompt = llm.prompts.single;
      expect(prompt, contains('AI Agent Security Review'));
      expect(prompt, contains('gateway, VPC'));
      expect(prompt, contains('we reviewed the gateway yesterday.'));
      expect(prompt, contains('can you explain how the agent reaches the model?'));
      // 目标轮之后的发言不进上下文
      expect(prompt, isNot(contains('sure, next topic.')));
      expect(draft.textEn, 'We route through the gateway.');
      expect(draft.truncated, isFalse);
    });

    test('超预算时截断并标记', () async {
      final long = List.generate(
          50, (i) => 'this is a fairly long prior turn number $i with words.');
      final llm = _FakeLlm('ok.');
      final gen = AnswerGenerator(llm, maxContextChars: 200);
      final draft = await gen.suggestAnswer(
          meeting: meeting(texts: [...long, 'question?']), questionTurnIndex: 50);

      expect(draft.truncated, isTrue);
      expect(llm.prompts.single, contains('only the most recent turns'));
    });

    test('目标轮之前没有内容时不崩', () async {
      final llm = _FakeLlm('A reply.');
      final gen = AnswerGenerator(llm);
      final draft = await gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 0);
      expect(draft.textEn, 'A reply.');
    });
  });

  group('中文转英文', () {
    test('中文原文被保留并返回', () async {
      final llm = _FakeLlm('We go through the gateway.');
      final gen = AnswerGenerator(llm);
      final draft = await gen.translateAnswer(
        meeting: meeting(),
        questionTurnIndex: 1,
        chinese: '我们是通过网关走的。',
      );
      expect(draft.textZh, '我们是通过网关走的。');
      expect(draft.textEn, 'We go through the gateway.');
      expect(llm.prompts.single, contains('我们是通过网关走的。'));
      expect(llm.prompts.single, contains('Do not add arguments'));
    });

    test('空中文直接拒绝，不浪费一次调用', () async {
      final llm = _FakeLlm('x');
      final gen = AnswerGenerator(llm);
      expect(
        () => gen.translateAnswer(
            meeting: meeting(), questionTurnIndex: 1, chinese: '   '),
        throwsA(isA<AnswerGenerationException>()),
      );
      expect(llm.prompts, isEmpty);
    });
  });

  group('输出清洗与校验', () {
    test('剥掉代码围栏与首尾引号', () async {
      final gen = AnswerGenerator(_FakeLlm('```\n"Hello there."\n```'));
      final draft = await gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1);
      expect(draft.textEn, 'Hello there.');
    });

    test('剥掉 "Here is the reply:" 这类引导语', () async {
      final gen = AnswerGenerator(_FakeLlm('Here is the reply:\nWe did it.'));
      final draft = await gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1);
      expect(draft.textEn, 'We did it.');
    });

    test('空输出报可读错误', () async {
      final gen = AnswerGenerator(_FakeLlm('   '));
      expect(
        () => gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1),
        throwsA(isA<AnswerGenerationException>()
            .having((e) => e.message, 'message', contains('空'))),
      );
    });

    test('不像英文的输出被拒，不把废话存成回答', () async {
      final gen = AnswerGenerator(_FakeLlm('好的，我来回答。'));
      expect(
        () => gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1),
        throwsA(isA<AnswerGenerationException>()),
      );
    });

    test('LLM 异常转成可读错误', () async {
      final gen = AnswerGenerator(_FakeLlm('__throw__'));
      expect(
        () => gen.suggestAnswer(meeting: meeting(), questionTurnIndex: 1),
        throwsA(isA<AnswerGenerationException>()
            .having((e) => e.message, 'message', contains('生成失败'))),
      );
    });
  });
}
