import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../password/vault_models.dart';
import '../../password/vault_store.dart';
import '../models/registered_account.dart';
import 'excel_helper.dart';

class RegisteredAccountStore extends ChangeNotifier {
  RegisteredAccountStore._();
  static final RegisteredAccountStore instance = RegisteredAccountStore._();

  static const String _storageFileName = 'registered_accounts.json';

  List<RegisteredAccount> _accounts = [];
  bool _loaded = false;

  List<RegisteredAccount> get accounts => List.unmodifiable(_accounts);
  bool get isLoaded => _loaded;

  File _getStoreFile() {
    return File(p.join(AppPaths.root.path, _storageFileName));
  }

  /// 加载账号列表
  Future<void> load() async {
    final file = _getStoreFile();
    if (file.existsSync()) {
      try {
        final content = await file.readAsString();
        final list = jsonDecode(content);
        if (list is List) {
          _accounts = list
              .whereType<Map<String, dynamic>>()
              .map((m) => RegisteredAccount.fromJson(m))
              .toList();
        }
      } catch (e) {
        debugPrint('[RegisteredAccountStore] 加载账号失败: $e');
      }
    }
    _loaded = true;
    notifyListeners();
  }

  /// 持久化
  Future<void> _persist() async {
    final file = _getStoreFile();
    final tmp = File('${file.path}.tmp');
    final raw = jsonEncode(_accounts.map((a) => a.toJson()).toList());
    await tmp.writeAsString(raw, flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }

  /// 添加或更新单条账号（按 email 去重更新）
  Future<void> saveAccount(RegisteredAccount account) async {
    if (!_loaded) await load();
    final idx = _accounts.indexWhere((a) => a.email.toLowerCase() == account.email.toLowerCase());
    if (idx >= 0) {
      _accounts[idx] = account;
    } else {
      _accounts.insert(0, account);
    }
    await _persist();
    notifyListeners();
  }

  /// 批量导入账号（自动根据 email 去重）
  Future<int> importAccounts(List<RegisteredAccount> newAccounts) async {
    if (!_loaded) await load();
    int addedCount = 0;
    for (final acc in newAccounts) {
      final idx = _accounts.indexWhere((a) => a.email.toLowerCase() == acc.email.toLowerCase());
      if (idx >= 0) {
        _accounts[idx] = acc;
      } else {
        _accounts.insert(0, acc);
        addedCount++;
      }
    }
    await _persist();
    notifyListeners();
    return addedCount;
  }

  /// 从 Excel 文件导入
  Future<int> importFromExcel(String filePath) async {
    final list = await ExcelHelper.parseExcelFile(filePath);
    return await importAccounts(list);
  }

  /// 批量删除
  Future<void> deleteAccounts(Set<String> ids) async {
    if (!_loaded) await load();
    _accounts.removeWhere((a) => ids.contains(a.id));
    await _persist();
    notifyListeners();
  }

  /// 清空所有账号
  Future<void> clearAll() async {
    _accounts.clear();
    await _persist();
    notifyListeners();
  }

  /// 一键同步指定账号至系统密码保险箱 (Password Vault)
  Future<int> syncToPasswordVault({
    required List<String> accountIds,
    required VaultStore vaultStore,
  }) async {
    if (!_loaded) await load();
    final targets = _accounts.where((a) => accountIds.contains(a.id)).toList();
    if (targets.isEmpty) return 0;

    final entries = targets.map((acc) {
      final title = '${acc.platform.toUpperCase()} 邮箱 (${acc.email})';
      return (
        type: VaultEntryType.login,
        title: title,
        url: acc.email.contains('@outlook') ? 'https://outlook.live.com' : 'https://live.com',
        username: acc.email,
        secret: acc.password,
        totpSeed: '',
        tags: ['Auto-Registered', acc.platform.toUpperCase()],
        notes: '姓名: ${acc.firstName} ${acc.lastName}\n生日: ${acc.birthDate}\n辅助邮箱: ${acc.recoveryEmail ?? "无"}',
      );
    }).toList();

    await vaultStore.createBatch(entries);
    return entries.length;
  }

  /// 导出为多种格式
  Future<void> exportAccounts({
    required List<RegisteredAccount> targets,
    required String format, // 'xlsx' | 'csv' | 'txt' | 'json'
    required String outputPath,
    bool maskPassword = false,
  }) async {
    switch (format.toLowerCase()) {
      case 'xlsx':
        await ExcelHelper.exportToExcel(targets, outputPath, maskPassword: maskPassword);
        break;

      case 'csv':
        final lines = <String>[];
        lines.add('平台,邮箱账号,密码,姓,名,出生日期,恢复邮箱,注册时间,状态');
        for (final a in targets) {
          final pwd = maskPassword && a.password.length > 4
              ? '${a.password.substring(0, 2)}****${a.password.substring(a.password.length - 2)}'
              : a.password;
          lines.add('${a.platform},${a.email},$pwd,${a.lastName},${a.firstName},${a.birthDate},${a.recoveryEmail ?? ""},${a.createdAt.toIso8601String()},${a.status}');
        }
        await File(outputPath).writeAsString(lines.join('\n'));
        break;

      case 'json':
        final list = targets.map((a) {
          final m = a.toJson();
          if (maskPassword && a.password.length > 4) {
            m['password'] = '${a.password.substring(0, 2)}****${a.password.substring(a.password.length - 2)}';
          }
          return m;
        }).toList();
        await File(outputPath).writeAsString(const JsonEncoder.withIndent('  ').convert(list));
        break;

      case 'txt':
        final buffer = StringBuffer();
        for (final a in targets) {
          final pwd = maskPassword && a.password.length > 4
              ? '${a.password.substring(0, 2)}****${a.password.substring(a.password.length - 2)}'
              : a.password;
          buffer.writeln('${a.email}----$pwd');
        }
        await File(outputPath).writeAsString(buffer.toString());
        break;

      default:
        throw ArgumentError('不支持的导出格式: $format');
    }
  }
}
