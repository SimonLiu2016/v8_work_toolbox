import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import '../../../services/app_paths.dart';
import '../../../../services/agent_loop.dart';
import '../../../../services/mcp_service.dart';
import '../../../../services/web_search_service.dart';

enum ToolCallStatus { running, success, failed }

/// 单次工具调用的记录
class ToolCallInfo {
  final String toolName;
  final Map<String, dynamic> arguments;
  String? result;
  ToolCallStatus status;
  String? error;

  ToolCallInfo({
    required this.toolName,
    required this.arguments,
    this.result,
    this.status = ToolCallStatus.running,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'toolName': toolName,
    'arguments': arguments,
    'result': result,
    'status': status.name,
    if (error != null) 'error': error,
  };

  factory ToolCallInfo.fromJson(Map<String, dynamic> json) {
    return ToolCallInfo(
      toolName: json['toolName'] as String? ?? '',
      arguments: Map<String, dynamic>.from(json['arguments'] as Map? ?? {}),
      result: json['result'] as String?,
      status: ToolCallStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ToolCallStatus.success,
      ),
      error: json['error'] as String?,
    );
  }
}

/// 聊天消息模型
class ChatMessage {
  final String id;
  final String role; // 'user', 'assistant', 'system'
  String content;
  final DateTime timestamp;
  final List<ToolCallInfo> toolCalls;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    DateTime? timestamp,
    List<ToolCallInfo>? toolCalls,
  })  : timestamp = timestamp ?? DateTime.now(),
        toolCalls = toolCalls ?? [];

  bool get isUser => role == 'user';
  bool get isAssistant => role == 'assistant';

  Map<String, dynamic> toJson() => {
    'id': id,
    'role': role,
    'content': content,
    'timestamp': timestamp.toIso8601String(),
    'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
  };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawTools = (json['toolCalls'] as List<dynamic>?) ?? [];
    return ChatMessage(
      id: json['id'] as String? ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: json['role'] as String? ?? 'user',
      content: json['content'] as String? ?? '',
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      toolCalls: rawTools.map((t) => ToolCallInfo.fromJson(t as Map<String, dynamic>)).toList(),
    );
  }
}

/// AI 检索助手智能体会话服务
class AiAssistantService extends ChangeNotifier {
  AiAssistantService._();
  static final AiAssistantService instance = AiAssistantService._();

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  File? _historyFile;

  Future<void> init({Directory? customRootDir}) async {
    try {
      final root = customRootDir ?? AppPaths.root;
      if (!root.existsSync()) root.createSync(recursive: true);
      _historyFile = customRootDir == null
          ? AppPaths.aiAssistantHistoryFile
          : File(p.join(customRootDir.path, 'ai_assistant_history.json'));
      await _loadHistory();
    } catch (e) {
      debugPrint('初始化 AI 助手历史失败: $e');
    }
  }

  Future<void> _loadHistory() async {
    if (_historyFile == null || !await _historyFile!.exists()) return;
    try {
      final text = await _historyFile!.readAsString();
      if (text.trim().isEmpty) return;
      final raw = jsonDecode(text) as List<dynamic>;
      _messages.clear();
      _messages.addAll(raw.map((e) => ChatMessage.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (e) {
      debugPrint('读取 AI 助手历史失败: $e');
    }
  }

  Future<void> _saveHistory() async {
    if (_historyFile == null) return;
    try {
      final raw = jsonEncode(_messages.map((m) => m.toJson()).toList());
      await _historyFile!.writeAsString(raw);
    } catch (e) {
      debugPrint('保存 AI 助手历史失败: $e');
    }
  }

  /// 清空对话历史
  Future<void> clearHistory() async {
    _messages.clear();
    await _saveHistory();
    notifyListeners();
  }

  /// 发送用户消息并驱动 Agentic 循环
  Future<void> sendMessage(String userText) async {
    final query = userText.trim();
    if (query.isEmpty || _isProcessing) return;

    final userMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      role: 'user',
      content: query,
    );
    _messages.add(userMsg);

    final assistantMsg = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch + 1}',
      role: 'assistant',
      content: '正在思考与检索...',
    );
    _messages.add(assistantMsg);

    _isProcessing = true;
    notifyListeners();

    try {
      await _runAgentLoop(assistantMsg);
    } catch (e) {
      assistantMsg.content = '抱歉，执行过程中出现错误: $e';
    } finally {
      _isProcessing = false;
      await _saveHistory();
      notifyListeners();
    }
  }

