import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import '../../../services/app_paths.dart';

/// Keychain 桥接抽象（测试 mock 注入点）
abstract class KeychainBridge {
  Future<String?> read({required String service, required String account});
  Future<void> write({
    required String service,
    required String account,
    required String value,
  });
  Future<void> delete({required String service, required String account});
}

/// 文件桥接抽象（DEK 文件兜底存储；测试 mock 注入点）
abstract class DekFileBridge {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
  Future<int?> permissions();
}

/// 生产实现：`~/Library/Application Support/V8WorkToolbox/.dek`，0600 权限
class DefaultDekFileBridge implements DekFileBridge {
  DefaultDekFileBridge({this.customRootDir});

  static const String fileName = '.dek';
  final Directory? customRootDir;
  File? _file;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = customRootDir ?? AppPaths.root;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _file = File(p.join(dir.path, fileName));
    return _file!;
  }

  @override
  Future<String?> read() async {
    final f = await _ensureFile();
    if (!f.existsSync()) return null;
    final content = await f.readAsString();
    return content.trim().isEmpty ? null : content.trim();
  }

  @override
  Future<void> write(String value) async {
    final f = await _ensureFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(value, flush: true);
    if (f.existsSync()) await f.delete();
    await tmp.rename(f.path);
    await _enforcePermissions(f);
  }

  @override
  Future<void> delete() async {
    final f = await _ensureFile();
    if (f.existsSync()) await f.delete();
    _file = null;
  }

  @override
  Future<int?> permissions() async {
    final f = await _ensureFile();
    if (!f.existsSync()) return null;
    final stat = await f.stat();
    return stat.mode & 0x1FF;
  }

  Future<void> _enforcePermissions(File f) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    try {
      await Process.run('chmod', ['600', f.path]);
    } catch (_) {}
  }
}

/// 生产实现：绑定 flutter_secure_storage（macOS Keychain）
class FlutterKeychainBridge implements KeychainBridge {
  final Map<(String, String), FlutterSecureStorage> _storageCache = {};

  FlutterSecureStorage _storageFor(String service) {
    return _storageCache.putIfAbsent(
      (service, service),
      () => FlutterSecureStorage(
        mOptions: MacOsOptions(
          accountName: service,
          accessibility: KeychainAccessibility.unlocked,
          synchronizable: false,
          useDataProtectionKeyChain: true,
        ),
      ),
    );
  }

  @override
  Future<String?> read({required String service, required String account}) {
    return _storageFor(service).read(key: account);
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) {
    return _storageFor(service).write(key: account, value: value);
  }

  @override
  Future<void> delete({required String service, required String account}) {
    return _storageFor(service).delete(key: account);
  }
}

/// DEK 管理异常：DEK 缺失或 Keychain 不可用时抛出（fail-fast，不静默降级）
class DekUnavailableException implements Exception {
  final String message;
  final bool isKeychainLocked;

  DekUnavailableException(this.message, {this.isKeychainLocked = false});

  @override
  String toString() => 'DekUnavailableException: $message';
}

/// DEK 来源（UI 展示用）
enum DekSource { keychain, file, ephemeral, none }

/// DEK 生命周期管理：
/// - DEK 是 32 字节 CSPRNG 随机数（不从密码派生，无 KDF）
/// - 读取链：Keychain → 文件镜像（0600）→ 生成
/// - 写入链：Keychain（写后回读验证）+ 文件镜像双写
/// - 所有来源均不可用时 fail-fast 并指明恢复路径
///
/// 进程级单例：所有密钥消费者（AI 配置、密码库、设置面板）共享一个实例与
/// 内存缓存。测试用 [setForTesting] 注入桥接，[resetForTesting] 清状态。
class KekManager {
  KekManager({KeychainBridge? bridge, DekFileBridge? fileBridge})
      : _bridge = bridge ?? FlutterKeychainBridge(),
        _fileBridge = fileBridge ?? DefaultDekFileBridge();

  /// 进程级单例。生产代码统一经此访问，消除多实例缓存分叉。
  /// 测试如需隔离实例，直接 `KekManager(bridge:…, fileBridge:…)` 构造即可
  /// （构造器公开），不走单例。
  static final KekManager instance = KekManager._();

  KekManager._({KeychainBridge? bridge, DekFileBridge? fileBridge})
      : _bridge = bridge ?? FlutterKeychainBridge(),
        _fileBridge = fileBridge ?? DefaultDekFileBridge();

  /// 测试注入：替换单例的桥接实现（flutter test 无平台通道，真实 Keychain 不可用）。
  /// 注入后单例的内存缓存与来源状态被重置。
  @visibleForTesting
  static void setForTesting({KeychainBridge? bridge, DekFileBridge? fileBridge}) {
    instance._bridge = bridge ?? FlutterKeychainBridge();
    instance._fileBridge = fileBridge ?? DefaultDekFileBridge();
    instance._cachedDek = null;
    instance._source = DekSource.none;
  }

