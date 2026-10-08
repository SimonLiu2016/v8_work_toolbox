import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/security_toolbox/services/msgpack_coder.dart';

void main() {
  group('MsgPack Coder Tests', () {
    test('encode and decode primitives', () {
      expect(MsgPack.deserialize(MsgPack.serialize(null)), isNull);
      expect(MsgPack.deserialize(MsgPack.serialize(true)), isTrue);
      expect(MsgPack.deserialize(MsgPack.serialize(false)), isFalse);
      expect(MsgPack.deserialize(MsgPack.serialize(0)), equals(0));
      expect(MsgPack.deserialize(MsgPack.serialize(127)), equals(127));
      expect(MsgPack.deserialize(MsgPack.serialize(255)), equals(255));
      expect(MsgPack.deserialize(MsgPack.serialize(65535)), equals(65535));
      expect(MsgPack.deserialize(MsgPack.serialize(-1)), equals(-1));
      expect(MsgPack.deserialize(MsgPack.serialize(-32)), equals(-32));
      expect(MsgPack.deserialize(MsgPack.serialize(-128)), equals(-128));
      expect(MsgPack.deserialize(MsgPack.serialize(-32768)), equals(-32768));
    });

    test('encode and decode strings and binary', () {
      expect(MsgPack.deserialize(MsgPack.serialize('')), equals(''));
      expect(MsgPack.deserialize(MsgPack.serialize('hello')), equals('hello'));
      const longStr = 'Metasploit RPC - 安全渗透自动化测试工具链 - 1234567890';
      expect(MsgPack.deserialize(MsgPack.serialize(longStr)), equals(longStr));

      final bin = Uint8List.fromList([1, 2, 3, 4, 5, 255]);
      final decodedBin = MsgPack.deserialize(MsgPack.serialize(bin)) as Uint8List;
      expect(decodedBin, equals(bin));
    });

    test('encode and decode array and map (MSGRPC patterns)', () {
      final reqArray = ['auth.login', 'msf', 'secret123'];
      final decodedReq = MsgPack.deserialize(MsgPack.serialize(reqArray)) as List;
      expect(decodedReq, equals(reqArray));

      final respMap = {
        'result': 'success',
        'token': 'TEMP123456789',
      };
      final decodedResp = MsgPack.deserialize(MsgPack.serialize(respMap)) as Map;
      expect(decodedResp['result'], equals('success'));
      expect(decodedResp['token'], equals('TEMP123456789'));
    });

    test('nested structure', () {
      final nested = {
        'method': 'module.execute',
        'params': ['exploit', 'unix/ftp/vsftpd_234_backdoor', {'RHOSTS': '192.168.1.1', 'RPORT': 21}],
        'id': 1
      };
      final decoded = MsgPack.deserialize(MsgPack.serialize(nested)) as Map;
      expect(decoded['method'], equals('module.execute'));
      expect((decoded['params'] as List)[1], equals('unix/ftp/vsftpd_234_backdoor'));
      expect(((decoded['params'] as List)[2] as Map)['RHOSTS'], equals('192.168.1.1'));
    });
  });
}
