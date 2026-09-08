import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'ai_config_store.dart';

/// MCP 工具定义
class McpToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String serverId;
  final String serverName;

  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.serverId,
    required this.serverName,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
    'serverId': serverId,
    'serverName': serverName,
  };

  factory McpToolDefinition.fromJson(Map<String, dynamic> json, {String serverId = '', String serverName = ''}) {
    return McpToolDefinition(
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      inputSchema: Map<String, dynamic>.from(json['inputSchema'] as Map? ?? {}),
      serverId: (json['serverId'] as String?) ?? serverId,
      serverName: (json['serverName'] as String?) ?? serverName,
    );
  }
}

/// MCP 工具调用返回结果
class McpToolResult {
  final bool isError;
  final List<Map<String, dynamic>> content;
  final String? rawError;

  const McpToolResult({
    required this.isError,
    required this.content,
    this.rawError,
  });

  /// 提取所有文本内容并拼接
  String get text {
    final sb = StringBuffer();
    for (final item in content) {
      if (item['type'] == 'text') {
        final t = item['text'] as String?;
        if (t != null && t.isNotEmpty) {
          if (sb.isNotEmpty) sb.writeln();
          sb.write(t);
        }
      }
    }
    if (sb.isEmpty && rawError != null) {
      return '错误: $rawError';
    }
    return sb.toString();
  }

  Map<String, dynamic> toJson() => {
    'isError': isError,
    'content': content,
    if (rawError != null) 'rawError': rawError,
  };
}

/// MCP 服务状态报告
class McpServerStatus {
  final String serverId;
  final String serverName;
  final bool isHealthy;
  final int toolCount;
  final List<McpToolDefinition> tools;
  final String? lastError;

  const McpServerStatus({
    required this.serverId,
    required this.serverName,
    required this.isHealthy,
    required this.toolCount,
    this.tools = const [],
    this.lastError,
  });
}

/// 单个 stdio MCP 会话实现
class McpStdioSession {
  final McpClientConfig config;
  Process? _process;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  int _nextId = 1;
  final List<McpToolDefinition> _tools = [];
  bool _isInitialized = false;

  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  McpStdioSession(this.config);

  List<McpToolDefinition> get tools => List.unmodifiable(_tools);
  bool get isRunning => _process != null && _isInitialized;

  /// 构建安全的 macOS 环境变量，补充 GUI 启动时缺失的 Node/Brew PATH
  static Map<String, String> buildSanitizedEnv(Map<String, String> customEnv) {
    final env = Map<String, String>.from(Platform.environment);
    // 补充常规 PATH 保证在桌面 App 环境中能正常执行 npx / node
    final currentPath = env['PATH'] ?? '';
    const extraPaths = [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      '/usr/sbin',
      '/sbin',
    ];
    final pathSegments = currentPath.split(':').where((s) => s.isNotEmpty).toList();
    for (final p in extraPaths) {
      if (!pathSegments.contains(p) && Directory(p).existsSync()) {
        pathSegments.add(p);
      }
    }
    env['PATH'] = pathSegments.join(':');
    env.addAll(customEnv);
    return env;
  }

  /// 启动子进程并完成 MCP 协议握手
  Future<void> start() async {
    if (_process != null) return;

    final env = buildSanitizedEnv(config.env);
    try {
      _process = await Process.start(
        config.endpointOrCommand,
        config.args,
        environment: env,
        runInShell: true,
      );
    } catch (e) {
      throw Exception('无法启动 MCP 进程 [${config.endpointOrCommand}]: $e');
    }

    // 监听 stdout
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdoutLine, onError: (err) {
      debugPrint('MCP [${config.name}] stdout error: $err');
    });

