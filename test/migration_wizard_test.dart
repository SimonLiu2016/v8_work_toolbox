import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/password/migration/legacy_importer.dart';
import 'package:V8WorkToolbox/tools/password/migration/migration_service.dart';

Uint8List xorEncode(String plaintext) {
  const mask = 'v8_work_toolbox_credential_salt_2026_safe';
  final maskBytes = utf8.encode(mask);
  final raw = utf8.encode(plaintext);
  return Uint8List.fromList(
    List<int>.generate(raw.length, (i) => raw[i] ^ maskBytes[i % maskBytes.length]),
  );
}

class _TestKeychainBridge implements KeychainBridge {
  static final Map<String, String> store = {};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File legacyFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_migration_wizard_test_');
    legacyFile = File('${tempDir.path}/.secrets.dat');
    LegacyImporter.debugLegacyFileOverride = legacyFile;
    _TestKeychainBridge.store.clear();
    KeychainService.instance.setKekManagerForTesting(
      KekManager(bridge: _TestKeychainBridge()),
    );
    await KeychainService.instance.init(customRootDir: tempDir);
  });

  tearDown(() async {
    LegacyImporter.debugLegacyFileOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('迁移向导端到端（任务 6.5）', () {
    test('迁移成功后旧文件删除、读回一致', () async {
      final data = jsonEncode({
        'api_key_a': 'sk-aaa-111',
        'api_key_b': 'sk-bbb-222',
        'privacy_pin_hash': 'abc123hash',
      });
      await legacyFile.writeAsBytes(xorEncode(data));

      final service = MigrationService();
      expect(await service.needsMigration(), isTrue);

      final result = await service.migrate();

      expect(result.migratedCount, 3);
      expect(result.failures, isEmpty);
      expect(result.legacyFileDeleted, isTrue);
      expect(await legacyFile.exists(), isFalse);

      // 读回一致
      expect(await KeychainService.instance.readSecret('api_key_a'), 'sk-aaa-111');
      expect(await KeychainService.instance.readSecret('api_key_b'), 'sk-bbb-222');
      expect(await KeychainService.instance.readSecret('privacy_pin_hash'), 'abc123hash');

      // 迁移后不再提示
      expect(await service.needsMigration(), isFalse);
    });

    test('写入失败时保留旧文件并报告失败项', () async {
      final data = jsonEncode({'api_key_a': 'sk-aaa'});
      await legacyFile.writeAsBytes(xorEncode(data));

      // 注入总是失败的桥：写 KeychainService 的 DEK 管理器会失败 → writeSecret 抛
      final failingService = MigrationService(
        keychainService: _AlwaysFailingKeychainService(),
      );
      final result = await failingService.migrate();

      expect(result.migratedCount, 0);
      expect(result.failures, isNotEmpty);
      expect(result.failures.containsKey('api_key_a'), isTrue);
      expect(result.legacyFileDeleted, isFalse);
      // 旧文件保留
      expect(await legacyFile.exists(), isTrue);
    });

    test('部分失败时旧文件保留', () async {
      final data = jsonEncode({'good': 'ok-value', 'bad': 'will-fail'});
      await legacyFile.writeAsBytes(xorEncode(data));

      final service = MigrationService(
        keychainService: _PartiallyFailingKeychainService(failKey: 'bad'),
      );
      final result = await service.migrate();

      expect(result.migratedCount, 1);
      expect(result.failures.containsKey('bad'), isTrue);
      expect(result.legacyFileDeleted, isFalse);
      expect(await legacyFile.exists(), isTrue);
    });
  });
}

class _AlwaysFailingKeychainService implements KeychainService {
  @override
  Future<void> writeSecret(String keyId, String secret) async {
    throw StateError('write failed');
  }

  @override
  Future<String?> readSecret(String keyId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PartiallyFailingKeychainService implements KeychainService {
  _PartiallyFailingKeychainService({required this.failKey});
  final String failKey;
  final Map<String, String> _ok = {};

  @override
  Future<void> writeSecret(String keyId, String secret) async {
    if (keyId == failKey) throw StateError('write failed for $keyId');
    _ok[keyId] = secret;
  }

  @override
  Future<String?> readSecret(String keyId) async => _ok[keyId];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
