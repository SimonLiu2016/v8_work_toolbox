import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import '../../../services/app_paths.dart';

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

  /// 该密文文件预期所在的目录（用于在同目录下放置伴生文件，如自愈标记）。
  /// 仅在已确保文件存在后有效；调用前若未触发 `_ensureFile`，返回 null。
  File? get file => _file;

  /// 确保 `_file` 已解析到真实路径（不创建文件内容，仅解析路径）。
  /// 供消费方在读写前先确定目录，便于在同目录放置伴生文件。
  Future<void> ensureResolved() async => _ensureFile();

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final dir = _customRootDir ?? AppPaths.root;
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

  /// 失配残件备份：把当前密文文件 copy 为 `<name>.mismatch-yyyyMMdd-HHmmss`，
  /// 返回备份文件路径；原文件保持不动（由调用方随后重建覆盖）。
  /// copy 而非 rename——重建写盘失败的任何时刻残件都在盘上。
  Future<File?> backupMismatch({DateTime? at}) async {
    final f = await _ensureFile();
    if (!f.existsSync()) return null;
    final t = at ?? DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp =
        '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}';
    final backup = File('${f.path}.mismatch-$stamp');
    await f.copy(backup.path);
    return backup;
  }
}
