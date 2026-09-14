import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'crypto/kek_manager.dart';
import 'crypto/vault_cipher.dart';
import 'crypto/vault_file_store.dart';
import 'vault_models.dart';

/// Vault 存储（设计 D3：双文件结构）
///
/// - `.vault.meta.json`：全部条目元数据（明文，供列表/搜索/标签计数）
/// - `.vault.bin`：全部 secret 字段整体 AES-256-GCM 加密（`{secretRef: VaultSecret}`）
///
/// 内存 secret 缓存（设计 D4）：解锁会话内常驻；lock() 清空。
class VaultStore extends ChangeNotifier {
  VaultStore({KekManager? kekManager, Directory? customRootDir})
      : _kekManager = kekManager ?? KekManager(),
        _customRootDir = customRootDir;

  static const String metadataFileName = '.vault.meta.json';
  static const String secretsFileName = '.vault.bin';

  final KekManager _kekManager;
  final Directory? _customRootDir;
  final VaultCipher _cipher = VaultCipher();
  final Uuid _uuid = const Uuid();

  List<VaultItem> _items = [];
  final Map<String, VaultSecret> _secretCache = {};
  bool _loaded = false;
  bool _secretsLoaded = false;

  List<VaultItem> get items => List.unmodifiable(_items);
  bool get isLoaded => _loaded;

  // ---------------------------------------------------------------------------
  // 路径
  // ---------------------------------------------------------------------------

  Future<Directory> _rootDir() async {
    if (_customRootDir != null) return _customRootDir;
    final home = Platform.environment['HOME'];
    if (Platform.isMacOS && home != null && home.isNotEmpty) {
      return Directory(
        p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'),
      );
    }
    final dir = await getApplicationSupportDirectory();
    return Directory(p.join(dir.path, 'V8WorkToolbox'));
  }

  Future<File> _metadataFile() async {
    final dir = await _rootDir();
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return File(p.join(dir.path, metadataFileName));
  }

  VaultFileStore _secretFileStore(Directory dir) {
    return VaultFileStore(customRootDir: dir, fileName: secretsFileName);
  }

  // ---------------------------------------------------------------------------
  // 加载
  // ---------------------------------------------------------------------------

