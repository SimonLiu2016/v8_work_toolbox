import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai_service.dart';

/// 供 agent 循环使用的工具描述（用于生成 system prompt）。
class AgentTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const AgentTool({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });

  /// 渲染为 prompt 中的一行工具说明。
  String toPromptLine() =>
      '- $name: $description\n  参数模式: ${jsonEncode(inputSchema)}';
}

/// 工具执行结果。`isError` 为 true 时 [error] 非空。
class AgentToolOutcome {
  final bool isError;
  final String text;
  final String? error;

  const AgentToolOutcome.success(this.text)
      : isError = false,
        error = null;
  const AgentToolOutcome.failure(this.error)
      : isError = true,
        text = '';

  /// 供回灌给模型的文本表示。
  String get feedText => isError ? '工具执行失败: ${error ?? '未知错误'}' : text;
}

/// 一次工具调用的记录。
class AgentToolExecution {
  final String name;
  final Map<String, dynamic> arguments;
  final AgentToolOutcome outcome;

  const AgentToolExecution({
    required this.name,
    required this.arguments,
    required this.outcome,
  });

  @override
  String toString() => 'AgentToolExecution($name, error=${outcome.isError})';
}

/// agent 循环的最终产出。
class AgentLoopResult {
  /// 模型的最终回答（无工具调用时的最后一条回复）。
  final String text;

  /// 本轮循环中执行过的全部工具调用，按顺序。
  final List<AgentToolExecution> executions;

  const AgentLoopResult({required this.text, required this.executions});
}

/// 工具执行回调。签名：`(工具名, 参数) -> 结果`。
typedef AgentToolExecutor = Future<AgentToolOutcome> Function(
  String name,
  Map<String, dynamic> arguments,
);

/// 共享的 ReAct 循环。
///
/// 职责：调 LLM → 解析 ```tool_call 代码块 → 执行工具 → 把结果回灌 → 再调 LLM，
/// 直至模型给出不带工具调用的最终回答或达到迭代上限。
///
/// **工具集与执行方式由调用方注入**——循环本身不认识 MCP、笔记本或联网，只按
/// [AgentTool] 列表生成 prompt、按 [execute] 回调执行。这样 AI 助手（MCP 工具）
/// 与笔记本问答（笔记本检索 + 联网）可共用同一循环。
class AgentLoop {
  AgentLoop._();

  /// 匹配 ```tool_call { ... } ``` 代码块。
  static final RegExp toolCallPattern =
      RegExp(r'```tool_call\s*(\{[\s\S]*?\})\s*```');

  /// 运行循环。
  ///
  /// [systemPrompt] 通常由调用方用 [buildSystemPrompt] 生成；
  /// [initialPrompt] 是首轮的 user 消息（含对话历史与用户指令）；
  /// [onToolExecuted] 在每次工具执行后回调，供调用方更新自己的 UI 状态。
  static Future<AgentLoopResult> run({
    required String systemPrompt,
    required String initialPrompt,
    required AgentToolExecutor execute,
    void Function(String name, Map<String, dynamic> arguments)? onToolCallStart,
    void Function(AgentToolExecution execution)? onToolExecuted,
    int maxIterations = 3,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final executions = <AgentToolExecution>[];
    var currentPrompt = initialPrompt;
    var iterations = 0;
    var finalText = '';

    while (iterations < maxIterations) {
      iterations++;

      final chatResult = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': currentPrompt},
        ],
        timeout: timeout,
      );

      final reply = chatResult.text.trim();
      final callData = parseToolCall(reply);

      if (callData == null) {
        // 无工具调用 → 模型已给出最终回答。
        finalText = reply;
        break;
      }

      final toolName = callData['name'] as String;
      final args = Map<String, dynamic>.from(callData['arguments'] as Map? ?? {});

      // 通知调用方"即将执行"，供 UI 显示进行中状态。
      onToolCallStart?.call(toolName, args);

      final outcome = await execute(toolName, args);
      final execution = AgentToolExecution(
        name: toolName,
        arguments: args,
        outcome: outcome,
      );
      executions.add(execution);
      onToolExecuted?.call(execution);

      // 回灌工具结果，进入下一轮。
      currentPrompt += '\n\n【你发起的工具调用】: $toolName, '
          '参数: ${jsonEncode(args)}\n'
          '【工具返回结果】:\n${outcome.feedText}\n\n'
          '请根据上述工具返回结果，给出最终整理好的回答：';
    }

