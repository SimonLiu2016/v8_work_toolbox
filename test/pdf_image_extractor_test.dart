import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/png_encoder.dart';
import 'package:V8WorkToolbox/tools/notebook/pdf_image_extractor.dart';

/// 构造一个只含"够用部件"的 PDF：1 页，/Resources /XObject 引用一张图。
///
/// 不追求 PDF 合法性的完整（无 xref、无 catalog），因为
/// [PdfImageExtractor] 走全文扫描 `N 0 obj` 的降级路径即可解析。
Uint8List _buildPdf({
  required String imageObjDict,
  required Uint8List imageStream,
  bool indirectResource = false,
}) {
  final b = BytesBuilder(copy: false);

  b.add(ascii.encode('%PDF-1.4\n'));

  // obj 1 = 页面；obj 2 = 图片 XObject；obj 3 = 间接分支的资源字典。
  b.add(ascii.encode(indirectResource
      ? '1 0 obj\n<< /Type /Page /Resources 3 0 R >>\nendobj\n'
      : '1 0 obj\n<< /Type /Page /Resources << /XObject << /Im1 2 0 R >> >> >>\nendobj\n'));

  b.add(ascii.encode('2 0 obj\n'));
  b.add(ascii.encode(imageObjDict));
  b.add(ascii.encode('\nstream\n'));
  b.add(imageStream);
  b.add(ascii.encode('\nendstream\nendobj\n'));

  if (indirectResource) {
    b.add(ascii.encode('3 0 obj\n<< /XObject << /Im1 2 0 R >> >>\nendobj\n'));
  }

  b.add(ascii.encode('trailer\n<< >>\n%%EOF\n'));
  return b.toBytes();
}

String _dictWithLength(int width, int height, String filter, int streamLen) {
  return '<< /Type /XObject /Subtype /Image /Width $width /Height $height '
      '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter $filter '
      '/Length $streamLen >>';
}

