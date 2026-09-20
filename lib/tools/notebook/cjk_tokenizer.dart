/// CJK bigram 分词器。
///
/// SQLite FTS5 默认的 `unicode61` tokenizer 会把整串连续中文当作**单个 token**，
/// 导致 `MATCH '豆浆机'` 无法命中「我买了豆浆机延保」——只有与整串完全相等才匹配。
/// `trigram` tokenizer 虽能处理三字以上查询，但对两字词（延保/保险/保修/会员）
/// 全部失效，而中文词大量是两字，故不可用。
///
/// 本分词器在**应用层**做重叠双字切分：
/// - 索引时：`我买了豆浆机` → `我买 买了 了豆 豆浆 浆机`（空格分隔写入 FTS5）
/// - 查询时：同样切分后用 OR 拼接，靠 `bm25()` 把命中 bigram 更多的笔记排前
///
/// 无词典依赖，品牌名/型号等专有名词与普通词一视同仁。
library;

/// CJK 表意文字与假名范围。这些区段的字符按 bigram 切分；
/// 其余字母数字按整词保留；标点与空白作为分隔符丢弃。
bool _isCjk(int c) =>
    (c >= 0x4E00 && c <= 0x9FFF) || // CJK Unified Ideographs
    (c >= 0x3400 && c <= 0x4DBF) || // Extension A
    (c >= 0xF900 && c <= 0xFAFF) || // Compatibility Ideographs
    (c >= 0x3040 && c <= 0x30FF) || // Hiragana / Katakana
    (c >= 0xAC00 && c <= 0xD7AF);   // Hangul Syllables

bool _isAsciiWord(int c) =>
    (c >= 0x30 && c <= 0x39) || // 0-9
    (c >= 0x41 && c <= 0x5A) || // A-Z
    (c >= 0x61 && c <= 0x7A) || // a-z
    c == 0x5F;                  // _

/// 把文本切成 bigram / 整词 token 序列。
///
/// - CJK 连续段 → 重叠双字；单字段 → 其自身
/// - ASCII 字母数字连续段 → 原样保留（小写化，与 FTS5 大小写不敏感语义一致）
/// - 其余字符（标点、空白、全角符号）→ 分隔符，丢弃
List<String> cjkBigrams(String text) {
  final tokens = <String>[];
  final runes = text.runes.toList();
  var i = 0;
  while (i < runes.length) {
    final c = runes[i];
    if (_isCjk(c)) {
      final start = i;
      while (i < runes.length && _isCjk(runes[i])) {
        i++;
      }
      final seg = String.fromCharCodes(runes.sublist(start, i));
      final chars = seg.characters.toList();
      if (chars.length == 1) {
        tokens.add(chars.first);
      } else {
        for (var j = 0; j < chars.length - 1; j++) {
          tokens.add('${chars[j]}${chars[j + 1]}');
        }
      }
    } else if (_isAsciiWord(c)) {
      final start = i;
      while (i < runes.length && _isAsciiWord(runes[i])) {
        i++;
      }
      tokens.add(String.fromCharCodes(runes.sublist(start, i)).toLowerCase());
    } else {
      i++; // 分隔符，丢弃
    }
  }
  return tokens;
}

/// 归一化后写入 FTS5 的索引文本（空格分隔）。
String cjkIndexText(String text) => cjkBigrams(text).join(' ');

/// 把用户查询转换为 FTS5 `MATCH` 表达式。
///
/// 每个 token 加双引号（内部双引号双写转义）以防被当作 FTS5 语法；token 之间
/// 用 OR 连接，使 `豆浆机坏了怎么办` 能命中只含「豆浆机」的笔记，再由
/// `bm25()` 按命中数量排序。token 为空时返回空串（调用方据此判定"无有效查询"）。
String cjkFtsQuery(String text) {
  final tokens = cjkBigrams(text);
  if (tokens.isEmpty) return '';
  return tokens.map((t) => '"${t.replaceAll('"', '""')}"').join(' OR ');
}

extension on String {
  /// 按 Unicode 码位切分为字符列表（避免代理对拆断）。
  Iterable<String> get characters sync* {
    for (final r in runes) {
      yield String.fromCharCode(r);
    }
  }
}