    // 监听 stderr
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      debugPrint('MCP [${config.name}] stderr: $line');
    });

    _process!.exitCode.then((code) {
      debugPrint('MCP [${config.name}] 进程退出: $code');
      _cleanup();
    });

    // 协议握手
    await _handshake();
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      if (json.containsKey('id')) {
        final id = json['id'] as int?;
        if (id != null && _pendingRequests.containsKey(id)) {
          _pendingRequests.remove(id)!.complete(json);
        }
      }
    } catch (_) {
      // 忽略非 JSON 行
    }
  }

  Future<Map<String, dynamic>> sendRequest(String method, [Map<String, dynamic>? params]) async {
    if (_process == null) throw Exception('MCP 进程未启动');

    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final payload = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      if (params != null) 'params': params,
    };

    final raw = jsonEncode(payload);
    _process!.stdin.writeln(raw);

    final timeout = Duration(seconds: config.timeoutSeconds > 0 ? config.timeoutSeconds : 60);
    return completer.future.timeout(timeout, onTimeout: () {
      _pendingRequests.remove(id);
      throw TimeoutException('MCP 请求超时 ($method, ${timeout.inSeconds}s)');
    });
  }

  void sendNotification(String method, [Map<String, dynamic>? params]) {
    if (_process == null) return;
    final payload = {
      'jsonrpc': '2.0',
      'method': method,
      if (params != null) 'params': params,
    };
    _process!.stdin.writeln(jsonEncode(payload));
  }

  Future<void> _handshake() async {
    final initResp = await sendRequest('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {
        'name': 'V8WorkToolbox',
        'version': '0.1.0',
      },
    });

    if (initResp.containsKey('error')) {
      throw Exception('MCP 初始化失败: ${initResp['error']}');
    }

    sendNotification('notifications/initialized');
    _isInitialized = true;

    // 发现并缓存工具
    await refreshTools();
  }

  Future<List<McpToolDefinition>> refreshTools() async {
    final listResp = await sendRequest('tools/list');
    _tools.clear();

    if (listResp.containsKey('result') && listResp['result'] is Map) {
      final res = listResp['result'] as Map<String, dynamic>;
      final rawTools = (res['tools'] as List<dynamic>?) ?? [];
      for (final t in rawTools) {
        if (t is Map<String, dynamic>) {
          _tools.add(McpToolDefinition.fromJson(
            t,
            serverId: config.id,
            serverName: config.name,
          ));
        }
      }
    }
    return _tools;
  }

  Future<McpToolResult> callTool(String toolName, Map<String, dynamic> arguments) async {
    final resp = await sendRequest('tools/call', {
      'name': toolName,
      'arguments': arguments,
    });

    if (resp.containsKey('error')) {
      final err = resp['error'];
      return McpToolResult(
        isError: true,
        content: [],
        rawError: err is Map ? (err['message']?.toString() ?? jsonEncode(err)) : err.toString(),
      );
    }

    final result = resp['result'] as Map<String, dynamic>? ?? {};
    final isError = result['isError'] as bool? ?? false;
    final rawContent = (result['content'] as List<dynamic>?) ?? [];
    final content = rawContent
        .whereType<Map<String, dynamic>>()
        .toList();

    return McpToolResult(
      isError: isError,
      content: content,
      rawError: isError ? (content.isNotEmpty ? content.first['text']?.toString() : 'Tool reported error') : null,
    );
  }

  void _cleanup() {
    _isInitialized = false;
    for (final c in _pendingRequests.values) {
      if (!c.isCompleted) {
        c.completeError(Exception('MCP 进程已中断'));
      }
    }
    _pendingRequests.clear();
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process = null;
  }

  Future<void> dispose() async {
    if (_process != null) {
      try {
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {}
    }
    _cleanup();
  }
}

/// 全局 MCP 统一服务
class McpService {
  McpService._();
  static final McpService instance = McpService._();

  final Map<String, McpStdioSession> _sessions = {};

  /// 测试指定 MCP 配置的连通性并列出可用工具
  Future<McpServerStatus> testConnection(McpClientConfig config) async {
    final session = McpStdioSession(config);
    try {
      await session.start();
      final tools = session.tools;
      return McpServerStatus(
        serverId: config.id,
        serverName: config.name,
        isHealthy: true,
        toolCount: tools.length,
        tools: tools,
      );
    } catch (e) {
      return McpServerStatus(
        serverId: config.id,
        serverName: config.name,
        isHealthy: false,
        toolCount: 0,
        lastError: e.toString(),
      );
    } finally {
      await session.dispose();
    }
  }

  /// 获取或创建会话
  Future<McpStdioSession?> getOrCreateSession(String serverId) async {
    if (_sessions.containsKey(serverId) && _sessions[serverId]!.isRunning) {
      return _sessions[serverId];
    }

    final config = AiConfigStore.instance.mcpClients.firstWhere(
      (m) => m.id == serverId,
      orElse: () => throw Exception('未找到 MCP 客户端配置: $serverId'),
    );

    if (!config.enabled) return null;

    final session = McpStdioSession(config);
    await session.start();
    _sessions[serverId] = session;
    return session;
  }

  /// 获取当前所有已启用的 MCP 客户端的所有工具
  Future<List<McpToolDefinition>> getAllTools({bool refresh = false}) async {
    final configs = AiConfigStore.instance.mcpClients.where((m) => m.enabled).toList();
    final List<McpToolDefinition> all = [];

    for (final cfg in configs) {
      try {
        McpStdioSession? session = _sessions[cfg.id];
        if (session == null || !session.isRunning || refresh) {
          session?.dispose();
          session = McpStdioSession(cfg);
          await session.start();
          _sessions[cfg.id] = session;
        }
        all.addAll(session.tools);
      } catch (e) {
        debugPrint('获取 MCP [${cfg.name}] 工具失败: $e');
      }
    }
    return all;
  }

  /// 执行 MCP 工具调用
  Future<McpToolResult> callTool(
    String toolName,
    Map<String, dynamic> arguments, {
    String? targetServerId,
  }) async {
    // 如果指定了 serverId
    if (targetServerId != null) {
      final session = await getOrCreateSession(targetServerId);
      if (session == null) {
        return McpToolResult(
          isError: true,
          content: [],
          rawError: '指定的 MCP 服务未启用或无法连接 ($targetServerId)',
        );
      }
      return session.callTool(toolName, arguments);
    }

    // 否则根据工具名称自动寻找拥有该工具的服务
    final tools = await getAllTools();
    final matched = tools.where((t) => t.name == toolName).toList();
    if (matched.isEmpty) {
      return McpToolResult(
        isError: true,
        content: [],
        rawError: '在已启用的 MCP 服务中未找到工具 "$toolName"',
      );
    }

    final target = matched.first;
    final session = await getOrCreateSession(target.serverId);
    if (session == null) {
      return McpToolResult(
        isError: true,
        content: [],
        rawError: '无法连接到提供工具 "$toolName" 的 MCP 服务 [${target.serverName}]',
      );
    }

    return session.callTool(toolName, arguments);
  }

  /// 释放所有已建立的 MCP 子进程
  Future<void> disposeAll() async {
    for (final s in _sessions.values) {
      await s.dispose();
    }
    _sessions.clear();
  }
}
