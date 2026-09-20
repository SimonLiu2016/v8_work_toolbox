import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Vault 密文整体结构异常
///
/// 两类互斥：
/// - [isIntegrityError]：布局损坏（长度不足等），与密钥无关的真损坏
/// - [isAuthFailure]：布局完整但 GCM 认证失败——密钥不匹配（失配）或文件被篡改，
///   上层据此走"失配自愈"而非"损坏 fail-fast"
class VaultCipherException implements Exception {
  final String message;
  final bool isIntegrityError;
  final bool isAuthFailure;

  VaultCipherException(
    this.message, {
    this.isIntegrityError = false,
    this.isAuthFailure = false,
  }) : assert(
          !(isIntegrityError && isAuthFailure),
          'isIntegrityError 与 isAuthFailure 互斥',
        );

  @override
  String toString() => 'VaultCipherException: $message';
}

/// AES-256-GCM 加解密封装（VaultCipher）
///
/// - 密钥：外部传入的 32 字节 DEK（由 KekManager 管理）
/// - nonce：每次加密新随机 12 字节（GCM nonce 复用是密码学灾难，绝不允许）
/// - AAD：固定版本标记，兼具防篡改认证与版本识别
/// - 布局：`nonce(12) || ciphertext || tag(16)`
class VaultCipher {
  VaultCipher({Random? random})
      : _random = random ?? Random.secure(),
        _algorithm = AesGcm.with256bits();

  static const int nonceLength = 12;
  static const int macLength = 16;
  static const String aadV1 = 'v8toolbox.vault.v1';

  final Random _random;
  final AesGcm _algorithm;

  /// 加密 UTF-8 明文，返回 `nonce(12) || ciphertext || mac(16)` 字节
  Future<Uint8List> encrypt(
    Uint8List dek,
    String plaintext, {
    String aad = aadV1,
  }) async {
    if (dek.length != 32) {
      throw ArgumentError('DEK 必须为 32 字节');
    }
    final nonce = _newNonce();
    final secretKey = SecretKeyData(dek);
    final secretBox = await _algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  /// 解密 `nonce(12) || ciphertext || mac(16)` 字节；认证失败抛 VaultCipherException
  Future<String> decrypt(
    Uint8List dek,
    Uint8List sealed, {
    String aad = aadV1,
  }) async {
    if (sealed.length <= nonceLength + macLength) {
      throw VaultCipherException('密文布局损坏（长度不足）', isIntegrityError: true);
    }
    if (dek.length != 32) {
      throw ArgumentError('DEK 必须为 32 字节');
    }
    final nonce = sealed.sublist(0, nonceLength);
    final mac = sealed.sublist(sealed.length - macLength);
    final cipherText = sealed.sublist(nonceLength, sealed.length - macLength);
    try {
      final clear = await _algorithm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: SecretKeyData(dek),
        aad: utf8.encode(aad),
      );
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      throw VaultCipherException(
        '密文认证失败：密钥不匹配（DEK 失配）或文件被篡改',
        isAuthFailure: true,
      );
    }
  }

  Uint8List _newNonce() {
    return Uint8List.fromList(
      List<int>.generate(nonceLength, (_) => _random.nextInt(256)),
    );
  }
}