  /// 构建 ReAct 系统 Prompt
  String _buildSystemPrompt(List<McpToolDefinition> mcpTools) {
    // 1. 内置通用网络检索与网页抓取工具（基于 WebSearchService，零配置免外部依赖）
    final builtInToolDescs = [
      '- web_search: 全网实时搜索引擎检索（支持 Bing / SearXNG）。当需要获取最新外部资讯、新闻、技术文档或事实信息时调用。\n  参数模式: {"query":"string","limit":"int"}',
      '- web_scrape: 抓取指定网址的正文内容（转为纯净 Markdown 格式）。当需要阅读具体网页、文章正文、官方页面详情时调用。\n  参数模式: {"url":"string"}',
    ].join('\n\n');

    // 2. 外部 MCP 工具（如 Firecrawl 等高级扩展）
    final mcpToolDescs = mcpTools.map((t) {
      return '- ${t.name}: ${t.description}\n  参数模式: ${jsonEncode(t.inputSchema)}';
    }).join('\n\n');

    final toolDescs = mcpTools.isEmpty
        ? builtInToolDescs
        : '$builtInToolDescs\n\n$mcpToolDescs';

    return '''
你是一个集成了全网实时检索与爬虫工具的专业 AI 资讯助手。
你已内置开箱即用的实时网络检索（web_search）与网页正文抓取（web_scrape）能力，并支持外部高级 MCP 工具：

$toolDescs

【工具调用与联网规则】
1. 当用户的提问需要实时资讯、最新动态、客观事实或特定网址内容时，请自主调用合适的工具：
   - 通用实时联网查询优先调用 `web_search`；
   - 提取指定网址或链接的完整正文时调用 `web_scrape`；
   - 若用户指定或启用了外部 MCP 爬虫（如 firecrawl 系列），亦可调用对应 MCP 工具。
2. 你具备脱离外部 MCP 直接访问互联网的能力（通过内置的 `web_search` 与 `web_scrape` 工具）。绝对不要声称自己“无法脱离 MCP 工具访问互联网或 Google”。
3. 调用工具时，请严格输出且仅输出如下 JSON 格式（不要附加多余的开头问候），支持 ```tool_call 代码块或 <tool_call> 标签：
```tool_call
{
  "name": "工具名称",
  "arguments": {
    "参数名": "参数值"
  }
}
```
4. 系统在执行工具后会将真实的工具结果以【工具返回结果】提供给你。
5. 获取到工具返回内容后，请对信息进行严谨、清晰、详实的总结，注明信息来源与网页链接，使用美观的 Markdown 格式输出。
6. 如果用户只是进行普通技术交流或无需联网的问题，请直接回答，不要调用工具。
7. 如果工具调用报错，请根据返回信息向用户说明，并结合已有常识尽可能解答。
''';
  }

