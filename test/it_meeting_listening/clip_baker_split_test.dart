import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/clip_baker.dart';

void main() {
  group('ClipBaker.splitLongTurn 超长轮次切分', () {
    test('不超长的文本原样返回', () {
      const text = 'A short turn.';
      expect(ClipBaker.splitLongTurn(text), [text]);
    });

    test('超过上限时按句子边界切分', () {
      final text = List.filled(30, 'This is a reasonably long sentence about the system.')
          .join(' ');
      final parts = ClipBaker.splitLongTurn(text);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(ClipBaker.maxSynthesisChars));
      }
      // 切分后总字数不丢
      expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
          text.replaceAll(RegExp(r'\s+'), ' ').trim());
    });

    test('单句超长时按词硬切，每段仍不超上限', () {
      final text = List.filled(200, 'word').join(' ');
      final parts = ClipBaker.splitLongTurn(text);
      expect(parts.length, greaterThan(1));
      for (final p in parts) {
        expect(p.length, lessThanOrEqualTo(ClipBaker.maxSynthesisChars));
      }
    });

    test('切分不产生空段', () {
      final text = List.filled(50, 'alpha beta gamma delta.').join(' ');
      for (final p in ClipBaker.splitLongTurn(text)) {
        expect(p.trim(), isNotEmpty);
      }
    });

    test('上限 900 —— 端点要求 input < 1000 字，留出余量', () {
      expect(ClipBaker.maxSynthesisChars, lessThan(1000));
    });
  });
}
