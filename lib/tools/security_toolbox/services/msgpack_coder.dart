import 'dart:convert';
import 'dart:typed_data';

/// 轻量级纯 Dart MessagePack 编解码器
/// 支持类型：
/// - null
/// - bool (true, false)
/// - int (positive fixint, negative fixint, uint8/16/32/64, int8/16/32/64)
/// - String (fixstr, str8, str16, str32) - utf8 编码
/// - Uint8List (bin8, bin16, bin32)
/// - List (fixarray, array16, array32)
/// - Map (fixmap, map16, map32)
class MsgPack {
  const MsgPack._();

  /// 序列化 Dart 对象为 MessagePack 二进制字节流
  static Uint8List serialize(dynamic value) {
    final builder = BytesBuilder(copy: false);
    _serializeValue(value, builder);
    return builder.takeBytes();
  }

  /// 从 MessagePack 二进制字节流反序列化为 Dart 对象
  /// [normalizeStrings] 为 true 时，会自动将 Uint8List 二进制数据转为 UTF-8 字符串（适应 MSF/Ruby 默认按 raw bytes 发送字符串）
  static dynamic deserialize(Uint8List bytes, {bool normalizeStrings = true}) {
    if (bytes.isEmpty) return null;
    final reader = _ByteReader(bytes);
    final value = _deserializeValue(reader);
    return normalizeStrings ? _normalize(value) : value;
  }

  static dynamic _normalize(dynamic value) {
    if (value is Uint8List) {
      try {
        return utf8.decode(value);
      } catch (_) {
        return value;
      }
    } else if (value is Map) {
      final newMap = <String, dynamic>{};
      for (final entry in value.entries) {
        final keyStr = entry.key is Uint8List
            ? utf8.decode(entry.key as Uint8List, allowMalformed: true)
            : entry.key.toString();
        newMap[keyStr] = _normalize(entry.value);
      }
      return newMap;
    } else if (value is List) {
      return value.map(_normalize).toList();
    }
    return value;
  }

  static void _serializeValue(dynamic value, BytesBuilder b) {
    if (value == null) {
      b.addByte(0xc0);
    } else if (value is bool) {
      b.addByte(value ? 0xc3 : 0xc2);
    } else if (value is int) {
      _serializeInt(value, b);
    } else if (value is String) {
      _serializeString(value, b);
    } else if (value is Uint8List) {
      _serializeBinary(value, b);
    } else if (value is List) {
      _serializeList(value, b);
    } else if (value is Map) {
      _serializeMap(value, b);
    } else {
      // 默认尝试转成 String 序列化
      _serializeString(value.toString(), b);
    }
  }

  static void _serializeInt(int n, BytesBuilder b) {
    if (n >= 0) {
      if (n <= 0x7f) {
        // positive fixint: 0x00 - 0x7f
        b.addByte(n);
      } else if (n <= 0xff) {
        // uint 8: 0xcc
        b.addByte(0xcc);
        b.addByte(n);
      } else if (n <= 0xffff) {
        // uint 16: 0xcd
        b.addByte(0xcd);
        b.addByte((n >> 8) & 0xff);
        b.addByte(n & 0xff);
      } else if (n <= 0xffffffff) {
        // uint 32: 0xce
        b.addByte(0xce);
        final bd = ByteData(4)..setUint32(0, n, Endian.big);
        b.add(bd.buffer.asUint8List());
      } else {
        // uint 64: 0xcf
        b.addByte(0xcf);
        final bd = ByteData(8)..setUint64(0, n, Endian.big);
        b.add(bd.buffer.asUint8List());
      }
    } else {
      if (n >= -32) {
        // negative fixint: 0xe0 - 0xff (-32 .. -1)
        b.addByte(n & 0xff);
      } else if (n >= -128) {
        // int 8: 0xd0
        b.addByte(0xd0);
        b.addByte(n & 0xff);
      } else if (n >= -32768) {
        // int 16: 0xd1
        b.addByte(0xd1);
        final bd = ByteData(2)..setInt16(0, n, Endian.big);
        b.add(bd.buffer.asUint8List());
      } else if (n >= -2147483648) {
        // int 32: 0xd2
        b.addByte(0xd2);
        final bd = ByteData(4)..setInt32(0, n, Endian.big);
        b.add(bd.buffer.asUint8List());
      } else {
        // int 64: 0xd3
        b.addByte(0xd3);
        final bd = ByteData(8)..setInt64(0, n, Endian.big);
        b.add(bd.buffer.asUint8List());
      }
    }
  }

  static void _serializeString(String s, BytesBuilder b) {
    final bytes = utf8.encode(s);
    final len = bytes.length;
    if (len <= 31) {
      // fixstr: 0xa0 | len
      b.addByte(0xa0 | len);
    } else if (len <= 0xff) {
      // str 8: 0xd9
      b.addByte(0xd9);
      b.addByte(len);
    } else if (len <= 0xffff) {
      // str 16: 0xda
      b.addByte(0xda);
      b.addByte((len >> 8) & 0xff);
      b.addByte(len & 0xff);
    } else {
      // str 32: 0xdb
      b.addByte(0xdb);
      final bd = ByteData(4)..setUint32(0, len, Endian.big);
      b.add(bd.buffer.asUint8List());
    }
    b.add(bytes);
  }

  static void _serializeBinary(Uint8List bytes, BytesBuilder b) {
    final len = bytes.length;
    if (len <= 0xff) {
      // bin 8: 0xc4
      b.addByte(0xc4);
      b.addByte(len);
    } else if (len <= 0xffff) {
      // bin 16: 0xc5
      b.addByte(0xc5);
      b.addByte((len >> 8) & 0xff);
      b.addByte(len & 0xff);
    } else {
      // bin 32: 0xc6
      b.addByte(0xc6);
      final bd = ByteData(4)..setUint32(0, len, Endian.big);
      b.add(bd.buffer.asUint8List());
    }
    b.add(bytes);
  }

