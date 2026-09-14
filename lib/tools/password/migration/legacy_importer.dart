import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 迁移结果
class LegacyMigrationResult {
  /// 成功迁移的凭证数
  final int migratedCount;

  /// 迁移失败项（keyId → 错误描述）
  final Map<String, String> failures;

  /// 是否已删除 legacy 文件
  final bool legacyFileDeleted;

  const LegacyMigrationResult({
    required this.migratedCount,
    required this.failures,
    required this.legacyFileDeleted,
  });

  bool get hasFailures => failures.isNotEmpty;
}

/// Legacy XOR 存储读取器（v1 代码路径的最后残留，迁移完成后删除）
class LegacyImporter {
  static const String _xorMask = 'v8_work_toolbox_credential_salt_2026_safe';
  static const String _legacyFileName = '.secrets.dat';

  /// 测试注入：覆盖 legacy 文件路径
  static File? debugLegacyFileOverride;

  /// 导出 legacy 存储的所有条目（keyId → 明文）
  /// 损坏文件返回空 map（不抛异常，由调用方决定如何呈现）
  static Future<Map<String, String>> exportLegacyEntries() async {
    final file = debugLegacyFileOverride ?? await _legacyFile();
    if (!file.existsSync()) return {};

    try {
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return {};
      final decoded = _xorTransform(raw);
      final map = jsonDecode(utf8.decode(decoded));
      if (map is! Map) return {};
      final result = <String, String>{};
      map.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          result[k.toString()] = v;
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  /// 检测 legacy 文件是否存在且非空
  static Future<bool> hasLegacyData() async {
    final file = debugLegacyFileOverride ?? await _legacyFile();
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    if (length == 0) return false;
    // 尝试解码验证
    final entries = await exportLegacyEntries();
    return entries.isNotEmpty;
  }

  /// 删除 legacy 文件（迁移成功后调用）
  static Future<void> deleteLegacyFile() async {
    final file = debugLegacyFileOverride ?? await _legacyFile();
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static Future<File> _legacyFile() async {
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return File(p.join(
        home,
        'Library',
        'Application Support',
        'V8WorkToolbox',
        _legacyFileName,
      ));
    }
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'V8WorkToolbox', _legacyFileName));
  }

  /// XOR 混淆变换（与 v1 实现完全一致；迁移完成后删除）
  static Uint8List _xorTransform(List<int> input) {
    final mask = utf8.encode(_xorMask);
    final out = Uint8List(input.length);
    for (var i = 0; i < input.length; i++) {
      out[i] = input[i] ^ mask[i % mask.length];
    }
    return out;
  }
}
