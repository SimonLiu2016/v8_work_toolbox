import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

/// 全拒绝的 Keychain 桥（模拟 adhoc 未签名应用：读写均被拒）
class _AlwaysDeniedBridge implements KeychainBridge {
  @override
  Future<String?> read({required String service, required String account}) async {
    throw StateError('SecItemCopyMatching rejected (-34018)');
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    throw StateError('SecItemAdd rejected (-34018)');
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    throw StateError('SecItemDelete rejected');
  }
}

/// 全拒绝的文件桥（模拟极端场景）
class _AlwaysDeniedFileBridge implements DekFileBridge {
  @override
  Future<String?> read() async => throw StateError('file denied');

  @override
  Future<void> write(String value) async => throw StateError('file denied');

  @override
  Future<void> delete() async => throw StateError('file denied');

  @override
  Future<int?> permissions() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('启动集成：Keychain 全拒（adhoc 未签名环境）', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('v8_startup_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Keychain 拒绝 + 文件可用 → 应用正常初始化，写入读回一致', () async {
      // 模拟真实场景：Keychain 写被拒，文件兜底可用（真实 DefaultDekFileBridge）
      KeychainService.instance.setKekManagerForTesting(
        KekManager(
          bridge: _AlwaysDeniedBridge(),
          fileBridge: DefaultDekFileBridge(customRootDir: tempDir),
        ),
      );
      final service = KeychainService.instance;
      await service.init(customRootDir: tempDir);

      // 正常写入读回（不抛异常）
      await service.writeSecret('startup_key', 'startup-secret');
      expect(await service.readSecret('startup_key'), 'startup-secret');

      // 模拟重启
      await service.init(customRootDir: tempDir);
      expect(await service.readSecret('startup_key'), 'startup-secret');

      // .dek 文件已生成且 0600
      final dekFile = File('${tempDir.path}/.dek');
      expect(await dekFile.exists(), isTrue);
      final perms = await dekFile.stat();
      expect(perms.mode & 0x1FF, 0x180);
    });

    test('Keychain 与文件均拒绝 → 抛异常（不静默降级）', () async {
      KeychainService.instance.setKekManagerForTesting(
        KekManager(
          bridge: _AlwaysDeniedBridge(),
          fileBridge: _AlwaysDeniedFileBridge(),
        ),
      );
      final service = KeychainService.instance;
      await service.init(customRootDir: tempDir);

      await expectLater(
        service.writeSecret('k', 'v'),
        throwsA(isA<DekUnavailableException>()),
      );
    });

    test('PrivacySecurityService 风格的读取不再崩溃启动链', () async {
      KeychainService.instance.setKekManagerForTesting(
        KekManager(
          bridge: _AlwaysDeniedBridge(),
          fileBridge: DefaultDekFileBridge(customRootDir: tempDir),
        ),
      );
      final service = KeychainService.instance;
      await service.init(customRootDir: tempDir);

      // 模拟 PrivacySecurityService.init 的行为：读不存在的 key 不崩溃
      final value = await service.readSecret('nonexistent_auto_lock');
      expect(value, isNull);
    });
  });
}
