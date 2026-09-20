import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/password/crypto/vault_cipher.dart';

/// 全拒绝的 Keychain 桥（adhoc 未签名环境：读写均被拒，走文件兜底）
class _DeniedBridge implements KeychainBridge {
  @override
  Future<String?> read({required String service, required String account}) async =>
      throw StateError('rejected');

  @override
  Future<void> write(
          {required String service, required String account, required String value}) async =>
      throw StateError('rejected');

  @override
  Future<void> delete({required String service, required String account}) async =>
      throw StateError('rejected');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  KeychainService freshService(Directory dir) {
    final s = KeychainService.instance;
    s.setKekManagerForTesting(KekManager(
      bridge: _DeniedBridge(),
      fileBridge: DefaultDekFileBridge(customRootDir: dir),
    ));
    return s;
  }

  group('VaultCipher 失配/损坏分流', () {
    final dek = Uint8List.fromList(List<int>.generate(32, (i) => i));

    test('篡改 tag → isAuthFailure=true 且 isIntegrityError=false', () async {
      final cipher = VaultCipher();
      final sealed = await cipher.encrypt(dek, '{"k":"v"}');
      // 篡改最后一个字节（tag 区）
      sealed[sealed.length - 1] ^= 0xFF;
      expect(
        () => cipher.decrypt(dek, sealed),
        throwsA(isA<VaultCipherException>()
            .having((e) => e.isAuthFailure, 'isAuthFailure', isTrue)
            .having((e) => e.isIntegrityError, 'isIntegrityError', isFalse)),
      );
    });

    test('截断密文 → isIntegrityError=true 且 isAuthFailure=false', () async {
      final cipher = VaultCipher();
      expect(
        () => cipher.decrypt(dek, Uint8List.fromList([1, 2, 3])),
        throwsA(isA<VaultCipherException>()
            .having((e) => e.isIntegrityError, 'isIntegrityError', isTrue)
            .having((e) => e.isAuthFailure, 'isAuthFailure', isFalse)),
      );
    });
  });

  group('KeychainService 失配自愈', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8_mismatch_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('匹配路径零变化：写入读回一致，无重建信号', () async {
      final service = freshService(tempDir);
      await service.init(customRootDir: tempDir);

      await service.writeSecret('api_key', 'sk-secret');
      expect(await service.readSecret('api_key'), 'sk-secret');
      expect(service.consumeRebuildInfo(), isNull);

      // 模拟重启
      await service.init(customRootDir: tempDir);
      expect(await service.readSecret('api_key'), 'sk-secret');
      expect(service.consumeRebuildInfo(), isNull);
    });

    test('DEK 失配 → 备份残件 + 重建空库 + 一次性信号 + 立即可写', () async {
      // 1. 用 DEK-A 写入密钥
      final serviceA = freshService(tempDir);
      await serviceA.init(customRootDir: tempDir);
      await serviceA.writeSecret('api_key', 'sk-old');
      expect(await tempDir.list().any((f) => f.path.endsWith('.dek')), isTrue);

      // 2. 模拟 DEK 被重建（删掉 .dek，下次启动生成 DEK-B）
      await File('${tempDir.path}/.dek').delete();

      // 3. 模拟重启：新实例读取 → 失配自愈
      final serviceB = freshService(tempDir);
      await serviceB.init(customRootDir: tempDir);
      final value = await serviceB.readSecret('api_key');

      // 旧密钥不可恢复
      expect(value, isNull);

      // 残件备份存在（mismatch 文件）
      final backups = await tempDir
          .list()
          .where((f) => f.path.contains('.secrets.bin.mismatch-'))
          .toList();
      expect(backups.length, 1);

      // 一次性信号：含备份路径，二次 consume 为空
      final info = serviceB.consumeRebuildInfo();
      expect(info, isNotNull);
      expect(info!.backupPath, contains('.secrets.bin.mismatch-'));
      expect(serviceB.consumeRebuildInfo(), isNull);

      // 立即可写：新 DEK 加密，写读一致
      await serviceB.writeSecret('api_key', 'sk-new');
      expect(await serviceB.readSecret('api_key'), 'sk-new');

      // 再次重启：新库与新 DEK 匹配，不再触发自愈
      final serviceC = freshService(tempDir);
      await serviceC.init(customRootDir: tempDir);
      expect(await serviceC.readSecret('api_key'), 'sk-new');
      expect(serviceC.consumeRebuildInfo(), isNull);
    });

    test('密文布局损坏 → 上抛异常，不备份不重建', () async {
      // 写入正常密钥后，把密文替换为布局损坏的字节
      final service = freshService(tempDir);
      await service.init(customRootDir: tempDir);
      await service.writeSecret('k', 'v');

      final binPath = '${tempDir.path}/.secrets.bin';
      await File(binPath).writeAsBytes([1, 2, 3, 4, 5]); // 布局损坏（长度不足）

      final service2 = freshService(tempDir);
      await service2.init(customRootDir: tempDir);

      expect(
        () => service2.readSecret('k'),
        throwsA(isA<VaultCipherException>()
            .having((e) => e.isIntegrityError, 'isIntegrityError', isTrue)),
      );

      // 无 mismatch 备份，原损坏文件保留
      final backups = await tempDir
          .list()
          .where((f) => f.path.contains('.secrets.bin.mismatch-'))
          .toList();
      expect(backups, isEmpty);
      expect(await File(binPath).length(), 5);
    });
  });
}
