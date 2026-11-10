import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/sense_group_chunker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/connected_speech_marker.dart';

void main() {
  group('SenseGroupChunker 意群断句测试', () {
    test('长复合句能够按从句引导词与标点切分成多个意群', () {
      const text =
          "So means the structure is something like we first have the main branch, "
          "when we branch off to generate UAT branch, and then we branch off to generate dev branch, right?";

      final chunks = SenseGroupChunker.chunk(text);
      expect(chunks.length, greaterThanOrEqualTo(3));
      // 每个 chunk 都包含非空文字与停顿标识
      for (final c in chunks) {
        expect(c.text.trim().isNotEmpty, isTrue);
      }
      expect(chunks.first.text, contains('structure'));
      expect(chunks.last.isSentenceEnd, isTrue);
    });

    test('短句保持为一个完整意群不强制细碎打断', () {
      const text = "Alex, you're first.";
      final chunks = SenseGroupChunker.chunk(text);
      expect(chunks.length, equals(1));
      expect(chunks.single.text, equals("Alex, you're first."));
      expect(chunks.single.isSentenceEnd, isTrue);
    });
  });

  group('ConnectedSpeechMarker 连读与弱读分析测试', () {
    test('辅元连读如 not at all 能够被成功识别', () {
      const text = "It is not at all complicated.";
      final tokens = ConnectedSpeechMarker.analyze(text);

      // not -> at 形成连读
      final notToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'not');
      expect(notToken.hasLinkingToNext, isTrue);

      // at -> all 形成连读
      final atToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'at');
      expect(atToken.hasLinkingToNext, isTrue);
    });

    test('常见弱读功能词如 of, to, and 被标记为 weakForm', () {
      const text = "Speak to Oliver and ask for help.";
      final tokens = ConnectedSpeechMarker.analyze(text);

      final toToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'to');
      expect(toToken.type, equals(WordSpeechType.weakForm));

      final andToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'and');
      expect(andToken.type, equals(WordSpeechType.weakForm));

      final forToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'for');
      expect(forToken.type, equals(WordSpeechType.weakForm));

      final speakToken = tokens.firstWhere((t) => t.word.toLowerCase() == 'speak');
      expect(speakToken.type, equals(WordSpeechType.normal));
    });
  });
}
