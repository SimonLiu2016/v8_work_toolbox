import 'package:markdown/markdown.dart' as md;
import '../models/ops_models.dart';

class ReportGenerator {
  ReportGenerator._();

  static String generateHtml(Report report) {
    final sectionsHtml = report.sections.map((s) => _renderSection(s)).join('\n');

    return '''<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${_escapeHtml(report.title)}</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            line-height: 1.6;
            color: #333333;
            max-width: 900px;
            margin: 0 auto;
            padding: 24px;
            background: #ffffff;
        }
        h1 {
            color: #1a1a2e;
            border-bottom: 3px solid #16213e;
            padding-bottom: 10px;
            font-size: 24px;
            margin-top: 0;
        }
        .report-date {
            color: #666666;
            font-size: 14px;
            margin-bottom: 24px;
        }
        .section {
            margin-bottom: 24px;
            border: 1px solid #e8e8e8;
            border-radius: 8px;
            padding: 16px 20px;
            background: #fafafa;
        }
        .section-title {
            color: #16213e;
            font-size: 17px;
            font-weight: 600;
            margin: 0 0 12px 0;
            padding-bottom: 8px;
            border-bottom: 2px solid #0f3460;
        }
        .section-content {
            font-size: 14px;
            color: #222222;
        }
        table {
            border-collapse: collapse;
            width: 100%;
            font-size: 13px;
            margin: 12px 0;
        }
        th {
            padding: 8px 12px;
            background: #f0f2f5;
            border: 1px solid #d9d9d9;
            text-align: left;
            font-weight: 600;
        }
        td {
            padding: 8px 12px;
            border: 1px solid #d9d9d9;
        }
    </style>
</head>
<body>
    <h1>${_escapeHtml(report.title)}</h1>
    <div class="report-date">报告生成日期：${_escapeHtml(report.date)}</div>
    $sectionsHtml
</body>
</html>''';
  }

  static String _renderSection(ReportSection section) {
    String htmlContent;
    try {
      htmlContent = md.markdownToHtml(
        section.content,
        extensionSet: md.ExtensionSet.gitHubFlavored,
      );
    } catch (_) {
      htmlContent = '<pre>${_escapeHtml(section.content)}</pre>';
    }

    return '''
    <div class="section">
        <div class="section-title">${_escapeHtml(section.title)}</div>
        <div class="section-content">$htmlContent</div>
    </div>
    ''';
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
