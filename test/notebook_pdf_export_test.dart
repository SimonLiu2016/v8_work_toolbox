import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/export_service.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int counter = 0;
  final rootTempDir = Directory.systemTemp.createTempSync('pdf_export_test_');
  final createdDirs = <Directory>[];

  tearDownAll(() {
    for (final d in createdDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    if (rootTempDir.existsSync()) rootTempDir.deleteSync(recursive: true);
  });

  late Directory dir;

  setUp(() async {
    counter += 1;
    dir = Directory('${rootTempDir.path}/case_$counter');
    createdDirs.add(dir);
    await dir.create(recursive: true);
  });

  Note noteWithChinese() => Note(
    id: 'test-note-1',
    title: '中文笔记标题测试',
    deltaJson: jsonEncode([
      {'insert': '这是一段包含中文、日文「こんにちは」和韩文「안녕하세요」的正文内容。'},
      {'insert': '\n'},
      {'insert': '第二段落：支持中日韩混排。'},
      {'insert': '\n'},
      {'insert': '列表项中文'},
      {'insert': '\n', 'attributes': {'list': 'bullet'}},
    ]),
    notebookId: null,
    isPinned: false,
    isDeleted: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );

  group('CJK 字体加载', () {
    test('loadCjkFont 在 macOS 上能定位系统字体', () async {
      final font = await ExportService.instance.loadCjkFont();
      expect(font, isNotNull);
      expect(ExportService.instance.hasCjkFont, isTrue,
        reason: 'macOS 应加载到系统 CJK 字体');
    });

    test('缓存生效：多次调用返回同一实例', () async {
      final a = await ExportService.instance.loadCjkFont();
      final b = await ExportService.instance.loadCjkFont();
      expect(identical(a, b), isTrue);
    });

    test('重置缓存后仍可重新加载', () async {
      ExportService.instance.resetCjkFontCache();
      final font = await ExportService.instance.loadCjkFont();
      expect(font, isNotNull);
      expect(ExportService.instance.hasCjkFont, isTrue);
    });
  });

  group('PDF 中文字体嵌入', () {
    test('导出中文笔记会内嵌 TrueType 字体子集', () async {
      final note = noteWithChinese();
      await ExportService.instance.exportToFile(
        note: note,
        format: ExportFormat.pdf,
        outputDir: dir.path,
      );

      final pdf = File('${dir.path}/中文笔记标题测试.pdf');
      expect(pdf.existsSync(), isTrue, reason: 'PDF 应已生成');

      final bytes = await pdf.readAsBytes();
      expect(bytes.length, greaterThan(1024));
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]), reason: '应为 PDF 文件头');

      final text = utf8.decode(bytes, allowMalformed: true);
      // 中文走 unicode CID 路径，字体对象 subtype 为 `/Type0`，
      // 字形文件通过描述符的 `/FontFile2` 内嵌（TrueType 容器名）。
      // 仅用 Helvetica Type1 时不会出现这两个键。
      expect(text.contains('/FontFile2'), isTrue,
        reason: 'PDF 必须内嵌 TrueType 字体文件，否则中文字形缺失');
      expect(text.contains('/Type0'), isTrue,
        reason: 'CJK 文本应使用 CID 编码字体');
      // 子集化后体积应远小于原始 22MB 字体文件
      expect(bytes.length, lessThan(1 * 1024 * 1024),
        reason: '字体应被子集化，产物不应接近 22MB');
    });

    test('未找到系统字体时回退到内置字体且导出仍成功', () async {
      ExportService.instance.resetCjkFontCache();
      // 注入不存在的路径，模拟系统无 CJK 字体的环境
      expect(await ExportService.instance.loadCjkFont(paths: ['/nonexistent/cjk.ttf']), isNotNull);
      expect(ExportService.instance.hasCjkFont, isFalse,
        reason: '无系统字体时应标记为未加载');
      // 再次调用应返回缓存的回退字体而非重新读盘
      expect(await ExportService.instance.loadCjkFont(paths: ['/nonexistent/cjk.ttf']), isNotNull);

      // 此时缓存为回退状态，导出应使用内置字体完成而非崩溃
      final note = noteWithChinese();
      await ExportService.instance.exportToFile(
        note: note,
        format: ExportFormat.pdf,
        outputDir: dir.path,
      );

      final pdf = File('${dir.path}/中文笔记标题测试.pdf');
      expect(pdf.existsSync(), isTrue, reason: '回退路径下也应成功产出 PDF');
      final bytes = await pdf.readAsBytes();
      expect(bytes.sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
    });
  });

  group('非 PDF 导出回归', () {
    test('Markdown / HTML / TXT 均不受字体改动影响', () async {
      final note = noteWithChinese();

      final md = await ExportService.instance.exportNote(note, ExportFormat.markdown);
      expect(md.contains('中文笔记标题测试'), isTrue);
      expect(md.contains('こんにちは'), isTrue);

      final html = await ExportService.instance.exportNote(note, ExportFormat.html);
      expect(html.contains('中文笔记标题测试'), isTrue);

      final txt = await ExportService.instance.exportNote(note, ExportFormat.plainText);
      expect(txt.contains('안녕하세요'), isTrue);
    });
  });
}
