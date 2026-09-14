import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart' show ZLibDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/export_service.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  int counter = 0;
  final rootTempDir = Directory.systemTemp.createTempSync('pdf_image_table_test_');
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

  /// 1x1 透明 PNG（base64）。
  const kTinyPngBase64 =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

  Future<String> writeTinyPng() async {
    final f = File('${dir.path}/sample.png');
    await f.writeAsBytes(base64Decode(kTinyPngBase64));
    return f.path;
  }

  Note createNote(List<Map<String, dynamic>> ops, {String title = '导出测试'}) => Note(
    id: 'test-note',
    title: title,
    deltaJson: jsonEncode(ops),
    notebookId: null,
    isPinned: false,
    isDeleted: false,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 2),
  );

  Future<String> pdfStreamText(Note note) async {
    final pdf = await ExportService.instance.exportToFile(
      note: note,
      format: ExportFormat.pdf,
      outputDir: dir.path,
    );
    expect(pdf.existsSync(), isTrue, reason: 'PDF 应已生成');
    expect((await pdf.readAsBytes()).sublist(0, 4), equals([0x25, 0x50, 0x44, 0x46]));
    return _uncompressedStreams(await pdf.readAsBytes());
  }

  group('PDF 图片嵌入', () {
    test('笔记含图片时 PDF 会嵌入图像对象', () async {
      final imgPath = await writeTinyPng();
      final note = createNote([
        {'insert': '正文第一段'},
        {'insert': '\n'},
        {'insert': {'image': imgPath}},
        {'insert': '\n'},
        {'insert': '正文第二段'},
        {'insert': '\n'},
      ]);

      final pdf = await ExportService.instance.exportToFile(
        note: note,
        format: ExportFormat.pdf,
        outputDir: dir.path,
      );
      expect(pdf.existsSync(), isTrue, reason: 'PDF 应已生成');

      final text = utf8.decode(await pdf.readAsBytes(), allowMalformed: true);
      // 位图嵌入后 PDF 对象字典里会出现 `/Subtype /Image`（未压缩，可直接搜索）。
      expect(text.contains('/Image'), isTrue,
        reason: 'PDF 必须包含图像对象，否则图片在导出中丢失');
      // 内容流里也要有绘图指令，证明图片真的被画进了页面。
      final streamText = _uncompressedStreams(await pdf.readAsBytes());
      expect(streamText.contains('Do'), isTrue,
        reason: '内容流应出现图像 XObject 引用（Do 指令）');
    });

    test('图片文件不存在时导出仍成功并给出提示', () async {
      final note = createNote([
        {'insert': {'image': '${dir.path}/missing.png'}},
        {'insert': '\n'},
      ]);

      final streamText = await pdfStreamText(note);
      expect(streamText.contains('TJ'), isTrue,
        reason: '缺图时应渲染占位提示文字，而不是静默丢弃');
    });
  });

  group('表格导出', () {
    Note tableNote() => createNote([
      {'insert': '表格前的文字'},
      {'insert': '\n'},
      {'insert': {'table': {'rows': [
        ['姓名', '年龄'],
        ['张三', '30'],
        ['李四', '25'],
      ]}}},
      {'insert': '\n'},
    ]);

    test('HTML 导出包含原生 table 结构', () async {
      final html = await ExportService.instance.exportNote(
        tableNote(), ExportFormat.html);
      expect(html.contains('<table>'), isTrue,
        reason: '表格 embed 必须被转成 HTML table');
      expect(html.contains('<tr>'), isTrue);
      expect(html.contains('<th>姓名</th>'), isTrue,
        reason: '首行应为表头 <th>');
      expect(html.contains('<td>张三</td>'), isTrue);
      expect(html.contains('李四'), isTrue);
    });

    test('纯文本导出用竖线保留列结构', () async {
      final txt = await ExportService.instance.exportNote(
        tableNote(), ExportFormat.plainText);
      expect(txt.contains('张三 | 30'), isTrue);
      expect(txt.contains('姓名 | 年龄'), isTrue);
    });

    test('PDF 导出渲染出表格矩形与填充', () async {
      final streamText = await pdfStreamText(tableNote());
      // 表头单元格底色 + 单元格文本：`re` 矩形、`f` 填充、`TJ` 文字。
      // 不能用字面汉字断言 —— CJK 走 CID 子集编码，内容是 glyph id。
      expect(streamText.contains('re'), isTrue,
        reason: '内容流应出现矩形绘制指令（表格单元格）');
      expect(streamText.contains('TJ'), isTrue,
        reason: '内容流应出现文字绘制指令（单元格文本）');
    });

    test('未知 embed 导出为占位提示而非静默丢弃', () async {
      // 对照组：同标题、无 embed 的笔记。占位文字的存在体现为多出一段文字指令。
      final baseline = await pdfStreamText(createNote([{'insert': '\n'}]));
      final withUnknown = await pdfStreamText(createNote([
        {'insert': {'widget_card': 'payload'}},
        {'insert': '\n'},
      ]));

      int textOps(String s) => s.split('TJ').length - 1;
      expect(textOps(withUnknown), greaterThan(textOps(baseline)),
        reason: '未知 embed 应渲染占位文字（比无 embed 笔记多出文字指令）');
    });
  });
}

/// 解压 PDF 所有 stream 对象，返回拼接后的内容流文本。
///
/// 必须在字节层定位 stream/endstream：UTF-8 里中文占 3 字节，用字符串下标会错位，
/// 导致切出的字节范围不对、zlib 解压全部失败（表现为「什么都没解压出来」）。
String _uncompressedStreams(List<int> bytes) {
  final out = StringBuffer();
  final streamTok = const [0x73, 0x74, 0x72, 0x65, 0x61, 0x6d]; // "stream"
  final endTok = const [0x65, 0x6e, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6d];

  var pos = 0;
  while (true) {
    final mpos = _indexOf(bytes, pos, streamTok);
    if (mpos < 0) break;
    var s0 = mpos + streamTok.length;
    if (s0 < bytes.length && (bytes[s0] == 0x0d || bytes[s0] == 0x0a)) s0++;
    final end = _indexOf(bytes, s0, endTok);
    if (end < 0) break;
    pos = end + endTok.length;

    // endstream 前的 \n\r 属于 PDF 语法，不属于 zlib 数据。
    var e0 = end;
    if (e0 > s0 && (bytes[e0 - 1] == 0x0a || bytes[e0 - 1] == 0x0d)) e0--;
    if (e0 > s0 && (bytes[e0 - 1] == 0x0a || bytes[e0 - 1] == 0x0d)) e0--;

    try {
      final inflated = const ZLibDecoder().decodeBytes(bytes.sublist(s0, e0));
      out.write(utf8.decode(inflated, allowMalformed: true));
      out.write('\n');
    } catch (_) {
      // 非内容流的 stream（字体子集、对象流等）解压失败，跳过。
    }
  }
  return out.toString();
}

int _indexOf(List<int> hay, int from, List<int> needle) {
  outer:
  for (var i = from; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}
