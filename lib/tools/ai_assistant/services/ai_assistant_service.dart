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

/// 今天（用于 system prompt 的日期上下文）。
///
/// 单独抽成可注入的函数而不是在 `_buildSystemPrompt` 里直接调 `DateTime.now()`：
/// 测试要断言"prompt 含当天日期"，写死某一天会随时间腐烂，而能注入时钟的
/// 断言才可以长期跑。
@visibleForTesting
typedef TodayProvider = DateTime Function();

TodayProvider todayProvider = () => DateTime.now();

/// 格式化为 prompt 用的一行日期，形如 `2026-10-08 星期四`。
String formatTodayForPrompt(DateTime now) {
  const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  // weekday: 1=周一 … 7=周日。
  return '$y-$m-$d ${weekdays[now.weekday - 1]}';
}

/// 检索结果看起来是否与 query 相关。
///
/// 启发式，且刻意保守：**只有"明显不相关"才返回 false**。弱相关（部分命中、
/// 只命中同义词）一律算相关——宁可漏判，不可错判。错判的代价是模型被误导着
/// 说"没检索到"，而那比多灌一份材料更糟。
///
/// 判定方式：从 query 里取若干个有实质意义的**字片段**，再看 top 结果的
/// 标题+摘要里是否命中至少一个。
///
/// 为什么用字片段而不是词：这个项目没有中文分词器（无 jieba 类依赖），
/// 而整串匹配是无效的——"今天股市为什么大跌"切成词会得到它自己，永远命不中
/// "A股今日大跌原因分析"里的任何子串。取 2-4 字的滑动片段则能跨这种表述差异
/// （"股市"/"大跌"/"股指"/"下行" 都可命中）。
///
/// 它不可能是完备的：同义改写（"下行" vs "大跌"）测不出来。所以它的产物只是
/// "是否要提醒模型一句"，不是"结果好不好"的最终裁决。
@visibleForTesting
bool searchResultsLookRelevant(String query, List<SearchResult> results) {
  if (results.isEmpty) return true; // 空结果由既有路径处理，不在此判定
  final terms = _relevanceTerms(query);
  if (terms.isEmpty) return true; // 问得太空泛，无从判定

  for (final r in results) {
    final haystack = '${r.title} ${r.snippet}'.toLowerCase();
    if (terms.any((t) => haystack.contains(t))) return true;
  }
  return false;
}

/// 从 query 提取用于相关性匹配的字片段。
///
///  latin（空格分词）按词取；中文按 2-4 字滑动窗口取，并在停用片段处断开。
///  停用词既会稀释信号（"今天"在任何结果里都可能出现），也会让整段查询
///  退化成一个大片段。
List<String> _relevanceTerms(String query) {
  final lower = query.toLowerCase();
  final out = <String>{};

  // 1. 拉丁词：空格/标点切开，长度 ≥2 且非停用。
  for (final raw in lower.split(RegExp(r'[\s,，。？?！!、；;：:]+'))) {
    final w = raw.trim();
    if (w.length >= 2 && !_stopTerms.contains(w)) out.add(w);
  }

  // 2. 中文字片段：在停用词处把串切成若干段，每段取 2-4 字滑动窗口。
  for (final seg in lower.split(RegExp(r'[\s,，。？?！!、；;：:]+'))) {
    if (!_containsHan(seg)) continue;
    // 去掉段内的纯数字/拉丁部分，只留汉字连续段
    for (final han in RegExp(r'[一-龥]+').allMatches(seg).map((m) => m.group(0)!)) {
      if (_stopTerms.contains(han)) continue;
      final start = han.length >= 4 ? 0 : 0;
      final end = han.length >= 4 ? han.length - 1 : han.length;
      for (var i = start; i < end; i++) {
        for (var len = 2; len <= 4 && i + len <= han.length; len++) {
          final frag = han.substring(i, i + len);
          if (_stopTerms.contains(frag)) continue;
          out.add(frag);
        }
      }
    }
  }

  // 片段太多时只保留最长的那些：短片段（2 字）误命中率最高。
  final list = out.toList()..sort((a, b) => b.length.compareTo(a.length));
  return list.take(24).toList();
}

const _stopTerms = {
  '今天', '今日', '现在', '目前', '最新', '最近', '什么', '为什么', '为何',
  '怎么', '如何', '哪些', '多少', '原因', 'the', 'a', 'an', 'is', 'are', 'of',
  'to', 'in', 'on', 'for', 'and', 'or', 'what', 'why', 'how',
};

bool _containsHan(String s) => RegExp(r'[一-龥]').hasMatch(s);

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

    // 当前日期。没有它，模型会自己猜年份——实机上见过一次 query 里拼
    // "2024"（当天其实是 2026-10-08），于是检索关键词从第一步就是错的。
    final today = formatTodayForPrompt(todayProvider());

    return '''
你是一个集成了全网实时检索与爬虫工具的专业 AI 资讯助手。
你已内置开箱即用的实时网络检索（web_search）与网页正文抓取（web_scrape）能力，并支持外部高级 MCP 工具：

$toolDescs

【当前时间上下文】
今天是 $today。涉及"今天/最近/最新"等时间概念时以此为准，不要自行推测年份。

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
          var text =
              res.results.map((r) => '### ${r.title}\n链接: ${r.url}\n${r.snippet}').join('\n\n');
          if (text.isEmpty) {
            return const AgentToolOutcome.success('（未搜索到匹配结果）');
          }

          // 检索结果与问题明显无关时，明确告诉模型"这份材料不相关"。
          //
          // 为什么要这一段：实机上问"今天股市为什么大跌"，web_search 显示执行
          // 成功，回来的却是十条日历网/老黄历，且摘要曾经全空。模型看着这份
          // 材料答不出股市问题，于是说"我无法实时联网获取最新股市数据"——
          // 与界面上的"执行成功"自相矛盾。它不是无故撒谎，是手上真的只有这份
          // 材料，而系统从没告诉它这份材料不相关。
          //
          // 注意两件事：
          //   1. 结果本身仍然灌给模型，让它能否决我们的启发式（宁可漏判不可错判）；
          //   2. 徽章仍是 success——工具确实成功了，把我们的猜测升级成"失败"
          //      是冒领权威。区分只活在模型读到的内容里。
          if (!searchResultsLookRelevant(q, res.results)) {
            text = '【系统提示】以上检索结果与用户的问题看起来不相关'
                '（关键词未在标题或摘要中出现）。请如实地告诉用户"检索未命中'
                '相关资料"，不要把这些结果当作答案依据；可以基于通用知识回答，'
                '但必须说明这一点。\n\n$text';
          }
          return AgentToolOutcome.success(text);
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