  /// 加载元数据（不解密 secret）
  Future<void> load() async {
    final file = await _metadataFile();
    if (file.existsSync()) {
      try {
        final jsonStr = await file.readAsString();
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          _items = decoded
              .whereType<Map>()
              .map((e) => VaultItem.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else {
          _items = [];
        }
      } catch (_) {
        _items = [];
      }
    } else {
      _items = [];
    }
    _loaded = true;
    notifyListeners();
  }

  /// 加载并解密 secret blob（需要 DEK；fail-fast）
  Future<void> _ensureSecretsLoaded() async {
    if (_secretsLoaded) return;
    final dek = await _kekManager.getOrCreateDek();
    final dir = await _rootDir();
    final store = _secretFileStore(dir);
    final jsonStr = await store.readDecrypted(_cipher, dek);
    _secretCache.clear();
    if (jsonStr != null) {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is Map) {
            _secretCache[k.toString()] =
                VaultSecret.fromJson(Map<String, dynamic>.from(v));
          }
        });
      }
    }
    _secretsLoaded = true;
  }

  Future<void> _persistSecrets() async {
    final dek = await _kekManager.getOrCreateDek();
    final dir = await _rootDir();
    final store = _secretFileStore(dir);
    final map = _secretCache.map((k, v) => MapEntry(k, v.toJson()));
    await store.writeEncrypted(_cipher, dek, jsonEncode(map));
  }

  Future<void> _persistMetadata() async {
    final file = await _metadataFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode(_items.map((e) => e.toJson()).toList()),
      flush: true,
    );
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }

  // ---------------------------------------------------------------------------
  // CRUD
  // ---------------------------------------------------------------------------

  /// 创建条目（secret 为空串时不写 secret blob）
  Future<VaultItem> create({
    required VaultEntryType type,
    required String title,
    String url = '',
    String username = '',
    String secret = '',
    String totpSeed = '',
    List<String> tags = const [],
    String notes = '',
  }) async {
    if (!_loaded) await load();
    final now = DateTime.now();
    final id = _uuid.v4();
    final secretRef = 'sec_$id';

    final item = VaultItem(
      id: id,
      type: type,
      title: title,
      url: url,
      username: username,
      tags: tags,
      notes: notes,
      createdAt: now,
      updatedAt: now,
      passwordUpdatedAt: now,
      secretRef: secretRef,
    );
    _items.add(item);
    await _persistMetadata();

    if (secret.isNotEmpty || totpSeed.isNotEmpty) {
      await _ensureSecretsLoaded();
      _secretCache[secretRef] = VaultSecret(secret: secret, totpSeed: totpSeed);
      await _persistSecrets();
    }
    notifyListeners();
    return item;
  }

  /// 更新条目元数据；secret/totpSeed 非 null 时同步更新 secret
  Future<VaultItem> update(
    String id, {
    String? title,
    String? url,
    String? username,
    List<String>? tags,
    String? notes,
    String? secret,
    String? totpSeed,
  }) async {
    if (!_loaded) await load();
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) throw ArgumentError('条目不存在: $id');

    final now = DateTime.now();
    final secretChanged = secret != null || totpSeed != null;
    final updated = _items[idx].copyWith(
      title: title,
      url: url,
      username: username,
      tags: tags,
      notes: notes,
      updatedAt: now,
      passwordUpdatedAt: secretChanged ? now : null,
    );
    _items[idx] = updated;
    await _persistMetadata();

    if (secretChanged) {
      await _ensureSecretsLoaded();
      final existing = _secretCache[updated.secretRef] ?? const VaultSecret();
      _secretCache[updated.secretRef] = VaultSecret(
        secret: secret ?? existing.secret,
        totpSeed: totpSeed ?? existing.totpSeed,
      );
      await _persistSecrets();
    }
    notifyListeners();
    return updated;
  }

  /// 删除条目（元数据 + secret 一并清除）
  Future<void> delete(String id) async {
    if (!_loaded) await load();
    final idx = _items.indexWhere((e) => e.id == id);
    if (idx < 0) return;
    final ref = _items[idx].secretRef;
    _items.removeAt(idx);
    await _persistMetadata();

    await _ensureSecretsLoaded();
    if (_secretCache.remove(ref) != null) {
      await _persistSecrets();
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 查询
  // ---------------------------------------------------------------------------

  /// 读取条目 secret（触发解密；fail-fast 于 DEK 缺失）
  Future<VaultSecret> readSecret(String id) async {
    if (!_loaded) await load();
    final item = _items.firstWhere(
      (e) => e.id == id,
      orElse: () => throw ArgumentError('条目不存在: $id'),
    );
    await _ensureSecretsLoaded();
    return _secretCache[item.secretRef] ?? const VaultSecret();
  }

  /// 明文元数据搜索（不解密 secret）
  List<VaultItem> search(String query, {String? tag}) {
    var pool = _items;
    if (tag != null && tag.isNotEmpty) {
      pool = pool.where((e) => e.tags.contains(tag)).toList();
    }
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List.unmodifiable(pool);
    return pool.where((e) {
      return e.title.toLowerCase().contains(q) ||
          e.username.toLowerCase().contains(q) ||
          e.url.toLowerCase().contains(q);
    }).toList();
  }

  /// 标签计数（侧栏展示）
  Map<String, int> tagCounts() {
    final counts = <String, int>{};
    for (final item in _items) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    return counts;
  }

  // ---------------------------------------------------------------------------
  // 会话控制（设计 D4）
  // ---------------------------------------------------------------------------

  /// 锁定：清空内存 secret 缓存与 DEK 缓存（不删磁盘数据）
  void lock() {
    _secretCache.clear();
    _secretsLoaded = false;
    _kekManager.lock();
    notifyListeners();
  }

  bool get hasSecretsInMemory => _secretsLoaded && _secretCache.isNotEmpty;

  // ---------------------------------------------------------------------------
  // 测试钩子
  // ---------------------------------------------------------------------------

  @visibleForTesting
  void resetForTesting() {
    _items = [];
    _secretCache.clear();
    _loaded = false;
    _secretsLoaded = false;
  }
}