    // 达到迭代上限仍未收敛时，返回最后一次的回复内容（可能为空）。
    if (finalText.isEmpty && iterations >= maxIterations) {
      finalText = '(已达到工具调用次数上限，未能收敛出最终回答)';
    }

    return AgentLoopResult(text: finalText, executions: executions);
  }

  /// 从模型回复中解析工具调用。
  ///
  /// 兼容 Markdown (```tool_call / ```json)、XML 标签 (<tool_call>...</tool_call> 或省略闭合标签)
  /// 以及裸 JSON 格式。自动剔除 <think> 思考链，并将 `parameters` 或 `args` 归一化为 `arguments`。
  /// 无工具调用或 JSON 非法时返回 null。
  @visibleForTesting
  static Map<String, dynamic>? parseToolCall(String reply) {
    // 1. 过滤思考链（如 DeepSeek-R1 等模型的 <think>...</think>）
    final text = reply.replaceAll(RegExp(r'<think>[\s\S]*?</think>'), '').trim();

    // 2. 依次匹配常见代码块与标签标记
    final markerPatterns = [
      RegExp(r'```tool_call'),
      RegExp(r'<tool_call>'),
      RegExp(r'```json'),
    ];

    for (final marker in markerPatterns) {
      final match = marker.firstMatch(text);
      if (match != null) {
        final braceIndex = text.indexOf('{', match.end);
        if (braceIndex != -1) {
          final jsonStr = _extractBalancedJson(text, braceIndex);
          if (jsonStr != null) {
            final res = _tryDecodeToolCall(jsonStr);
            if (res != null) return res;
          }
        }
      }
    }

    // 3. 兜底匹配：裸 JSON 块（在文本中寻找包含 "name" 的顶级 JSON）
    final nameIndex = text.indexOf('"name"');
    if (nameIndex != -1) {
      final lastBrace = text.lastIndexOf('{', nameIndex);
      if (lastBrace != -1) {
        final jsonStr = _extractBalancedJson(text, lastBrace);
        if (jsonStr != null) {
          final res = _tryDecodeToolCall(jsonStr);
          if (res != null) return res;
        }
      }
    }

    return null;
  }

  static String? _extractBalancedJson(String input, int startIndex) {
    var depth = 0;
    var inString = false;
    var escape = false;

    for (var i = startIndex; i < input.length; i++) {
      final char = input[i];

      if (escape) {
        escape = false;
        continue;
      }

      if (char == r'\') {
        escape = true;
        continue;
      }

      if (char == '"') {
        inString = !inString;
        continue;
      }

      if (!inString) {
        if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            return input.substring(startIndex, i + 1);
          }
        }
      }
    }
    return null;
  }

  static Map<String, dynamic>? _tryDecodeToolCall(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) return null;
      final name = decoded['name'];
      if (name is! String || name.trim().isEmpty) return null;

      final rawArgs =
          decoded['arguments'] ?? decoded['parameters'] ?? decoded['args'];
      final Map<String, dynamic>? args;
      if (rawArgs is Map) {
        args = Map<String, dynamic>.from(rawArgs);
      } else {
        args = null;
      }

      return {
        'name': name.trim(),
        'arguments': args,
      };
    } catch (_) {
      return null;
    }
  }

  /// 由工具列表生成 system prompt 的工具说明段。调用方拼接自己的角色描述与规则。
  static String renderTools(List<AgentTool> tools) =>
      tools.map((t) => t.toPromptLine()).join('\n\n');

  /// 把对话历史渲染为 prompt 中的「对话历史」段（最多保留 [maxTurns] 条）。
  static String renderHistory(
    List<({bool isUser, String content})> history, {
    int maxTurns = 6,
  }) {
    final recent = history.length > maxTurns
        ? history.sublist(history.length - maxTurns)
        : history;
    final buffer = StringBuffer();
    for (final m in recent) {
      buffer.writeln('${m.isUser ? "用户" : "助手"}: ${m.content}');
    }
    return buffer.toString();
  }
}
