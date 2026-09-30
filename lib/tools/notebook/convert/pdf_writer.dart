import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../export_service.dart';
import 'document_model.dart';

/// T2 PDF 写出器——将 [DocumentModel] 转换为 PDF 字节。
///
/// 特性：
/// - 块级排字：段落、标题、列表项、代码块、水平线、表格
/// - 图片保留：从 [DocumentModel.images] 读取字节并内嵌到 PDF
/// - CJK 字体保真：复用 [ExportService.instance.loadCjkFont] 保证中文不乱码
class PdfWriter {
  PdfWriter._();

  /// 将 [DocumentModel] 转换为 PDF 字节。
  static Future<Uint8List> write(DocumentModel doc) async {
    final font = await ExportService.instance.loadCjkFont();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: font,
        bold: font,
        italic: font,
        boldItalic: font,
      ),
    );

    final widgets = <pw.Widget>[];

    for (final block in doc.blocks) {
      final w = _renderBlock(block, doc, font);
      if (w != null) {
        widgets.add(w);
      }
    }

    if (widgets.isEmpty) {
      widgets.add(pw.Text(' ', style: _style(font, 12)));
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => widgets,
      ),
    );

    return pdf.save();
  }

  static pw.Widget? _renderBlock(DocBlock block, DocumentModel doc, pw.Font font) {
    switch (block) {
      case HeadingBlock h:
        final size = switch (h.level) {
          1 => 22.0,
          2 => 18.0,
          3 => 15.0,
          _ => 13.0,
        };
        return pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
          child: pw.Text(
            h.text,
            style: _style(font, size, bold: true),
          ),
        );

      case ParagraphBlock p:
        if (p.text.trim().isEmpty) return null;
        return pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            p.text,
            style: _style(font, 11),
          ),
        );

      case ListItemBlock li:
        return pw.Padding(
          padding: pw.EdgeInsets.only(left: li.depth * 12.0, bottom: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                li.ordered ? '• ' : '- ',
                style: _style(font, 11, bold: true),
              ),
              pw.Expanded(
                child: pw.Text(
                  li.text,
                  style: _style(font, 11),
                ),
              ),
            ],
          ),
        );

      case CodeBlock c:
        return pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.symmetric(vertical: 6),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            c.code,
            style: _style(font, 9, color: PdfColors.grey800),
          ),
        );

      case HorizontalRuleBlock _:
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: PdfColors.grey400, thickness: 0.5),
        );

      case ImageBlock img:
        final docImg = doc.images[img.imageKey];
        if (docImg != null && docImg.bytes.isNotEmpty) {
          try {
            final image = pw.MemoryImage(docImg.bytes);
            return pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 8),
              alignment: pw.Alignment.center,
              child: pw.ConstrainedBox(
                constraints: const pw.BoxConstraints(maxWidth: 400, maxHeight: 300),
                child: pw.Image(image, fit: pw.BoxFit.contain),
              ),
            );
          } catch (_) {}
        }
        return null;

      case TableBlock t:
        if (t.rows.isEmpty) return null;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            children: t.rows.map((row) {
              return pw.TableRow(
                children: row.map((cell) {
                  return pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: pw.Text(
                      cell,
                      style: _style(font, 10, bold: t.hasHeader && row == t.rows.first),
                    ),
                  );
                }).toList(),
              );
            }).toList(),
          ),
        );

      case BlankBlock _:
        return pw.SizedBox(height: 8);
    }
  }

  static pw.TextStyle _style(
    pw.Font font,
    double size, {
    bool bold = false,
    PdfColor? color,
  }) {
    return pw.TextStyle(
      font: font,
      fontNormal: font,
      fontBold: font,
      fontItalic: font,
      fontBoldItalic: font,
      fontSize: size,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      color: color,
    );
  }
}
