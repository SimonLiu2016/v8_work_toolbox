/// 连读（Liaison）与弱读功能词（Weak Forms）分析器。
///
/// 帮助学习者攻破“单词认识但连读/吞音认不出”的隐形听力障碍。
library;

import 'package:flutter/material.dart';

enum WordSpeechType {
  normal,
  weakForm,
}

class SpeechToken {
  final String word;
  final String rawPrefix;
  final String rawSuffix;
  final WordSpeechType type;
  final bool hasLinkingToNext;

  const SpeechToken({
    required this.word,
    this.rawPrefix = '',
    this.rawSuffix = '',
    this.type = WordSpeechType.normal,
    this.hasLinkingToNext = false,
  });
}

class ConnectedSpeechMarker {
  ConnectedSpeechMarker._();

  static const Set<String> _vowels = {'a', 'e', 'i', 'o', 'u'};

  /// 常见弱读功能词（介词、连词、冠词、助动词）
  static const Set<String> _weakForms = {
    'to', 'of', 'for', 'at', 'from',
    'and', 'as', 'than', 'but',
    'a', 'an', 'the',
    'can', 'could', 'was', 'were', 'do', 'does', 'have', 'has', 'had',
  };

  /// 高频必连短语（白名单快速命中）
  static const Set<String> _fixedLinkings = {
    'not at all', 'kind of', 'sort of', 'a lot of',
    'out of', 'instead of', 'because of',
    'set up', 'pick up', 'give up', 'check out', 'branch off',
    'roll out', 'shut down', 'log in', 'opt in', 'point out',
  };

  /// 将文本分析切分为带语音现象属性的标记序列
  static List<SpeechToken> analyze(String text) {
    final rawTokens = _splitRawTokens(text);
    if (rawTokens.isEmpty) return const [];

    final results = <SpeechToken>[];

    for (var i = 0; i < rawTokens.length; i++) {
      final current = rawTokens[i];
      final wordLower = current.word.toLowerCase();
      final isWeak = _weakForms.contains(wordLower);

      var isLinked = false;
      if (i < rawTokens.length - 1) {
        final next = rawTokens[i + 1];
        isLinked = _isLinked(current.word, next.word);
      }

      results.add(
        SpeechToken(
          word: current.word,
          rawPrefix: current.rawPrefix,
          rawSuffix: current.rawSuffix,
          type: isWeak ? WordSpeechType.weakForm : WordSpeechType.normal,
          hasLinkingToNext: isLinked,
        ),
      );
    }

    return results;
  }

  /// 判断两个连续单词是否形成连读（辅音+元音 或 固定搭配）
  static bool _isLinked(String first, String second) {
    if (first.isEmpty || second.isEmpty) return false;
    final f = first.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
    final s = second.toLowerCase().replaceAll(RegExp(r'[^\w]'), '');
    if (f.isEmpty || s.isEmpty) return false;

    // 白名单双词匹配
    if (_fixedLinkings.contains('$f $s')) return true;

    // 经典辅音接元音（Consonant-to-Vowel linking）
    final lastChar = f[f.length - 1];
    final firstChar = s[0];

    final isFirstConsonant = !_vowels.contains(lastChar) && RegExp(r'[a-z]').hasMatch(lastChar);
    final isSecondVowel = _vowels.contains(firstChar);

    if (isFirstConsonant && isSecondVowel) {
      // 避开非连读尾辅音（如 -w, -y 常做半元音）
      return lastChar != 'w' && lastChar != 'y';
    }

    return false;
  }

  /// 提取单句中的所有单词及其前后标点
  static List<({String rawPrefix, String word, String rawSuffix})> _splitRawTokens(String text) {
    final tokens = <({String rawPrefix, String word, String rawSuffix})>[];
    final words = text.split(RegExp(r'\s+'));

    for (final w in words) {
      if (w.trim().isEmpty) continue;
      final m = RegExp(r'^([^\w]*)([\w-]+)([^\w]*)$').firstMatch(w);
      if (m != null) {
        tokens.add((
          rawPrefix: m.group(1) ?? '',
          word: m.group(2) ?? '',
          rawSuffix: m.group(3) ?? '',
        ));
      } else {
        tokens.add((rawPrefix: '', word: w, rawSuffix: ''));
      }
    }

    return tokens;
  }

  /// 构建具备连读与弱读视觉样式的 TextSpan
  static TextSpan buildSpans({
    required String text,
    required Color normalColor,
    required Color accentColor,
    required Color weakColor,
    double fontSize = 13.0,
    FontWeight fontWeight = FontWeight.normal,
  }) {
    final tokens = analyze(text);
    final spans = <InlineSpan>[];

    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];

      // 前导标点
      if (t.rawPrefix.isNotEmpty) {
        spans.add(TextSpan(text: t.rawPrefix, style: TextStyle(color: normalColor, fontSize: fontSize)));
      }

      // 单词正文：弱读浅色展示，普通正常展示
      final wordStyle = TextStyle(
        color: t.type == WordSpeechType.weakForm ? weakColor : normalColor,
        fontSize: fontSize,
        fontWeight: fontWeight,
      );
      spans.add(TextSpan(text: t.word, style: wordStyle));

      // 后缀标点
      if (t.rawSuffix.isNotEmpty) {
        spans.add(TextSpan(text: t.rawSuffix, style: TextStyle(color: normalColor, fontSize: fontSize)));
      }

      // 连读连线符号（弧线 ‿）或普通空格
      if (t.hasLinkingToNext) {
        spans.add(
          TextSpan(
            text: '‿',
            style: TextStyle(
              color: accentColor,
              fontWeight: FontWeight.bold,
              fontSize: fontSize * 0.95,
            ),
          ),
        );
      } else if (i < tokens.length - 1) {
        spans.add(TextSpan(text: ' ', style: TextStyle(fontSize: fontSize)));
      }
    }

    return TextSpan(children: spans);
  }
}
