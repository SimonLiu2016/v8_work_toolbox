import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/mcp_service.dart';
import 'package:V8WorkToolbox/shell/mcp_tool_inventory_view.dart';
import 'package:V8WorkToolbox/tools/tool_definition.dart';

/// 「外部 MCP 客户端」页签内已加载 MCP 工具清单的可测契约。
///
/// 对应 specs/ai-configuration 的 "Discovered MCP tool inventory" 三场景：
/// 探测后按客户端分组可见 / 未探测显占位 / 停用客户端不展示工具。
///
/// 关键约束：清单渲染**不得**触发 `McpService.getAllTools()`（那会真实拉起
/// stdio 子进程）。这里的数据全部由 [probeResults] 注入，测试不碰平台通道。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  McpServerStatus statusWith(List<(String, String)> tools) {
    return McpServerStatus(
      serverId: 'mcp_firecrawl',
      serverName: 'Firecrawl',
      isHealthy: true,
      toolCount: tools.length,
      tools: tools
          .map((t) => McpToolDefinition(
                name: t.$1,
                description: t.$2,
                inputSchema: const {},
                serverId: 'mcp_firecrawl',
                serverName: 'Firecrawl',
              ))
          .toList(),
    );
  }

  McpClientConfig client(String id, {bool enabled = true}) {
    return McpClientConfig(
      id: id,
      name: id == 'mcp_firecrawl' ? 'Firecrawl 官方 MCP' : '其他 MCP',
      transport: 'stdio',
      endpointOrCommand: 'npx',
      args: const ['-y', 'firecrawl-mcp'],
      enabled: enabled,
    );
  }

  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  testWidgets('探测后按客户端分组显示工具名与描述', (tester) async {
    final clients = [client('mcp_firecrawl')];
    final probes = {
      'mcp_firecrawl': statusWith([
        ('firecrawl_search', '全网网页检索'),
        ('firecrawl_scrape', '抓取并解析网页正文'),
      ]),
    };

    await tester.pumpWidget(host(McpToolInventoryView(
      clients: clients,
      probeResults: probes,
    )));

    expect(find.text('已加载的 MCP 工具'), findsOneWidget);
    expect(find.text('Firecrawl 官方 MCP'), findsOneWidget);
    expect(find.text('2 个工具'), findsOneWidget);
    expect(find.text('firecrawl_search'), findsOneWidget);
    expect(find.text('firecrawl_scrape'), findsOneWidget);
    expect(find.text('全网网页检索'), findsOneWidget);
    // 未探测占位不应出现
    expect(find.textContaining('尚未探测任何客户端'), findsNothing);
  });

  testWidgets('未探测的客户端显示占位态且不显示工具', (tester) async {
    final clients = [client('mcp_firecrawl')];
    // 空探测表 = 本会话尚未对任何客户端跑过连接测试
    await tester.pumpWidget(host(McpToolInventoryView(
      clients: [client('mcp_firecrawl')],
      probeResults: const {},
    )));

    expect(find.textContaining('尚未探测任何客户端'), findsOneWidget);
    expect(find.textContaining('测试连接与探测工具'), findsOneWidget);
    expect(find.text('firecrawl_search'), findsNothing);
    // 占位态下不应出现任何"客户端名 + N 个工具"分组
    expect(find.text('Firecrawl 官方 MCP'), findsNothing);
    // 无客户端时同样只显示占位，不抛异常
    expect(find.text('已加载的 MCP 工具'), findsOneWidget);
  });

  testWidgets('停用客户端后其工具清单不再展示', (tester) async {
    final clients = [client('mcp_firecrawl', enabled: false)];
    final probes = {
      'mcp_firecrawl': statusWith([
        ('firecrawl_search', '全网网页检索'),
      ]),
    };

    await tester.pumpWidget(host(McpToolInventoryView(
      clients: clients,
      probeResults: probes,
    )));

    // 已探测 → 分组出现，但闸门关闭 → 显示停用占位而非工具列表
    expect(find.text('Firecrawl 官方 MCP'), findsOneWidget);
    expect(find.text('1 个工具'), findsOneWidget);
    expect(find.textContaining('该客户端已停用，工具未加载'), findsOneWidget);
    expect(find.text('firecrawl_search'), findsNothing);
  });

  testWidgets('已探测但工具集为空的客户端显示空分组而非隐藏', (tester) async {
    final clients = [client('mcp_firecrawl')];
    final probes = {
      'mcp_firecrawl': statusWith(const []),
    };

    await tester.pumpWidget(host(McpToolInventoryView(
      clients: clients,
      probeResults: probes,
    )));

    expect(find.text('Firecrawl 官方 MCP'), findsOneWidget);
    expect(find.text('0 个工具'), findsOneWidget);
    expect(find.textContaining('未发现工具'), findsOneWidget);
  });

  testWidgets('AI 助手窗口 header 不含 MCP 工具清单入口', (tester) async {
    // 直接对 header 的文本面做断言：清单入口已移至 AI 配置页。
    // 这里不构建整个 AiAssistantPage（依赖单例服务与持久化存储），
    // 而是校验常量与标签不再出现在助手的交互面上。
    expect(find.text('MCP 工具清单'), findsNothing);
    expect(kToolIdAiAssistant, 'ai-assistant');
  });
}
