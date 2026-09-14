import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

/// KeychainBridge 失败模拟
class _FailingBridge implements KeychainBridge {
  final Object? readError;
  final bool failWrite;

  _FailingBridge({this.readError, this.failWrite = false});

  @override
  Future<String?> read({required String service, required String account}) async {
    final e = readError;
    if (e != null) throw e;
    return null;
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    if (failWrite) throw StateError('钥匙串写入被拒绝');
  }

  @override
  Future<void> delete({required String service, required String account}) async {}
}

class _MemoryBridge implements KeychainBridge {
  final Map<String, String> store = {};

  @override
  Future<String?> read({required String service, required String account}) async {
    return store['$service/$account'];
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    store['$service/$account'] = value;
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    store.remove('$service/$account');
  }
}

class _MemoryFileBridge implements DekFileBridge {
  String? content;
  bool failWrite = false;
  int? perms = 0x180; // 0600

  @override
  Future<String?> read() async => content;

  @override
  Future<void> write(String value) async {
    if (failWrite) throw StateError('file write failed');
    content = value;
  }

  @override
  Future<void> delete() async {
    content = null;
  }

  @override
  Future<int?> permissions() async => perms;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KekManager 首次生成与持久化', () {
    test('首次 getOrCreateDek 生成 32 字节 DEK 并写入 Keychain', () async {
      final bridge = _MemoryBridge();
      final manager = KekManager(bridge: bridge, fileBridge: _MemoryFileBridge());

      final dek = await manager.getOrCreateDek();

      expect(dek.length, KekManager.dekLengthBytes);
      expect(bridge.store['com.v8worktoolbox.vault.dek/dek'], startsWith('v8dek1:'));
      expect(manager.source, DekSource.keychain);
    });

