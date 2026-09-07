import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/ai_service.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_ai_config_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('KeychainService Tests', () {
    test('密钥保存、读取与删除正常', () async {
      final keyService = KeychainService.instance;
      await keyService.init(customRootDir: tempDir);
      await keyService.writeSecret('test_key_1', 'sk-test-secret-value');

      final readVal = await keyService.readSecret('test_key_1');
      expect(readVal, 'sk-test-secret-value');

      final exists = await keyService.containsSecret('test_key_1');
      expect(exists, isTrue);

      await keyService.deleteSecret('test_key_1');
      final afterDelete = await keyService.readSecret('test_key_1');
      expect(afterDelete, isNull);
    });

    test('模拟重启：当内存被清空时，从本地安全文件 .secrets.dat 正确恢复密钥', () async {
      final keyService = KeychainService.instance;
      await keyService.init(customRootDir: tempDir);
      await keyService.writeSecret('key_persisted_test', 'sk-durable-secret-999');

      // 验证 .secrets.dat 文件已在磁盘上生成
      final secretsFile = File('${tempDir.path}/.secrets.dat');
      expect(await secretsFile.exists(), isTrue);

      // 模拟重启：重新初始化 KeychainService 并读取
      await keyService.init(customRootDir: tempDir);
      final restored = await keyService.readSecret('key_persisted_test');
      expect(restored, 'sk-durable-secret-999');
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.1: SlotCandidate 序列化/反序列化
  // ---------------------------------------------------------------------------
  group('SlotCandidate Serialization Tests', () {
    test('toJson / fromJson 往返一致', () {
      const candidate = SlotCandidate(
        providerId: 'provider_abc',
        model: 'gpt-4o',
        priority: 2,
      );

      final json = candidate.toJson();
      expect(json['providerId'], 'provider_abc');
      expect(json['model'], 'gpt-4o');
      expect(json['priority'], 2);

      final restored = SlotCandidate.fromJson(json);
      expect(restored.providerId, 'provider_abc');
      expect(restored.model, 'gpt-4o');
      expect(restored.priority, 2);
    });

    test('fromJson 缺少字段时使用默认值', () {
      final restored = SlotCandidate.fromJson({});
      expect(restored.providerId, '');
      expect(restored.model, '');
      expect(restored.priority, 0);
    });

    test('copyWith 正确覆盖字段', () {
      const original = SlotCandidate(providerId: 'a', model: 'b', priority: 0);
      final updated = original.copyWith(priority: 5, model: 'new-model');
      expect(updated.providerId, 'a');
      expect(updated.model, 'new-model');
      expect(updated.priority, 5);
    });

    test('equality 基于 providerId 和 model', () {
      const a = SlotCandidate(providerId: 'p1', model: 'm1', priority: 0);
      const b = SlotCandidate(providerId: 'p1', model: 'm1', priority: 5);
      const c = SlotCandidate(providerId: 'p1', model: 'm2', priority: 0);
      expect(a, equals(b)); // 同 provider+model，不同 priority → 相等
      expect(a, isNot(equals(c))); // 不同 model → 不等
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.2: AiConfigStore 旧格式自动迁移
  // ---------------------------------------------------------------------------
  group('AiConfigStore Legacy Format Migration Tests', () {
    test('旧格式 defaultSlots 自动迁移为候选列表', () async {
      // 手动写入旧格式配置文件
      final configFile = File('${tempDir.path}/ai_config.json');
      final legacyConfig = {
        'providers': [
          {
            'id': 'legacy_provider',
            'name': 'Legacy Provider',
            'protocol': 'openai',
            'baseUrl': 'https://api.test.com',
            'keychainKeyId': 'key_legacy',
            'enabled': true,
            'models': {'text': ['gpt-4o'], 'multimodal': [], 'tts': [], 'stt': []},
          },
        ],
        'defaultSlots': {
          'text': {'providerId': 'legacy_provider', 'model': 'gpt-4o'},
          'multimodal': {'providerId': '', 'model': ''},
          'tts': {'providerId': '', 'model': ''},
          'stt': {'providerId': '', 'model': ''},
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(legacyConfig));

      // 加载配置，应触发自动迁移
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      // 验证迁移结果：text 槽位应有一个候选
      final textCandidates = store.slotBindings['text']!;
      expect(textCandidates.length, 1);
      expect(textCandidates.first.providerId, 'legacy_provider');
      expect(textCandidates.first.model, 'gpt-4o');
      expect(textCandidates.first.priority, 0);

      // 空绑定应迁移为空列表
      expect(store.slotBindings['multimodal'], isEmpty);
      expect(store.slotBindings['tts'], isEmpty);

      // 验证重新保存后格式为新格式
      final savedText = await configFile.readAsString();
      final savedJson = jsonDecode(savedText) as Map<String, dynamic>;
      final savedSlots = savedJson['defaultSlots'] as Map<String, dynamic>;
      expect(savedSlots['text'], isList);
      expect((savedSlots['text'] as List).first['providerId'], 'legacy_provider');
    });

    test('新格式文件直接加载无迁移', () async {
      final configFile = File('${tempDir.path}/ai_config.json');
      final newConfig = {
        'providers': [],
        'defaultSlots': {
          'text': [
            {'providerId': 'p1', 'model': 'm1', 'priority': 0},
            {'providerId': 'p2', 'model': 'm2', 'priority': 1},
          ],
          'multimodal': [],
          'tts': [],
          'stt': [],
        },
        'mcpServers': [],
      };
      await configFile.writeAsString(const JsonEncoder.withIndent('  ').convert(newConfig));

      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      final textCandidates = store.slotBindings['text']!;
      expect(textCandidates.length, 2);
      expect(textCandidates[0].providerId, 'p1');
      expect(textCandidates[1].providerId, 'p2');
    });
  });

  group('AiConfigStore Slot Candidate CRUD Tests', () {
    test('addSlotCandidate 追加到最低优先级', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      await store.addSlotCandidate('text', 'p1', 'm1');
      await store.addSlotCandidate('text', 'p2', 'm2');

      final candidates = store.slotBindings['text']!;
      expect(candidates.length, 2);
      expect(candidates[0].providerId, 'p1');
      expect(candidates[0].priority, 0);
      expect(candidates[1].providerId, 'p2');
      expect(candidates[1].priority, 1);
    });

    test('removeSlotCandidate 移除并重新分配优先级', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      await store.addSlotCandidate('text', 'p1', 'm1');
      await store.addSlotCandidate('text', 'p2', 'm2');
      await store.addSlotCandidate('text', 'p3', 'm3');
      await store.removeSlotCandidate('text', 1); // 移除 p2

      final candidates = store.slotBindings['text']!;
      expect(candidates.length, 2);
      expect(candidates[0].providerId, 'p1');
      expect(candidates[0].priority, 0);
      expect(candidates[1].providerId, 'p3');
      expect(candidates[1].priority, 1);
    });

    test('reorderSlotCandidates 拖拽排序', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      await store.addSlotCandidate('text', 'p1', 'm1');
      await store.addSlotCandidate('text', 'p2', 'm2');
      await store.addSlotCandidate('text', 'p3', 'm3');

      // 将 p3 (index 2) 拖到 index 0 位置
      await store.reorderSlotCandidates('text', 2, 0);

      final candidates = store.slotBindings['text']!;
      expect(candidates[0].providerId, 'p3');
      expect(candidates[1].providerId, 'p1');
      expect(candidates[2].providerId, 'p2');
    });

    test('deleteProvider 清理所有槽位中的引用', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      const provider = AiProviderConfig(
        id: 'p_to_delete',
        name: '待删除供应商',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.test.com',
        keychainKeyId: 'key_delete_me',
      );
      await store.saveProvider(provider, apiKey: 'sk-val');
      await store.addSlotCandidate('text', 'p_to_delete', 'm1');
      await store.addSlotCandidate('text', 'other_provider', 'm2');
      await store.addSlotCandidate('multimodal', 'p_to_delete', 'mm1');

      await store.deleteProvider('p_to_delete');
      expect(store.providers, isEmpty);
      // text 应只剩 other_provider
      expect(store.slotBindings['text']!.length, 1);
      expect(store.slotBindings['text']!.first.providerId, 'other_provider');
      // multimodal 应为空
      expect(store.slotBindings['multimodal'], isEmpty);
    });

    test('setSlotBinding (deprecated) 设置单候选', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      await store.setSlotBinding('text', 'p1', 'gpt-4o');
      final candidates = store.slotBindings['text']!;
      expect(candidates.length, 1);
      expect(candidates.first.providerId, 'p1');
      expect(candidates.first.model, 'gpt-4o');

      // 空 providerId → 清空列表
      await store.setSlotBinding('text', '', '');
      expect(store.slotBindings['text'], isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.3: ProviderHealthState 冷却窗口逻辑
  // ---------------------------------------------------------------------------
  group('ProviderHealthState Cooldown Tests', () {
    test('冷却窗口内跳过不健康供应商', () {
      final service = AiService.instance;
      service.cooldownDuration = const Duration(seconds: 60);

      // 初始：未知供应商应视为健康
      expect(service.getProviderHealth('unknown'), isNull);

      // 标记不健康
      service.markProviderUnhealthy('test_p', 'connection refused');
      final health = service.getProviderHealth('test_p')!;
      expect(health.isHealthy, isFalse);
      expect(health.lastError, 'connection refused');
      expect(health.failureCount, 1);

      // 冷却窗口内应返回 false
      expect(service.isProviderHealthy('test_p'), isFalse);
    });

    test('冷却过期后重新尝试', () {
      final service = AiService.instance;
      service.cooldownDuration = Duration.zero; // 立即过期

      service.markProviderUnhealthy('test_p2', 'timeout');
      // 冷却为 0，应立即可用
      expect(service.isProviderHealthy('test_p2'), isTrue);
    });

    test('成功后重置健康状态', () {
      final service = AiService.instance;
      service.cooldownDuration = const Duration(seconds: 60);

      service.markProviderUnhealthy('test_p3', 'error');
      expect(service.getProviderHealth('test_p3')!.isHealthy, isFalse);

      service.markProviderHealthy('test_p3');
      expect(service.getProviderHealth('test_p3')!.isHealthy, isTrue);
      expect(service.getProviderHealth('test_p3')!.failureCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.5: SlotUnavailableException
  // ---------------------------------------------------------------------------
  group('SlotUnavailableException Tests', () {
    test('零候选场景', () {
      const ex = SlotUnavailableException(
        slotName: 'tts',
        candidateCount: 0,
        candidateErrors: [],
      );
      final msg = ex.toString();
      expect(msg, contains('tts'));
      expect(msg, contains('无可用候选'));
    });

    test('全部失败场景', () {
      const ex = SlotUnavailableException(
        slotName: 'text',
        candidateCount: 2,
        candidateErrors: ['timeout', 'invalid key'],
      );
      final msg = ex.toString();
      expect(msg, contains('text'));
      expect(msg, contains('2'));
      expect(msg, contains('timeout'));
      expect(msg, contains('invalid key'));
    });
  });
}