  /// 测试注入辅助：把本实例的桥接应用到进程单例（供 [KeychainService.setKekManagerForTesting]
  /// 等消费方在单例化后仍能以旧签名注入桥接）。仅测试使用。
  void applyBridgesToSingleton() {
    KekManager.instance._bridge = _bridge;
    KekManager.instance._fileBridge = _fileBridge;
    KekManager.instance._cachedDek = _cachedDek;
    KekManager.instance._source = _source;
  }

  /// 测试清理：清内存缓存与来源状态，但保留注入的桥接（供下一组用例复用）。
  @visibleForTesting
  void resetForTesting() {
    _cachedDek = null;
    _source = DekSource.none;
  }

  static const String defaultService = 'com.v8worktoolbox.vault.dek';
  static const String defaultAccount = 'dek';
  static const int dekLengthBytes = 32;

  /// Base64 编码的 DEK 在 Keychain 中的存储前缀（防误读其他数据）
  static const String _dekMarker = 'v8dek1:';

  KeychainBridge _bridge;
  DekFileBridge _fileBridge;
  final Random _random = Random.secure();
  Uint8List? _cachedDek;
  DekSource _source = DekSource.none;

  /// 当前 DEK 来源（keychain / file / ephemeral / none）
  DekSource get source => _source;

  /// 获取 DEK：内存缓存 → Keychain → 文件镜像 → 首次生成
  Future<Uint8List> getOrCreateDek({
    String service = defaultService,
    String account = defaultAccount,
  }) async {
    if (_cachedDek != null) return _cachedDek!;

    // 1. Keychain 读
    final keychainDek = await _tryReadKeychain(service, account);
    if (keychainDek != null) {
      _cachedDek = keychainDek;
      _source = DekSource.keychain;
      // Keychain 可读，但文件镜像可能缺失或陈旧——补齐镜像，保证重启兜底。
      await _ensureFileMirror(keychainDek);
      return keychainDek;
    }

    // 2. 文件镜像读
    final fileDek = await _tryReadFile();
    if (fileDek != null) {
      _cachedDek = fileDek;
      _source = DekSource.file;
      // 若 Keychain 现在可写，自动迁移回去（并维护镜像）
      await _tryMigrateFileToKeychain(fileDek, service, account);
      return fileDek;
    }

    // 3. 首次生成——双写 Keychain（写后回读验证）+ 文件镜像
    final fresh = _generateDek();
    final encoded = '$_dekMarker${_encodeBase64(fresh)}';
    final keychainOk = await _writeKeychainWithReadback(encoded, service, account);
    if (!keychainOk) {
      // Keychain 事实不可用（写后回读失败）——必须落文件镜像，否则重启即丢。
      try {
        await _fileBridge.write(encoded);
        _source = DekSource.file;
      } catch (e2) {
        throw DekUnavailableException(
          '钥匙串与本地文件均无法保存数据加密密钥。'
          '请检查磁盘权限，或从密钥备份恢复（设置 → DEK 备份恢复）。',
        );
      }
    } else {
      _source = DekSource.keychain;
      // Keychain 写后回读成功——同时维护文件镜像作为重启兜底。
      await _ensureFileMirror(fresh);
    }
    _cachedDek = fresh;
    return fresh;
  }

  /// 仅读取 DEK（不生成）。所有来源均缺失时抛异常。
  Future<Uint8List> getDek({
    String service = defaultService,
    String account = defaultAccount,
  }) async {
    if (_cachedDek != null) return _cachedDek!;

    final keychainDek = await _tryReadKeychain(service, account);
    if (keychainDek != null) {
      _cachedDek = keychainDek;
      _source = DekSource.keychain;
      return keychainDek;
    }

    final fileDek = await _tryReadFile();
    if (fileDek != null) {
      _cachedDek = fileDek;
      _source = DekSource.file;
      return fileDek;
    }

    throw DekUnavailableException(
      '数据加密密钥不存在。请从密钥备份恢复（设置 → DEK 备份恢复）。',
    );
  }

  /// 写入外部 DEK（备份恢复路径使用）
  Future<void> importDek(
    Uint8List dek, {
    String service = defaultService,
    String account = defaultAccount,
  }) async {
    if (dek.length != dekLengthBytes) {
      throw ArgumentError('DEK 必须为 $dekLengthBytes 字节');
    }
    final encoded = '$_dekMarker${_encodeBase64(dek)}';
    final keychainOk = await _writeKeychainWithReadback(encoded, service, account);
    if (!keychainOk) {
      // Keychain 事实不可用——落文件镜像兜底。
      await _fileBridge.write(encoded);
      _source = DekSource.file;
    } else {
      await _ensureFileMirror(dek);
    }
    _cachedDek = Uint8List.fromList(dek);
  }

