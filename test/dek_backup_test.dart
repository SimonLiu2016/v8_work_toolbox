import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/crypto/dek_backup.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List makeDek([int seed = 0]) {
    return Uint8List.fromList(List<int>.generate(32, (i) => (i + seed) % 256));
  }

  group('DekBackup 导出/恢复', () {
    test('导出后用同一口令恢复 DEK', () async {
      final backup = DekBackup();
      final dek = makeDek();
      final exported = await backup.exportDek(dek, 'test-passphrase-1');

      final restored = await backup.importDek(exported, 'test-passphrase-1');
      expect(restored, equals(dek));
    });

    test('错误口令抛 DekBackupException', () async {
      final backup = DekBackup();
      final exported = await backup.exportDek(makeDek(), 'correct-pass');
      expect(
        () => backup.importDek(exported, 'wrong-pass-999'),
        throwsA(isA<DekBackupException>().having(
          (e) => e.message,
          'message',
          contains('口令错误'),
        )),
      );
    });

    test('备份文件不含 DEK 明文', () async {
      final backup = DekBackup();
      final dek = makeDek(77);
      final exported = await backup.exportDek(dek, 'test-passphrase-1');

      // DEK 的连续 8 字节片段不应出现在备份中（salt 区域之后的密文部分）
      final dekSegment = dek.sublist(4, 12);
      bool found = false;
      for (var i = 0; i + 8 <= exported.length; i++) {
        var match = true;
        for (var j = 0; j < 8; j++) {
          if (exported[i + j] != dekSegment[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          found = true;
          break;
        }
      }
      expect(found, isFalse);
    });

    test('两次导出产生不同密文（随机 salt/nonce）', () async {
      final backup = DekBackup();
      final dek = makeDek();
      final a = await backup.exportDek(dek, 'test-passphrase-1');
      final b = await backup.exportDek(dek, 'test-passphrase-1');
      expect(a, isNot(equals(b)));
      // 但两者都能恢复同一 DEK
      expect(await backup.importDek(a, 'test-passphrase-1'), equals(dek));
      expect(await backup.importDek(b, 'test-passphrase-1'), equals(dek));
    });

    test('短口令拒绝导出', () async {
      expect(
        () => DekBackup().exportDek(makeDek(), 'short'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('非 32 字节 DEK 拒绝导出', () async {
      expect(
        () => DekBackup().exportDek(Uint8List.fromList([1, 2, 3]), 'test-pass-123'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('篡改备份抛异常', () async {
      final backup = DekBackup();
      final exported = await backup.exportDek(makeDek(), 'test-passphrase-1');
      exported[exported.length - 1] ^= 0xFF;
      expect(
        () => backup.importDek(exported, 'test-passphrase-1'),
        throwsA(isA<DekBackupException>()),
      );
    });

    test('magic 头不符拒绝', () async {
      final backup = DekBackup();
      final exported = await backup.exportDek(makeDek(), 'test-passphrase-1');
      exported[0] = 0x00;
      expect(
        () => backup.importDek(exported, 'test-passphrase-1'),
        throwsA(isA<DekBackupException>().having(
          (e) => e.message,
          'message',
          contains('不是有效'),
        )),
      );
    });

    test('长度不足拒绝', () async {
      expect(
        () => DekBackup().importDek(Uint8List.fromList([1, 2, 3]), 'test-pass-123'),
        throwsA(isA<DekBackupException>()),
      );
    });
  });

  group('DEK 长度常量一致性', () {
    test('KekManager.dekLengthBytes 为 32', () {
      expect(KekManager.dekLengthBytes, 32);
    });
  });
}
