import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/meeting_script_generator.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_llm.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/speech_draft_generator.dart';

/// 假 text 槽位：返回预置输出，并记录收到的 prompt。
class _FakeGenerator implements RehearsalTextGenerator {
  _FakeGenerator(this.output);
  String output;
  String? lastPrompt;

  @override
  Future<String> generate(String prompt) async {
    lastPrompt = prompt;
    return output;
  }
}

RehearsalMaterial _material() => RehearsalMaterial(
      id: 'mat_1',
      title: 'Q4 容量评审',
      sourcePath: '/tmp/q4.md',
      fileName: 'q4.md',
      text: '''
# Q4 容量评审

集群当前 72 节点，P99 延迟 120ms。需要扩容到 96 节点。
支付网关 503 错误率上升到 0.4%。
客户 Acme 要求 SLA 99.95%。
''',
      importedAt: DateTime(2026, 10, 22),
    );

void main() {
  group('讲稿生成', () {
    test('分节、保留术语、占位标记出现', () async {
      final fake = _FakeGenerator('''
## 容量现状

Our cluster is running on 72 nodes today, and P99 latency sits at 120ms.

## 扩容计划

We need to scale to 96 nodes before the peak season.

## 风险与依赖

The payment gateway 503 error rate went up to 0.4%. We owe Acme an SLA of
99.95%. The rollback window is [待补充: 尚未确认].
''');
      final draft = await SpeechDraftGeneratorImpl(fake).generateDraft(_material());

      expect(draft.materialId, 'mat_1');
      expect(draft.sections, hasLength(3));
      expect(draft.sections.first.title, '容量现状');
      // 术语与数字逐字保留
      expect(draft.fullText, contains('72 nodes'));
      expect(draft.fullText, contains('99.95%'));
      expect(draft.fullText, contains('503'));
      // 信息不足处有占位
      expect(draft.fullText, contains('[待补充:'));
      // prompt 里带了材料内容与"禁止编造"要求
      expect(fake.lastPrompt, contains('需要扩容到 96 节点'));
      expect(fake.lastPrompt, contains('NEVER fabricate'));
    });

    test('模型没按议题分节时明确失败（而非交出单块文本）', () async {
      final fake = _FakeGenerator('Just one long paragraph of speech with no '
          'section markers at all.');
      expect(
        () => SpeechDraftGeneratorImpl(fake).generateDraft(_material()),
        throwsA(isA<DraftGenerationException>()
            .having((e) => e.message, 'message', contains('少于')),
        ),
      );
    });

    test('首节缺标题时补通用标题，不丢内容', () async {
      final fake = _FakeGenerator('''
Hello everyone, let me start with the capacity numbers.

## 扩容计划

We need to scale to 96 nodes.

## 风险

The 503 error rate is 0.4%.
''');
      final draft = await SpeechDraftGeneratorImpl(fake).generateDraft(_material());
      expect(draft.sections.first.title, 'Opening');
      expect(draft.sections.first.body, contains('capacity numbers'));
      expect(draft.sections, hasLength(3));
    });

    test('空材料直接拒绝', () async {
      final fake = _FakeGenerator('whatever');
      final empty = RehearsalMaterial(
        id: 'm',
        title: 't',
        sourcePath: '/x',
        fileName: 'x.md',
        text: '   ',
        importedAt: DateTime(2026),
      );
      expect(
        () => SpeechDraftGeneratorImpl(fake).generateDraft(empty),
        throwsA(isA<DraftGenerationException>()
            .having((e) => e.message, 'message', contains('材料内容为空'))),
      );
    });

    test('LLM 失败时带上具体原因', () async {
      final fake = _ThrowingGenerator('HTTP 402 quota_exceeded');
      expect(
        () => SpeechDraftGeneratorImpl(fake).generateDraft(_material()),
        throwsA(isA<DraftGenerationException>()
            .having((e) => e.message, 'message', contains('quota_exceeded'))),
      );
    });
  });

  group('剧本生成', () {
    SpeechDraft _draft() => SpeechDraft(
          id: 'draft_mat_1',
          materialId: 'mat_1',
          title: 'Q4 容量评审 · 汇报讲稿',
          sections: const [
            DraftSection(title: '容量现状', body: 'We run 72 nodes.'),
            DraftSection(title: '扩容计划', body: 'We scale to 96.'),
            DraftSection(title: '风险', body: '503 rate is 0.4%.'),
          ],
          generatedAt: DateTime(2026, 10, 22),
        );

    test('5 角色都出现、四段结构覆盖', () async {
      final fake = _FakeGenerator(_scriptText());
      final script = await _scriptAllowingShort(
        MeetingScriptGeneratorImpl(fake),
        material: _material(),
        draft: _draft(),
      );

      // 5 角色齐全
      expect(script.rolesPresent, hasLength(5));
      for (final r in RehearsalRole.values) {
        expect(script.turns.any((t) => t.role == r), isTrue,
            reason: '剧本里缺少角色 ${r.speaker}');
      }
      // 四段结构
      for (final p in ScriptPhase.values) {
        expect(script.turns.any((t) => t.phase == p), isTrue,
            reason: '剧本里缺少结构段 ${p.id}');
      }
      // 客户方有台词（追问的一方）
      expect(script.turns.where((t) => t.role.isClientSide), isNotEmpty);
    });

    test('按语速折算的时长落在目标区间', () async {
      final fake = _FakeGenerator(_scriptText());
      final script = await _scriptAllowingShort(
        MeetingScriptGeneratorImpl(fake),
        material: _material(),
        draft: _draft(),
      );
      expect(script.estimatedMs, greaterThan(0));
      // stub 剧本远短于 30 分钟——区间判断本身要被验证
      expect(script.isWithinTargetRange, isFalse);
      // 但构造一个落在区间内的剧本时判断要翻转（边界两侧都验）
      final inRange = MeetingScript(
        id: 's',
        materialId: 'm',
        draftId: 'd',
        title: 't',
        targetMinutes: 30,
        generatedAt: DateTime(2026),
        turns: List.generate(
          140,
          (i) => ScriptTurn(
            role: RehearsalRole.simon,
            text: 'word ' * 31,
            startMs: i * 13000,
            endMs: i * 13000 + 13000,
          ),
        ),
      );
      expect(inRange.isWithinTargetRange, isTrue);
    });

    test('轮次远少于目标时明确拒绝（避免产出 5 分钟的"30 分钟会议"）', () async {
      final fake = _FakeGenerator('''
Simon: We are here to talk about capacity.
xiaofeng: How many nodes do we have?
''');
      expect(
        () => MeetingScriptGeneratorImpl(fake).generateScript(
          material: _material(),
          draft: _draft(),
          targetMinutes: 30,
        ),
        throwsA(isA<ScriptGenerationException>()
            .having((e) => e.message, 'message', contains('远少于')),
        ),
      );
    });

    test('轮次偏短时给出带剧本的警告（提示但不阻断）', () async {
      // 80 轮：过告警线（60）但低于目标（120）——应当警告而非拒绝。
      final fake = _FakeGenerator(_scriptText(topicRepeats: 70));
      final caught = await _catchShort(() =>
          MeetingScriptGeneratorImpl(fake).generateScript(
            material: _material(),
            draft: _draft(),
            targetMinutes: 30,
          ));
      expect(caught, isA<ScriptTooShortWarning>());
      final warning = caught as ScriptTooShortWarning;
      // 警告里带着可用的剧本——用户可以先拿去用
      expect(warning.script.turns, isNotEmpty);
      expect(warning.script.rolesPresent, hasLength(5));
    });

    test('轮次达到目标时不抛警告', () async {
      final fake = _FakeGenerator(_scriptText());
      final caught = await _catchShort(() =>
          MeetingScriptGeneratorImpl(fake).generateScript(
            material: _material(),
            draft: _draft(),
            targetMinutes: 30,
          ));
      expect(caught, isNull);
    });

    test('未登记的说话人被忽略（不引入第六个音色）', () async {
      final fake = _FakeGenerator('''
${_scriptText()}
Moderator: Let us move on.
''');
      final script = await _scriptAllowingShort(
        MeetingScriptGeneratorImpl(fake),
        material: _material(),
        draft: _draft(),
      );
      expect(script.turns.any((t) => t.text.contains('Let us move on')), isFalse);
    });

    test('prompt 给出轮次目标而非"30 分钟"', () async {
      final fake = _FakeGenerator(_scriptText());
      await _scriptAllowingShort(
        MeetingScriptGeneratorImpl(fake),
        material: _material(),
        draft: _draft(),
      );
      expect(fake.lastPrompt, contains('between 120 and 161 turns'));
      expect(fake.lastPrompt, contains('pushes back'));
    });

    test('LLM 失败时带上具体原因', () async {
      final fake = _ThrowingGenerator('HTTP 451 censorship_blocked');
      expect(
        () => MeetingScriptGeneratorImpl(fake).generateScript(
          material: _material(),
          draft: _draft(),
          targetMinutes: 30,
        ),
        throwsA(isA<ScriptGenerationException>()
            .having((e) => e.message, 'message', contains('censorship_blocked')),
        ),
      );
    });
  });
}

