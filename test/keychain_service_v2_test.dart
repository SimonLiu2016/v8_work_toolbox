import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

/// 共享内存桥（跨 KeychainService 实例持久，模拟 Keychain）
class _SharedMemoryBridge implements KeychainBridge {
  final Map<String, String> store;

  _SharedMemoryBridge(this.store);

  @override
  Future<String?> read({required String service, required String account}) async {
    return store['$service/$account'];
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    store['$service/$account'] = value;
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    store.remove('$service/$account');
  }
}

class _AlwaysFailBridge implements KeychainBridge {
  @override
  Future<String?> read({required String service, required String account}) async {
    throw StateError('keychain unavailable');
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    throw StateError('keychain unavailable');
  }

  @override
  Future<void> delete({required String service, required String account}) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Map<String, String> keychainStore;

  KeychainService freshService() {
    final service = KeychainService.instance;
    service.setKekManagerForTesting(
      KekManager(bridge: _SharedMemoryBridge(keychainStore)),
    );
    return service;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_keychain_v2_test_');
    keychainStore = {};
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('写读删往返', () {
    test('写入后可读回，containsSecret 正确', () async {
      final service = freshService();
      await service.init(customRootDir: tempDir);

      await service.writeSecret('k1', 'secret-1');
      expect(await service.readSecret('k1'), 'secret-1');
      expect(await service.containsSecret('k1'), isTrue);
      expect(await service.containsSecret('missing'), isFalse);
    });

    test('删除后读回 null 且持久化生效', () async {
      final service = freshService();
      await service.init(customRootDir: tempDir);
      await service.writeSecret('k1', 'secret-1');
      await service.deleteSecret('k1');

      expect(await service.readSecret('k1'), isNull);

      // 模拟重启
      await service.init(customRootDir: tempDir);
      expect(await service.readSecret('k1'), isNull);
    });
  });

  group('跨重启持久化（模拟 init 重载）', () {
    test('重新 init 后数据仍在', () async {
      final service = freshService();
      await service.init(customRootDir: tempDir);
      await service.writeSecret('api_key', 'sk-persist-123');

      // 模拟重启：同目录重新 init（内存缓存清空）
      await service.init(customRootDir: tempDir);
      expect(await service.readSecret('api_key'), 'sk-persist-123');
    });

    test('密文文件不含明文 secret', () async {
      final service = freshService();
      await service.init(customRootDir: tempDir);
      await service.writeSecret('api_key', 'sk-plaintext-marker-999');

      final file = File('${tempDir.path}/.secrets.bin');
      expect(await file.exists(), isTrue);
      final raw = await file.readAsBytes();
      final rawStr = utf8.decode(raw, allowMalformed: true);
      expect(rawStr.contains('sk-plaintext-marker-999'), isFalse);
      expect(rawStr.contains('api_key'), isFalse);
    });
  });

  group('fail-fast', () {
    test('Keychain 完全不可用时抛 DekUnavailableException 且文案含恢复路径', () async {
      final service = KeychainService.instance;
      service.setKekManagerForTesting(
        KekManager(bridge: _AlwaysFailBridge()),
      );
      await service.init(customRootDir: tempDir);

      try {
        await service.readSecret('any');
        fail('应抛出 DekUnavailableException');
      } on DekUnavailableException catch (e) {
        expect(e.message, contains('恢复'));
      }
    });

    test('密文被篡改时抛完整性错误，不返回损坏数据', () async {
      final service = freshService();
      await service.init(customRootDir: tempDir);
      await service.writeSecret('k1', 'secret-1');

      // 篡改密文
      final file = File('${tempDir.path}/.secrets.bin');
      final raw = await file.readAsBytes();
      raw[raw.length - 1] ^= 0xFF;
      await file.writeAsBytes(raw, flush: true);

      // 模拟重启强制重读
      await service.init(customRootDir: tempDir);
      expect(
        () => service.readSecret('k1'),
        throwsA(anything), // VaultCipherException 或其包装
      );
    });
  });

  group('不读 legacy XOR 存储', () {
    test('目录中存在 .secrets.dat 时忽略之', () async {
      // 构造 legacy XOR 文件（含一个明文 key）
      const xorMask = 'v8_work_toolbox_credential_salt_2026_safe';
      final legacy = jsonEncode({'legacy_key': 'legacy_secret_value'});
      final maskBytes = utf8.encode(xorMask);
      final rawBytes = utf8.encode(legacy);
      final xored = List<int>.generate(
        rawBytes.length,
        (i) => rawBytes[i] ^ maskBytes[i % maskBytes.length],
      );
      await File('${tempDir.path}/.secrets.dat').writeAsBytes(xored);

      final service = freshService();
      await service.init(customRootDir: tempDir);

      // v2 服务不应读到 legacy 数据
      expect(await service.readSecret('legacy_key'), isNull);
    });
  });
}
