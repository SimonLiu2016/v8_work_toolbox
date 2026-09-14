import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vault_cipher.dart';

/// 密文文件存储（VaultFileStore）
///
/// - 单文件 `.vault.bin`：`nonce || ciphertext || tag` 原始字节
/// - 原子写：tmp + flush + rename，崩溃不损坏旧数据
/// - 篡改/损坏时由 VaultCipher 抛完整性错误
class VaultFileStore {
  VaultFileStore({Directory? customRootDir, String fileName = defaultFileName})
      : _customRootDir = customRootDir,
        _fileName = fileName;

  static const String defaultFileName = '.vault.bin';

  final Directory? _customRootDir;
  final String _fileName;
  File? _file;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    Directory dir;
    if (_customRootDir != null) {
      dir = _customRootDir;
    } else {
      final home = Platform.environment['HOME'];
      if (Platform.isMacOS && home != null && home.isNotEmpty) {
        dir = Directory(
          p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'),
        );
      } else {
        final appSupport = await getApplicationSupportDirectory();
        dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
      }
    }
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _file = File(p.join(dir.path, _fileName));
    return _file!;
  }

  Future<bool> exists() async {
    final f = await _ensureFile();
    return f.existsSync();
  }

  Future<Uint8List?> read() async {
    final f = await _ensureFile();
    if (!f.existsSync()) return null;
    final raw = await f.readAsBytes();
    if (raw.isEmpty) return null;
    return Uint8List.fromList(raw);
  }

  Future<void> write(Uint8List sealed) async {
    final f = await _ensureFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(sealed, flush: true);
    if (f.existsSync()) {
      await f.delete();
    }
    await tmp.rename(f.path);
  }

  /// 读取并解密（便捷方法）；文件缺失返回 null，认证失败抛完整性错误
  Future<String?> readDecrypted(VaultCipher cipher, Uint8List dek) async {
    final sealed = await read();
    if (sealed == null) return null;
    try {
      return await cipher.decrypt(dek, sealed);
    } on VaultCipherException catch (e) {
      if (e.isIntegrityError) rethrow;
      rethrow;
    }
  }

  /// 加密并原子写入（便捷方法）
  Future<void> writeEncrypted(
    VaultCipher cipher,
    Uint8List dek,
    String plaintext,
  ) async {
    final sealed = await cipher.encrypt(dek, plaintext);
    await write(sealed);
  }

  /// JSON 明文编码便捷方法（供上层序列化 vault 数据）
  static String encodeJson(Object? data) => jsonEncode(data);

  static Object? decodeJson(String s) => jsonDecode(s);

  /// 彻底删除密文文件（wipe 场景）
  Future<void> destroy() async {
    final f = await _ensureFile();
    if (f.existsSync()) {
      await f.delete();
    }
    _file = null;
  }
}
