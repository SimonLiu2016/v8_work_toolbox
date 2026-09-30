import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('T1 原地回写字节级断言', () {
    test('DOCX 解包、回写并重新打包，media 字节完全一致', () {
      final pngBytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13]);
      final archive = Archive();
      const docXml = '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
          '<w:body><w:p><w:r><w:t>Hello world</w:t></w:r></w:p></w:body></w:document>';
      archive.addFile(ArchiveFile.bytes('word/document.xml', utf8.encode(docXml)));
      archive.addFile(ArchiveFile.bytes('word/media/image1.png', pngBytes));
      archive.addFile(ArchiveFile.bytes('word/styles.xml', utf8.encode('<w:styles/>')));

      final originalZip = Uint8List.fromList(ZipEncoder().encode(archive));

      // 解码并模拟替换文本回写
      final decodedArchive = ZipDecoder().decodeBytes(originalZip);
      final newArchive = Archive();
      for (final f in decodedArchive.files) {
        if (f.name == 'word/document.xml') {
          const newDocXml = '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
              '<w:body><w:p><w:r><w:t>你好，世界</w:t></w:r></w:p></w:body></w:document>';
          newArchive.addFile(ArchiveFile.bytes(f.name, utf8.encode(newDocXml)));
        } else {
          newArchive.addFile(f);
        }
      }
      final rewrittenZip = Uint8List.fromList(ZipEncoder().encode(newArchive));

      // 验证重写后的包
      final verifyArchive = ZipDecoder().decodeBytes(rewrittenZip);
      final mediaFile = verifyArchive.findFile('word/media/image1.png');
      expect(mediaFile, isNotNull);
      expect(mediaFile!.content as List<int>, pngBytes);

      final stylesFile = verifyArchive.findFile('word/styles.xml');
      expect(stylesFile, isNotNull);
      expect(utf8.decode(stylesFile!.content as List<int>), '<w:styles/>');
    });

    test('XLSX 解包、回写 sharedStrings，sheet 结构和非字符串完全保留', () {
      final archive = Archive();
      archive.addFile(ArchiveFile.bytes('xl/sharedStrings.xml', utf8.encode('<sst><si><t>Item A</t></si></sst>')));
      archive.addFile(ArchiveFile.bytes('xl/worksheets/sheet1.xml', utf8.encode('<worksheet><sheetData/></worksheet>')));

      final originalZip = Uint8List.fromList(ZipEncoder().encode(archive));
      final decoded = ZipDecoder().decodeBytes(originalZip);

      final newArchive = Archive();
      for (final f in decoded.files) {
        if (f.name == 'xl/sharedStrings.xml') {
          newArchive.addFile(ArchiveFile.bytes(f.name, utf8.encode('<sst><si><t>条目甲</t></si></sst>')));
        } else {
          newArchive.addFile(f);
        }
      }

      final rewrittenZip = Uint8List.fromList(ZipEncoder().encode(newArchive));
      final verifyArchive = ZipDecoder().decodeBytes(rewrittenZip);

      final sheet = verifyArchive.findFile('xl/worksheets/sheet1.xml');
      expect(sheet, isNotNull);
      expect(utf8.decode(sheet!.content as List<int>), '<worksheet><sheetData/></worksheet>');

      final sst = verifyArchive.findFile('xl/sharedStrings.xml');
      expect(sst, isNotNull);
      expect(utf8.decode(sst!.content as List<int>), '<sst><si><t>条目甲</t></si></sst>');
    });
  });
}