    test('持久化后新实例读回同一 DEK（非重新生成）', () async {
      final bridge = _MemoryBridge();
      final first = await KekManager(bridge: bridge, fileBridge: _MemoryFileBridge())
          .getOrCreateDek();
      final second = await KekManager(bridge: bridge, fileBridge: _MemoryFileBridge())
          .getOrCreateDek();

      expect(second, equals(first));
      expect(bridge.store.length, 1);
    });
  });

  group('文件回退（Keychain 写失败）', () {
    test('Keychain 写失败时写入文件并标记 file 来源', () async {
      final bridge = _FailingBridge(failWrite: true);
      final fileBridge = _MemoryFileBridge();
      final manager = KekManager(bridge: bridge, fileBridge: fileBridge);

      final dek = await manager.getOrCreateDek();

      expect(dek.length, 32);
      expect(fileBridge.content, startsWith('v8dek1:'));
      expect(manager.source, DekSource.file);
    });

    test('重启后从文件读回同一 DEK', () async {
      final bridge = _FailingBridge(failWrite: true);
      final fileBridge = _MemoryFileBridge();

      final first = await KekManager(bridge: bridge, fileBridge: fileBridge)
          .getOrCreateDek();
      final second = await KekManager(bridge: bridge, fileBridge: fileBridge)
          .getOrCreateDek();

      expect(second, equals(first));
    });

    test('Keychain 恢复可写时自动迁移文件 DEK 回 Keychain', () async {
      final fileBridge = _MemoryFileBridge();
      // 第一阶段：Keychain 写失败 → 落文件
      final failBridge = _FailingBridge(failWrite: true);
      final dek = await KekManager(bridge: failBridge, fileBridge: fileBridge)
          .getOrCreateDek();
      expect(fileBridge.content, isNotNull);

      // 第二阶段：Keychain 恢复 → 新实例读文件后迁移
      final okBridge = _MemoryBridge();
      final manager = KekManager(bridge: okBridge, fileBridge: fileBridge);
      final restored = await manager.getOrCreateDek();

      expect(restored, equals(dek));
      expect(manager.source, DekSource.keychain);
      expect(okBridge.store['com.v8worktoolbox.vault.dek/dek'], startsWith('v8dek1:'));
      expect(fileBridge.content, isNull); // 文件已删除
    });
  });

  group('fail-fast', () {
    test('Keychain 与文件均失败时抛 DekUnavailableException', () async {
      final manager = KekManager(
        bridge: _FailingBridge(failWrite: true),
        fileBridge: _MemoryFileBridge()..failWrite = true,
      );
      await expectLater(
        manager.getOrCreateDek(),
        throwsA(isA<DekUnavailableException>()),
      );
    });

    test('缺失 DEK 时 getDek 抛异常且文案含恢复路径', () async {
      final manager = KekManager(
        bridge: _MemoryBridge(),
        fileBridge: _MemoryFileBridge(),
      );
      try {
        await manager.getDek();
        fail('应抛出异常');
      } on DekUnavailableException catch (e) {
        expect(e.message, contains('备份恢复'));
      }
    });

    test('损坏的文件 DEK 抛异常', () async {
      final fileBridge = _MemoryFileBridge()..content = 'v8dek1:!!!bad!!!';
      final manager = KekManager(
        bridge: _MemoryBridge(),
        fileBridge: fileBridge,
      );
      await expectLater(manager.getDek(), throwsA(isA<DekUnavailableException>()));
    });

    test('正确 base64 但长度不足 32 字节的 DEK 抛异常', () async {
      final fileBridge = _MemoryFileBridge()
        ..content = 'v8dek1:${base64UrlNoPad(List<int>.generate(9, (i) => i))}';
      final manager = KekManager(
        bridge: _MemoryBridge(),
        fileBridge: fileBridge,
      );
      await expectLater(manager.getDek(), throwsA(isA<DekUnavailableException>()));
    });
  });

  group('DEK 导入（备份恢复路径）', () {
    test('importDek Keychain 不可写时落文件', () async {
      final bridge = _FailingBridge(failWrite: true);
      final fileBridge = _MemoryFileBridge();
      final dek = Uint8List.fromList(List<int>.generate(32, (i) => i));

      await KekManager(bridge: bridge, fileBridge: fileBridge).importDek(dek);

      expect(fileBridge.content, startsWith('v8dek1:'));
      final readBack = await KekManager(bridge: bridge, fileBridge: fileBridge)
          .getDek();
      expect(readBack, equals(dek));
    });

    test('importDek 拒绝非 32 字节', () async {
      final manager = KekManager(
        bridge: _MemoryBridge(),
        fileBridge: _MemoryFileBridge(),
      );
      await expectLater(
        () => manager.importDek(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('锁定与销毁', () {
    test('lock 清空内存缓存但保留持久数据', () async {
      final bridge = _MemoryBridge();
      final manager = KekManager(bridge: bridge, fileBridge: _MemoryFileBridge());
      final dek = await manager.getOrCreateDek();

      manager.lock();
      expect(manager.hasCachedDek, isFalse);

      final restored = await manager.getOrCreateDek();
      expect(restored, equals(dek));
    });

    test('destroyDek 删除 Keychain 与文件', () async {
      final bridge = _FailingBridge(failWrite: true);
      final fileBridge = _MemoryFileBridge();
      final manager = KekManager(bridge: bridge, fileBridge: fileBridge);
      await manager.getOrCreateDek();
      expect(fileBridge.content, isNotNull);

      await manager.destroyDek();

      expect(fileBridge.content, isNull);
      expect(manager.hasCachedDek, isFalse);
      expect(manager.source, DekSource.none);
    });
  });

  group('真实文件桥（0600 权限）', () {
    test('DefaultDekFileBridge 写入后权限为 0600', () async {
      final dir = await Directory.systemTemp.createTemp('v8_dek_file_test_');
      try {
        final bridge = DefaultDekFileBridge(customRootDir: dir);
        await bridge.write('v8dek1:test-value');

        final perms = await bridge.permissions();
        expect(perms, 0x180); // 0600 octal = 384 decimal = 0x180

        final readBack = await bridge.read();
        expect(readBack, 'v8dek1:test-value');

        await bridge.delete();
        expect(await bridge.read(), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  group('base64url 编解码', () {
    test('无 padding 往返，且不含 + / =', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (i) => (i * 13 + 7) % 256),
      );
      final encoded = base64UrlNoPad(bytes);

      expect(encoded.contains('='), isFalse);
      expect(encoded.contains('+'), isFalse);
      expect(encoded.contains('/'), isFalse);
      expect(base64UrlDecodeNoPad(encoded), equals(bytes));
    });

    test('非法字符抛 FormatException', () {
      expect(() => base64UrlDecodeNoPad('ab@cd'), throwsA(isA<FormatException>()));
    });
  });
}