  /// 删除 DEK（彻底清除场景；危险操作，仅 wipe 流程调用）
  Future<void> destroyDek({
    String service = defaultService,
    String account = defaultAccount,
  }) async {
    try {
      await _bridge.delete(service: service, account: account);
    } catch (_) {}
    try {
      await _fileBridge.delete();
    } catch (_) {}
    _cachedDek = null;
    _source = DekSource.none;
  }

  /// 清空内存缓存（"锁定"语义：不删持久存储，仅清进程内密钥）
  void lock() {
    _cachedDek = null;
  }

  bool get hasCachedDek => _cachedDek != null;

  // ---------------------------------------------------------------------------

  Future<Uint8List?> _tryReadKeychain(String service, String account) async {
    try {
      final stored = await _bridge.read(service: service, account: account);
      return _parseStored(stored);
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List?> _tryReadFile() async {
    try {
      final stored = await _fileBridge.read();
      return _parseStored(stored);
    } catch (_) {
      return null;
    }
  }

  Uint8List? _parseStored(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    if (!stored.startsWith(_dekMarker)) return null;
    final dek = _decodeBase64(stored.substring(_dekMarker.length));
    if (dek == null || dek.length != dekLengthBytes) return null;
    return dek;
  }

  Future<void> _tryMigrateFileToKeychain(
    Uint8List dek,
    String service,
    String account,
  ) async {
    final encoded = '$_dekMarker${_encodeBase64(dek)}';
    final ok = await _writeKeychainWithReadback(encoded, service, account);
    if (ok) {
      _source = DekSource.keychain;
      // 迁移成功后仍保留文件镜像作为重启兜底（ad-hoc 签名下 Keychain 可能
      // 再次对其他进程不可见）。不再删除文件——见 design D2。
    }
    // 不可写则保持文件来源；镜像已存在。
  }

  /// 写 Keychain 并立即回读验证。ad-hoc 签名下 `_bridge.write` 可能不抛异常
  /// 但写入的 item 对后续读不可见（半成功状态）。回读比对是唯一能识别它的
  /// 方法。返回 true 表示 Keychain 事实可用；false 表示应落文件镜像兜底。
  Future<bool> _writeKeychainWithReadback(
    String encoded,
    String service,
    String account,
  ) async {
    try {
      await _bridge.write(service: service, account: account, value: encoded);
    } catch (_) {
      return false;
    }
    try {
      final readBack = await _bridge.read(service: service, account: account);
      return readBack == encoded;
    } catch (_) {
      return false;
    }
  }

  /// 维护文件镜像：写入与给定 DEK 一致的编码值（0600 权限由 fileBridge 强制）。
  /// 若文件已存在且内容一致则不重写，避免无谓 I/O。
  Future<void> _ensureFileMirror(Uint8List dek) async {
    final encoded = '$_dekMarker${_encodeBase64(dek)}';
    try {
      final existing = await _fileBridge.read();
      if (existing == encoded) return;
      await _fileBridge.write(encoded);
    } catch (_) {
      // 文件镜像写入失败不致命——Keychain 仍可用。但若两者都不可用则重启丢，
      // 这是已知风险，由 _persist 失败时的上层路径处理。
    }
  }

  Uint8List _generateDek() {
    return Uint8List.fromList(
      List<int>.generate(dekLengthBytes, (_) => _random.nextInt(256)),
    );
  }

  String _encodeBase64(Uint8List bytes) {
    return base64UrlNoPad(bytes);
  }

  Uint8List? _decodeBase64(String s) {
    try {
      return Uint8List.fromList(base64UrlDecodeNoPad(s));
    } catch (_) {
      return null;
    }
  }
}

/// base64url 无 padding 编码（供 DEK 序列化；避免 Keychain 值中含 '+' '/'）
String base64UrlNoPad(List<int> bytes) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final out = StringBuffer();
  for (int i = 0; i < bytes.length; i += 3) {
    final b0 = bytes[i];
    final b1 = i + 1 < bytes.length ? bytes[i + 1] : null;
    final b2 = i + 2 < bytes.length ? bytes[i + 2] : null;

    out.write(alphabet[b0 >> 2]);
    out.write(alphabet[((b0 & 0x03) << 4) | ((b1 ?? 0) >> 4)]);
    if (b1 != null) out.write(alphabet[((b1 & 0x0f) << 2) | ((b2 ?? 0) >> 6)]);
    if (b2 != null) out.write(alphabet[b2 & 0x3f]);
  }
  return out.toString();
}

/// base64url 无 padding 解码
List<int> base64UrlDecodeNoPad(String input) {
  const alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  final clean = input.replaceAll('=', '');
  final out = <int>[];
  int buffer = 0;
  int bits = 0;
  for (final ch in clean.split('')) {
    final idx = alphabet.indexOf(ch);
    if (idx < 0) throw FormatException('非法 base64url 字符: $ch');
    buffer = (buffer << 6) | idx;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xff);
    }
  }
  return out;
}
