import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

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

  final VaultCipher _cipher = VaultCipher();
  VaultFileStore? _store;

  /// 内存中的明文 secret map（解锁会话内常驻；null 表示尚未加载）
  Map<String, String>? _secrets;

  /// 进程级 DEK 生命周期管理器（单例）。所有密钥消费者共享同一缓存。
  KekManager get _kekManager => KekManager.instance;

  /// 测试注入：替换单例的 DEK 桥接（flutter test 无平台通道，真实 Keychain 不可用）。
  /// 把传入 manager 的桥接应用到进程单例。
  @visibleForTesting
  void setKekManagerForTesting(KekManager manager) {
    manager.applyBridgesToSingleton();
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
    // 确保底层 File 路径已解析，便于后续在同目录写/读自愈标记。
    await store.ensureResolved();

    final dek = await _kekManager.getOrCreateDek();
    Map<String, String>? loaded = await _tryDecrypt(store, dek);

    // 失配自愈修正：GCM 认证失败时，先尝试从文件镜像重新取 DEK 解密——
    // 现实中 Keychain 不可见会让 getOrCreateDek 生成新 DEK，但文件镜像里
    // 可能还存着能解密旧密文的真 DEK。先试文件再自愈，避免误清空。
    if (loaded == null) {
      try {
        final fileDek = await _kekManager.getDek();
        if (!_listEquals(fileDek, dek)) {
          loaded = await _tryDecrypt(store, fileDek);
        }
      } on DekUnavailableException {
        // 文件镜像也没有可用的 DEK——走自愈。
      }
    }

    if (loaded != null) {
      _secrets = loaded;
      return loaded;
    }

    // 真失配：Keychain 与文件 DEK 均无法认证密文 → 备份 + 重建空库 + 信号。
    return _runMismatchRecovery(store);
  }

  /// 用给定 DEK 尝试解密。成功返回 map；密文为空返回空 map；认证失败返回 null
  /// （由调用方决定是否试下一来源或进自愈）。
  Future<Map<String, String>?> _tryDecrypt(VaultFileStore store, Uint8List dek) async {
    try {
      final jsonStr = await store.readDecrypted(_cipher, dek);
      if (jsonStr == null) return <String, String>{};
      final decoded = jsonDecode(jsonStr);
      final result = <String, String>{};
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is String && v.isNotEmpty) {
            result[k.toString()] = v;
          }
        });
      }
      return result;
    } on VaultCipherException catch (e) {
      if (e.isAuthFailure) return null; // 失配，交由调用方处理
      rethrow; // 布局损坏，原样上抛保留现场
    }
  }

  Future<Map<String, String>> _runMismatchRecovery(VaultFileStore store) async {
    // DEK 与密文失配（旧 DEK 不可恢复）：备份残件 → 当前 DEK 重建空库 →
    // 立即可写，并留下一次性信号供 UI 告知用户重填，同时写持久化标记文件
    // 防止一次性信号被错过。
    final backup = await store.backupMismatch();
    _secrets = <String, String>{};
    await _persist();
    final info = RebuildInfo(
      backupPath: backup?.path ?? '(备份失败：原文件不存在)',
      at: DateTime.now(),
    );
    _rebuildInfo = info;
    await _writeRebuildNoticeMarker(info);
    return _secrets!;
  }

  bool _listEquals(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 失配重建信号（一次性）：本次会话若发生过"DEK 失配 → 备份重建"，
  /// 返回重建信息并清空；否则返回 null。
  RebuildInfo? consumeRebuildInfo() {
    final info = _rebuildInfo;
    _rebuildInfo = null;
    return info;
  }

  RebuildInfo? _rebuildInfo;

  /// 持久化自愈标记：写一个 `.secrets.bin.rebuilt-<timestamp>` 空文件，
  /// 使 UI 即便错过会话内的一次性信号也能在启动时察觉并提示用户。
  Future<void> _writeRebuildNoticeMarker(RebuildInfo info) async {
    try {
      final store = _store;
      if (store == null) return;
      final file = store.file;
      if (file == null) return;
      // 用 VaultFileStore 同目录写标记文件，便于统一清理。
      final dir = file.parent;
      final marker = File(p.join(
        dir.path,
        '$secretsFileName.rebuilt-${_timestampForFile(info.at)}',
      ));
      if (!marker.existsSync()) await marker.create();
    } catch (_) {
      // 标记写入失败不致命——一次性信号仍可用。
    }
  }

  /// 检查是否有未读的自愈标记文件。若存在则返回 true 并删除标记（一次性）。
  /// UI 启动时调用以提示"密钥库此前被重置，已存密钥需重新填入"。
  Future<bool> consumeRebuildNotice() async {
    try {
      final store = _store;
      if (store == null) return false;
      final file = store.file;
      if (file == null) return false;
      final dir = file.parent;
      final entities = dir.listSync(followLinks: false);
      for (final e in entities) {
        final name = p.basename(e.path);
        if (name.startsWith('$secretsFileName.rebuilt-')) {
          try { await e.delete(); } catch (_) {}
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  String _timestampForFile(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }

  Future<void> _persist() async {
    final store = _store ?? VaultFileStore(fileName: secretsFileName);
    _store = store;
    final dek = await _kekManager.getOrCreateDek();
    await store.writeEncrypted(_cipher, dek, jsonEncode(_secrets ?? {}));
  }
}

/// 失配重建信息：DEK 与密文失配触发自愈后留下的一次性信号。
class RebuildInfo {
  const RebuildInfo({required this.backupPath, required this.at});

  /// 失配密文的备份文件路径（`.secrets.bin.mismatch-*`）。
  final String backupPath;

  /// 重建发生时间。
  final DateTime at;
}
