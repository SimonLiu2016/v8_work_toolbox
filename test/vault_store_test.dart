import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/password/vault_models.dart';
import 'package:V8WorkToolbox/tools/password/vault_store.dart';

class _TestKeychainBridge implements KeychainBridge {
  static final Map<String, String> store = {};

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  VaultStore freshStore() {
    return VaultStore(
      kekManager: KekManager(bridge: _TestKeychainBridge()),
      customRootDir: tempDir,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_vault_store_test_');
    _TestKeychainBridge.store.clear();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('CRUD 往返', () {
    test('创建 login 条目并可读回 secret', () async {
      final store = freshStore();
      final item = await store.create(
        type: VaultEntryType.login,
        title: 'GitHub',
        url: 'github.com',
        username: 'simon',
        secret: 's3cret-pass',
        tags: ['dev'],
      );

      expect(item.id, isNotEmpty);
      expect(store.items.length, 1);

      final secret = await store.readSecret(item.id);
      expect(secret.secret, 's3cret-pass');
    });

    test('创建 note 与 totp 条目', () async {
      final store = freshStore();
      final note = await store.create(
        type: VaultEntryType.note,
        title: 'Recovery Codes',
        secret: 'code1 code2 code3',
      );
      final totp = await store.create(
        type: VaultEntryType.totp,
        title: 'AWS MFA',
        totpSeed: 'JBSWY3DPEHPK3PXP',
      );

      expect((await store.readSecret(note.id)).secret, 'code1 code2 code3');
      expect((await store.readSecret(totp.id)).totpSeed, 'JBSWY3DPEHPK3PXP');
    });

    test('更新条目元数据与 secret，passwordUpdatedAt 随 secret 变化', () async {
      final store = freshStore();
      final item = await store.create(
        type: VaultEntryType.login,
        title: 'GitLab',
        secret: 'old-pass',
      );
      final originalUpdatedAt = item.passwordUpdatedAt;

      await Future.delayed(const Duration(milliseconds: 5));
      final updated = await store.update(item.id, title: 'GitLab CE');
      expect(updated.title, 'GitLab CE');
      expect(updated.passwordUpdatedAt, originalUpdatedAt);

      await Future.delayed(const Duration(milliseconds: 5));
      final updated2 = await store.update(item.id, secret: 'new-pass');
      expect(updated2.passwordUpdatedAt.isAfter(originalUpdatedAt), isTrue);
      expect((await store.readSecret(item.id)).secret, 'new-pass');
    });

    test('删除条目后 secret 一并清除', () async {
      final store = freshStore();
      final item = await store.create(
        type: VaultEntryType.login,
        title: 'ToDelete',
        secret: 'bye',
      );
      await store.delete(item.id);

      expect(store.items, isEmpty);

      // 新实例重载后 secret blob 中无残留
      final store2 = freshStore();
      await store2.load();
      expect(store2.items, isEmpty);
    });
  });

  group('持久化与分离原则', () {
    test('新实例重载后元数据与 secret 完整', () async {
      final store = freshStore();
      final item = await store.create(
        type: VaultEntryType.login,
        title: 'Persistent',
        username: 'user1',
        secret: 'persist-me',
      );

      final store2 = freshStore();
      await store2.load();
      expect(store2.items.length, 1);
      expect(store2.items.first.title, 'Persistent');
      expect((await store2.readSecret(item.id)).secret, 'persist-me');
    });

    test('元数据文件为明文 JSON 且不含 secret 值', () async {
      final store = freshStore();
      await store.create(
        type: VaultEntryType.login,
        title: 'MetaCheck',
        username: 'metauser',
        secret: 'super-secret-value-123',
      );

      final metaFile = File('${tempDir.path}/.vault.meta.json');
      expect(await metaFile.exists(), isTrue);
      final content = await metaFile.readAsString();
      expect(content.contains('MetaCheck'), isTrue);
      expect(content.contains('metauser'), isTrue);
      expect(content.contains('super-secret-value-123'), isFalse);
    });

    test('密文文件不含明文 secret', () async {
      final store = freshStore();
      await store.create(
        type: VaultEntryType.login,
        title: 'CipherCheck',
        secret: 'plaintext-marker-777',
      );

      final binFile = File('${tempDir.path}/.vault.bin');
      expect(await binFile.exists(), isTrue);
      final raw = await binFile.readAsBytes();
      final rawStr = String.fromCharCodes(raw);
      expect(rawStr.contains('plaintext-marker-777'), isFalse);
    });
  });

  group('搜索与标签', () {
    test('明文搜索 title/username/url，大小写不敏感', () async {
      final store = freshStore();
      await store.create(
        type: VaultEntryType.login,
        title: 'GitHub',
        username: 'Simon@Example.com',
        url: 'github.com',
      );
      await store.create(
        type: VaultEntryType.login,
        title: 'GitLab',
        username: 'work',
        url: 'gitlab.com',
      );

      expect(store.search('github').length, 1);
      expect(store.search('SIMON').length, 1);
      expect(store.search('git').length, 2);
      expect(store.search('').length, 2);
    });

    test('标签过滤与计数', () async {
      final store = freshStore();
      await store.create(
        type: VaultEntryType.login,
        title: 'A',
        tags: ['dev', 'work'],
      );
      await store.create(
        type: VaultEntryType.login,
        title: 'B',
        tags: ['dev'],
      );
      await store.create(type: VaultEntryType.login, title: 'C');

      final counts = store.tagCounts();
      expect(counts['dev'], 2);
      expect(counts['work'], 1);

      expect(store.search('', tag: 'work').length, 1);
      expect(store.search('', tag: 'dev').length, 2);
    });
  });

  group('会话控制', () {
    test('lock 清空内存缓存但磁盘数据完好', () async {
      final store = freshStore();
      final item = await store.create(
        type: VaultEntryType.login,
        title: 'LockTest',
        secret: 'lock-secret',
      );
      await store.readSecret(item.id);
      expect(store.hasSecretsInMemory, isTrue);

      store.lock();
      expect(store.hasSecretsInMemory, isFalse);

      // 磁盘数据完好：新实例可读
      final store2 = freshStore();
      await store2.load();
      expect((await store2.readSecret(item.id)).secret, 'lock-secret');
    });
  });
}
