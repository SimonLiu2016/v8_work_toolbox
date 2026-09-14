import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/services/totp_service.dart';

void main() {
  late TotpService totp;

  setUp(() {
    totp = TotpService();
  });

  group('RFC 6238 官方测试向量（SHA-1，8 位码）', () {
    // RFC 6238 Appendix B 测试密钥（ASCII "12345678901234567890"）
    const secretBytes = [
      0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30,
      0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30,
    ];
    late String secret;

    setUp(() {
      secret = TotpService.encodeBase32(secretBytes);
    });

    test('T=59s → 94287082', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '94287082');
    });

    test('T=1111111109s → 07081804', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(1111111109 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '07081804');
    });

    test('T=1111111111s → 14050471', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(1111111111 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '14050471');
    });

    test('T=1234567890s → 89005924', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(1234567890 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '89005924');
    });

    test('T=2000000000s → 69279037', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(2000000000 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '69279037');
    });

    test('T=20000000000s → 65353130', () {
      final code = totp.generateCode(
        secret,
        time: DateTime.fromMillisecondsSinceEpoch(20000000000 * 1000, isUtc: true),
        digits: 8,
      );
      expect(code, '65353130');
    });
  });

  group('Base32 编解码', () {
    test('编解码往返', () {
      final bytes = [0x48, 0x65, 0x6c, 0x6c, 0x6f]; // "Hello"
      final encoded = TotpService.encodeBase32(bytes);
      final decoded = TotpService.decodeBase32(encoded);
      expect(decoded, bytes);
    });

    test('容忍小写与无 padding', () {
      // "Hello" 标准 Base32 为 JBSWY3DP（无 padding）
      final decoded = TotpService.decodeBase32('jbswy3dp');
      expect(decoded, [0x48, 0x65, 0x6c, 0x6c, 0x6f]);
    });

    test('容忍空格', () {
      final decoded = TotpService.decodeBase32('JBSW Y3DP');
      expect(decoded, [0x48, 0x65, 0x6c, 0x6c, 0x6f]);
    });

    test('非法字符抛 FormatException', () {
      expect(() => TotpService.decodeBase32('ABC0'), throwsFormatException);
      expect(() => TotpService.decodeBase32('ABC1'), throwsFormatException);
    });

    test('空 secret 抛 FormatException', () {
      expect(() => TotpService.decodeBase32(''), throwsFormatException);
      expect(() => TotpService.decodeBase32('==='), throwsFormatException);
    });
  });

  group('剩余秒数与漂移校验', () {
    test('remainingSeconds 正确', () {
      // T=65s：65 % 30 = 5，剩余 25
      final remaining = totp.remainingSeconds(
        time: DateTime.fromMillisecondsSinceEpoch(65 * 1000, isUtc: true),
      );
      expect(remaining, 25);
    });

    test('verify 容忍 ±1 周期漂移', () {
      const secret = 'JBSWY3DPEHPK3PXP';
      final t = DateTime.fromMillisecondsSinceEpoch(1000 * 1000, isUtc: true);
      final current = totp.generateCode(secret, time: t);
      final prev = totp.generateCode(secret, time: t, periodOffset: -1);
      final next = totp.generateCode(secret, time: t, periodOffset: 1);

      expect(totp.verify(secret, current, time: t), isTrue);
      expect(totp.verify(secret, prev, time: t), isTrue);
      expect(totp.verify(secret, next, time: t), isTrue);
      expect(totp.verify(secret, '000000', time: t), isFalse);
    });
  });

  group('otpauth URI 解析', () {
    test('标准 URI 解析 secret/issuer/account', () {
      final data = TotpService.parseOtpauthUri(
        'otpauth://totp/GitHub:simon@example.com?secret=JBSWY3DPEHPK3PXP&issuer=GitHub',
      );
      expect(data, isNotNull);
      expect(data!.secret, 'JBSWY3DPEHPK3PXP');
      expect(data.issuer, 'GitHub');
      expect(data.account, 'simon@example.com');
      expect(data.digits, 6);
      expect(data.period, 30);
    });

    test('无 issuer 参数时从 label 提取', () {
      final data = TotpService.parseOtpauthUri(
        'otpauth://totp/AWS:deploy?secret=ABC234&issuer=',
      );
      expect(data, isNotNull);
      expect(data!.account, 'deploy');
    });

    test('digits 与 period 参数', () {
      final data = TotpService.parseOtpauthUri(
        'otpauth://totp/x?secret=ABC234&digits=8&period=60',
      );
      expect(data!.digits, 8);
      expect(data.period, 60);
    });

    test('非 totp URI 返回 null', () {
      expect(TotpService.parseOtpauthUri('otpauth://hotp/x?secret=ABC'), isNull);
      expect(TotpService.parseOtpauthUri('https://example.com'), isNull);
    });

    test('缺 secret 返回 null', () {
      expect(
        TotpService.parseOtpauthUri('otpauth://totp/x?issuer=Y'),
        isNull,
      );
    });

    test('secret 中空格被清除并大写化', () {
      final data = TotpService.parseOtpauthUri(
        'otpauth://totp/x?secret=jbsw%20y3dp',
      );
      expect(data!.secret, 'JBSWY3DP');
    });
  });
}
