import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../services/ai_service.dart';
import '../../../../services/mcp_service.dart';

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
      Directory dir;
      if (customRootDir != null) {
        dir = customRootDir;
      } else {
        final home = Platform.environment['HOME'];
        if (Platform.isMacOS && home != null && home.isNotEmpty) {
          dir = Directory(p.join(home, 'Library', 'Application Support', 'V8WorkToolbox'));
        } else {
          final appSupport = await getApplicationSupportDirectory();
          dir = Directory(p.join(appSupport.path, 'V8WorkToolbox'));
        }
      }

      if (!dir.existsSync()) dir.createSync(recursive: true);
      _historyFile = File(p.join(dir.path, 'ai_assistant_history.json'));
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
  String _buildSystemPrompt(List<McpToolDefinition> tools) {
    final toolDescs = tools.map((t) {
      return '- ${t.name}: ${t.description}\n  参数模式: ${jsonEncode(t.inputSchema)}';
    }).join('\n\n');

    return '''
你是一个集成了全网实时爬虫与检索工具的专业 AI 资讯助手。
你可以使用以下外部 MCP 工具获取最新的互联网资讯、抓取特定网页内容或提取结构化数据：

$toolDescs

【工具调用规则】
1. 当用户的提问需要实时信息、新闻资讯、最新动态或具体网址的内容时，请自主调用合适的工具（如 firecrawl_search 或 firecrawl_scrape）。
2. 调用工具时，请严格输出且仅输出如下 JSON 代码块（不要附加多余的开头问候）：
```tool_call
{
  "name": "工具名称",
  "arguments": {
    "参数名": "参数值"
  }
}
```
3. 系统在执行工具后会将真实的工具结果以【工具返回结果】提供给你。
4. 获取到工具返回内容后，请对信息进行严谨、清晰、详实的总结，注明信息来源与网页链接，使用美观的 Markdown 格式输出。
5. 如果用户只是进行普通技术交流或无需联网的问题，请直接回答，不要调用工具。
6. 如果工具调用报错（例如 502 Bad Gateway），请向用户说明可能由于远程服务未启动，并基于已有常识尽可能解答。
''';
  }

  /// 智能体循环执行
  Future<void> _runAgentLoop(ChatMessage assistantMsg) async {
    final tools = await McpService.instance.getAllTools();
    final systemPrompt = _buildSystemPrompt(tools);

    final historyContext = StringBuffer();
    // 纳入最近的对话上下文（最多保留 6 条）
    final recent = _messages.length > 7 ? _messages.sublist(_messages.length - 7, _messages.length - 1) : _messages.sublist(0, _messages.length - 1);
    for (final m in recent) {
      historyContext.writeln('${m.isUser ? "用户" : "助手"}: ${m.content}');
    }

    String currentPrompt = '对话历史:\n$historyContext\n\n用户最新指令: ${recent.last.content}\n请思考并回答：';
    int iterations = 0;
    const maxIterations = 3;

    while (iterations < maxIterations) {
      iterations++;

      // 调用当前配置的 text 槽位模型（设置 90 秒超时以支持思考链深度推理模型）
      final chatResult = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': currentPrompt},
        ],
        timeout: const Duration(seconds: 90),
      );

      final reply = chatResult.text.trim();

      // 检查是否有 tool_call 代码块
      final toolCallMatch = RegExp(r'```tool_call\s*(\{[\s\S]*?\})\s*```').firstMatch(reply);
      if (toolCallMatch != null) {
        final rawJson = toolCallMatch.group(1)!;
        Map<String, dynamic>? callData;
        try {
          callData = jsonDecode(rawJson) as Map<String, dynamic>;
        } catch (_) {}

        if (callData != null && callData.containsKey('name')) {
          final toolName = callData['name'] as String;
          final args = Map<String, dynamic>.from(callData['arguments'] as Map? ?? {});

          final info = ToolCallInfo(toolName: toolName, arguments: args);
          assistantMsg.toolCalls.add(info);
          assistantMsg.content = '正在调用外部工具 [$toolName] 检索数据...';
          notifyListeners();

          // 执行工具调用
          final result = await McpService.instance.callTool(toolName, args);

          if (result.isError) {
            info.status = ToolCallStatus.failed;
            info.error = result.rawError ?? '未知错误';
            info.result = '工具执行失败: ${info.error}';
          } else {
            info.status = ToolCallStatus.success;
            info.result = result.text.isEmpty ? '（工具返回了空内容）' : result.text;
          }
          notifyListeners();

          // 组织下一步思考 prompt
          currentPrompt += '\n\n【你发起的工具调用】: $toolName, 参数: ${jsonEncode(args)}\n【工具返回结果】:\n${info.result}\n\n请根据上述工具返回结果，给出最终整理好的回答：';
          continue;
        }
      }

      // 如果没有工具调用，说明已经完成回答
      assistantMsg.content = reply;
      break;
    }
  }
}
