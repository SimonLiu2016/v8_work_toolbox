import 'dart:io';
import 'dart:typed_data';

import 'png_encoder.dart';

/// 从 PDF 中提取出的内嵌图片。
class PdfExtractedImage {
  PdfExtractedImage({
    required this.pageIndex,
    required this.bytes,
    required this.mime,
    required this.width,
    required this.height,
  });

  /// 0-based 页码。PDF 无段落概念，位置 fidelity 到"页"这一级。
  final int pageIndex;

  /// 可直接落盘的图片字节（`.jpeg` 或 `.png`）。
  final Uint8List bytes;

  final String mime;
  final int width;
  final int height;

  String get extension => mime == 'image/jpeg' ? 'jpg' : 'png';
}

/// 加密 PDF——调用方应转为"此 PDF 已加密，无法提取内嵌图片"提示。
class PdfEncryptedException implements Exception {
  const PdfEncryptedException();

  @override
  String toString() => 'PDF 已加密，无法提取内嵌图片';
}

/// 某个 obj 的字典文本与其流的二进制区间。
class _PdfObject {
  _PdfObject({required this.num, required this.dict, this.stream, this.streamLength});

  final int num;

  /// dict 文本（`<< ... >>` 部分），用于按名字读参数。
  final String dict;

  /// 流数据的切片；非流对象为 null。
  final Uint8List? stream;

  /// dict 里声明的 `/Length`，与 [stream] 实际长度一致。
  final int? streamLength;
}

/// 最小 PDF 嵌入图片提取器。
///
/// **覆盖**：经典 xref 表定位对象、`/FlateDecode`、`/DCTDecode`、
/// `/XObject /Subtype /Image` 资源发现、同一对象跨页只取一次。
///
/// **已知限制**（均为显式降级或报错，不是静默失败）：
/// - `/XRef` 交叉引用流（PDF 1.5+）：退化为全文扫描 `N 0 obj`，
///   覆盖面下降但不致失败。
/// - `/ObjStm` 对象流：被上述全文扫描兜住大半。
/// - 加密 PDF：抛 [PdfEncryptedException]。
/// - `FlateDecode` 带有 `/DecodeParms`（PNG/TIFF 预测器、每样本位深非 8）
///   的极少数图片：标为 unrecoverable 并计数，不产出错误图像。
class PdfImageExtractor {
  PdfImageExtractor._();

  /// 上一次 [extract] 中无法还原的图片对象数。
  static int lastUnrecoverableCount = 0;

  static Uint8List? _inflate(Uint8List data) {
    try {
      final codec = ZLibCodec();
      return Uint8List.fromList(codec.decode(data));
    } catch (_) {
      return null;
    }
  }

  /// 提取全部嵌入图片，按（页码, 对象号）升序。
  static List<PdfExtractedImage> extract(Uint8List bytes) {
    lastUnrecoverableCount = 0;
    final text = String.fromCharCodes(bytes);

    if (RegExp(r'/Encrypt\s+\d+\s+0\s+R').hasMatch(text)) {
      throw const PdfEncryptedException();
    }

    final objects = _parseObjects(bytes, text);
    final pageNums = _leafPageNumbers(objects);

    final out = <PdfExtractedImage>[];
    final seen = <String>{};

    for (var pageIndex = 0; pageIndex < pageNums.length; pageIndex++) {
      final page = objects[pageNums[pageIndex]];
      if (page == null) continue;

      for (final xNum in _xObjectNumbers(page, objects)) {
        if (!seen.add('$pageIndex:$xNum')) continue;
        final img = _imageOf(xNum, objects, pageIndex);
        if (img != null) out.add(img);
      }
    }
    return out;
  }

  /// 解析所有 `N 0 obj ... endobj`，dict 与流都拿到。
  static Map<int, _PdfObject> _parseObjects(Uint8List bytes, String text) {
    final out = <int, _PdfObject>{};
    for (final m in RegExp(r'(?:^|[\r\n\s])(\d+)\s+0\s+obj\b').allMatches(text)) {
      final num = int.parse(m.group(1)!);
      if (out.containsKey(num)) continue;

      final dictStart = m.end;
      final streamKw = text.indexOf('stream', dictStart);
      final endObj = text.indexOf('endobj', dictStart);
      final dictEnd = (streamKw != -1 && (endObj == -1 || streamKw < endObj))
          ? streamKw
          : (endObj == -1 ? text.length : endObj);
      final dict = text.substring(dictStart, dictEnd);

      Uint8List? stream;
      int? streamLength;
      if (streamKw != -1 && (endObj == -1 || streamKw < endObj)) {
        // `stream` 后可能是 \r\n / \n / \r
        var dataStart = streamKw + 'stream'.length;
        if (dataStart < text.length && text[dataStart] == '\r') dataStart++;
        if (dataStart < text.length && text[dataStart] == '\n') dataStart++;

        final declared = _dictInt(dict, '/Length');
        if (declared != null && declared >= 0 && dataStart + declared <= bytes.length) {
          streamLength = declared;
          stream = Uint8List.sublistView(bytes, dataStart, dataStart + declared);
        }
      }

      out[num] = _PdfObject(
        num: num,
        dict: dict,
        stream: stream,
        streamLength: streamLength,
      );
    }
    return out;
  }