  static void _serializeList(List list, BytesBuilder b) {
    final len = list.length;
    if (len <= 15) {
      // fixarray: 0x90 | len
      b.addByte(0x90 | len);
    } else if (len <= 0xffff) {
      // array 16: 0xdc
      b.addByte(0xdc);
      b.addByte((len >> 8) & 0xff);
      b.addByte(len & 0xff);
    } else {
      // array 32: 0xdd
      b.addByte(0xdd);
      final bd = ByteData(4)..setUint32(0, len, Endian.big);
      b.add(bd.buffer.asUint8List());
    }
    for (final item in list) {
      _serializeValue(item, b);
    }
  }

  static void _serializeMap(Map map, BytesBuilder b) {
    final len = map.length;
    if (len <= 15) {
      // fixmap: 0x80 | len
      b.addByte(0x80 | len);
    } else if (len <= 0xffff) {
      // map 16: 0xde
      b.addByte(0xde);
      b.addByte((len >> 8) & 0xff);
      b.addByte(len & 0xff);
    } else {
      // map 32: 0xdf
      b.addByte(0xdf);
      final bd = ByteData(4)..setUint32(0, len, Endian.big);
      b.add(bd.buffer.asUint8List());
    }
    for (final entry in map.entries) {
      _serializeValue(entry.key, b);
      _serializeValue(entry.value, b);
    }
  }

  static dynamic _deserializeValue(_ByteReader r) {
    if (r.remaining == 0) return null;
    final b = r.readUint8();

    // positive fixint
    if ((b & 0x80) == 0) {
      return b;
    }
    // fixmap
    if ((b & 0xf0) == 0x80) {
      return _readMap(r, b & 0x0f);
    }
    // fixarray
    if ((b & 0xf0) == 0x90) {
      return _readList(r, b & 0x0f);
    }
    // fixstr
    if ((b & 0xe0) == 0xa0) {
      return _readString(r, b & 0x1f);
    }
    // negative fixint (0xe0 - 0xff) -> -32 .. -1
    if ((b & 0xe0) == 0xe0) {
      return (b & 0xff) - 256;
    }

    switch (b) {
      case 0xc0: // nil
        return null;
      case 0xc2: // false
        return false;
      case 0xc3: // true
        return true;
      case 0xc4: // bin 8
        final len = r.readUint8();
        return r.readBytes(len);
      case 0xc5: // bin 16
        final len = r.readUint16();
        return r.readBytes(len);
      case 0xc6: // bin 32
        final len = r.readUint32();
        return r.readBytes(len);
      case 0xcc: // uint 8
        return r.readUint8();
      case 0xcd: // uint 16
        return r.readUint16();
      case 0xce: // uint 32
        return r.readUint32();
      case 0xcf: // uint 64
        return r.readUint64();
      case 0xd0: // int 8
        return r.readInt8();
      case 0xd1: // int 16
        return r.readInt16();
      case 0xd2: // int 32
        return r.readInt32();
      case 0xd3: // int 64
        return r.readInt64();
      case 0xd9: // str 8
        final len = r.readUint8();
        return _readString(r, len);
      case 0xda: // str 16
        final len = r.readUint16();
        return _readString(r, len);
      case 0xdb: // str 32
        final len = r.readUint32();
        return _readString(r, len);
      case 0xdc: // array 16
        final len = r.readUint16();
        return _readList(r, len);
      case 0xdd: // array 32
        final len = r.readUint32();
        return _readList(r, len);
      case 0xde: // map 16
        final len = r.readUint16();
        return _readMap(r, len);
      case 0xdf: // map 32
        final len = r.readUint32();
        return _readMap(r, len);
      default:
        // 未知或扩展类型，跳过或返回 null
        return null;
    }
  }

  static String _readString(_ByteReader r, int len) {
    if (len == 0) return '';
    final bytes = r.readBytes(len);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static List<dynamic> _readList(_ByteReader r, int len) {
    final list = <dynamic>[];
    for (int i = 0; i < len; i++) {
      list.add(_deserializeValue(r));
    }
    return list;
  }

  static Map<dynamic, dynamic> _readMap(_ByteReader r, int len) {
    final map = <dynamic, dynamic>{};
    for (int i = 0; i < len; i++) {
      final key = _deserializeValue(r);
      final val = _deserializeValue(r);
      if (key != null) {
        map[key] = val;
      }
    }
    return map;
  }
}

class _ByteReader {
  final Uint8List _data;
  final ByteData _bd;
  int _offset = 0;

  _ByteReader(Uint8List data)
      : _data = data,
        _bd = ByteData.sublistView(data);

  int get remaining => _data.length - _offset;

  int readUint8() {
    final v = _bd.getUint8(_offset);
    _offset += 1;
    return v;
  }

  int readInt8() {
    final v = _bd.getInt8(_offset);
    _offset += 1;
    return v;
  }

  int readUint16() {
    final v = _bd.getUint16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  int readInt16() {
    final v = _bd.getInt16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  int readUint32() {
    final v = _bd.getUint32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  int readInt32() {
    final v = _bd.getInt32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  int readUint64() {
    final v = _bd.getUint64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  int readInt64() {
    final v = _bd.getInt64(_offset, Endian.big);
    _offset += 8;
    return v;
  }

  Uint8List readBytes(int len) {
    if (len > remaining) {
      len = remaining;
    }
    final sub = Uint8List.view(_data.buffer, _data.offsetInBytes + _offset, len);
    _offset += len;
    return sub;
  }
}
