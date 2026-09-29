/// 轻量 HTML → Markdown 转换器
///
/// 仅覆盖常见结构标签：H1-H6、p、strong/b、em/i、ul/ol/li、code、pre、
/// table/tr/th/td、img、a、blockquote。
/// 复杂/嵌套结构降级为纯文本（剥离标签保留文字）。
/// 不依赖外部 HTML 解析库，避免增加依赖。
library;

/// 将 HTML 字符串转换为 Markdown 字符串。
///
/// [html] 输入 HTML（可以是片段，不必是完整文档）。
/// 返回 Markdown 文本，段落间用空行分隔。
String htmlToMarkdown(String html) {
  if (html.isEmpty) return '';
  return _HtmlToMarkdownConverter(html).convert();
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

class _HtmlToMarkdownConverter {
  final String _html;

  _HtmlToMarkdownConverter(this._html);

  String convert() {
    var text = _html;

    // 移除 script/style 块
    text = text.replaceAll(RegExp(r'<script[^>]*>.*?</script>', dotAll: true, caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<style[^>]*>.*?</style>', dotAll: true, caseSensitive: false), '');

    // 预处理：规范化换行
    text = text.replaceAll(RegExp(r'\r\n?'), '\n');

    // 结构标签转换（顺序很重要）
    text = _convertBlocks(text);
    text = _convertInline(text);

    // 清理剩余 HTML 标签
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');

    // 解码 HTML 实体
    text = _decodeEntities(text);

    // 清理多余空行（最多两个连续空行）
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    text = text.trim();

    return text;
  }

  // ---------------------------------------------------------------------------
  // 块级标签转换
  // ---------------------------------------------------------------------------

  String _convertBlocks(String text) {
    // blockquote
    text = text.replaceAllMapped(
      RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', dotAll: true, caseSensitive: false),
      (m) {
        final inner = _stripTags(m.group(1) ?? '').trim();
        final lines = inner.split('\n').map((l) => '> $l').join('\n');
        return '\n\n$lines\n\n';
      },
    );

    // pre > code (代码块)
    text = text.replaceAllMapped(
      RegExp(r'<pre[^>]*>.*?<code[^>]*>(.*?)</code>.*?</pre>', dotAll: true, caseSensitive: false),
      (m) => '\n\n```\n${_stripTags(m.group(1) ?? '').trim()}\n```\n\n',
    );
    text = text.replaceAllMapped(
      RegExp(r'<pre[^>]*>(.*?)</pre>', dotAll: true, caseSensitive: false),
      (m) => '\n\n```\n${_stripTags(m.group(1) ?? '').trim()}\n```\n\n',
    );

    // 标题 H1-H6
    for (var i = 6; i >= 1; i--) {
      final hashes = '#' * i;
      text = text.replaceAllMapped(
        RegExp('<h$i[^>]*>(.*?)</h$i>', dotAll: true, caseSensitive: false),
        (m) => '\n\n$hashes ${_stripTags(m.group(1) ?? '').trim()}\n\n',
      );
    }

    // 表格（简化版：th→加粗，td→普通）
    text = _convertTable(text);

    // 有序列表
    text = _convertList(text, ordered: true);

    // 无序列表
    text = _convertList(text, ordered: false);

    // 段落
    text = text.replaceAllMapped(
      RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false),
      (m) => '\n\n${m.group(1)?.trim() ?? ''}\n\n',
    );

    // br → 换行
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');

    // hr → 分隔线
    text = text.replaceAll(RegExp(r'<hr\s*/?>', caseSensitive: false), '\n\n---\n\n');

    // div → 段落
    text = text.replaceAllMapped(
      RegExp(r'<div[^>]*>(.*?)</div>', dotAll: true, caseSensitive: false),
      (m) => '\n${m.group(1)?.trim() ?? ''}\n',
    );

    return text;
  }

  String _convertList(String text, {required bool ordered}) {
    final tag = ordered ? 'ol' : 'ul';
    return text.replaceAllMapped(
      RegExp('<$tag[^>]*>(.*?)</$tag>', dotAll: true, caseSensitive: false),
      (m) {
        final inner = m.group(1) ?? '';
        var index = 0;
        final items = inner.replaceAllMapped(
          RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true, caseSensitive: false),
          (li) {
            index++;
            final content = _stripTags(li.group(1) ?? '').trim();
            return ordered ? '$index. $content' : '- $content';
          },
        );
        return '\n\n${_stripTags(items).split('\n').where((l) => l.trim().isNotEmpty).join('\n')}\n\n';
      },
    );
  }

  String _convertTable(String text) {
    return text.replaceAllMapped(
      RegExp(r'<table[^>]*>(.*?)</table>', dotAll: true, caseSensitive: false),
      (m) {
        final tableHtml = m.group(1) ?? '';
        final rows = <List<String>>[];
        bool hasHeader = false;

        // 处理 thead
        final theadMatch = RegExp(r'<thead[^>]*>(.*?)</thead>', dotAll: true, caseSensitive: false)
            .firstMatch(tableHtml);
        if (theadMatch != null) {
          hasHeader = true;
          rows.add(_extractCells(theadMatch.group(1) ?? '', isHeader: true));
        }

        // 处理 tbody / tr
        final tbodyContent = tableHtml
            .replaceAll(RegExp(r'<thead[^>]*>.*?</thead>', dotAll: true, caseSensitive: false), '')
            .replaceAll(RegExp(r'<tbody[^>]*>', caseSensitive: false), '')
            .replaceAll(RegExp(r'</tbody>', caseSensitive: false), '');

        for (final trMatch in RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true, caseSensitive: false)
            .allMatches(tbodyContent)) {
          rows.add(_extractCells(trMatch.group(1) ?? '', isHeader: false));
        }

        if (rows.isEmpty) return _stripTags(tableHtml);

        final sb = StringBuffer('\n\n');
        for (var i = 0; i < rows.length; i++) {
          sb.write('| ${rows[i].join(' | ')} |\n');
          if (i == 0 && (hasHeader || rows.length > 1)) {
            sb.write('| ${rows[i].map((_) => '---').join(' | ')} |\n');
          }
        }
        sb.write('\n');
        return sb.toString();
      },
    );
  }

  List<String> _extractCells(String rowHtml, {required bool isHeader}) {
    final cells = <String>[];
    final pattern = isHeader
        ? RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true, caseSensitive: false)
        : RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true, caseSensitive: false);
    for (final m in pattern.allMatches(rowHtml)) {
      final content = _stripTags(m.group(1) ?? '').trim().replaceAll('|', '\\|');
      cells.add(isHeader ? '**$content**' : content);
    }
    return cells.isEmpty ? [''] : cells;
  }

  // ---------------------------------------------------------------------------
  // 行内标签转换
  // ---------------------------------------------------------------------------

  String _convertInline(String text) {
    // 图片（网页场景保留远端 URL）
    text = text.replaceAllMapped(
      RegExp(r'<img\s+([^>]+)/?>', caseSensitive: false),
      (m) {
        final attrs = m.group(1) ?? '';
        final srcMatch = RegExp(r"""src=["']([^"']+)["']""", caseSensitive: false).firstMatch(attrs);
        final altMatch = RegExp(r"""alt=["']([^"']*)["']""", caseSensitive: false).firstMatch(attrs);
        final src = srcMatch?.group(1) ?? '';
        final alt = altMatch?.group(1)?.trim();
        return '![${alt != null && alt.isNotEmpty ? alt : 'image'}]($src)';
      },
    );

    // 链接
    text = text.replaceAllMapped(
      RegExp(r"""<a[^>]+href=["']([^"']+)["'][^>]*>(.*?)</a>""",
          dotAll: true, caseSensitive: false),
      (m) {
        final href = m.group(1) ?? '';
        final label = _stripTags(m.group(2) ?? '').trim();
        if (label.isEmpty) return href;
        return '[$label]($href)';
      },
    );

    // 粗体
    text = text.replaceAllMapped(
      RegExp(r'<(?:strong|b)[^>]*>(.*?)</(?:strong|b)>', dotAll: true, caseSensitive: false),
      (m) => '**${m.group(1)?.trim()}**',
    );

    // 斜体
    text = text.replaceAllMapped(
      RegExp(r'<(?:em|i)[^>]*>(.*?)</(?:em|i)>', dotAll: true, caseSensitive: false),
      (m) => '*${m.group(1)?.trim()}*',
    );

    // 行内代码
    text = text.replaceAllMapped(
      RegExp(r'<code[^>]*>(.*?)</code>', dotAll: true, caseSensitive: false),
      (m) => '`${m.group(1) ?? ''}`',
    );

    // 删除线
    text = text.replaceAllMapped(
      RegExp(r'<(?:del|s|strike)[^>]*>(.*?)</(?:del|s|strike)>',
          dotAll: true, caseSensitive: false),
      (m) => '~~${m.group(1)?.trim()}~~',
    );

    return text;
  }

  // ---------------------------------------------------------------------------
  // 工具方法
  // ---------------------------------------------------------------------------

  String _stripTags(String html) => html.replaceAll(RegExp(r'<[^>]+>'), '');

  String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '');
          if (code == null) return m.group(0)!;
          return String.fromCharCode(code);
        });
  }
}
