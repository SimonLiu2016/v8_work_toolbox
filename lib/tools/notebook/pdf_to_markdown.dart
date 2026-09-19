import 'dart:convert';
import 'dart:io';

/// PDF → Markdown 转换器（基于 macOS PDFKit 排版属性）
///
/// PDF 是页面描述格式（定位字形），没有语义标记。"格式还原"的做法是从
/// 每个文本 run 的字号反推结构：正文字号取出现频次最高者，相对其倍数
/// 映射标题层级。粗体用于区分加粗的标签（`**Name:** 值`）与加粗的小节标题。
///
/// 走 PDFKit 的 `attributedString`（逐 run 带 NSFont），而非 `doc.string`
/// ——后者只有扁平文本，无字号信息，结构在提取阶段就丢失了。
class PdfToMarkdown {
  PdfToMarkdown._();

  /// 标题层级判定阈值（相对正文字号的倍数）
  static const double _h1Ratio = 1.8;
  static const double _h2Ratio = 1.35;
  static const double _h3Ratio = 1.12;

  /// bullet 行首符号。含私用区码位（Wingdings / Symbol 等字体常用私用区
  /// 映射 bullet，PDFKit 直接输出这些码位而不还原为 U+2022）。
  /// 覆盖常见 bullet：• · ◦ ▪ ▫ ‣ ⁃ ° 与私用区 U+F0A8 / U+F0B7 / U+F076。
  static const String _bulletPattern =
      '•·◦▪▫‣⁃°\u{F0A8}\u{F0B7}\u{F076}';

  /// 章节标记行首：`(A)` / `(B)` / `1.` / `一、` / `（二）` 等。
  /// 命中即判为 h2——这类前缀是 Word / 官方文档里最可靠的"小节标题"信号，
  /// 比字号或粗体更稳定。
  static final RegExp _chapterMarker =
      RegExp(r'^[（(]\s*([A-Za-z]|[0-9]{1,2}|[一二三四五六七八九十]+)\s*[)）.]');

  /// bullet 字符集合，用于快速判定"行首是否 bullet"与"行是否纯符号"
  static final Set<String> _isBulletSet =
      _bulletPattern.split('').toSet();

  /// 一次 run 的提取结果
  static const String _jxaScript = r'''
function run(argv) {
  ObjC.import("PDFKit");
  ObjC.import("Foundation");
  var url = $.NSURL.fileURLWithPath(argv[0]);
  var doc = $.PDFDocument.alloc.initWithURL(url);
  if (!doc) return "[]";
  var pages = [];
  for (var p = 0; p < doc.pageCount; p++) {
    var page = doc.pageAtIndex(p);
    var attr = page.attributedString;
    if (!attr) { pages.push([]); continue; }
    var len = attr.length;
    var runs = [];
    var idx = 0;
    while (idx < len) {
      var effRange = $.NSMakeRange(0, 0);
      var attrs = attr.attributesAtIndexEffectiveRange(idx, effRange);
      var size = 0;
      var bold = false;
      try {
        var f = attrs.objectForKey("NSFont");
        if (f) {
          size = f.pointSize;
          var name = f.fontName.js;
          if (typeof name === 'string') {
            // Bold 字形名：Arial-BoldMT / TimesNewRomanPS-BoldMT / ...Black
            bold = name.indexOf('Bold') >= 0 || name.indexOf('Black') >= 0;
          }
        }
      } catch (e) { size = 0; bold = false; }
      var effLen = effRange.length;
      if (effLen <= 0) effLen = 1;
      var end = idx + effLen;
      if (end > len) end = len;
      var text = attr.string.js.substring(idx, end);
      // 非字符串属性（图片等）在此方案中忽略
      runs.push([size, text, bold]);
      idx = end;
    }
    pages.push(runs);
  }
  return JSON.stringify(pages);
}
''';

  /// 解析 PDF 为 Markdown。无文字层时抛 [PdfNoTextLayerException]。
  static Future<String> convert(String pdfPath) async {
    final proc = await Process.run(
      'osascript',
      ['-l', 'JavaScript', '-e', _jxaScript, pdfPath],
    );
    if (proc.exitCode != 0) {
      throw Exception('PDF 解析失败: ${proc.stderr}');
    }
    final raw = (proc.stdout as String).trim();
    if (raw.isEmpty || raw == '[]') {
      throw const PdfNoTextLayerException();
    }

    final List<dynamic> pages = jsonDecode(raw) as List<dynamic>;
    return convertFromRuns(pages);
  }

