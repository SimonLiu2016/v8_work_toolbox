import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/services/password_generator.dart';

void main() {
  late PasswordGenerator gen;

  setUp(() {
    gen = PasswordGenerator();
  });

  group('随机密码生成', () {
    test('默认长度 20 且含各字符集', () {
      final pwd = gen.generate();
      expect(pwd.length, 20);
      expect(pwd.contains(RegExp(r'[a-z]')), isTrue);
      expect(pwd.contains(RegExp(r'[A-Z]')), isTrue);
      expect(pwd.contains(RegExp(r'[0-9]')), isTrue);
      expect(pwd.contains(RegExp(r'[^a-zA-Z0-9]')), isTrue);
    });

    test('长度约束生效', () {
      expect(gen.generate(length: 8).length, 8);
      expect(gen.generate(length: 128).length, 128);
      expect(() => gen.generate(length: 7), throwsArgumentError);
      expect(() => gen.generate(length: 129), throwsArgumentError);
    });

    test('每启用字符集至少一字符', () {
      for (var i = 0; i < 50; i++) {
        final pwd = gen.generate(
          length: 8,
          useLowercase: true,
          useUppercase: true,
          useDigits: true,
          useSymbols: true,
        );
        expect(pwd.contains(RegExp(r'[a-z]')), isTrue);
        expect(pwd.contains(RegExp(r'[A-Z]')), isTrue);
        expect(pwd.contains(RegExp(r'[0-9]')), isTrue);
        expect(pwd.contains(RegExp(r'[^a-zA-Z0-9]')), isTrue);
      }
    });

    test('仅数字字符集', () {
      final pwd = gen.generate(
        length: 16,
        useLowercase: false,
        useUppercase: false,
        useDigits: true,
        useSymbols: false,
      );
      expect(RegExp(r'^[0-9]+$').hasMatch(pwd), isTrue);
    });

    test('无字符集抛 ArgumentError', () {
      expect(
        () => gen.generate(
          useLowercase: false,
          useUppercase: false,
          useDigits: false,
          useSymbols: false,
        ),
        throwsArgumentError,
      );
    });

    test('排除易混淆字符', () {
      for (var i = 0; i < 50; i++) {
        final pwd = gen.generate(length: 32, excludeAmbiguous: true);
        for (final ch in PasswordGenerator.ambiguousChars.split('')) {
          expect(pwd.contains(ch), isFalse, reason: '含易混淆字符 $ch');
        }
      }
    });

    test('两次生成不同（随机性冒烟）', () {
      final a = gen.generate(length: 32);
      final b = gen.generate(length: 32);
      expect(a, isNot(equals(b)));
    });
  });

  group('passphrase 生成', () {
    test('默认 5 词连字符分隔', () {
      final phrase = gen.generatePassphrase();
      final words = phrase.split('-');
      expect(words.length, 5);
      for (final w in words) {
        expect(passphraseWordList.contains(w), isTrue);
      }
    });

    test('自定义词数与分隔符', () {
      final phrase = gen.generatePassphrase(wordCount: 3, separator: '.');
      expect(phrase.split('.').length, 3);
    });

    test('数字后缀', () {
      final phrase = gen.generatePassphrase(wordCount: 4, appendDigit: true);
      expect(RegExp(r'-[0-9]$').hasMatch(phrase), isTrue);
      // 4 词 + 1 数字 = 5 段
      expect(phrase.split('-').length, 5);
    });

    test('词数边界', () {
      expect(() => gen.generatePassphrase(wordCount: 1), throwsArgumentError);
      expect(() => gen.generatePassphrase(wordCount: 13), throwsArgumentError);
      expect(gen.generatePassphrase(wordCount: 2).split('-').length, 2);
      expect(gen.generatePassphrase(wordCount: 12).split('-').length, 12);
    });
  });
}
