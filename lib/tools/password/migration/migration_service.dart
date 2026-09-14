import '../../../services/keychain_service.dart';
import 'legacy_importer.dart';

/// 迁移三段式执行器：
/// 1. 逐条 writeSecret 到新加密存储
/// 2. 读回校验一致
/// 3. 删除 legacy `.secrets.dat`
///
/// 任何阶段失败均保留 legacy 文件，可安全重试。
class MigrationService {
  MigrationService({KeychainService? keychainService})
      : _keychain = keychainService ?? KeychainService.instance;

  final KeychainService _keychain;

  /// 预览将迁移的 keyId 列表（不含明文，供向导 UI 展示）
  Future<List<String>> previewLegacyKeys() async {
    final entries = await LegacyImporter.exportLegacyEntries();
    return entries.keys.toList();
  }

  Future<bool> needsMigration() => LegacyImporter.hasLegacyData();

  /// 执行迁移。返回结果含成功数与逐条失败项。
  Future<LegacyMigrationResult> migrate() async {
    final entries = await LegacyImporter.exportLegacyEntries();
    if (entries.isEmpty) {
      return const LegacyMigrationResult(
        migratedCount: 0,
        failures: {},
        legacyFileDeleted: false,
      );
    }

    final failures = <String, String>{};
    var migrated = 0;

    // 阶段 1+2：逐条写入并读回校验
    for (final entry in entries.entries) {
      try {
        await _keychain.writeSecret(entry.key, entry.value);
        final readBack = await _keychain.readSecret(entry.key);
        if (readBack != entry.value) {
          failures[entry.key] = '读回校验不一致';
        } else {
          migrated++;
        }
      } catch (e) {
        failures[entry.key] = e.toString();
      }
    }

    // 阶段 3：全部成功才删除 legacy 文件
    var deleted = false;
    if (failures.isEmpty) {
      try {
        await LegacyImporter.deleteLegacyFile();
        deleted = true;
      } catch (e) {
        failures['__delete__'] = e.toString();
      }
    }

    return LegacyMigrationResult(
      migratedCount: migrated,
      failures: failures,
      legacyFileDeleted: deleted,
    );
  }
}