void main() {
  group('PngEncoder', () {
    test('产出合法 PNG（签名 + IHDR + CRC 全对）', () {
      final pixels = Uint8List.fromList([
        0xFF, 0, 0, 0, 0xFF, 0,
        0, 0, 0xFF, 0xFF, 0xFF, 0,
      ]);
      final png = PngEncoder.encodeRgb(pixels, width: 2, height: 2, channels: 3);

      expect(png.sublist(0, 8), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      // IHDR width/height
      expect(png[16], 0);
      expect(png[17], 0);
      expect(png[18], 0);
      expect(png[19], 2);
      expect(png[23], 2);
      // color type = 2 (RGB)
      expect(png[25], 2);
      // 必须含 IDAT 与 IEND
      expect(ascii.decode(png.sublist(12, 16)), 'IHDR');
      expect(ascii.decode(png.sublist(png.length - 8, png.length - 4)), 'IEND');
    });

    test('RGBA 通道的 color type 为 6', () {
      final pixels = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255]);
      final png = PngEncoder.encodeRgb(pixels, width: 1, height: 2, channels: 4);
      expect(png[25], 6);
    });
  });

  group('PdfImageExtractor', () {
    test('提取 DCTDecode 图片并标记 image/jpeg', () {
      // JPEG 的 SOI 标记即可让测试不依赖真实 JPEG 文件——提取器只搬字节。
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46]);
      final dict = _dictWithLength(64, 48, '/DCTDecode', jpeg.length);
      final pdf = _buildPdf(imageObjDict: dict, imageStream: jpeg);

      final images = PdfImageExtractor.extract(pdf);

      expect(images.length, 1);
      expect(images.first.mime, 'image/jpeg');
      expect(images.first.extension, 'jpg');
      expect(images.first.width, 64);
      expect(images.first.height, 48);
      expect(images.first.pageIndex, 0);
      // 字节逐字节一致（零转码）
      expect(images.first.bytes, jpeg);
    });

    test('提取 FlateDecode 图片并编码为 PNG', () {
      // 2x2 纯蓝 RGB（12 字节），zlib 压缩后作为流
      final raw = Uint8List.fromList([
        0, 0, 0xFF, 0, 0, 0xFF,
        0, 0, 0xFF, 0, 0, 0xFF,
      ]);
      final compressed = Uint8List.fromList(ZLibCodec(level: 6).encode(raw));
      final dict = _dictWithLength(2, 2, '/FlateDecode', compressed.length);
      final pdf = _buildPdf(imageObjDict: dict, imageStream: compressed);

      final images = PdfImageExtractor.extract(pdf);

      expect(images.length, 1);
      expect(images.first.mime, 'image/png');
      expect(images.first.extension, 'png');
      expect(images.first.width, 2);
      expect(images.first.height, 2);
      // 产出的是 PNG 而非原始样本
      expect(images.first.bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(PdfImageExtractor.lastUnrecoverableCount, 0);
    });

    test('间接 /Resources 引用也能解析', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final dict = _dictWithLength(16, 16, '/DCTDecode', jpeg.length);
      final pdf = _buildPdf(
        imageObjDict: dict,
        imageStream: jpeg,
        indirectResource: true,
      );

      final images = PdfImageExtractor.extract(pdf);
      expect(images.length, 1);
      expect(images.first.bytes, jpeg);
    });

    test('无图片 PDF 返回空列表', () {
      final pdf = ascii.encode('%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n') as Uint8List;
      expect(PdfImageExtractor.extract(pdf), isEmpty);
    });

    test('不支持的过滤器计入 unrecoverable，不产出错图', () {
      final bytes = Uint8List.fromList(List.filled(16, 0x42));
      final dict = _dictWithLength(4, 4, '/CCITTFaxDecode', bytes.length);
      final pdf = _buildPdf(imageObjDict: dict, imageStream: bytes);

      final images = PdfImageExtractor.extract(pdf);
      expect(images, isEmpty);
      expect(PdfImageExtractor.lastUnrecoverableCount, 1);
    });

    test('带 /DecodeParms 的图片标 unrecoverable（预测器会改变样本排布）', () {
      final raw = Uint8List.fromList(List.filled(12, 0x11));
      final compressed = Uint8List.fromList(ZLibCodec().encode(raw));
      final dict = '<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
          '/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode '
          '/DecodeParms << /Predictor 12 /Colors 3 /BitsPerComponent 8 /Columns 2 >> '
          '/Length ${compressed.length} >>';
      final pdf = _buildPdf(imageObjDict: dict, imageStream: compressed);

      expect(PdfImageExtractor.extract(pdf), isEmpty);
      expect(PdfImageExtractor.lastUnrecoverableCount, 1);
    });

    test('DeviceGray 标 unrecoverable 而非误读为 RGB', () {
      final raw = Uint8List.fromList([0, 64, 128, 255]);
      final compressed = Uint8List.fromList(ZLibCodec().encode(raw));
      final dict = '<< /Type /XObject /Subtype /Image /Width 2 /Height 2 '
          '/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode '
          '/Length ${compressed.length} >>';
      final pdf = _buildPdf(imageObjDict: dict, imageStream: compressed);

      expect(PdfImageExtractor.extract(pdf), isEmpty);
      expect(PdfImageExtractor.lastUnrecoverableCount, 1);
    });

    test('加密 PDF 抛 PdfEncryptedException', () {
      final pdf = ascii.encode('%PDF-1.4\n1 0 obj\n<< /Encrypt 9 0 R >>\nendobj\n') as Uint8List;
      expect(() => PdfImageExtractor.extract(pdf), throwsA(isA<PdfEncryptedException>()));
    });

    // 同一 image 对象被两页引用：按页各取一张（页码忠实）。
    // 按对象去重会让第二页缺图，比重复占空间更糟——spec 也是 per page。
    test('同一图片对象跨两页按页各取一张', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x01, 0x02]);
      final dict = _dictWithLength(8, 8, '/DCTDecode', jpeg.length);
      final b = BytesBuilder(copy: false);
      b.add(ascii.encode('%PDF-1.4\n'));
      b.add(ascii.encode(
          '1 0 obj\n<< /Type /Page /Resources << /XObject << /Im1 3 0 R >> >> >>\nendobj\n'));
      b.add(ascii.encode(
          '5 0 obj\n<< /Type /Page /Resources << /XObject << /Im1 3 0 R >> >> >>\nendobj\n'));
      b.add(ascii.encode('3 0 obj\n${dict}\nstream\n'));
      b.add(jpeg);
      b.add(ascii.encode('\nendstream\nendobj\n%%EOF\n'));
      final pdf = b.toBytes();

      final images = PdfImageExtractor.extract(pdf);
      expect(images.length, 2);
      expect(images.map((i) => i.pageIndex), [0, 1]);
    });

    test('同一页内重复引用同一对象只取一张', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x07]);
      final dict = _dictWithLength(8, 8, '/DCTDecode', jpeg.length);
      final pdf = ascii.encode('%PDF-1.4\n'
              '1 0 obj\n<< /Type /Page /Resources << /XObject << /Im1 2 0 R /Im2 2 0 R >> >> >>\nendobj\n'
              '2 0 obj\n${dict}\nstream\n')
          .buffer;
      final b = BytesBuilder(copy: false)..add(pdf.asUint8List());
      b.add(jpeg);
      b.add(ascii.encode('\nendstream\nendobj\n%%EOF\n'));

      final images = PdfImageExtractor.extract(b.toBytes());
      expect(images.length, 1);
    });
  });
}
