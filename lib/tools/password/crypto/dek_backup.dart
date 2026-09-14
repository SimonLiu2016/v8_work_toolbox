import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'kek_manager.dart';

/// DEK 备份导出/恢复（设计 D5：passphrase-wrapped）
///
/// 格式：`salt(32B) || nonce(12B) || ciphertext || mac(16B)`
/// KEK = PBKDF2-HMAC-SHA256(passphrase, salt, 200_000 iter)
/// 文件不含任何 vault 明文；口令不存储、不可恢复。
class DekBackup {
  DekBackup({Random? random}) : _random = random ?? Random.secure();

  static const int saltLength = 32;
  static const int nonceLength = 12;
  static const int macLength = 16;
  static const int pbkdf2Iterations = 200000;
  static const String magic = 'V8DEKBK1';

  final Random _random;
  final _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: pbkdf2Iterations,
    bits: 256,
  );
  final _aes = AesGcm.with256bits();

  /// 导出：用口令包裹 DEK，返回可写文件的字节
  Future<Uint8List> exportDek(Uint8List dek, String passphrase) async {
    if (dek.length != KekManager.dekLengthBytes) {
      throw ArgumentError('DEK 必须为 ${KekManager.dekLengthBytes} 字节');
    }
    if (passphrase.length < 8) {
      throw ArgumentError('口令至少 8 个字符');
    }

    final salt = Uint8List.fromList(
      List<int>.generate(saltLength, (_) => _random.nextInt(256)),
    );
    final kek = await _pbkdf2.deriveKey(
      secretKey: SecretKeyData(utf8.encode(passphrase)),
      nonce: salt,
    );

    final nonce = Uint8List.fromList(
      List<int>.generate(nonceLength, (_) => _random.nextInt(256)),
    );
    final box = await _aes.encrypt(
      dek,
      secretKey: kek,
      nonce: nonce,
      aad: utf8.encode(magic),
    );

    return Uint8List.fromList([
      ...utf8.encode(magic),
      ...salt,
      ...box.nonce,
      ...box.cipherText,
      ...box.mac.bytes,
    ]);
  }

  /// 恢复：从备份字节与口令解出 DEK；口令错误或数据损坏抛异常
  Future<Uint8List> importDek(Uint8List backup, String passphrase) async {
    final headerLength =
        magic.length + saltLength + nonceLength + macLength;
    if (backup.length <= headerLength) {
      throw const DekBackupException('备份文件损坏（长度不足）');
    }
    final fileMagic = utf8.decode(backup.sublist(0, magic.length));
    if (fileMagic != magic) {
      throw const DekBackupException('不是有效的 DEK 备份文件');
    }

    var offset = magic.length;
    final salt = backup.sublist(offset, offset + saltLength);
    offset += saltLength;
    final nonce = backup.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final mac = backup.sublist(backup.length - macLength);
    final cipherText = backup.sublist(offset, backup.length - macLength);

    final kek = await _pbkdf2.deriveKey(
      secretKey: SecretKeyData(utf8.encode(passphrase)),
      nonce: salt,
    );

    try {
      final clear = await _aes.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: kek,
        aad: utf8.encode(magic),
      );
      final dek = Uint8List.fromList(clear);
      if (dek.length != KekManager.dekLengthBytes) {
        throw const DekBackupException('备份内容异常（密钥长度不符）');
      }
      return dek;
    } on SecretBoxAuthenticationError {
      throw const DekBackupException('口令错误或备份已被篡改');
    }
  }
}

class DekBackupException implements Exception {
  final String message;
  const DekBackupException(this.message);

  @override
  String toString() => 'DekBackupException: $message';
}
