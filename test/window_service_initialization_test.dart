import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/main.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';
import 'package:V8WorkToolbox/tools/password/vault_store.dart';

/// 窗口服务初始化清单测试。
///
/// 这些测试防的是「子窗口进程漏初始化平台级单例」这类静默失效：单例状态是
/// 进程级的，每个 `desktop_multi_window` 子窗口都会完整重跑 `main()`，漏一项
/// 的后果是该功能在子窗口里表现为「配置为空」，而同机主窗口一切正常
/// （笔记本子窗口曾因此报「槽位 "text" 无可用候选供应商」）。
class _TestKeychainBridge implements KeychainBridge {
  static final Map<String, String> store = {};

  @override
  Future<String?> read({
    required String service,
    required String account,
  }) async {
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
  Future<void> delete({
    required String service,
    required String account,
  }) async {
    store.remove('$service/$account');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_window_services_test_');
    _TestKeychainBridge.store.clear();
    KeychainService.instance.setKekManagerForTesting(
      KekManager(bridge: _TestKeychainBridge()),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// 写入一份与主窗口等价的配置：一个可用 provider + text 槽位绑定。
  Future<void> seedConfig(Directory dir) async {
    final configFile = File('${dir.path}/ai_config.json');
    await configFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'providers': [
          {
            'id': 'provider_test',
            'name': 'Test Provider',
            'protocol': 'openai',
            'baseUrl': 'https://api.test.local/v1',
            'keychainKeyId': 'key_provider_test',
            'enabled': true,
            'models': {
              'text': ['test-model'],
              'multimodal': [],
              'tts': [],
              'stt': [],
            },
          },
        ],
        'defaultSlots': {
          'text': [
            {
              'providerId': 'provider_test',
              'model': 'test-model',
              'priority': 0,
            },
          ],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      }),
    );
  }

  group('窗口必需服务清单', () {
    test('notebook 子窗口清单覆盖 AI 与代理通道', () {
      final names = WindowServices.requiredNames(WindowKind.notebook);
      expect(
        names,
        containsAll([
          'SettingsStore',
          'ProxySettings',
          'AiConfigStore',
          'NoteStore',
        ]),
      );
    });

    test('单篇笔记子窗口同样覆盖 AI（编辑器可打开整理弹窗）', () {
      final names = WindowServices.requiredNames(WindowKind.singleNote);
      expect(
        names,
        containsAll([
          'SettingsStore',
          'ProxySettings',
          'AiConfigStore',
          'NoteStore',
        ]),
      );
    });

    test('密码工具子窗口不声明 AI 服务（本地密码库不消费 AI），但声明基础设施 AppPaths 与 SettingsStore', () {
      final names = WindowServices.requiredNames(WindowKind.passwordVault);
      // SettingsStore：该窗口渲染 themed MaterialApp，必须读到持久化 themeMode。
      expect(names, ['AppPaths', 'SettingsStore']);
      expect(names, isNot(contains('AiConfigStore')));
      expect(names, isNot(contains('ProxySettings')));
      expect(names, isNot(contains('NoteStore')));
    });

    test('密码工具子窗口 initFor 后 AppPaths 就绪且 VaultStore.load 可正常执行', () async {
      AppPaths.resetForTesting();
      expect(AppPaths.isInitialized, isFalse);

      await WindowServices.initFor(WindowKind.passwordVault);

      expect(AppPaths.isInitialized, isTrue);
      expect(() => AppPaths.root, returnsNormally);

      final vaultDir = await Directory.systemTemp.createTemp('v8_vault_subwindow_test_');
      try {
        AppPaths.overrideRootForTesting(vaultDir);
        final store = VaultStore();
        await store.load();
        expect(store.isLoaded, isTrue);
      } finally {
        AppPaths.resetForTesting();
        if (await vaultDir.exists()) {
          await vaultDir.delete(recursive: true);
        }
      }
    });

    test('主窗口清单是各子窗口清单的超集', () {
      final mainNames = WindowServices.requiredNames(WindowKind.main);
      for (final kind in [
        WindowKind.notebook,
        WindowKind.singleNote,
        WindowKind.passwordVault,
        WindowKind.opsTool,
      ]) {
        for (final name in WindowServices.requiredNames(kind)) {
          expect(mainNames, contains(name), reason: '主窗口缺少 $name');
        }
      }
    });

    test('清单按拓扑序：SettingsStore 在 ProxySettings 之前', () {
      final names = WindowServices.requiredNames(WindowKind.notebook);
      expect(
        names.indexOf('SettingsStore'),
        lessThan(names.indexOf('ProxySettings')),
      );
    });

    test('清单覆盖全部 WindowKind，新增窗口类型不会漏声明', () {
      for (final kind in WindowKind.values) {
        expect(
          () => WindowServices.requiredNames(kind),
          returnsNormally,
          reason: '${kind.name} 未在必需服务清单中声明',
        );
      }
    });
  });

  group('子窗口槽位解析', () {
    test('初始化后槽位绑定可解析（不再报无可用候选）', () async {
      await seedConfig(tempDir);
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      expect(store.isInitialized, isTrue);
      expect(store.uninitializedReason, isNull);

      final candidates = store.slotBindings['text']!;
      expect(candidates, isNotEmpty);
      expect(candidates.first.providerId, 'provider_test');
      expect(candidates.first.model, 'test-model');
    });

    test('未初始化时错误消息指明初始化缺失，而非「请添加绑定」', () async {
      final store = AiConfigStore.instance;
      // 不调用 init —— 模拟子窗口进程漏掉初始化的状态。
      // 注意：若前一个测试已 init 过同一单例，这里显式重置状态。
      await store.resetForTesting();

      expect(store.isInitialized, isFalse);
      expect(store.uninitializedReason, isNotNull);
      expect(store.uninitializedReason, contains('尚未初始化'));

      // 槽位路由在候选为空时应带上该原因，而非给出错的指引。
      Object? caught;
      try {
        await AiService.instance.chat(
          slot: 'text',
          messages: [
            {'role': 'user', 'content': 'ping'},
          ],
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<SlotUnavailableException>());
      final ex = caught as SlotUnavailableException;
      expect(ex.candidateCount, 0);
      expect(ex.isConfigNotReady, isTrue);
      expect(ex.toString(), contains('尚未初始化'));
      expect(ex.toString(), isNot(contains('请在 AI 配置中为该槽位添加')));
    });

    test('配置已初始化但槽位为空时，错误消息指向「请添加绑定」', () async {
      // 写一份 text 槽位为空的合法配置。
      final configFile = File('${tempDir.path}/ai_config.json');
      await configFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'providers': [],
          'defaultSlots': {'text': [], 'multimodal': [], 'tts': [], 'stt': []},
          'mcpServers': [],
        }),
      );

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      expect(store.isInitialized, isTrue);
      expect(store.slotBindings['text'], isEmpty);

      Object? caught;
      try {
        await AiService.instance.chat(
          slot: 'text',
          messages: [
            {'role': 'user', 'content': 'ping'},
          ],
        );
      } catch (e) {
        caught = e;
      }

      expect(caught, isA<SlotUnavailableException>());
      final ex = caught as SlotUnavailableException;
      expect(ex.isConfigNotReady, isFalse);
      expect(ex.toString(), contains('请在 AI 配置中为该槽位添加'));
    });

    test('配置损坏时保留失败原因，不与「未绑定」混淆', () async {
      final configFile = File('${tempDir.path}/ai_config.json');
      await configFile.writeAsString('这不是合法 JSON');

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // 配置损坏是真实的加载失败：原因必须被保留下来。
      expect(store.lastInitError, isNotNull);
      expect(store.lastInitError, contains('ai_config.json'));
      // 但仍回落默认值以保证功能可继续（不阻断启动）。
      expect(store.slotBindings.containsKey('text'), isTrue);

      final reason = store.uninitializedReason;
      expect(reason, isNotNull);
      expect(reason, contains('ai_config.json'));
    });
  });
}
