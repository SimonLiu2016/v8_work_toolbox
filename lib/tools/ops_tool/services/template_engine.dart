import '../models/ops_models.dart';

class TemplateEngine {
  TemplateEngine._();

  static String fmtNumber(num val) {
    if (val is int || val == val.roundToDouble()) {
      return val.toInt().toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
    final parts = val.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return '$intPart.${parts[1]}';
  }

  static String fmtPercent(num val) {
    return '${(val * 100).toStringAsFixed(2)}%';
  }

  static String fmtCurrency(num val) {
    return fmtNumber(val);
  }

  static String applyFormat(num val, String? format) {
    switch (format) {
      case 'number':
        return fmtNumber(val);
      case 'percent':
        return fmtPercent(val);
      case 'currency':
        return fmtCurrency(val);
      case 'raw':
      default:
        return val.toString();
    }
  }

  static SheetData? findSheet(List<SheetData> sheets, String? name) {
    if (name == null || name.isEmpty) return null;
    try {
      return sheets.firstWhere((s) => s.name == name);
    } catch (_) {
      try {
        return sheets.firstWhere(
            (s) => s.name.contains(name) || name.contains(s.name));
      } catch (_) {
        return null;
      }
    }
  }

  static int findColumnIndex(List<String> headers, String? columnName) {
    if (columnName == null || columnName.isEmpty) return -1;
    final exact = headers.indexOf(columnName);
    if (exact >= 0) return exact;
    return headers.indexWhere(
        (h) => h.contains(columnName) || columnName.contains(h));
  }

  static List<List<String>> getFilteredRows(
    SheetData sheet,
    String? filterColumn,
    String? filterValue,
  ) {
    if (filterColumn == null ||
        filterColumn.isEmpty ||
        filterValue == null ||
        filterValue.isEmpty) {
      return sheet.rows;
    }

    final filterColIdx = findColumnIndex(sheet.headers, filterColumn);
    if (filterColIdx < 0) return sheet.rows;

    return sheet.rows.where((row) {
      final cell = filterColIdx < row.length ? row[filterColIdx] : '';
      return cell.contains(filterValue) || cell == filterValue;
    }).toList();
  }

  static num? toNumber(String val) {
    final cleaned = val.replaceAll(RegExp(r'[,，\s]'), '');
    return num.tryParse(cleaned);
  }

  static (int col, int row)? parseCellRef(String ref) {
    final match = RegExp(r'^([A-Za-z]+)(\d+)$').firstMatch(ref.trim());
    if (match == null) return null;

    final colLetters = match.group(1)!.toUpperCase();
    final rowNum = int.tryParse(match.group(2)!) ?? 0;

    int col = 0;
    for (int i = 0; i < colLetters.length; i++) {
      col = col * 26 + (colLetters.codeUnitAt(i) - 64);
    }
    col -= 1;
    final row = rowNum - 2; // row 1 is headers, row 2 is rows[0]
    return (col, row);
  }

  static String getCellByIndices(SheetData sheet, int col, int row) {
    if (row == -1 && col >= 0 && col < sheet.headers.length) {
      return sheet.headers[col];
    }
    if (row >= 0 && row < sheet.rows.length && col >= 0) {
      final r = sheet.rows[row];
      if (col < r.length) return r[col];
    }
    return '';
  }

  static String formatValue(String raw, String? format) {
    if (raw.isEmpty) return raw;
    final n = toNumber(raw);
    if (n != null && format != null && format != 'raw') {
      return applyFormat(n, format);
    }
    return raw;
  }

  static String extractExcelValue(
    List<SheetData> sheets,
    ExtractionRule rule,
  ) {
    final sheet = findSheet(sheets, rule.sheetName);
    if (sheet == null) return '{${rule.placeholder}}';

    if (rule.cellRef != null && rule.cellRef!.isNotEmpty) {
      final ref = parseCellRef(rule.cellRef!);
      if (ref == null) return '{${rule.placeholder}}';
      final raw = getCellByIndices(sheet, ref.$1, ref.$2);
      if (raw.isEmpty) return '{${rule.placeholder}}';
      return formatValue(raw, rule.format);
    }

    final colIdx = findColumnIndex(sheet.headers, rule.column);
    if (colIdx < 0) return '{${rule.placeholder}}';

    final rows = getFilteredRows(sheet, rule.filterColumn, rule.filterValue);
    if (rows.isEmpty) return '0';

    final values = rows
        .map((r) => colIdx < r.length ? toNumber(r[colIdx]) : null)
        .whereType<num>()
        .toList();

    final agg = rule.aggregation ?? 'value';
    num result = 0;

    switch (agg) {
      case 'sum':
        result = values.fold<num>(0, (a, b) => a + b);
        break;
      case 'count':
        result = rows.length;
        break;
      case 'avg':
        result = values.isNotEmpty
            ? values.fold<num>(0, (a, b) => a + b) / values.length
            : 0;
        break;
      case 'max':
        result = values.isNotEmpty
            ? values.reduce((a, b) => a > b ? a : b)
            : 0;
        break;
      case 'min':
        result = values.isNotEmpty
            ? values.reduce((a, b) => a < b ? a : b)
            : 0;
        break;
      case 'value':
      default:
        final firstRow = rows[0];
        final raw = colIdx < firstRow.length ? firstRow[colIdx] : '';
        return formatValue(raw, rule.format);
    }

    return applyFormat(result, rule.format);
  }

  static List<String> extractPlaceholders(String template) {
    final matches = RegExp(r'\{([^}]+)\}').allMatches(template);
    return matches.map((m) => m.group(1)!).toSet().toList();
  }

  static String resolveTemplate({
    required String template,
    required List<ExtractionRule> rules,
    List<SheetData>? sheets,
    Map<String, String>? dbValues,
  }) {
    var result = template;

    // Built-in variables
    final now = DateTime.now();
    final builtIn = {
      '当前日期':
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      '当前时间':
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}',
      '报告日期': '${now.month}月${now.day}日',
      '报告日期_完整': '${now.year}年${now.month}月${now.day}日',
    };

    for (final entry in builtIn.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }

    // Database values
    if (dbValues != null) {
      for (final entry in dbValues.entries) {
        result = result.replaceAll('{${entry.key}}', entry.value);
      }
    }

    // Excel rules
    if (sheets != null && sheets.isNotEmpty) {
      for (final rule in rules) {
        if (rule.sourceType == 'excel') {
          final val = extractExcelValue(sheets, rule);
          result = result.replaceAll('{${rule.placeholder}}', val);
        }
      }
    }

    return result;
  }

  static String formatAsHtmlTable(
    List<String> headers,
    List<List<String>> rows, {
    int maxRows = 50,
  }) {
    if (rows.isEmpty) return '<p>(无数据)</p>';

    final headerHtml = headers
        .map((h) =>
            '<th style="padding: 6px 12px; background: #262b33; color: #e5e5e5; border: 1px solid #3c424d; text-align: left; font-weight: 600;">$h</th>')
        .join('');

    final bodyHtml = rows.take(maxRows).map((row) {
      final cells = headers.asMap().entries.map((e) {
        final c = e.key < row.length ? row[e.key] : '-';
        return '<td style="padding: 6px 12px; border: 1px solid #3c424d; color: #cfcfcf;">$c</td>';
      }).join('');
      return '<tr>$cells</tr>';
    }).join('');

    return '''
<table style="border-collapse: collapse; width: 100%; font-size: 13px; margin: 12px 0; background: #1a1d21;">
  <thead><tr>$headerHtml</tr></thead>
  <tbody>$bodyHtml</tbody>
</table>
''';
  }
}
