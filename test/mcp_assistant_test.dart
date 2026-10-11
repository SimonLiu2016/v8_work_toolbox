import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/mcp_service.dart';
import 'package:V8WorkToolbox/services/proxy_settings.dart';
import 'package:V8WorkToolbox/services/scheduled_news_service.dart';
import 'package:V8WorkToolbox/services/web_search_service.dart';
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

    test('buildSanitizedEnv does not inject proxy vars when proxy unconfigured', () {
      // Ensure proxy is unconfigured for this test.
      ProxySettings.instance.setForTesting(host: '', port: 0, enabled: false);
      final env = McpStdioSession.buildSanitizedEnv({});

      // App-level proxy vars must NOT be injected when unconfigured, and the
      // user's pre-existing environment must be preserved (not overwritten).
      for (final key in [
        'HTTP_PROXY',
        'HTTPS_PROXY',
        'ALL_PROXY',
        'http_proxy',
        'https_proxy',
        'all_proxy',
        'NO_PROXY',
        'no_proxy',
      ]) {
        expect(
          env[key],
          equals(Platform.environment[key]),
          reason: '$key should match the pre-existing environment, not be injected',
        );
      }
    });

    test('buildSanitizedEnv injects proxy vars and NO_PROXY bypass when configured', () {
      ProxySettings.instance.setForTesting(host: '127.0.0.1', port: 7897, enabled: true);
      final env = McpStdioSession.buildSanitizedEnv({'MY_TOOL_ENV': 'keep'});

      expect(env['HTTP_PROXY'], equals('http://127.0.0.1:7897'));
      expect(env['HTTPS_PROXY'], equals('http://127.0.0.1:7897'));
      expect(env['ALL_PROXY'], equals('http://127.0.0.1:7897'));
      expect(env['http_proxy'], equals('http://127.0.0.1:7897'));
      // NO_PROXY must include localhost / loopback so the proxy doesn't proxy itself.
      expect(env['NO_PROXY']!.contains('localhost'), isTrue);
      expect(env['NO_PROXY']!.contains('127.0.0.1'), isTrue);
      // Custom env still merged.
      expect(env['MY_TOOL_ENV'], equals('keep'));

      // Reset after test so other tests see unconfigured state.
      ProxySettings.instance.setForTesting(host: '', port: 0, enabled: false);
    });

    test('ProxySettings rejects invalid host/port on save and preserves prior state', () async {
      final ps = ProxySettings.instance;
      ps.setForTesting(host: 'old.host', port: 1111, enabled: true);
      // Invalid port
      expect(
        () async => ps.save(host: 'good.host', port: 0, enabled: true),
        throwsArgumentError,
      );
      // Invalid host (empty)
      expect(
        () async => ps.save(host: '   ', port: 8080, enabled: true),
        throwsArgumentError,
      );
      // Prior state preserved.
      expect(ps.host, equals('old.host'));
      expect(ps.port, equals(1111));
      expect(ps.isConfigured, isTrue);

      ps.setForTesting(host: '', port: 0, enabled: false);
    });

    test('getDiscoveredPath resolves valid system PATH with directories', () {
      final path = McpStdioSession.getDiscoveredPath();
      expect(path.isNotEmpty, isTrue);
      expect(path.contains('/usr/bin') || path.contains('/bin'), isTrue);
    });

    test('resolveExecutable locates binary in path or preserves explicit path', () {
      final path = McpStdioSession.getDiscoveredPath();
      // 'sh' is guaranteed to exist on macOS/Linux
      final resolvedSh = McpStdioSession.resolveExecutable('sh', path);
      expect(resolvedSh.endsWith('/sh') || resolvedSh == 'sh', isTrue);

      // Explicit path is preserved
      final explicit = McpStdioSession.resolveExecutable('/bin/non_existent', path);
      expect(explicit, equals('/bin/non_existent'));
    });

    test('testConnection captures stderr and non-zero exit code on failure', () async {
      final failingConfig = McpClientConfig(
        id: 'failing_mcp',
        name: 'Failing MCP Server',
        transport: 'stdio',
        endpointOrCommand: 'sh',
        args: ['-c', 'echo "FATAL: custom stderr failure" >&2; exit 127'],
        timeoutSeconds: 5,
      );

      final status = await McpService.instance.testConnection(failingConfig);
      expect(status.isHealthy, isFalse);
      expect(status.lastError, isNotNull);
      expect(
        status.lastError!.contains('FATAL: custom stderr failure') ||
            status.lastError!.contains('127') ||
            status.lastError!.contains('MCP 进程已退出'),
        isTrue,
      );
    });

    test('testConnection successfully handshakes and discovers tools with Firecrawl preset', () async {
      final config = McpClientConfig.firecrawlPreset().copyWith(timeoutSeconds: 30);
      final status = await McpService.instance.testConnection(config);
      // 本地子进程 SHALL 可达——initialize + tools/list 成功。
      expect(status.toolCount, greaterThan(0));
      expect(status.tools.any((t) => t.name.contains('firecrawl')), isTrue);
      // 远端服务可达性：远端实例当前可能不可用（502），因此 remoteReachable
      // 可能为 false。本地握手成功即证明子进程可达，整体 healthy 取决于远端。
      // 这里只断言本地层与远端探活字段都已填充，不强行要求远端健康。
      expect(status.remoteReachable, isNotNull,
          reason: 'testConnection MUST probe the real remote backend, not just list tools');
    }, timeout: const Timeout(Duration(seconds: 60)));
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

    test('AiAssistantService includes web_search and web_scrape in system prompt', () {
      final prompt = AiAssistantService.instance.buildSystemPromptForTesting([]);
      expect(prompt.contains('web_search: 全网实时搜索引擎检索'), isTrue);
      expect(prompt.contains('web_scrape: 抓取指定网址的正文内容'), isTrue);
      expect(prompt.contains('绝对不要声称自己“无法脱离 MCP 工具访问互联网或 Google”'), isTrue);
    });

    // 模型曾经自己猜年份：实机上问"今天股市为什么大跌"，它拼出的 query 是
    // "… 2024"（当天 2026-10-08），检索关键词从第一步就错。所以 prompt 必须
    // 带上真实日期，且用注入的时钟断言——写死某一天会随时间腐烂。
    test('system prompt carries the current date so the model does not guess a year', () {
      final original = todayProvider;
      try {
        todayProvider = () => DateTime(2026, 10, 8); // 星期四
        final prompt = AiAssistantService.instance.buildSystemPromptForTesting([]);
        expect(prompt.contains('2026-10-08'), isTrue, reason: 'prompt 必须含当天日期');
        expect(prompt.contains('星期四'), isTrue);
        expect(prompt.contains('今天是 2026-10-08 星期四'), isTrue);
      } finally {
        todayProvider = original;
      }
    });

    test('formatTodayForPrompt pads and names the weekday', () {
      expect(formatTodayForPrompt(DateTime(2026, 1, 2)), '2026-01-02 星期五');
      expect(formatTodayForPrompt(DateTime(2026, 10, 8)), '2026-10-08 星期四');
      // 周日是 weekday 7，不能越界。
      expect(formatTodayForPrompt(DateTime(2026, 10, 11)), '2026-10-11 星期日');
    });
  });

  // 检索结果与问题不相关时必须能被识别出来。
  //
  // 这条测试的存在理由是一场实机事故：问"今天股市为什么大跌"，web_search 显示
  // 执行成功，回来的却是十条日历网/老黄历。模型看着这份材料答不出股市问题，
  // 于是说"我无法实时联网获取最新股市数据"——与界面上的"执行成功"直接矛盾。
  // 它不是无故撒谎：系统从没告诉它这份材料不相关。
  group('searchResultsLookRelevant', () {
    SearchResult r(String title, String snippet) =>
        SearchResult(title: title, url: 'https://example.com', snippet: snippet);

    test('the real failure case is detected: stock question, calendar results', () {
      // 实机复现的那批结果。
      final results = [
        r('日历网', '日历网提供万年历查询'),
        r('今日黄历宜忌查询,今日老黄历,今天是什么日子老黄历_天天黄历', '老黄历查询'),
        r('万年历_日历网', '万年历,农历,黄历'),
      ];
      expect(
        searchResultsLookRelevant('今天 股市 大跌 原因 A股 2024', results),
        isFalse,
        reason: '十条日历网里没有任何一条命中股市/A股/大跌',
      );
    });

    test('relevant results are not flagged', () {
      final results = [
        r('A股今日大跌原因分析', '沪指收跌2.3%，市场情绪谨慎'),
        r('股市调整的深层逻辑', '资金面变化是主因'),
      ];
      expect(searchResultsLookRelevant('今天股市为什么大跌', results), isTrue);
    });

    test('partial overlap counts as relevant — 宁可漏判不可错判', () {
      // 设计原则：只有"明显不相关"才提醒模型。这里五条里只有一条命中片段
      // "下行"，仍然算相关。错判会让模型被误导着说"没检索到"，那比多灌一份
      // 材料更糟。
      final results = [
        r('大盘下行趋势何时结束', '沪指收跌2.3%，市场情绪谨慎'),
        r('宏观经济观察', '政策预期影响市场'),
      ];
      expect(searchResultsLookRelevant('今日股指下行原因', results), isTrue);
    });

    test('pure synonymy is a documented miss, not a bug', () {
      // 「股指」≠「指数」、「下行」≠「调整」——真正的同义改写，这个启发式
      // 明确声明测不出来（项目无中文分词器）。这两种情况它会判"不相关"。
      //
      // 钉住这个行为而不是掩饰它：将来若有人误以为漏判是缺陷而放宽匹配，
      // 这条测试会告诉他"不，这是代价，而且被记录在案"。
      final synonymOnly = [
        r('A股三大指数集体调整', '沪指收跌2.3%'),
        r('宏观经济观察', '政策预期影响市场'),
      ];
      expect(searchResultsLookRelevant('今日股指下行原因', synonymOnly), isFalse);
    });

    test('empty query terms are treated as relevant (nothing to judge)', () {
      final results = [r('日历网', '万年历')];
      // 全是停用词/时间词 → 无从判定 → 不插话
      expect(searchResultsLookRelevant('今天 最新 为什么', results), isTrue);
      expect(searchResultsLookRelevant('', results), isTrue);
    });

    test('no results is not our call', () {
      expect(searchResultsLookRelevant('股市大跌', const []), isTrue);
    });

    test('match is case-insensitive for latin queries', () {
      final relevant = [r('Stock market falls after Fed decision', 'S&P 500 down 1.8%')];
      expect(searchResultsLookRelevant('why did the stock market drop', relevant), isTrue);

      final unrelated = [r('Best pizza recipes', 'cheese and tomato')];
      expect(searchResultsLookRelevant('why did the stock market drop', unrelated), isFalse);
    });
  });

  // MCP 未启用时，搜索链不该包含 MCP 后端。
  //
  // 此前 `McpSearchBackend()` 无条件入链，而用户的 `ai_config.json` 里
  // `mcp_firecrawl.enabled: false` —— 每次搜索都白发一次注定失败的请求、
  // 还把后端名丢进冷却表。用户为一个没启用的服务承担等待与噪声。
  group('search chain excludes MCP backend when no server is enabled', () {
    test('AiConfigStore defaults to a disabled firecrawl preset', () async {
      // 复现实机状态：配置过 mcpServers 且全部未启用。
      final dir = await Directory.systemTemp.createTemp('v8_mcp_chain_test_');
      try {
        await AiConfigStore.instance.init(customRootDir: dir);
        await AiConfigStore.instance.saveMcpClient(
          McpClientConfig.firecrawlPreset().copyWith(enabled: false),
        );
        expect(
          AiConfigStore.instance.mcpClients.every((m) => !m.enabled),
          isTrue,
          reason: '测试前提：没有任何启用的 MCP server',
        );
        expect(
          WebSearchService.instance.debugSearchChainNames.any((n) => n.contains('MCP')),
          isFalse,
          reason: 'MCP 未启用时搜索链不该含 MCP 后端',
        );
      } finally {
        await AiConfigStore.instance.deleteMcpClient('mcp_firecrawl');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });

    test('an enabled MCP server puts the backend back in the chain', () async {
      final dir = await Directory.systemTemp.createTemp('v8_mcp_chain_test2_');
      try {
        await AiConfigStore.instance.init(customRootDir: dir);
        await AiConfigStore.instance.saveMcpClient(
          McpClientConfig.firecrawlPreset().copyWith(enabled: true),
        );
        expect(
          WebSearchService.instance.debugSearchChainNames.any((n) => n.contains('MCP')),
          isTrue,
        );
      } finally {
        await AiConfigStore.instance.deleteMcpClient('mcp_firecrawl');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    });
  });
}

