import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/lookup_panel/ui/lookup_window.dart';

/// 查词深链的 mode 解析（capability: `browser-lookup-deep-link`）。
///
/// 三件事必须钉住：
///   1. `ai` → AI 模式（这是修"问 AI 反而先查词典"的那一刀）；
///   2. **缺省/空/null → dict** —— 既有调用方（右键查词、⌘D 热键、「在桌面端打开」）
///      不带 mode，它们必须保持词典优先；
///   3. 任意未知值 → dict，不抛异常（深链是外部输入，浏览器能拼出任意字符串）。
void main() {
  group('parseLookupStartMode', () {
    test('ai maps to the AI mode', () {
      expect(parseLookupStartMode('ai'), LookupStartMode.ai);
    });

    test('dict maps explicitly', () {
      expect(parseLookupStartMode('dict'), LookupStartMode.dict);
    });

    test('absent, empty and null all mean dictionary-first', () {
      // 这条最重要：三个真实入口都不带 mode。若哪天改成"认不出就报错"，
      // 用户在浏览器里点右键查词会没反应。
      expect(parseLookupStartMode(null), LookupStartMode.dict);
      expect(parseLookupStartMode(''), LookupStartMode.dict);
      expect(parseLookupStartMode('   '), LookupStartMode.dict);
    });

    test('unknown values fall back to dictionary-first, not an error', () {
      expect(parseLookupStartMode('banana'), LookupStartMode.dict);
      expect(parseLookupStartMode('translate'), LookupStartMode.dict);
      expect(parseLookupStartMode('/etc/passwd'), LookupStartMode.dict);
    });

    test('matching is case-insensitive and trims surrounding space', () {
      // 大小写不该影响结果 —— 深链可能由人手拼（地址栏、脚本）。
      // 扩展侧只发小写 'ai'，宽松匹配不改变扩展的行为。
      expect(parseLookupStartMode('AI'), LookupStartMode.ai);
      expect(parseLookupStartMode('Ai'), LookupStartMode.ai);
      expect(parseLookupStartMode(' ai '), LookupStartMode.ai);
    });
  });
}
