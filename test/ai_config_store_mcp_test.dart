import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('ai_config_store_mcp_test_');
    await AiConfigStore.instance.resetForTesting();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('fresh initialization creates default Firecrawl preset', () async {
    final store = AiConfigStore.instance;
    await store.init(customRootDir: tempDir);

    expect(store.mcpClients.length, equals(1));
    expect(store.mcpClients.first.id, equals('mcp_firecrawl'));

    final configFile = File('${tempDir.path}/ai_config.json');
    expect(configFile.existsSync(), isTrue);
    final json = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    expect(json.containsKey('mcpServers'), isTrue);
    expect((json['mcpServers'] as List).length, equals(1));
  });

  test('legacy config missing mcpServers injects Firecrawl preset', () async {
    final configFile = File('${tempDir.path}/ai_config.json');
    final legacyMap = {
      'providers': [],
      'defaultSlots': {'text': [], 'multimodal': [], 'tts': [], 'stt': []},
    };
    configFile.writeAsStringSync(jsonEncode(legacyMap));

    final store = AiConfigStore.instance;
    await store.init(customRootDir: tempDir);

    expect(store.mcpClients.length, equals(1));
    expect(store.mcpClients.first.id, equals('mcp_firecrawl'));
  });

  test('deleting all MCP clients persists across reloads and restarts', () async {
    final store = AiConfigStore.instance;
    await store.init(customRootDir: tempDir);
    expect(store.mcpClients.length, equals(1));

    // 删除唯一的 MCP 客户端
    await store.deleteMcpClient('mcp_firecrawl');
    expect(store.mcpClients, isEmpty);

    // 检查磁盘上的 ai_config.json
    final configFile = File('${tempDir.path}/ai_config.json');
    final jsonBeforeReload = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    expect(jsonBeforeReload['mcpServers'], isEmpty);

    // 模拟软件重启：重置单例并重新 init
    await store.resetForTesting();
    await store.init(customRootDir: tempDir);

    // 重新加载后，列表必须保持为空，不能重新注入 Firecrawl 预置
    expect(store.mcpClients, isEmpty);

    final jsonAfterReload = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    expect(jsonAfterReload['mcpServers'], isEmpty);
  });
}
