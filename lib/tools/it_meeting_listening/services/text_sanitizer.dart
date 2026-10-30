/// 送入 TTS 前的文本清洗。
///
/// **为什么需要**：实测 `Today I'll continue — but I'm blocked.` 被合成成
/// "but unblocked"——破折号让模型把语义读反了。这类错误对听力训练是致命的：
/// 用户练的是"听懂技术英语"，读反一个词就等于教错。
///
/// **清洗边界**：只动标点与空白，**不改动任何单词、术语、数字或标识符**
/// （`503s` / `1,200` / `14:32 UTC` / `JIRA-4821` 逐字保持）。
///
/// **原文分离**：清洗只作用于送入合成的副本；原始文本单独保留供文稿展示，
/// 否则文稿与音频对不上，用户精听时无法定位。
library;

/// 破折号的全部形态。
///
/// 源站点混用 em dash（`—`）、en dash（`–`）与双连字符（`--`）。
const _dashChars = <String>['—', '–', '―', '－'];

/// 规范化送入 TTS 的文本。
///
/// 规则：
/// 1. 破折号 → 逗号（保留语义停顿，不改词）
/// 2. 连续空白折叠为单个空格
/// 3. 剥除仅由引号包裹的冗余引号（`"..."` → `...`）
///
/// 引号剥除只处理**首尾成对**的引号；句子内部的引号（如引述他人原话）保留。
String sanitizeForSynthesis(String raw) {
  var text = raw;

  // 1a. 独立成词的破折号：两侧有空白/行首行尾时才算破折号。
  //     `a--b` 这类记号不受影响。
  //     注意：Dart 的 String.replaceAll 不支持 `$1` 捕获组引用（那是
  //     replaceFirst 的行为），必须用 replaceAllMapped。
  text = text.replaceAllMapped(
      RegExp(r'(\s)--(\s)'), (m) => '${m.group(1)},${m.group(2)}');
  text = text.replaceAll(RegExp(r'^\s*--\s*'), ', ');
  text = text.replaceAll(RegExp(r'\s*--\s*$'), ',');

  // 1b. 单字符破折号形态：直接替换为逗号。
  for (final dash in _dashChars) {
    text = text.replaceAll(dash, ',');
  }

  // 2. 折叠空白（含换行、Tab）
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 3. 剥除首尾成对引号
  text = _stripWrappingQuotes(text);

  // 4. 规范逗号周围的空白：", ," → ","，"a , b" → "a, b"，但 ", b" 保留逗号后空格。
  text = text.replaceAll(RegExp(r',\s*,'), ',');
  text = text.replaceAll(RegExp(r'\s+,'), ',');

  return text.trim();
}

/// 剥除包裹整句的首尾成对引号。
String _stripWrappingQuotes(String text) {
  if (text.length < 2) return text;
  const pairs = <String, String>{
    '"': '"',
    '“': '”',
    '‘': '’',
  };
  for (final entry in pairs.entries) {
    final open = entry.key;
    final close = entry.value;
    if (text.startsWith(open) && text.endsWith(close) && text.length > 1) {
      return text.substring(1, text.length - 1).trim();
    }
  }
  return text;
}