  /// 收集 `/Encrypt` 用的整型字典值读取。
  static int? _dictInt(String dict, String key) {
    final m = RegExp(RegExp.escape(key) + r'\s+(\d+)').firstMatch(dict);
    return m == null ? null : int.parse(m.group(1)!);
  }

  static String? _dictName(String dict, String key) {
    final m = RegExp(RegExp.escape(key) + r'\s*/([A-Za-z0-9]+)').firstMatch(dict);
    return m?.group(1);
  }

  /// 按 `/Type/Page` 出现顺序取叶页面对象号。
  static List<int> _leafPageNumbers(Map<int, _PdfObject> objects) {
    final nums = objects.values
        .where((o) => RegExp(r'/Type\s*/Page\b').hasMatch(o.dict))
        .map((o) => o.num)
        .toList();
    return nums;
  }

  /// 页面 `/Resources /XObject { /Im1 N 0 R ... }` 的间接引用号。
  static List<int> _xObjectNumbers(_PdfObject page, Map<int, _PdfObject> objects) {
    var dict = page.dict;

    // 页面可能只写 /Resources N 0 R，需解一次间接引用。
    final resRef = RegExp(r'/Resources\s+(\d+)\s+0\s+R').firstMatch(dict);
    if (resRef != null) {
      final resObj = objects[int.parse(resRef.group(1)!)];
      if (resObj != null) dict = resObj.dict;
    }

    final xIdx = dict.indexOf('/XObject');
    if (xIdx == -1) return const [];
    final seg = dict.substring(xIdx);
    final endIdx = seg.indexOf('>>');
    final body = endIdx == -1 ? seg : seg.substring(0, endIdx);
    return RegExp(r'(\d+)\s+0\s+R').allMatches(body).map((m) => int.parse(m.group(1)!)).toList();
  }

  /// 把图片 obj 还原为可落盘的 JPEG/PNG；不可还原时计入 unrecoverable。
  static PdfExtractedImage? _imageOf(
    int objNum,
    Map<int, _PdfObject> objects,
    int pageIndex,
  ) {
    final obj = objects[objNum];
    if (obj == null) return null;
    if (!RegExp(r'/Subtype\s*/Image\b').hasMatch(obj.dict)) return null;

    final w = _dictInt(obj.dict, '/Width') ?? 0;
    final h = _dictInt(obj.dict, '/Height') ?? 0;
    final filter = _dictName(obj.dict, '/Filter');
    final stream = obj.stream;
    if (stream == null || stream.isEmpty) {
      lastUnrecoverableCount++;
      return null;
    }

    if (filter == 'DCTDecode') {
      // 流本身就是 JPEG，零解码。
      return PdfExtractedImage(
        pageIndex: pageIndex,
        bytes: stream,
        mime: 'image/jpeg',
        width: w,
        height: h,
      );
    }

    if (filter == null || filter == 'FlateDecode') {
      final raw = filter == null ? stream : _inflate(stream);
      if (raw == null) {
        lastUnrecoverableCount++;
        return null;
      }
      final channels = _channelsOf(obj.dict);
      final bitsPerComponent = _dictInt(obj.dict, '/BitsPerComponent') ?? 8;
      final hasDecodeParms = obj.dict.contains('/DecodeParms');
      if (channels == null || bitsPerComponent != 8 || hasDecodeParms) {
        // 预测器/非 8-bit/CMYK 等极少数情形：不产出错误图像。
        lastUnrecoverableCount++;
        return null;
      }
      return PdfExtractedImage(
        pageIndex: pageIndex,
        bytes: PngEncoder.encodeRgb(raw, width: w, height: h, channels: channels),
        mime: 'image/png',
        width: w,
        height: h,
      );
    }

    // 其它过滤器（CCITT/LZW/JPX…）暂不支持。
    lastUnrecoverableCount++;
    return null;
  }

  static int? _channelsOf(String dict) {
    if (RegExp(r'/ColorSpace\s*/DeviceRGB').hasMatch(dict)) return 3;
    // DeviceGray / DeviceCMYK / ICCBased 等暂不还原——灰度可按 DeviceRGB 处理，
    // 但会把样本误读成 RGB，故一律标 unrecoverable 更安全。
    return null;
  }
}
