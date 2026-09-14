import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/crypto/vault_cipher.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List makeDek() {
    final rnd = DateTime.now().microsecondsSinceEpoch;
    return Uint8List.fromList(
      List<int>.generate(32, (i) => (rnd + i * 7) % 256),
    );
  }

  group('VaultCipher AES-256-GCM', () {
    test('加解密往返', () async {
      final cipher = VaultCipher();
      final dek = makeDek();
      final plaintext = '{"items":[{"title":"GitHub","password":"s3cret!"}]}';

      final sealed = await cipher.encrypt(dek, plaintext);
      final decrypted = await cipher.decrypt(dek, sealed);

      expect(decrypted, plaintext);
    });

    test('同明文两次加密产生不同密文（nonce 不重复）', () async {
      final cipher = VaultCipher();
      final dek = makeDek();
      final plaintext = 'same plaintext';

      final a = await cipher.encrypt(dek, plaintext);
      final b = await cipher.encrypt(dek, plaintext);

      expect(a, isNot(equals(b)));
      // nonce 前 12 字节应不同
      final nonceA = a.sublist(0, 12);
      final nonceB = b.sublist(0, 12);
      expect(nonceA, isNot(equals(nonceB)));
    });

    test('篡改密文抛完整性错误', () async {
      final cipher = VaultCipher();
      final dek = makeDek();
      final plaintext = 'integrity check';

      final sealed = await cipher.encrypt(dek, plaintext);
      sealed[sealed.length - 1] ^= 0xFF; // 翻转最后一字节（tag 区域）

      expect(
        () => cipher.decrypt(dek, sealed),
        throwsA(isA<VaultCipherException>().having(
          (e) => e.isIntegrityError,
          'isIntegrityError',
          isTrue,
        )),
      );
    });

    test('AAD 不匹配拒绝解密', () async {
      final cipher = VaultCipher();
      final dek = makeDek();
      final plaintext = 'aad binding test';

      final sealed = await cipher.encrypt(dek, plaintext, aad: 'version-1');
      expect(
        () => cipher.decrypt(dek, sealed, aad: 'version-2'),
        throwsA(isA<VaultCipherException>()),
      );
      // 正确 AAD 仍可解
      final ok = await cipher.decrypt(dek, sealed, aad: 'version-1');
      expect(ok, plaintext);
    });

    test('错误密钥拒绝解密', () async {
      final cipher = VaultCipher();
      final dek1 = makeDek();
      final dek2 = makeDek();
      final plaintext = 'wrong key test';

      final sealed = await cipher.encrypt(dek1, plaintext);
      expect(
        () => cipher.decrypt(dek2, sealed),
        throwsA(isA<VaultCipherException>()),
      );
    });

    test('密文长度不足抛布局错误', () async {
      final cipher = VaultCipher();
      final dek = makeDek();
      expect(
        () => cipher.decrypt(dek, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<VaultCipherException>().having(
          (e) => e.isIntegrityError,
          'isIntegrityError',
          isTrue,
        )),
      );
    });
  });

  group('KekManager base64url', () {
    test('无 padding 编解码往返', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (i) => i * 8 % 256),
      );
      final encoded = base64UrlNoPad(bytes);
      expect(encoded.contains('='), isFalse);
      expect(encoded.contains('+'), isFalse);
      expect(encoded.contains('/'), isFalse);
      final decoded = base64UrlDecodeNoPad(encoded);
      expect(decoded, equals(bytes));
    });

    test('非法字符抛 FormatException', () {
      expect(
        () => base64UrlDecodeNoPad('ab@cd'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('KekManager DEK 生命周期', () {
    test('首次生成 DEK 并持久化到 Keychain 桥', () async {
      final store = <String, String>{};
      final bridge = _FakeBridge(store);
      final manager = KekManager(bridge: bridge);

      final dek = await manager.getOrCreateDek();

      expect(dek.length, 32);
      expect(store['dek'], isNotNull);
      expect(store['dek'], startsWith('v8dek1:'));
      // 第二次读取应返回同一 DEK（来自持久化，而非重新生成）
      final again = await KekManager(bridge: _FakeBridge(store)).getOrCreateDek();
      expect(again, equals(dek));
    });

    test('DEK 缺失时 getDek 抛异常且文案含恢复路径', () async {
      final manager = KekManager(bridge: _FakeBridge({}));
      expect(
        () => manager.getDek(),
        throwsA(isA<DekUnavailableException>().having(
          (e) => e.message,
          'message',
          contains('备份恢复'),
        )),
      );
    });

    test('损坏的 DEK 抛异常', () async {
      final store = {'dek': 'v8dek1:garbage!!'};
      final manager = KekManager(bridge: _FakeBridge(store));
      expect(
        () => manager.getDek(),
        throwsA(isA<DekUnavailableException>()),
      );
    });

    test('importDek 接受 32 字节并写回', () async {
      final store = <String, String>{};
      final bridge = _FakeBridge(store);
      final manager = KekManager(bridge: bridge);
      final dek = Uint8List.fromList(List<int>.generate(32, (i) => i));

      await manager.importDek(dek);

      expect(store['dek'], startsWith('v8dek1:'));
      final readBack = await KekManager(bridge: _FakeBridge(store)).getDek();
      expect(readBack, equals(dek));
    });

    test('importDek 拒绝非 32 字节', () async {
      final manager = KekManager(bridge: _FakeBridge({}));
      expect(
        () => manager.importDek(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('lock 清空内存缓存但不删除 Keychain 数据', () async {
      final store = <String, String>{};
      final bridge = _FakeBridge(store);
      final manager = KekManager(bridge: bridge);

      await manager.getOrCreateDek();
      expect(manager.hasCachedDek, isTrue);

      manager.lock();
      expect(manager.hasCachedDek, isFalse);
      expect(store['dek'], isNotNull); // Keychain 数据仍在

      // 再次获取应从 Keychain 读回同一 DEK
      final dek = await manager.getOrCreateDek();
      expect(dek.length, 32);
    });
  });
}

class _FakeBridge implements KeychainBridge {
  final Map<String, String> store;
  _FakeBridge(this.store);

  @override
  Future<String?> read({required String service, required String account}) async {
    return store[account];
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    store[account] = value;
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    store.remove(account);
  }
}
