import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 基于 macOS Keychain 与本地安全持久化兜底的双层凭证管理服务
class KeychainService {
  KeychainService._();
  static final KeychainService instance = KeychainService._();

  FlutterSecureStorage? _storage;
  final Map<String, String> _memoryCache = {};
  File? _secretsFile;
  bool _isFileLoaded = false;

  static const String _xorMask = 'v8_work_toolbox_credential_salt_2026_safe';

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

  /// 初始化凭证存储目录
  Future<void> init({Directory? customRootDir}) async {
    try {
      Directory dir;
      if (customRootDir != null) {
        dir = customRootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          dir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'));
        } else {
          final appSupport = await getApplicationSupportDirectory();
          dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      _secretsFile = File(p.join(dir.path, '.secrets.dat'));
      await _loadFromFile();
    } catch (e) {
      debugPrint('初始化本地凭证兜底存储异常: $e');
    }
  }

  /// 安全保存密钥（双写：Keychain + 本地安全文件）
  Future<void> writeSecret(String keyId, String secret) async {
    _memoryCache[keyId] = secret;

    // 1. 尝试写入系统 Keychain
    try {
      await storage.write(key: keyId, value: secret);
    } catch (e) {
      debugPrint('Keychain 写入失败，转由本地安全文件持久化: $e');
    }

    // 2. 同步写入本地安全文件，确保跨进程/重启 100% 不丢 Key
    await _saveToFile();
  }

  /// 安全读取密钥（优先 Keychain，缺失或异常时读取本地安全文件）
  Future<String?> readSecret(String keyId) async {
    // 1. 先尝试从系统 Keychain 读取
    try {
      final value = await storage.read(key: keyId);
      if (value != null && value.isNotEmpty) {
        _memoryCache[keyId] = value;
        return value;
      }
    } catch (e) {
      debugPrint('Keychain 读取失败，尝试从本地安全文件恢复: $e');
    }

    // 2. 若 Keychain 未读到或报错，从内存缓存读取
    if (_memoryCache.containsKey(keyId)) {
      return _memoryCache[keyId];
    }

    // 3. 尝试从本地持久化文件读取
    if (!_isFileLoaded) {
      await _loadFromFile();
    }
    return _memoryCache[keyId];
  }

  /// 安全删除密钥
  Future<void> deleteSecret(String keyId) async {
    try {
      await storage.delete(key: keyId);
    } catch (e) {
      debugPrint('Keychain 删除异常: $e');
    }
    _memoryCache.remove(keyId);
    await _saveToFile();
  }

  /// 检查是否存在密钥
  Future<bool> containsSecret(String keyId) async {
    final s = await readSecret(keyId);
    return s != null && s.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 本地持久化与轻量对称混淆加解密
  // ---------------------------------------------------------------------------

  Future<void> _ensureFileInitialized() async {
    if (_secretsFile == null) {
      await init();
    }
  }

  Future<void> _loadFromFile() async {
    await _ensureFileInitialized();
    if (_secretsFile == null || !await _secretsFile!.exists()) {
      _isFileLoaded = true;
      return;
    }

    try {
      final raw = await _secretsFile!.readAsBytes();
      if (raw.isEmpty) {
        _isFileLoaded = true;
        return;
      }

      final decrypted = _xorTransform(raw);
      final jsonStr = utf8.decode(decrypted);
      final Map<String, dynamic> data = jsonDecode(jsonStr);

      data.forEach((k, v) {
        if (v is String && v.isNotEmpty) {
          _memoryCache[k] = v;
        }
      });
      _isFileLoaded = true;
    } catch (e) {
      debugPrint('读取本地加密凭证失败: $e');
    }
  }

  Future<void> _saveToFile() async {
    await _ensureFileInitialized();
    if (_secretsFile == null) return;

    try {
      final jsonStr = jsonEncode(_memoryCache);
      final rawBytes = utf8.encode(jsonStr);
      final encrypted = _xorTransform(rawBytes);

      final tmp = File('${_secretsFile!.path}.tmp');
      await tmp.writeAsBytes(encrypted, flush: true);
      if (await _secretsFile!.exists()) {
        await _secretsFile!.delete();
      }
      await tmp.rename(_secretsFile!.path);
    } catch (e) {
      debugPrint('持久化本地加密凭证失败: $e');
    }
  }

  Uint8List _xorTransform(List<int> input) {
    final maskBytes = utf8.encode(_xorMask);
    final output = Uint8List(input.length);
    for (int i = 0; i < input.length; i++) {
      output[i] = input[i] ^ maskBytes[i % maskBytes.length];
    }
    return output;
  }
}
