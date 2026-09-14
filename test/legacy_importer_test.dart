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
    tempDir = await Directory.systemTemp.createTemp('v8_migration_test_');
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

  group('LegacyImporter', () {
    test('导出样例 XOR 文件得到正确明文', () async {
      final data = jsonEncode({
        'api_key_anthropic': 'sk-ant-abc123',
        'api_key_openai': 'sk-openai-def456',
      });
      await legacyFile.writeAsBytes(xorEncode(data));

      final entries = await LegacyImporter.exportLegacyEntries();

      expect(entries['api_key_anthropic'], 'sk-ant-abc123');
      expect(entries['api_key_openai'], 'sk-openai-def456');
    });

    test('文件不存在返回空 map', () async {
      final entries = await LegacyImporter.exportLegacyEntries();
      expect(entries, isEmpty);
    });

    test('损坏文件返回空 map 且不抛异常', () async {
      await legacyFile.writeAsBytes([0xFF, 0xFE, 0x00, 0x01, 0x80]);
      final entries = await LegacyImporter.exportLegacyEntries();
      expect(entries, isEmpty);
    });

    test('hasLegacyData 正确检测', () async {
      expect(await LegacyImporter.hasLegacyData(), isFalse);
      await legacyFile.writeAsBytes(xorEncode(jsonEncode({'k': 'v'})));
      expect(await LegacyImporter.hasLegacyData(), isTrue);
    });

    test('空文件不视为 legacy 数据', () async {
      await legacyFile.writeAsBytes([]);
      expect(await LegacyImporter.hasLegacyData(), isFalse);
    });

    test('deleteLegacyFile 删除文件', () async {
      await legacyFile.writeAsBytes(xorEncode(jsonEncode({'k': 'v'})));
      await LegacyImporter.deleteLegacyFile();
      expect(await legacyFile.exists(), isFalse);
    });
  });

  group('MigrationService 三段式', () {
    test('完整迁移：写入新存储、读回校验、删除 legacy 文件', () async {
      final data = jsonEncode({
        'api_key_a': 'sk-aaa',
        'api_key_b': 'sk-bbb',
      });
      await legacyFile.writeAsBytes(xorEncode(data));

      final service = MigrationService();
      final result = await service.migrate();

      expect(result.migratedCount, 2);
      expect(result.failures, isEmpty);
      expect(result.legacyFileDeleted, isTrue);
      expect(await legacyFile.exists(), isFalse);

      // 新存储中可读回
      expect(await KeychainService.instance.readSecret('api_key_a'), 'sk-aaa');
      expect(await KeychainService.instance.readSecret('api_key_b'), 'sk-bbb');
    });

    test('previewLegacyKeys 返回 keyId 列表不含明文', () async {
      final data = jsonEncode({'key1': 'secret1', 'key2': 'secret2'});
      await legacyFile.writeAsBytes(xorEncode(data));

      final service = MigrationService();
      final keys = await service.previewLegacyKeys();

      expect(keys, containsAll(['key1', 'key2']));
      expect(keys.join(), isNot(contains('secret')));
    });

    test('无 legacy 数据时 migrate 返回零迁移', () async {
      final service = MigrationService();
      final result = await service.migrate();

      expect(result.migratedCount, 0);
      expect(result.failures, isEmpty);
      expect(result.legacyFileDeleted, isFalse);
    });

    test('needsMigration 正确反映 legacy 数据存在性', () async {
      final service = MigrationService();
      expect(await service.needsMigration(), isFalse);
      await legacyFile.writeAsBytes(xorEncode(jsonEncode({'k': 'v'})));
      expect(await service.needsMigration(), isTrue);
    });
  });
}
