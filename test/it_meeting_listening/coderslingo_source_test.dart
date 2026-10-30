import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/listening_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/coderslingo_source.dart';

void main() {
  group('extractTranscriptBlocks', () {
    test('提取所有 transcript 块', () {
      const html = '''
        <div class="exercise-item" id="ex-1" data-id="1">
          <pre class="transcript-text">First block text</pre>
        </div>
        <div class="exercise-item" id="ex-2" data-id="2">
          <pre class="transcript-text">Second block text</pre>
        </div>
      ''';
      final blocks = CoderSlingoSource.extractTranscriptBlocks(html);
      expect(blocks, ['First block text', 'Second block text']);
    });

    test('HTML 实体被解码', () {
      const html = '<pre class="transcript-text">He said &quot;hi&quot; &amp; left.</pre>';
      final blocks = CoderSlingoSource.extractTranscriptBlocks(html);
      expect(blocks.single, 'He said "hi" & left.');
    });

    test('页面无 transcript 块时返回空列表', () {
      expect(CoderSlingoSource.extractTranscriptBlocks('<html><body>404</body></html>'), isEmpty);
    });
  });

  group('parseDialogue 轮次切分', () {
    test('带角色标注的说话人', () {
      const block = 'Lena (Scrum Master): "Good morning everyone."';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns, hasLength(1));
      expect(r.turns.single.speaker, 'Lena');
      expect(r.turns.single.role, 'Scrum Master');
      expect(r.turns.single.rawText, 'Good morning everyone.');
    });

    test('不带角色标注的说话人', () {
      const block = 'IC: "Do we have a theory on root cause yet?"';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns, hasLength(1));
      expect(r.turns.single.speaker, 'IC');
      expect(r.turns.single.role, isEmpty);
      expect(r.turns.single.rawText, 'Do we have a theory on root cause yet?');
    });

    test('场景说明行不产生轮次', () {
      const block = '''
[Live incident bridge call — SEV-1. Payment service down. 11 minutes into the call.]
IC: "Okay, let's get a status update."
Lead: "We've confirmed the payment service is returning 503s."
''';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns, hasLength(2));
      expect(r.note, contains('SEV-1'));
      expect(r.note, isNot(contains('IC:')));
    });

    test('折行续接并入前一轮', () {
      const block = '''
Lead: "We've confirmed the payment service is returning 503s
across all regions."
IC: "Do we have a theory?"
''';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns, hasLength(2));
      expect(r.turns.first.rawText, contains('across all regions.'));
    });

    test('句内引号保留', () {
      const block = 'Dev: "He said \'that is the blocker\' yesterday."';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns.single.rawText, contains('that is the blocker'));
    });

    test('多轮对话的顺序保持不变', () {
      const block = '''
Lena: "Good morning."
Alex: "No blockers."
Maria: "I'm blocked."
''';
      final r = CoderSlingoSource.parseDialogue(block);
      expect(r.turns.map((t) => t.speaker), ['Lena', 'Alex', 'Maria']);
    });
  });

  group('显式栏目映射', () {
    test('采用的栏目都映射到会议场景', () {
      for (final entry in CoderSlingoSource.columnMapping.entries) {
        expect(entry.value.$1, isA<MeetingScene>());
        expect(entry.value.$2, isNotEmpty);
      }
    });

    test('站会对白映射到站会场景', () {
      expect(CoderSlingoSource.columnMapping['standup-dialogues']!.$1,
          MeetingScene.standup);
    });

    test('故障排查映射到故障场景', () {
      expect(CoderSlingoSource.columnMapping['incident-calls']!.$1,
          MeetingScene.incident);
    });

    test('未登记的栏目被拒绝', () {
      expect(CoderSlingoSource.columnMapping.containsKey('not-mapped'), isFalse);
    });
  });
}
