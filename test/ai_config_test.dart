import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
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

  group('AiConfigStore Persistence Tests', () {
    test('保存供应商并持久化至 ai_config.json', () async {
      final store = AiConfigStore.instance;
      await store.init(customRootDir: tempDir);

      const provider = AiProviderConfig(
        id: 'openai_test',
        name: 'OpenAI 官方',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com/v1',
        keychainKeyId: 'key_openai_test',
        textModels: ['gpt-4o', 'gpt-4o-mini'],
      );

      await store.saveProvider(provider, apiKey: 'sk-secret-key-123');

      expect(store.providers.length, 1);
      expect(store.providers.first.name, 'OpenAI 官方');
      expect(store.providers.first.textModels, contains('gpt-4o'));

      // 验证 Keychain 保存成功
      final key = await KeychainService.instance.readSecret('key_openai_test');
      expect(key, 'sk-secret-key-123');

      // 绑定全局能力槽位
      await store.setSlotBinding('text', 'openai_test', 'gpt-4o');
      expect(store.slotBindings['text']?['providerId'], 'openai_test');
      expect(store.slotBindings['text']?['model'], 'gpt-4o');

      // 添加外部 MCP 客户端
      const mcp = McpClientConfig(
        id: 'mcp_fs',
        name: 'Filesystem MCP',
        transport: 'stdio',
        endpointOrCommand: 'npx -y @modelcontextprotocol/server-filesystem',
      );
      await store.saveMcpClient(mcp);
      expect(store.mcpClients.length, 1);

      // 重新读取持久化状态
      await store.init(customRootDir: tempDir);
      expect(store.providers.length, 1);
      expect(store.slotBindings['text']?['model'], 'gpt-4o');
      expect(store.mcpClients.first.name, 'Filesystem MCP');
    });

    test('删除供应商时自动解绑能力槽位并清除 Keychain', () async {
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
      await store.setSlotBinding('text', 'p_to_delete', 'm1');

      await store.deleteProvider('p_to_delete');
      expect(store.providers, isEmpty);
      expect(store.slotBindings['text']?['providerId'], '');

      final key = await KeychainService.instance.readSecret('key_delete_me');
      expect(key, isNull);
    });
  });
}
