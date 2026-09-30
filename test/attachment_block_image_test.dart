import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/markdown_converter.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/attachment_block_component.dart';

/// 1x1 PNG（最小可用图片字节）
final _pngBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8AAAwAB/AEBjB1LhwAAAABJRU5ErkJggg==');

void main() {
  group('附件块图片预览', () {
    test('mime 为 image/png 的节点被识别为图片附件', () {
      final json = MarkdownConverter.markdownToDelta('{{attachment:local:x.png}}');
      final out = AppFlowyCodec.replacePlaceholderWithAttachment(
        json,
        placeholder: '{{attachment:local:x.png}}',
        attachmentId: 'att-img',
        filename: 'x.png',
        sizeBytes: _pngBytes.length,
        mime: 'image/png',
      );
      expect(out, contains('image/png'));

      // 节点属性可读回
      final doc = AppFlowyCodec.parseToDocument(out);
      final node = doc.root.children.firstWhere((n) => n.type == 'attachment');
      expect(node.attributes['mime'], 'image/png');
    });

    test('mime 为 application/pdf 的节点不是图片附件', () {
      final json = MarkdownConverter.markdownToDelta('{{attachment:local:a.pdf}}');
      final out = AppFlowyCodec.replacePlaceholderWithAttachment(
        json,
        placeholder: '{{attachment:local:a.pdf}}',
        attachmentId: 'att-pdf',
        filename: 'a.pdf',
        sizeBytes: 100,
        mime: 'application/pdf',
      );
      final doc = AppFlowyCodec.parseToDocument(out);
      final node = doc.root.children.firstWhere((n) => n.type == 'attachment');
      expect(node.attributes['mime'], 'application/pdf');
    });

    testWidgets('图片附件块渲染 Image.file', (tester) async {
      // 落一个真实附件文件，并让 NoteStore 能按 attId 查回它
      final dir = Directory.systemTemp.createTempSync('v8_att_blk_');
      final file = File('${dir.path}/thumb.png')..writeAsBytesSync(_pngBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              // 直接构造 attachment 节点（legacy localPath 回退路径可渲染）
              final json = AppFlowyCodec.placeholderToAttachmentJson(
                attachmentId: 'att-thumb',
                filename: 'thumb.png',
                sizeBytes: _pngBytes.length,
                localPath: file.path,
                mime: 'image/png',
              );
              final doc = AppFlowyCodec.parseToDocument(json);
              return AttachmentBlockComponentWidget(
                node: doc.root.children.firstWhere((n) => n.type == 'attachment'),
              );
            }),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsOneWidget,
          reason: '图片附件块应渲染缩略图');
      expect(find.text('thumb.png'), findsOneWidget);

      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    testWidgets('非图片附件块不渲染 Image', (tester) async {
      final dir = Directory.systemTemp.createTempSync('v8_att_blk2_');
      final file = File('${dir.path}/doc.pdf')..writeAsBytesSync([1, 2, 3]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(builder: (context) {
              final json = AppFlowyCodec.placeholderToAttachmentJson(
                attachmentId: 'att-pdf',
                filename: 'doc.pdf',
                sizeBytes: 3,
                localPath: file.path,
                mime: 'application/pdf',
              );
              final doc = AppFlowyCodec.parseToDocument(json);
              return AttachmentBlockComponentWidget(
                node: doc.root.children.firstWhere((n) => n.type == 'attachment'),
              );
            }),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Image), findsNothing,
          reason: 'PDF 附件应保持图标 + 文件名形态');
      expect(find.text('doc.pdf'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget, reason: '应渲染删除按钮');

      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
  });
}
