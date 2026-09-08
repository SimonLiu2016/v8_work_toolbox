import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/mcp_service.dart';
import 'package:V8WorkToolbox/services/scheduled_news_service.dart';
import 'package:V8WorkToolbox/tools/ai_assistant/services/ai_assistant_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('McpClientConfig Model Tests', () {
    test('serialization and deserialization preserves all fields', () {
      final config = McpClientConfig(
        id: 'test_mcp_1',
        name: 'Test MCP Server',
        transport: 'stdio',
        endpointOrCommand: 'npx',
        args: const ['-y', 'my-mcp'],
        env: const {'MY_KEY': 'my_val', 'PORT': '8080'},
        headers: const {'Authorization': 'Bearer 123'},
        enabled: true,
        timeoutSeconds: 90,
      );

      final json = config.toJson();
      expect(json['id'], equals('test_mcp_1'));
      expect(json['name'], equals('Test MCP Server'));
      expect(json['transport'], equals('stdio'));
      expect(json['endpointOrCommand'], equals('npx'));
      expect(json['args'], equals(['-y', 'my-mcp']));
      expect(json['env'], equals({'MY_KEY': 'my_val', 'PORT': '8080'}));
      expect(json['timeoutSeconds'], equals(90));
      expect(json['enabled'], isTrue);

      final fromJson = McpClientConfig.fromJson(json);
      expect(fromJson.id, equals(config.id));
      expect(fromJson.name, equals(config.name));
      expect(fromJson.endpointOrCommand, equals(config.endpointOrCommand));
      expect(fromJson.args, equals(config.args));
      expect(fromJson.env, equals(config.env));
      expect(fromJson.timeoutSeconds, equals(config.timeoutSeconds));
      expect(fromJson.enabled, equals(config.enabled));
    });

    test('copyWith properly modifies target fields', () {
      final config = McpClientConfig(
        id: 'id_1',
        name: 'Old Name',
        transport: 'stdio',
        endpointOrCommand: 'node',
      );

      final updated = config.copyWith(
        name: 'New Name',
        enabled: false,
        timeoutSeconds: 120,
      );

      expect(updated.id, equals('id_1'));
      expect(updated.name, equals('New Name'));
      expect(updated.enabled, isFalse);
      expect(updated.timeoutSeconds, equals(120));
      expect(updated.endpointOrCommand, equals('node'));
    });

    test('firecrawlPreset contains valid firecrawl defaults from MCPtools.md', () {
      final preset = McpClientConfig.firecrawlPreset();
      expect(preset.id, equals('mcp_firecrawl'));
      expect(preset.name, contains('Firecrawl'));
      expect(preset.endpointOrCommand, equals('npx'));
      expect(preset.args, equals(['-y', 'firecrawl-mcp']));
      expect(preset.env.containsKey('FIRECRAWL_API_URL'), isTrue);
      expect(preset.env.containsKey('FIRECRAWL_API_KEY'), isTrue);
      expect(preset.env['FIRECRAWL_API_URL'], equals('https://43-133-77-38.nip.io'));
      expect(preset.env['FIRECRAWL_API_KEY'], isNotEmpty);
      expect(preset.timeoutSeconds, equals(120));
      expect(preset.enabled, isTrue);
    });
  });

  group('McpService Protocol & Result Tests', () {
    test('McpToolDefinition serialization', () {
      final tool = const McpToolDefinition(
        name: 'firecrawl_scrape',
        description: 'Scrape a single URL',
        inputSchema: {'type': 'object', 'required': ['url']},
        serverId: 'srv_1',
        serverName: 'Firecrawl',
      );

      final json = tool.toJson();
      expect(json['name'], equals('firecrawl_scrape'));
      expect(json['serverId'], equals('srv_1'));

      final fromJson = McpToolDefinition.fromJson(json);
      expect(fromJson.name, equals(tool.name));
      expect(fromJson.description, equals(tool.description));
      expect(fromJson.serverId, equals(tool.serverId));
      expect(fromJson.serverName, equals(tool.serverName));
    });

    test('McpToolResult joins multiple text blocks and handles errors', () {
      final successResult = const McpToolResult(
        isError: false,
        content: [
          {'type': 'text', 'text': 'Header information'},
          {'type': 'text', 'text': 'Main body content'},
        ],
      );
      expect(successResult.text, equals('Header information\nMain body content'));

      final errorResult = const McpToolResult(
        isError: true,
        content: [],
        rawError: 'Request failed with 502 Bad Gateway',
      );
      expect(errorResult.text, contains('502 Bad Gateway'));
    });

    test('buildSanitizedEnv injects PATH paths and merges custom variables', () {
      final env = McpStdioSession.buildSanitizedEnv({
        'CUSTOM_TEST_VAR': 'abc_123',
      });

      expect(env.containsKey('PATH'), isTrue);
      expect(env['CUSTOM_TEST_VAR'], equals('abc_123'));
      // PATH should have standard bin directories
      final path = env['PATH']!;
      expect(path.contains('/usr/bin') || path.contains('/bin'), isTrue);
    });
  });

  group('ScheduledNewsService Models & Persistence Tests', () {
    test('ScheduledNewsTask serialization and state update', () {
      final task = ScheduledNewsTask(
        id: 't_news_1',
        title: 'Fed Rate Cut',
        query: 'Fed rate cut July 2026',
        intervalMinutes: 30,
        enabled: true,
      );

      final json = task.toJson();
      expect(json['id'], equals('t_news_1'));
      expect(json['intervalMinutes'], equals(30));

      final fromJson = ScheduledNewsTask.fromJson(json);
      expect(fromJson.title, equals(task.title));
      expect(fromJson.query, equals(task.query));
      expect(fromJson.intervalMinutes, equals(30));
      expect(fromJson.enabled, isTrue);
    });

    test('NewsBriefingItem serialization', () {
      final briefing = NewsBriefingItem(
        id: 'b_1',
        taskId: 't_news_1',
        taskTitle: 'Fed Rate Cut',
        content: 'Latest consensus is 62% for no cut, 35% for 25bps cut.',
        isRead: false,
      );

      final json = briefing.toJson();
      expect(json['taskId'], equals('t_news_1'));
      expect(json['isRead'], isFalse);

      final fromJson = NewsBriefingItem.fromJson(json);
      expect(fromJson.id, equals(briefing.id));
      expect(fromJson.content, equals(briefing.content));
      expect(fromJson.isRead, isFalse);
    });

    test('ScheduledNewsService in-memory operations', () async {
      final tempDir = Directory.systemTemp.createTempSync('news_test');
      try {
        await ScheduledNewsService.instance.init(customRootDir: tempDir);

        final initialTasksCount = ScheduledNewsService.instance.tasks.length;
        expect(initialTasksCount >= 1, isTrue); // Has default task

        final customTask = ScheduledNewsTask(
          id: 'custom_1',
          title: 'Flutter Desktop 2026',
          query: 'Flutter 3.24 desktop features',
          intervalMinutes: 15,
        );

        await ScheduledNewsService.instance.saveTask(customTask);
        expect(ScheduledNewsService.instance.tasks.any((t) => t.id == 'custom_1'), isTrue);

        await ScheduledNewsService.instance.deleteTask('custom_1');
        expect(ScheduledNewsService.instance.tasks.any((t) => t.id == 'custom_1'), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('ChatMessage & ToolCallInfo Tests', () {
    test('ToolCallInfo serialization and status values', () {
      final toolCall = ToolCallInfo(
        toolName: 'firecrawl_search',
        arguments: {'query': 'Bitcoin ETF'},
        status: ToolCallStatus.running,
      );

      expect(toolCall.status, equals(ToolCallStatus.running));
      final json = toolCall.toJson();
      expect(json['status'], equals('running'));

      toolCall.status = ToolCallStatus.success;
      toolCall.result = 'Found 5 articles';
      expect(toolCall.toJson()['status'], equals('success'));
    });

    test('ChatMessage serialization preserves role, content, and toolCalls', () {
      final msg = ChatMessage(
        id: 'm_1',
        role: 'assistant',
        content: 'Here are the latest findings.',
        toolCalls: [
          ToolCallInfo(
            toolName: 'firecrawl_scrape',
            arguments: {'url': 'https://example.com'},
            result: 'Example domain text',
            status: ToolCallStatus.success,
          ),
        ],
      );

      expect(msg.isAssistant, isTrue);
      expect(msg.isUser, isFalse);
      expect(msg.toolCalls.length, equals(1));

      final json = msg.toJson();
      final fromJson = ChatMessage.fromJson(json);

      expect(fromJson.id, equals(msg.id));
      expect(fromJson.content, equals(msg.content));
      expect(fromJson.toolCalls.length, equals(1));
      expect(fromJson.toolCalls.first.toolName, equals('firecrawl_scrape'));
      expect(fromJson.toolCalls.first.status, equals(ToolCallStatus.success));
    });
  });
}
