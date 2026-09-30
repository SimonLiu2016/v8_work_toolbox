import 'dart:convert' show AsciiCodec;
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

const _ascii = AsciiCodec();

/// 最小 PNG 编码器：把 raw RGB(A) 样本编码为合法 PNG 字节。
///
/// 为什么需要它：PDF 的 `/FlateDecode` 图片解出来的只是原始像素样本
/// （row-major RGB/RGBA），浏览器与 Flutter 都认不出，必须裹成 PNG 才能
/// 作为图片落盘渲染。`dart:ui` 的图片编码需要 GPU 上下文，测试里不可用；
/// `pdf` 包的 `PdfImage` 是往 PDF 内部对象塞数据，不返回 PNG 字节。
///
/// 因此这里自写一个只覆盖"常见输入"的极小编码器（约 60 行）：
/// - 过滤方式固定为 0（None），每个 scanline 前 1 字节 filter type
/// - zlib 由 `dart:io` 无关的 `dart:convert` + `ZLibCodec` 提供
/// - CRC32 手写，避免再引依赖
class PngEncoder {
  PngEncoder._();

  static const _signature = <int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
  ];

  /// [channels] 为 3（RGB）或 4（RGBA）。
  static Uint8List encodeRgb(
    Uint8List pixels, {
    required int width,
    required int height,
    required int channels,
  }) {
    assert(channels == 3 || channels == 4);
    final stride = width * channels;

    // 每个 scanline = 1 字节 filter type + 像素行。
    final raw = Uint8List((stride + 1) * height);
    for (var y = 0; y < height; y++) {
      final dstStart = y * (stride + 1);
      raw[dstStart] = 0; // filter: None
      final srcStart = y * stride;
      for (var i = 0; i < stride; i++) {
        final src = srcStart + i;
        if (src >= pixels.length) break;
        raw[dstStart + 1 + i] = pixels[src];
      }
    }

    final compressed = ZLibCodec(level: 6).encode(raw);

    final out = <int>[]
      ..addAll(_signature)
      ..addAll(_chunk('IHDR', _ihdr(width, height, channels)))
      ..addAll(_chunk('IDAT', compressed))
      ..addAll(_chunk('IEND', const []));
    return Uint8List.fromList(out);
  }

  static List<int> _ihdr(int width, int height, int channels) {
    final b = <int>[];
    void u32(int v) => b..add((v >> 24) & 0xFF)..add((v >> 16) & 0xFF)..add((v >> 8) & 0xFF)..add(v & 0xFF);
    u32(width);
    u32(height);
    b.add(8); // bit depth: 8-bit per channel
    b.add(channels == 4 ? 6 : 2); // color type: 6 = RGBA, 2 = RGB
    b..add(0)..add(0)..add(0); // compression / filter / interlace
    return b;
  }

  static List<int> _chunk(String type, List<int> data) {
    final b = <int>[];
    void u32(int v) => b..add((v >> 24) & 0xFF)..add((v >> 16) & 0xFF)..add((v >> 8) & 0xFF)..add(v & 0xFF);
    u32(data.length);
    final typeBytes = _ascii.encode(type);
    b..addAll(typeBytes)..addAll(data);
    final crcInput = [...typeBytes, ...data];
    u32(_crc32(crcInput));
    return b;
  }

  static int _crc32(List<int> data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (var k = 0; k < 8; k++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
