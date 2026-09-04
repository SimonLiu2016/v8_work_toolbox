import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 基于 macOS Keychain 的安全凭证管理服务
class KeychainService {
  KeychainService._();
  static final KeychainService instance = KeychainService._();

  FlutterSecureStorage? _storage;
  final Map<String, String> _memoryFallback = {};

  FlutterSecureStorage get storage {
    _storage ??= const FlutterSecureStorage(
      mOptions: MacOsOptions(
        accountName: 'v8_work_toolbox_credentials',
      ),
    );
    return _storage!;
  }

  @visibleForTesting
  void setMockStorage(FlutterSecureStorage mock) {
    _storage = mock;
  }

  /// 安全保存密钥
  Future<void> writeSecret(String keyId, String secret) async {
    try {
      await storage.write(key: keyId, value: secret);
      _memoryFallback[keyId] = secret;
    } catch (e) {
      debugPrint('Keychain 写入失败，回退内存缓存: $e');
      _memoryFallback[keyId] = secret;
    }
  }

  /// 安全读取密钥
  Future<String?> readSecret(String keyId) async {
    try {
      final value = await storage.read(key: keyId);
      if (value != null) {
        _memoryFallback[keyId] = value;
        return value;
      }
      return _memoryFallback[keyId];
    } catch (e) {
      debugPrint('Keychain 读取失败，回退内存缓存: $e');
      return _memoryFallback[keyId];
    }
  }

  /// 安全删除密钥
  Future<void> deleteSecret(String keyId) async {
    try {
      await storage.delete(key: keyId);
    } catch (e) {
      debugPrint('Keychain 删除异常: $e');
    }
    _memoryFallback.remove(keyId);
  }

  /// 检查是否存在密钥
  Future<bool> containsSecret(String keyId) async {
    final s = await readSecret(keyId);
    return s != null && s.isNotEmpty;
  }
}