  /// 智能体循环执行。
  ///
  /// 循环逻辑已提取到共享组件 [AgentLoop]（笔记本问答复用同一循环），此处
  /// 提供 AI 助手自己的工具集（内置 web_search / web_scrape + MCP 工具）。
  Future<void> _runAgentLoop(ChatMessage assistantMsg) async {
    final mcpTools = await McpService.instance.getAllTools();
    final systemPrompt = _buildSystemPrompt(mcpTools);

    final historyContext = StringBuffer();
    // 纳入最近的对话上下文（最多保留 6 条）
    final recent = _messages.length > 7 ? _messages.sublist(_messages.length - 7, _messages.length - 1) : _messages.sublist(0, _messages.length - 1);
    for (final m in recent) {
      historyContext.writeln('${m.isUser ? "用户" : "助手"}: ${m.content}');
    }

    final initialPrompt = '对话历史:\n$historyContext\n\n用户最新指令: ${recent.last.content}\n请思考并回答：';

    final result = await AgentLoop.run(
      systemPrompt: systemPrompt,
      initialPrompt: initialPrompt,
      execute: (name, args) async {
        // 1. 分流内置网络搜索与抓取工具
        if (name == 'web_search') {
          final q = (args['query'] ?? args['q'] ?? '').toString().trim();
          if (q.isEmpty) return const AgentToolOutcome.failure('搜索关键词不能为空');
          final limit = (args['limit'] as num?)?.toInt() ?? 5;
          final res = await WebSearchService.instance.search(q, limit: limit);
          if (res.isError) {
            return AgentToolOutcome.failure(res.error ?? '搜索失败');
          }
          final text = res.results.map((r) => '### ${r.title}\n链接: ${r.url}\n${r.snippet}').join('\n\n');
          return AgentToolOutcome.success(text.isEmpty ? '（未搜索到匹配结果）' : text);
        }

        if (name == 'web_scrape') {
          final url = (args['url'] ?? '').toString().trim();
          if (url.isEmpty) return const AgentToolOutcome.failure('抓取 URL 不能为空');
          final res = await WebSearchService.instance.scrape(url);
          if (res.isError) {
            return AgentToolOutcome.failure(res.error ?? '网页抓取失败');
          }
          return AgentToolOutcome.success(res.content.isEmpty ? '（网页内容为空）' : res.content);
        }

        // 2. 外部 MCP 工具调用（带有限重试）
        final r = await _callToolWithRetry(name, args);
        return r.isError
            ? AgentToolOutcome.failure(r.rawError ?? '未知错误')
            : AgentToolOutcome.success(
                r.text.isEmpty ? '（工具返回了空内容）' : r.text);
      },
      onToolCallStart: (name, args) {
        assistantMsg.content = '正在调用工具 [$name] 检索数据...';
        notifyListeners();
      },
      onToolExecuted: (execution) {
        final info = ToolCallInfo(
          toolName: execution.name,
          arguments: execution.arguments,
        );
        if (execution.outcome.isError) {
          info.status = ToolCallStatus.failed;
          info.error = execution.outcome.error ?? '未知错误';
          info.result = '工具执行失败: ${info.error}';
        } else {
          info.status = ToolCallStatus.success;
          info.result = execution.outcome.text;
        }
        assistantMsg.toolCalls.add(info);
        notifyListeners();
      },
      maxIterations: 3,
      timeout: const Duration(seconds: 90),
    );

    assistantMsg.content = result.text;
    notifyListeners();
  }

  /// 带有界重试的工具调用。仅对瞬时故障（连接重置/超时/Socket 异常）重试，
  /// 重试总耗时不超过工具调用配置的超时预算。业务级错误（isError 且非瞬时）
  /// 不重试。
  Future<McpToolResult> _callToolWithRetry(
    String toolName,
    Map<String, dynamic> args, {
    int maxRetries = 2,
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    McpToolResult lastResult;
    int attempts = 0;
    do {
      attempts++;
      lastResult = await McpService.instance.callTool(toolName, args);
      if (!lastResult.isError) return lastResult;
      final err = lastResult.rawError ?? '';
      final transient = err.contains('ECONNRESET') ||
          err.contains('SocketException') ||
          err.contains('TimeoutException') ||
          err.contains('timeout') ||
          err.contains('EPIPE');
      if (!transient) return lastResult;
      if (attempts > maxRetries) return lastResult;
      if (DateTime.now().isAfter(deadline)) return lastResult;
      await Future.delayed(Duration(milliseconds: 800 * attempts));
    } while (attempts <= maxRetries);
    return lastResult;
  }

  @visibleForTesting
  String buildSystemPromptForTesting(List<McpToolDefinition> mcpTools) => _buildSystemPrompt(mcpTools);
}
