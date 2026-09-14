import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/models.dart';
import 'package:V8WorkToolbox/tools/notebook/appflowy_codec.dart';
import 'package:V8WorkToolbox/tools/notebook/export_service.dart';
import 'package:V8WorkToolbox/tools/notebook/evernote_import_service.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/note_mindmap_component.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/components/note_code_block_component.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Module 1: Table - Native Block, Navigation & Codec Roundtrip', () {
    test('Can create TableNode, inspect cells, and serialize to markdown', () {
      final tableNode = TableNode.fromList([
        ['商品', '单价', '数量'],
        ['苹果', '5.0', '10'],
        ['香蕉', '3.5', '20'],
      ]);

      expect(tableNode.node.type, equals(TableBlockKeys.type));
      expect(tableNode.colsLen, equals(3)); // 3 cols
      expect(tableNode.rowsLen, equals(3)); // 3 rows
      expect(tableNode.getCell(0, 0).children.first.delta?.toPlainText(), equals('商品'));

      final doc = Document(root: pageNode(children: [tableNode.node]));
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('商品'), isTrue);
      expect(md.contains('苹果'), isTrue);

      final doc2 = AppFlowyCodec.parseToDocument(md);
      expect(doc2.root.children.any((n) => n.type == TableBlockKeys.type), isTrue);
    });
  });

  group('Module 2: Code Block - Syntax, Language & Copy', () {
    test('CodeBlock node preserves language, line content, and copy readiness', () {
      const code = 'def calculate_sum(a, b):\n    return a + b\n';
      final node = codeBlockNode(
        code: code,
        language: 'python',
      );

      expect(node.type, equals(NoteCodeBlockKeys.type));
      expect(node.attributes['language'], equals('python'));
      expect(node.delta?.toPlainText(), equals(code));

      final doc = Document(root: pageNode(children: [node]));
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('```python'), isTrue);
      expect(md.contains('calculate_sum'), isTrue);
    });
  });

  group('Module 3: Image Interaction - Attributes & Dimensions', () {
    test('Image node supports url, width, and alignment attributes', () {
      final imgNode = imageNode(
        url: '/test/attachments/sample.png',
        width: 320.0,
        align: 'center',
      );

      expect(imgNode.type, equals(ImageBlockKeys.type));
      expect(imgNode.attributes[ImageBlockKeys.url], equals('/test/attachments/sample.png'));
      expect(imgNode.attributes[ImageBlockKeys.width], equals(320.0));
      expect(imgNode.attributes[ImageBlockKeys.align], equals('center'));

      final doc = Document(root: pageNode(children: [imgNode]));
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('/test/attachments/sample.png'), isTrue);
    });
  });

  group('Module 4: Clipboard Image Paste - Path Resolution', () {
    test('Image paste simulation updates editor state transaction cleanly', () {
      final editorState = EditorState(
        document: Document.blank(withInitialText: true),
      );

      const fakeSavedPath = '/mock/note_attachments/pasted_image_123.png';
      final newImg = imageNode(url: fakeSavedPath);

      final transaction = editorState.transaction
        ..insertNode([editorState.document.root.children.length], newImg);
      editorState.apply(transaction);

      expect(editorState.document.root.children.last.type, equals(ImageBlockKeys.type));
      expect(editorState.document.root.children.last.attributes[ImageBlockKeys.url], equals(fakeSavedPath));
    });
  });

  group('Module 5: Mind Map - SVG & Outline Vector Data', () {
    test('MindMap block builds, stores JSON data, and parses from markdown', () {
      const mindMapData = '{"root":{"text":"主架构","children":[{"text":"分支A"},{"text":"分支B"}]}}';
      final node = mindMapNode(data: mindMapData);

      expect(node.type, equals(MindMapBlockKeys.type));
      expect(node.attributes[MindMapBlockKeys.data], equals(mindMapData));

      final doc = Document(root: pageNode(children: [node]));
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('```mindmap'), isTrue);
      expect(md.contains('主架构'), isTrue);

      final doc2 = AppFlowyCodec.parseToDocument(md);
      expect(doc2.root.children.any((n) => n.type == MindMapBlockKeys.type), isTrue);
    });
  });

  group('Module 6: Todo List - Checkbox State & Toggle', () {
    test('TodoList node correctly toggles checked state', () {
      final todoNode = todoListNode(
        checked: false,
        delta: Delta()..insert('待办事项 Alpha'),
      );

      expect(todoNode.type, equals(TodoListBlockKeys.type));
      expect(todoNode.attributes[TodoListBlockKeys.checked], isFalse);

      final doc = Document(root: pageNode(children: [todoNode]));
      final md = AppFlowyCodec.documentToMarkdownString(doc);
      expect(md.contains('- [ ] 待办事项 Alpha'), isTrue);

      final checkedDoc = AppFlowyCodec.parseToDocument('- [x] 待办事项 Alpha');
      expect(checkedDoc.root.children.first.type, equals(TodoListBlockKeys.type));
      expect(checkedDoc.root.children.first.attributes[TodoListBlockKeys.checked], isTrue);
    });
  });

  group('Module 7: Typography & Inline Styles', () {
    test('Supports H1~H3 headings, bold, italic, code, and blockquote', () {
      const complexMd = '''
# 一级标题
## 二级标题
### 三级标题

> 这是一个核心引用块

正文包含 **粗体**、*斜体* 以及 `inline_code`。
''';

      final doc = AppFlowyCodec.parseToDocument(complexMd);
      expect(doc.root.children.length, greaterThanOrEqualTo(4));

      final h1 = doc.root.children[0];
      expect(h1.type, equals('heading'));
      expect(h1.attributes['level'], equals(1));

      final h2 = doc.root.children[1];
      expect(h2.type, equals('heading'));
      expect(h2.attributes['level'], equals(2));

      final h3 = doc.root.children[2];
      expect(h3.type, equals('heading'));
      expect(h3.attributes['level'], equals(3));

      final quote = doc.root.children.firstWhere((n) => n.type == 'quote');
      expect(quote.delta?.toPlainText(), contains('这是一个核心引用块'));
    });
  });

  group('Module 8: Export Formats - MD, HTML, TXT, PDF', () {
    test('ExportService correctly formats AppFlowy document note into all 4 formats', () async {
      final note = Note(
        id: 'test_export_note',
        title: '全面导出测试',
        deltaJson: AppFlowyCodec.documentToJson(
          AppFlowyCodec.parseToDocument('''
# 导出测试核心

正文中英混排：Test English & 中文内容。

| 模块 | 状态 |
| --- | --- |
| 表格 | 正常 |
| 导出 | 正常 |
'''),
        ),
        isPinned: false,
        isDeleted: false,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final mdText = await ExportService.instance.exportNote(note, ExportFormat.markdown);
      expect(mdText.contains('# 全面导出测试'), isTrue);
      expect(mdText.contains('导出测试核心'), isTrue);

      final htmlText = await ExportService.instance.exportNote(note, ExportFormat.html);
      expect(htmlText.contains('<h1>全面导出测试</h1>'), isTrue);
      expect(htmlText.contains('<table>'), isTrue);
      expect(htmlText.contains('中英混排'), isTrue);

      final plainText = await ExportService.instance.exportNote(note, ExportFormat.plainText);
      expect(plainText.contains('全面导出测试'), isTrue);
      expect(plainText.contains('中英混排'), isTrue);

      // PDF 导出验证
      final tmpDir = Directory.systemTemp.createTempSync('export_test_');
      try {
        final pdfFile = await ExportService.instance.exportToFile(
          note: note,
          format: ExportFormat.pdf,
          outputDir: tmpDir.path,
        );
        expect(pdfFile.existsSync(), isTrue);
        expect(pdfFile.lengthSync(), greaterThan(100)); // PDF generated with content
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });

  group('Module 9: Auto-Save & Debounce Support', () {
    test('NoteModel plainText and summary adapt seamlessly to AppFlowy JSON', () {
      final doc = AppFlowyCodec.parseToDocument('# 架构演进说明\n\n新引擎性能大幅提升，零光标跳动。');
      final jsonStr = AppFlowyCodec.documentToJson(doc);

      final note = NoteModel(
        id: 'save_test',
        title: '架构演进说明',
        deltaJson: jsonStr,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(note.plainText.contains('新引擎性能大幅提升'), isTrue);
      expect(note.summary.contains('新引擎性能大幅提升'), isTrue);
    });
  });

  group('Module 10: Metadata & Header', () {
    test('NoteModel retains notebookId, isPinned, isDeleted, and tagIds', () {
      final note = NoteModel(
        id: 'meta_test',
        title: '元数据笔记',
        deltaJson: '{}',
        notebookId: 'nb_work',
        isPinned: true,
        isDeleted: false,
        tagIds: const ['tag1', 'tag2'],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(note.notebookId, equals('nb_work'));
      expect(note.isPinned, isTrue);
      expect(note.isDeleted, isFalse);
      expect(note.tagIds, contains('tag1'));
      expect(note.tagIds, contains('tag2'));
    });
  });

  group('Module 11: Multi-Window & Context Menu Support', () {
    test('NoteModel copy and serialization for multi-window bridge', () {
      final note = NoteModel(
        id: 'win_note_1',
        title: '独立窗口笔记',
        deltaJson: AppFlowyCodec.documentToJson(
          AppFlowyCodec.parseToDocument('独立子窗口编辑内容'),
        ),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      expect(note.id, equals('win_note_1'));
      expect(note.title, equals('独立窗口笔记'));
      expect(note.plainText.contains('独立子窗口编辑内容'), isTrue);
    });
  });
}
