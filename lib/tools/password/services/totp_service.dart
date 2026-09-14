import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// TOTP 服务（RFC 6238）
///
/// - HMAC-SHA1，6 位码，30 秒周期
/// - Base32 解码容忍无 padding / 小写（RFC 4648 字母表）
/// - ±1 周期时钟漂移容忍
/// - otpauth:// URI 解析
class TotpService {
  static const int defaultDigits = 6;
  static const int defaultPeriod = 30;

  /// 计算指定时间戳的 TOTP 码
  String generateCode(
    String base32Secret, {
    DateTime? time,
    int digits = defaultDigits,
    int period = defaultPeriod,
    int periodOffset = 0,
  }) {
    final key = decodeBase32(base32Secret);
    final now = time ?? DateTime.now();
    final counter =
        (now.millisecondsSinceEpoch ~/ 1000) ~/ period + periodOffset;
    return _hotp(key, counter, digits);
  }

  /// 当前周期剩余秒数
  int remainingSeconds({DateTime? time, int period = defaultPeriod}) {
    final now = time ?? DateTime.now();
    final seconds = now.millisecondsSinceEpoch ~/ 1000;
    return period - (seconds % period);
  }

  /// 校验用户输入码（容忍 ±1 周期漂移）
  bool verify(
    String base32Secret,
    String code, {
    DateTime? time,
    int digits = defaultDigits,
    int period = defaultPeriod,
  }) {
    final normalized = code.replaceAll(' ', '');
    for (final offset in [-1, 0, 1]) {
      final expected = generateCode(
        base32Secret,
        time: time,
        digits: digits,
        period: period,
        periodOffset: offset,
      );
      if (expected == normalized) return true;
    }
    return false;
  }

  /// 解析 otpauth://totp/... URI
  /// 返回 null 表示无法解析；忽略不支持的参数
  static TotpUriData? parseOtpauthUri(String uri) {
    if (!uri.startsWith('otpauth://totp/')) return null;
    try {
      final parsed = Uri.parse(uri);
      final label = parsed.path.startsWith('/')
          ? parsed.path.substring(1)
          : parsed.path;
      final params = parsed.queryParameters;
      final secret = params['secret'];
      if (secret == null || secret.isEmpty) return null;

      String issuer = params['issuer'] ?? '';
      String account = '';
      // label 形如 "Issuer:account" 或 "account"
      final decodedLabel = Uri.decodeComponent(label);
      if (decodedLabel.contains(':')) {
        final parts = decodedLabel.split(':');
        if (issuer.isEmpty) issuer = parts.first;
        account = parts.sublist(1).join(':');
      } else {
        account = decodedLabel;
      }

      return TotpUriData(
        secret: secret.replaceAll(' ', '').toUpperCase(),
        issuer: issuer,
        account: account,
        digits: int.tryParse(params['digits'] ?? '') ?? defaultDigits,
        period: int.tryParse(params['period'] ?? '') ?? defaultPeriod,
      );
    } catch (_) {
      return null;
    }
  }

  /// Base32 解码（RFC 4648，容忍小写、无 padding、空格）
  static Uint8List decodeBase32(String input) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final clean = input
        .toUpperCase()
        .replaceAll(' ', '')
        .replaceAll('=', '');
    if (clean.isEmpty) {
      throw FormatException('Base32 secret 为空');
    }

    final out = <int>[];
    var buffer = 0;
    var bits = 0;
    for (final ch in clean.split('')) {
      final idx = alphabet.indexOf(ch);
      if (idx < 0) {
        throw FormatException('非法 Base32 字符: $ch');
      }
      buffer = (buffer << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }

  /// Base32 编码（无 padding；供测试与显示）
  static String encodeBase32(List<int> bytes) {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final b in bytes) {
      buffer = (buffer << 8) | (b & 0xff);
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(alphabet[(buffer >> bits) & 0x1f]);
      }
    }
    if (bits > 0) {
      out.write(alphabet[(buffer << (5 - bits)) & 0x1f]);
    }
    return out.toString();
  }

  String _hotp(Uint8List key, int counter, int digits) {
    final counterBytes = ByteData(8)..setUint64(0, counter);
    final hmac = Hmac(sha1, key);
    final digest = hmac.convert(counterBytes.buffer.asUint8List());
    final bytes = digest.bytes;

    final offset = bytes[bytes.length - 1] & 0x0f;
    final binary = ((bytes[offset] & 0x7f) << 24) |
        ((bytes[offset + 1] & 0xff) << 16) |
        ((bytes[offset + 2] & 0xff) << 8) |
        (bytes[offset + 3] & 0xff);

    final mod = _pow10(digits);
    final otp = binary % mod;
    return otp.toString().padLeft(digits, '0');
  }

  int _pow10(int n) {
    var result = 1;
    for (var i = 0; i < n; i++) {
      result *= 10;
    }
    return result;
  }
}

class TotpUriData {
  final String secret;
  final String issuer;
  final String account;
  final int digits;
  final int period;

  const TotpUriData({
    required this.secret,
    required this.issuer,
    required this.account,
    required this.digits,
    required this.period,
  });
}
