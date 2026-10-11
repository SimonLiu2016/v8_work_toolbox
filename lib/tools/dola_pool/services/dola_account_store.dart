import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../../../services/keychain_service.dart';
import '../models/dola_account.dart';

/// 负责 Dola 账号的加密持久化、读取与更新。
class DolaAccountStore extends ChangeNotifier {
  DolaAccountStore._();
  static final DolaAccountStore instance = DolaAccountStore._();

  static const String _accountsFileName = 'dola_accounts.json';
  static const String _keychainPrefix = 'dola_account_session_';

  final List<DolaAccount> _accounts = [];
  bool _initialized = false;

  List<DolaAccount> get accounts => List.unmodifiable(_accounts);
  bool get isInitialized => _initialized;

  File get _storageFile {
    final dir = AppPaths.root;
    return File(p.join(dir.path, _accountsFileName));
  }

  /// 初始化加载账号元数据与安全钥匙串凭据
  Future<void> init() async {
    if (_initialized) return;
    try {
      final file = _storageFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final list = jsonDecode(content) as List<dynamic>;
          _accounts.clear();
          for (final item in list) {
            final acc = DolaAccount.fromJson(item as Map<String, dynamic>);
            // 从 Keychain 读取真实的 sessionid
            final session = await KeychainService.instance
                .readSecret('$_keychainPrefix${acc.id}');
            if (session != null && session.isNotEmpty) {
              _accounts.add(acc.copyWith(sessionid: session));
            } else {
              _accounts.add(acc);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[DolaAccountStore] init error: $e');
    } finally {
      _initialized = true;
      notifyListeners();
    }
  }

  /// 持久化落盘元数据
  Future<void> _save() async {
    try {
      final file = _storageFile;
      await file.parent.create(recursive: true);
      // 元数据中不存放明文 sessionid
      final rawList = _accounts.map((a) {
        final json = a.toJson();
        json['sessionid'] = ''; // 脱敏
        return json;
      }).toList();
      await file.writeAsString(jsonEncode(rawList), flush: true);
    } catch (e) {
      debugPrint('[DolaAccountStore] _save error: $e');
    }
  }

  /// 批量从 Cookie 文本中解析并导入账号
  Future<int> importFromCookieText(String text, {String? defaultProxy}) async {
    await init();
    final lines = text.split('\n');
    var importedCount = 0;

    for (var rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      // 提取 sessionid
      String? sessionid;
      if (line.contains('sessionid=')) {
        final match = RegExp(r'sessionid=([^;\s]+)').firstMatch(line);
        if (match != null) sessionid = match.group(1);
      } else if (!line.contains('=') && line.length > 20) {
        // 直接粘贴了 sessionid 值
        sessionid = line;
      }

      if (sessionid == null || sessionid.trim().isEmpty) continue;
      sessionid = sessionid.trim();

      // 检查是否已存在相同 sessionid
      final exists = _accounts.any((a) => a.sessionid == sessionid);
      if (exists) continue;

      final id = 'dola_${DateTime.now().millisecondsSinceEpoch}_${importedCount + 1}';
      final name = 'Dola账号_${_accounts.length + 1}';

      // 写入 Keychain
      await KeychainService.instance.writeSecret('$_keychainPrefix$id', sessionid);

      final account = DolaAccount(
        id: id,
        name: name,
        sessionid: sessionid,
        proxyUrl: defaultProxy,
        points: 4,
        dailyLimit: 4,
        status: DolaAccountStatus.full,
      );

      _accounts.add(account);
      importedCount++;
    }

    if (importedCount > 0) {
      await _save();
      notifyListeners();
    }
    return importedCount;
  }

  /// 更新单个账号信息
  Future<void> updateAccount(DolaAccount updated) async {
    await init();
    final index = _accounts.indexWhere((a) => a.id == updated.id);
    if (index != -1) {
      _accounts[index] = updated;
      if (updated.sessionid.isNotEmpty) {
        await KeychainService.instance
            .writeSecret('$_keychainPrefix${updated.id}', updated.sessionid);
      }
      await _save();
      notifyListeners();
    }
  }

  /// 删除账号
  Future<void> deleteAccount(String accountId) async {
    await init();
    final index = _accounts.indexWhere((a) => a.id == accountId);
    if (index != -1) {
      _accounts.removeAt(index);
      await KeychainService.instance.deleteSecret('$_keychainPrefix$accountId');
      await _save();
      notifyListeners();
    }
  }

  /// 批量重置所有账号的额度（东京时间 0 点）
  Future<void> resetAllQuotas() async {
    await init();
    for (var i = 0; i < _accounts.length; i++) {
      final acc = _accounts[i];
      // 异常或被手动停用的不强制拉回，冷却或半额恢复为满额
      if (acc.status == DolaAccountStatus.cooling ||
          acc.status == DolaAccountStatus.half) {
        _accounts[i] = acc.copyWith(
          points: acc.dailyLimit,
          status: DolaAccountStatus.full,
          lastError: null,
        );
      }
    }
    await _save();
    notifyListeners();
  }
}