/// 一段覆盖 5 角色与四段结构的剧本。
///
/// 轮次要够过 [MeetingScriptGeneratorImpl.warnTurns]（60）的告警线——真实的
/// LLM 输出有 140+ 轮，测试用重复的角色循环把规模拉到同一量级。
String _scriptText({int topicRepeats = 140}) {
  final b = StringBuffer()
    ..writeln('[opening]')
    ..writeln('Simon: Morning everyone. Today I want to walk through the Q4 '
        'capacity review.')
    ..writeln('xiaofeng: Thanks Simon. Go ahead.')
    ..writeln('[topics]');
  const topicTurns = [
    'Simon: We are running 72 nodes with a P99 of 120ms.',
    'songyang: On the Huawei side, the new rack is already commissioned.',
    'deepan: And what happens if we do not scale?',
    'Simon: We would breach the 99.95% SLA we owe Acme.',
  ];
  for (var i = 0; i < topicRepeats; i++) {
    b.writeln(topicTurns[i % topicTurns.length]);
  }
  b
    ..writeln('[qa]')
    ..writeln('Josh: How did the 503 rate get to 0.4%?')
    ..writeln('xiaofeng: Yes, I want the root cause before we approve anything.')
    ..writeln('Simon: It traces back to the connection pool change.')
    ..writeln('[closing]')
    ..writeln('Simon: I will own the capacity plan, and xiaofeng will confirm '
        'the SLA.');
  return b.toString();
}

/// 生成剧本，允许偏短警告（返回剧本本身）。
Future<MeetingScript> _scriptAllowingShort(
  MeetingScriptGeneratorImpl gen, {
  required RehearsalMaterial material,
  required SpeechDraft draft,
  int targetMinutes = 30,
}) async {
  try {
    return await gen.generateScript(
      material: material,
      draft: draft,
      targetMinutes: targetMinutes,
    );
  } on ScriptTooShortWarning catch (w) {
    return w.script;
  }
}

/// 抓取抛出的异常（用于断言"带产物的警告"）。
Future<Object?> _catchShort(Future<void> Function() body) async {
  try {
    await body();
    return null;
  } catch (e) {
    return e;
  }
}

class _ThrowingGenerator implements RehearsalTextGenerator {
  _ThrowingGenerator(this.message);
  final String message;

  @override
  Future<String> generate(String prompt) async => throw Exception(message);
}