  /// 从 run 结构生成 Markdown（抽离出来便于单测）
  ///
  /// [pages] 形如 `[[[fontSize, text, bold?], ...], ...]`，每页一组 run。
  /// 第三个元素 `bold` 可选，缺省视为非粗体（向后兼容旧 2 元素格式）。
  static String convertFromRuns(List<dynamic> pages) {
    // 1. 摊平所有 run，统计正文字号（频次最高者，按总字符数加权）
    final sizeWeights = <double, int>{};
    for (final page in pages) {
      for (final run in (page as List<dynamic>)) {
        final size = (run[0] as num).toDouble();
        final text = run[1] as String;
        if (size <= 0 || text.trim().isEmpty) continue;
        sizeWeights[size] = (sizeWeights[size] ?? 0) + text.trim().length;
      }
    }
    if (sizeWeights.isEmpty) throw const PdfNoTextLayerException();

    final bodySize = sizeWeights.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;

    // 2. 逐页把 run 合并成行（run 之间无换行时按段落累积）
    final blocks = <_Block>[];
    for (var p = 0; p < pages.length; p++) {
      final page = pages[p] as List<dynamic>;
      blocks.addAll(_blocksFromPage(page, bodySize, p, pages.length));
    }

    // 3. 段落回流：PDF 的换行是物理换行（排版需要），不是语义段落边界。
    //    把连续正文行按标点判断合并回真正的段落。
    final reflowed = _reflowParagraphs(blocks);

    // 4. 渲染 Markdown
    final buffer = StringBuffer();
    for (final b in reflowed) {
      final text = b.text.trim();
      if (text.isEmpty) continue;
      switch (b.level) {
        case 1:
          buffer.writeln('# $text');
          break;
        case 2:
          buffer.writeln('## $text');
          break;
        case 3:
          buffer.writeln('### $text');
          break;
        default:
          // bullet 行：补 `- ` 前缀
          if (b.isBullet) {
            buffer.writeln('- $text');
          // 加粗标签行：整行 `**...**`
          } else if (b.bold) {
            buffer.writeln('**$text**');
          } else {
            buffer.writeln(text);
          }
      }
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  /// 句子终结标点（全角 + 半角）。行尾是这些字符时视为段落边界。
  ///
  /// 含英文 `.`：该正则锚定行尾 `$`，因此 `3.14`、`v.2` 这类 `.` 后接数字的行
  /// 不会命中——`.` 与后续数字之间不存在行尾，`$` 断言失败。仅 `.` 位于行末时
  /// 判为句末（`e.g.` 这种缩写结尾会被判为句末，可接受）。
  static final RegExp _sentenceEnd =
      RegExp(r'[。！？；：!?;:.][”"）)\]】]*$');

  /// 列表标记行首（`o ` / `a ` / `i ` 等单字母 + 空格 + 内容）。
  /// 这些行是独立列表项，不应作为上一行的物理续行被合并。
  static final RegExp _listMarkerLine = RegExp(r'^[a-z] \S');

  /// 判断 [nextText] 是否应被视为上一行的物理续行（PDF 排版换行造成的截断）。
  ///
  /// 返回 false 的情况都是"新条目"的开始，不应与上一行合并：
  /// - bullet 行首（含 Wingdings 私用区）
  /// - 大写字母或数字开头（新句子/新条目/列表编号）
  /// - 单字母列表标记（`o ...`）
  ///
  /// 返回 true 的情况：小写字母或标点开头且上一行未以句末标点收尾——
  /// 这正是"物理换行截断的句子"特征，需要合并回同一段落。
  static bool _isContinuation(String nextText) {
    final t = nextText.trim();
    if (t.isEmpty) return false;
    if (_stripBullet(t).isBullet) return false;
    final first = t.codeUnitAt(0);
    if ((first >= 0x30 && first <= 0x39) ||
        (first >= 0x41 && first <= 0x5A)) {
      return false; // 数字或大写：新条目
    }
    if (_listMarkerLine.hasMatch(t)) return false;
    return true;
  }

  /// 剥离行首 bullet 符号，返回剥离后的文本与"是否以 bullet 开头"标记。
  ///
  /// 仅当行首第一个非空白字符属于 [_bulletPattern] 时判定为 bullet。
  /// 剥离后再丢弃前导空格。剥离后内容为空也视为 bullet（孤立符号行）。
  static _StripResult _stripBullet(String text) {
    final t = text.trimLeft();
    if (t.isEmpty) return _StripResult(t, false);
    if (!_isBulletSet.contains(t[0])) return _StripResult(t, false);
    final rest = t.substring(1).trimLeft();
    return _StripResult(rest, true);
  }

  /// 把连续的正文块合并为段落：上一行未以终结标点收尾、且下一行判为
  /// 物理续行时，视为被换行截断的同一段落，与下一行拼接。
  /// 标题（level > 0）始终独占一块，不参与回流。
  static List<_Block> _reflowParagraphs(List<_Block> blocks) {
    final out = <_Block>[];
    for (final b in blocks) {
      final canMerge = out.isNotEmpty &&
          b.level == 0 &&
          out.last.level == 0 &&
          !out.last.isBullet &&
          !b.isBullet &&
          !_sentenceEnd.hasMatch(out.last.text.trim()) &&
          _isContinuation(b.text);
      if (canMerge) {
        final prev = out.removeLast();
        out.add(_Block(
          _joinWrapped(prev.text.trim(), b.text.trim()),
          0,
          prev.bold || b.bold,
          false,
        ));
      } else {
        out.add(b);
      }
    }
    return out;
  }

  /// 拼接被换行截断的两段文本：中日韩字符之间不加空格，
  /// 拉丁字母/数字之间补一个空格（与既有 MarkdownConverter 的 CJK 处理一致）。
  static String _joinWrapped(String prev, String next) {
    if (prev.isEmpty) return next;
    if (next.isEmpty) return prev;
    final lastChar = prev.codeUnitAt(prev.length - 1);
    final firstChar = next.codeUnitAt(0);
    final needsSpace = _isLatin(lastChar) && _isLatin(firstChar);
    return needsSpace ? '$prev $next' : '$prev$next';
  }

  static bool _isLatin(int codeUnit) {
    return (codeUnit >= 0x30 && codeUnit <= 0x39) || // 0-9
        (codeUnit >= 0x41 && codeUnit <= 0x5A) || // A-Z
        (codeUnit >= 0x61 && codeUnit <= 0x7A); // a-z
  }

  /// 把一页的 run 序列切成块（标题 / 段落 / 标签 / bullet 项），并过滤页眉页脚噪声
  static List<_Block> _blocksFromPage(
    List<dynamic> runs,
    double bodySize,
    int pageIndex,
    int pageCount,
  ) {
    // 先按文本中的换行拆成行组，并记录每行主导字号与粗体
    final lines = <_Line>[];
    for (final run in runs) {
      final size = (run[0] as num).toDouble();
      final text = run[1] as String;
      // 无字号属性的 run（图片占位/装饰元素）不是正文，跳过
      if (size <= 0 || text.isEmpty) continue;
      // 第三个元素 bold 可选（向后兼容旧 2 元素格式）
      final bold = run.length > 2 && run[2] == true;
      final parts = text.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (i > 0) lines.add(_Line.empty());
        if (parts[i].isNotEmpty) lines.add(_Line(parts[i], size, bold));
      }
    }
    if (lines.isEmpty) return [];

    // 合并相邻同字号片段为逻辑行（bold 取或）
    final merged = <_Line>[];
    for (final l in lines) {
      if (merged.isNotEmpty &&
          merged.last.size == l.size &&
          merged.last.text.isNotEmpty &&
          l.text.isNotEmpty) {
        merged[merged.length - 1] = _Line(
          merged.last.text + l.text,
          l.size,
          merged.last.bold || l.bold,
        );
      } else {
        merged.add(l);
      }
    }

    // 噪声过滤：页内前 2 行 / 后 2 行中的纯数字或罗马数字短行（页码）
    // 然后按规则集判定每个块的类型
    final result = <_Block>[];
    for (var i = 0; i < merged.length; i++) {
      final line = merged[i];
      final text = line.text.trim();
      if (text.isEmpty) continue;
      final nearEdge = i < 2 || i >= merged.length - 2;
      if (nearEdge && _isPageNumberLike(text)) continue;

      result.add(_classifyBlock(text, line.size, line.bold, bodySize, i, merged));
    }
    return _dropLoneBullets(result);
  }

  /// 按 design D4 规则集判定单个块的类型。
  ///
  /// 优先级从上到下，首个命中即定：
  /// 1. 字号比值 ≥ 1.8 → h1
  /// 2. 字号比值 ≥ 1.35 → h2
  /// 3. 行首章节标记 → h2
  /// 4. 加粗且结尾为冒号 → 标签（bold=true, level=0）
  /// 5. 加粗且独占一行且长度 ≤ 40 → h3
  /// 6. 字号比值 ≥ 1.12 → h3
  /// 7. 字号 < bodySize → h3
  /// 8. 其余 → 正文
  static _Block _classifyBlock(
    String text,
    double size,
    bool bold,
    double bodySize,
    int index,
    List<_Line> merged,
  ) {
    // 先剥离行首 bullet——bullet 行的内容部分仍按规则判定
    final stripped = _stripBullet(text);
    final contentText = stripped.text;
    final isBullet = stripped.isBullet;

    if (bodySize > 0) {
      final ratio = size / bodySize;
      // 1. 字号比值 → h1
      if (ratio >= _h1Ratio) {
        return _Block(contentText, 1, false, isBullet);
      }
      // 2. 字号比值 → h2
      if (ratio >= _h2Ratio) {
        return _Block(contentText, 2, false, isBullet);
      }
    }

    // 3. 章节标记行首 → h2
    if (_chapterMarker.hasMatch(contentText)) {
      return _Block(contentText, 2, false, isBullet);
    }

    // 4. 加粗 + 冒号结尾 → 标签
    if (bold && _endsWithColon(contentText)) {
      return _Block(contentText, 0, true, isBullet);
    }

    // 5. 加粗 + 独占一行 + 短 + 不含冒号 → h3
    //    含冒号的是"标签: 值"行（即使值不以冒号结尾），应作为正文加粗，
    //    而非标题——否则标签-值行会被误判为 h3 标题
    if (bold &&
        _isLoneLine(index, merged) &&
        contentText.length <= 40 &&
        !_containsColon(contentText)) {
      return _Block(contentText, 3, false, isBullet);
    }

    if (bodySize > 0) {
      // 6. 字号比值 → h3
      if (size / bodySize >= _h3Ratio) {
        return _Block(contentText, 3, false, isBullet);
      }
      // 7. 字号 < bodySize → h3
      if (size < bodySize) {
        return _Block(contentText, 3, false, isBullet);
      }
    }

    // 8. 其余 → 正文
    return _Block(contentText, 0, bold, isBullet);
  }

  /// 判断文本是否以冒号（全角或半角）结尾
  static bool _endsWithColon(String text) {
    final t = text.trim();
    if (t.isEmpty) return false;
    return t.endsWith(':') || t.endsWith('：');
  }

  /// 判断文本是否含冒号（用于区分标签-值行与标题）
  static bool _containsColon(String text) {
    return text.contains(':') || text.contains('：');
  }

  /// 判断第 [index] 行是否"独占一行"——前后没有同字号的非空文本行紧邻。
  /// 用于区分"加粗的标题"与"行内加粗片段"。
  static bool _isLoneLine(int index, List<_Line> merged) {
    final line = merged[index];
    // 前一行不是同字号非空文本
    if (index > 0) {
      final prev = merged[index - 1];
      if (prev.text.trim().isNotEmpty && prev.size == line.size) {
        return false;
      }
    }
    // 后一行不是同字号非空文本
    if (index < merged.length - 1) {
      final next = merged[index + 1];
      if (next.text.trim().isNotEmpty && next.size == line.size) {
        return false;
      }
    }
    return true;
  }

  /// 丢弃孤立的 bullet 符号行（剥离后内容为空）。
  ///
  /// 带内容的 bullet 行已在 [_classifyBlock] 中保留（isBullet=true），
  /// 渲染时补 `- ` 前缀。这里只清理"纯符号无内容"的噪声行。
  static List<_Block> _dropLoneBullets(List<_Block> blocks) {
    return blocks.where((b) {
      if (!b.isBullet) return true;
      // bullet 行但内容为空 → 丢弃
      return b.text.trim().isNotEmpty;
    }).toList();
  }

  /// 页码样式：纯数字、罗马数字、"第 N 页"、长度很短
  static bool _isPageNumberLike(String text) {
    if (text.length > 12) return false;
    if (RegExp(r'^\d{1,4}$').hasMatch(text)) return true;
    if (RegExp(r'^[ivxlcIVXLC]{1,6}$').hasMatch(text)) return true;
    if (RegExp(r'^[—\-–\s]*\d{1,4}[—\-–\s]*$').hasMatch(text)) return true;
    if (RegExp(r'^第\s*\d{1,4}\s*页$').hasMatch(text)) return true;
    return false;
  }
}

/// 无文字层（扫描件）：明确报错，由调用方引导用户改为保留原文件为附件
class PdfNoTextLayerException implements Exception {
  const PdfNoTextLayerException();

  @override
  String toString() => '该 PDF 未包含可提取的文字层（可能是扫描图片文档）';
}

/// 剥离 bullet 后的结果
class _StripResult {
  const _StripResult(this.text, this.isBullet);
  final String text;
  final bool isBullet;
}

class _Line {
  _Line(this.text, this.size, [this.bold = false]);
  _Line.empty()
      : text = '',
        size = -1,
        bold = false;
  final String text;
  final double size;

  /// 该逻辑行是否含粗体片段（用于标签/标题判定）
  final bool bold;
}

class _Block {
  _Block(this.text, this.level, [this.bold = false, this.isBullet = false]);
  final String text;
  final int level;
  final bool bold;
  final bool isBullet;
}
