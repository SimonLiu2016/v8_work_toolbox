import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tools/password/crypto/kek_manager.dart';
import '../tools/password/crypto/vault_cipher.dart';
import '../tools/password/crypto/vault_file_store.dart';

/// 凭证管理服务 v2
///
/// 架构（KEK/DEK 分离）：
/// - DEK（32 字节随机数）由 [KekManager] 保管于 macOS Keychain
/// - 全部 secret 以单个 JSON map 经 AES-256-GCM 加密后原子写入 `.secrets.bin`
/// - 不再使用 XOR 混淆；DEK 不可用时 fail-fast（[DekUnavailableException]）
///
/// 对外 API 与 v1 完全一致：writeSecret / readSecret / deleteSecret /
/// containsSecret / init。消费方（ai_config_store、privacy_security_service、
/// tts_engine、ai_subtitle_service、ai_service）零改动。
class KeychainService {
  KeychainService._();
  static final KeychainService instance = KeychainService._();

  static const String secretsFileName = '.secrets.bin';

  KekManager _kekManager = KekManager();
  final VaultCipher _cipher = VaultCipher();
  VaultFileStore? _store;

  /// 内存中的明文 secret map（解锁会话内常驻；null 表示尚未加载）
  Map<String, String>? _secrets;

  /// 测试注入：替换 DEK 桥接（flutter test 无平台通道，真实 Keychain 不可用）
  @visibleForTesting
  void setKekManagerForTesting(KekManager manager) {
    _kekManager = manager;
  }

  /// 初始化凭证存储目录
  Future<void> init({Directory? customRootDir}) async {
    _store = VaultFileStore(
      customRootDir: customRootDir,
      fileName: secretsFileName,
    );
    _secrets = null;
  }

  /// 保存密钥（加密后原子写入本地密文文件）
  Future<void> writeSecret(String keyId, String secret) async {
    final secrets = await _ensureLoaded();
    secrets[keyId] = secret;
    await _persist();
  }

  /// 读取密钥（DEK 缺失或密文损坏时抛 [DekUnavailableException] /
  /// [VaultCipherException]，不静默降级）
  Future<String?> readSecret(String keyId) async {
    final secrets = await _ensureLoaded();
    return secrets[keyId];
  }

  /// 删除密钥
  Future<void> deleteSecret(String keyId) async {
    final secrets = await _ensureLoaded();
    secrets.remove(keyId);
    await _persist();
  }

  /// 检查是否存在密钥
  Future<bool> containsSecret(String keyId) async {
    final s = await readSecret(keyId);
    return s != null && s.isNotEmpty;
  }

  /// 导出全部条目（迁移/备份流程使用；返回副本）
  Future<Map<String, String>> exportAll() async {
    final secrets = await _ensureLoaded();
    return Map<String, String>.from(secrets);
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _ensureLoaded() async {
    if (_secrets != null) return _secrets!;
    _store ??= VaultFileStore(fileName: secretsFileName);
    final store = _store!;

    final dek = await _kekManager.getOrCreateDek();
    final jsonStr = await store.readDecrypted(_cipher, dek);
    if (jsonStr == null) {
      _secrets = <String, String>{};
      return _secrets!;
    }

    final decoded = jsonDecode(jsonStr);
    final result = <String, String>{};
    if (decoded is Map) {
      decoded.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          result[k.toString()] = v;
        }
      });
    }
    _secrets = result;
    return result;
  }

  Future<void> _persist() async {
    final store = _store ?? VaultFileStore(fileName: secretsFileName);
    _store = store;
    final dek = await _kekManager.getOrCreateDek();
    await store.writeEncrypted(_cipher, dek, jsonEncode(_secrets ?? {}));
  }
}
