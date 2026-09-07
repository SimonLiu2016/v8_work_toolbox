import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config_store.dart';
import 'ai_logger.dart';
import 'keychain_service.dart';

// ---------------------------------------------------------------------------
// 路由引擎数据类型
// ---------------------------------------------------------------------------

/// 单次路由尝试的记录
class RouteAttempt {
  final String providerId;
  final String model;
  final String outcome; // 'success', 'failure', 'skipped_cooldown'
  final int durationMs;
  final String? error;

  const RouteAttempt({
    required this.providerId,
    required this.model,
    required this.outcome,
    required this.durationMs,
    this.error,
  });

  @override
  String toString() => 'RouteAttempt($providerId/$model: $outcome, ${durationMs}ms${error != null ? ', error: $error' : ''})';
}

/// chat() 的结构化返回结果
class ChatResult {
  final String text;
  final String usedProviderId;
  final String usedModel;
  final List<RouteAttempt> routingTrace;

  const ChatResult({
    required this.text,
    required this.usedProviderId,
    required this.usedModel,
    required this.routingTrace,
  });

  @override
  String toString() => 'ChatResult(provider: $usedProviderId, model: $usedModel, trace: ${routingTrace.length} attempts)';
}

/// 槽位不可用结构化异常
class SlotUnavailableException implements Exception {
  final String slotName;
  final int candidateCount;
  final List<String> candidateErrors;

  const SlotUnavailableException({
    required this.slotName,
    required this.candidateCount,
    required this.candidateErrors,
  });

  @override
  String toString() {
    if (candidateCount == 0) {
      return '槽位 "$slotName" 无可用候选供应商。请在 AI 配置中为该槽位添加至少一个供应商绑定。';
    }
    final errorSummary = candidateErrors.asMap().entries
        .map((e) => '  候选 ${e.key + 1}: ${e.value}')
        .join('\n');
    return '槽位 "$slotName" 的全部 $candidateCount 个候选供应商均不可用：\n$errorSummary\n请检查供应商配置或网络连接。';
  }
}

// ---------------------------------------------------------------------------
// 供应商健康状态
// ---------------------------------------------------------------------------

/// 供应商运行时健康状态（仅内存缓存，不持久化）
class ProviderHealthState {
  final bool isHealthy;
  final DateTime lastCheckedAt;
  final String? lastError;
  final int failureCount;

  const ProviderHealthState({
    required this.isHealthy,
    required this.lastCheckedAt,
    this.lastError,
    this.failureCount = 0,
  });

  ProviderHealthState markHealthy() => ProviderHealthState(
    isHealthy: true,
    lastCheckedAt: DateTime.now(),
    lastError: null,
    failureCount: 0,
  );

  ProviderHealthState markUnhealthy(String error) => ProviderHealthState(
    isHealthy: false,
    lastCheckedAt: DateTime.now(),
    lastError: error,
    failureCount: failureCount + 1,
  );

  @override
  String toString() => 'ProviderHealthState(healthy: $isHealthy, failures: $failureCount, lastError: $lastError)';
}

// ---------------------------------------------------------------------------
// 统一 AI 能力服务
// ---------------------------------------------------------------------------

/// 统一 AI 能力服务
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  http.Client _client = http.Client();

  /// 供应商健康状态缓存（仅内存，应用重启后清空）
  final Map<String, ProviderHealthState> _healthCache = {};

  /// 已解析并验证可用的对话端点缓存（providerId -> 完整端点 URL）
  final Map<String, String> _resolvedChatEndpoint = {};

  /// 冷却窗口：失败的供应商在此时间内不会被重新尝试
  Duration _cooldownDuration = const Duration(seconds: 60);

  Duration get cooldownDuration => _cooldownDuration;

  @visibleForTesting
  set cooldownDuration(Duration value) => _cooldownDuration = value;

  @visibleForTesting
  void clearResolvedChatEndpoints() => _resolvedChatEndpoint.clear();

  void invalidateProviderEndpoint(String providerId) {
    _resolvedChatEndpoint.remove(providerId);
  }

  @visibleForTesting
  void setMockHttpClient(http.Client client) {
    _client = client;
  }

  /// 获取指定供应商的健康状态（供 UI 层读取）
  ProviderHealthState? getProviderHealth(String providerId) {
    return _healthCache[providerId];
  }

  /// 检查供应商是否健康（考虑冷却窗口）
  bool _isProviderHealthy(String providerId) {
    final state = _healthCache[providerId];
    if (state == null) return true; // 未知状态视为健康
    if (state.isHealthy) return true;
    // 检查冷却是否已过期
    final elapsed = DateTime.now().difference(state.lastCheckedAt);
    return elapsed >= _cooldownDuration;
  }

  /// 标记供应商为健康
  void _markProviderHealthy(String providerId) {
    _healthCache[providerId] = (_healthCache[providerId] ??
        ProviderHealthState(isHealthy: true, lastCheckedAt: DateTime(2000)))
        .markHealthy();
  }

  /// 标记供应商为不健康（对 429 速率限制豁免，不设置 60s 硬冷却）
  void _markProviderUnhealthy(String providerId, String error) {
    if (error.contains('429') || error.toLowerCase().contains('too many requests')) {
      AiLogger.logWarning('供应商 $providerId 遭遇限频 (429 Too Many Requests)，豁免 60 秒冷却锁定');
      return;
    }
    _healthCache[providerId] = (_healthCache[providerId] ??
        ProviderHealthState(isHealthy: true, lastCheckedAt: DateTime(2000)))
        .markUnhealthy(error);
  }

  @visibleForTesting
  void markProviderHealthy(String providerId) => _markProviderHealthy(providerId);

  @visibleForTesting
  void markProviderUnhealthy(String providerId, String error) => _markProviderUnhealthy(providerId, error);

  @visibleForTesting
  bool isProviderHealthy(String providerId) => _isProviderHealthy(providerId);

  /// 一键自动探测发现供应商支持的模型列表
  Future<List<String>> discoverModels(AiProviderConfig provider, {String? apiKey}) async {
    final key = apiKey ?? await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';

    switch (provider.protocol) {
      case AiProtocolType.openai:
        return _discoverOpenAiModels(provider.baseUrl, key);
      case AiProtocolType.anthropic:
        return _discoverAnthropicModels(provider.baseUrl, key);
      case AiProtocolType.gemini:
        return _discoverGeminiModels(provider.baseUrl, key);
    }
  }

  Future<List<String>> _discoverOpenAiModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim().isEmpty ? 'https://api.openai.com/v1' : baseUrl.trim();
      while (urlStr.endsWith('/')) {
        urlStr = urlStr.substring(0, urlStr.length - 1);
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) ...{
          'Authorization': 'Bearer $apiKey',
          'api-key': apiKey,
        },
      };

      final candidateUrls = <String>[];
      if (urlStr.endsWith('/v1')) {
        candidateUrls.add('$urlStr/models');
      } else {
        candidateUrls.add('$urlStr/v1/models');
        candidateUrls.add('$urlStr/models');
      }

      http.Response? lastResp;
      for (int i = 0; i < candidateUrls.length; i++) {
        final uri = Uri.parse(candidateUrls[i]);
        final resp = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
        lastResp = resp;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final list = data['data'] as List<dynamic>? ?? [];
          final models = list
              .map((e) => (e as Map<String, dynamic>)['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          models.sort();
          return models;
        } else if (resp.statusCode == 404 && i < candidateUrls.length - 1) {
          continue;
        }
      }
      throw Exception('OpenAI /models 探测失败: HTTP ${lastResp?.statusCode}: ${lastResp?.body}');
    } catch (e) {
      debugPrint('OpenAI 探测模型失败: $e');
      rethrow;
    }
  }

  Future<List<String>> _discoverAnthropicModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim().isEmpty ? 'https://api.anthropic.com' : baseUrl.trim();
      while (urlStr.endsWith('/')) {
        urlStr = urlStr.substring(0, urlStr.length - 1);
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        if (apiKey.isNotEmpty) ...{
          'x-api-key': apiKey,
          'api-key': apiKey,
        },
      };

      final candidateUrls = <String>[];
      if (urlStr.endsWith('/v1')) {
        candidateUrls.add('$urlStr/models');
      } else if (urlStr.endsWith('/anthropic')) {
        candidateUrls.add('$urlStr/v1/models');
        final root = urlStr.substring(0, urlStr.length - '/anthropic'.length);
        candidateUrls.add('$root/v1/models');
      } else {
        candidateUrls.add('$urlStr/v1/models');
        candidateUrls.add('$urlStr/models');
        candidateUrls.add('$urlStr/anthropic/v1/models');
      }

      http.Response? lastResp;
      for (int i = 0; i < candidateUrls.length; i++) {
        final uri = Uri.parse(candidateUrls[i]);
        final resp = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
        lastResp = resp;
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final list = data['data'] as List<dynamic>? ?? [];
          final models = list
              .map((e) => (e as Map<String, dynamic>)['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
          if (models.isNotEmpty) {
            models.sort();
            return models;
          }
          throw Exception('Anthropic /models 返回了空列表');
        } else if (resp.statusCode == 404 && i < candidateUrls.length - 1) {
          continue;
        }
      }
      throw Exception('Anthropic /models 探测失败: HTTP ${lastResp?.statusCode}: ${lastResp?.body}');
    } catch (e) {
      debugPrint('Anthropic 探测模型失败: $e');
      rethrow;
    }
  }

  Future<List<String>> _discoverGeminiModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim().isEmpty ? 'https://generativelanguage.googleapis.com' : baseUrl.trim();
      while (urlStr.endsWith('/')) {
        urlStr = urlStr.substring(0, urlStr.length - 1);
      }
      final uri = Uri.parse('$urlStr/v1beta/models?key=$apiKey');
      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      final resp = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['models'] as List<dynamic>? ?? [];
        final models = list
            .map((e) {
              final raw = (e as Map<String, dynamic>)['name'] as String? ?? '';
              return raw.startsWith('models/') ? raw.substring('models/'.length) : raw;
            })
            .where((id) => id.isNotEmpty && !id.contains('embedding') && !id.contains('aqa'))
            .toList();
        models.sort();
        if (models.isNotEmpty) return models;
        throw Exception('Gemini /models 返回中未找到支持 generateContent 的模型');
      } else {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      debugPrint('Gemini 探测模型失败: $e');
      rethrow;
    }
  }

  /// 测试与供应商的连通性（模型探测 + 真机对话 Ping 双阶段校验）
  Future<bool> testConnection(AiProviderConfig provider, {String? apiKey}) async {
    try {
      // 阶段 1：探测可用模型
      final models = await discoverModels(provider, apiKey: apiKey);
      if (models.isEmpty) {
        throw Exception('连接成功但未探测到可用模型列表');
      }

      // 阶段 2：真机轻量对话 Ping 校验，确保实际推理端点与鉴权完全连通
      final testModel = provider.textModels.isNotEmpty
          ? provider.textModels.first
          : models.first;
      await _pingChat(provider, testModel, apiKey: apiKey);
      return true;
    } catch (e) {
      debugPrint('连接测试失败: $e');
      rethrow;
    }
  }

  Future<void> _pingChat(AiProviderConfig provider, String model, {String? apiKey}) async {
    final key = apiKey ?? await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';
    final pingMessages = [
      {'role': 'user', 'content': 'ping'}
    ];
    switch (provider.protocol) {
      case AiProtocolType.openai:
        await _chatOpenAi(provider, key, model, pingMessages, maxTokens: 5);
        break;
      case AiProtocolType.anthropic:
        await _chatAnthropic(provider, key, model, pingMessages, maxTokens: 5);
        break;
      case AiProtocolType.gemini:
        await _chatGemini(provider.baseUrl, key, model, pingMessages);
        break;
    }
  }

  /// 统一文本对话能力调用（带自动愈合路由）
  Future<ChatResult> chat({
    String slot = 'text',
    String? explicitProviderId,
    String? explicitModel,
    required List<Map<String, String>> messages,
  }) async {
    final store = AiConfigStore.instance;

    // 显式指定供应商时，跳过路由逻辑直接调用
    if (explicitProviderId != null && explicitProviderId.isNotEmpty) {
      final provider = store.providers.firstWhere(
        (p) => p.id == explicitProviderId,
        orElse: () => throw Exception('未找到指定的 AI 供应商: $explicitProviderId'),
      );
      final modelName = explicitModel ?? '';
      final sw = Stopwatch()..start();
      try {
        final text = await _chatWithProvider(provider, modelName, messages);
        sw.stop();
        _markProviderHealthy(provider.id);
        return ChatResult(
          text: text,
          usedProviderId: provider.id,
          usedModel: modelName,
          routingTrace: [
            RouteAttempt(
              providerId: provider.id,
              model: modelName,
              outcome: 'success',
              durationMs: sw.elapsedMilliseconds,
            ),
          ],
        );
      } catch (e) {
        sw.stop();
        _markProviderUnhealthy(provider.id, e.toString());
        rethrow;
      }
    }

    // 多候选路由逻辑
    final candidates = store.slotBindings[slot] ?? <SlotCandidate>[];
    if (candidates.isEmpty) {
      throw SlotUnavailableException(
        slotName: slot,
        candidateCount: 0,
        candidateErrors: [],
      );
    }

    final routingTrace = <RouteAttempt>[];
    final candidateErrors = <String>[];

    for (final candidate in candidates) {
      // 检查健康状态冷却
      if (!_isProviderHealthy(candidate.providerId)) {
        final health = _healthCache[candidate.providerId];
        routingTrace.add(RouteAttempt(
          providerId: candidate.providerId,
          model: candidate.model,
          outcome: 'skipped_cooldown',
          durationMs: 0,
          error: health?.lastError ?? '供应商处于冷却期',
        ));
        candidateErrors.add('冷却中 (上次错误: ${health?.lastError ?? "未知"})');
        continue;
      }

      // 查找供应商配置
      final provider = store.providers.cast<AiProviderConfig?>().firstWhere(
        (p) => p!.id == candidate.providerId,
        orElse: () => null,
      );
      if (provider == null) {
        routingTrace.add(RouteAttempt(
          providerId: candidate.providerId,
          model: candidate.model,
          outcome: 'failure',
          durationMs: 0,
          error: '供应商配置不存在',
        ));
        candidateErrors.add('供应商配置不存在');
        continue;
      }

      final sw = Stopwatch()..start();
      try {
        final text = await _chatWithProvider(provider, candidate.model, messages);
        sw.stop();
        _markProviderHealthy(provider.id);
        routingTrace.add(RouteAttempt(
          providerId: provider.id,
          model: candidate.model,
          outcome: 'success',
          durationMs: sw.elapsedMilliseconds,
        ));
        return ChatResult(
          text: text,
          usedProviderId: provider.id,
          usedModel: candidate.model,
          routingTrace: routingTrace,
        );
      } catch (e) {
        sw.stop();
        final errorStr = e.toString();
        _markProviderUnhealthy(provider.id, errorStr);
        routingTrace.add(RouteAttempt(
          providerId: provider.id,
          model: candidate.model,
          outcome: 'failure',
          durationMs: sw.elapsedMilliseconds,
          error: errorStr,
        ));
        candidateErrors.add(errorStr);
        debugPrint('路由降级: 供应商 ${provider.name} 失败 ($errorStr), 尝试下一候选...');
      }
    }

    // 所有候选均失败
    throw SlotUnavailableException(
      slotName: slot,
      candidateCount: candidates.length,
      candidateErrors: candidateErrors,
    );
  }

  /// 使用指定供应商执行 chat 请求（内部方法）
  Future<String> _chatWithProvider(
    AiProviderConfig provider,
    String modelName,
    List<Map<String, String>> messages,
  ) async {
    final key = await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';

    switch (provider.protocol) {
      case AiProtocolType.openai:
        return _chatOpenAi(provider, key, modelName, messages);
      case AiProtocolType.anthropic:
        return _chatAnthropic(provider, key, modelName, messages);
      case AiProtocolType.gemini:
        return _chatGemini(provider.baseUrl, key, modelName, messages);
    }
  }

  Future<String> _chatOpenAi(
    AiProviderConfig provider,
    String apiKey,
    String model,
    List<Map<String, String>> messages, {
    int? maxTokens,
  }) async {
    var urlStr = provider.baseUrl.trim().isEmpty ? 'https://api.openai.com/v1' : provider.baseUrl.trim();
    while (urlStr.endsWith('/')) {
      urlStr = urlStr.substring(0, urlStr.length - 1);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) ...{
        'Authorization': 'Bearer $apiKey',
        'api-key': apiKey,
      },
    };

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      if (maxTokens != null) 'max_tokens': maxTokens,
    });

    final candidateEndpoints = <String>[];
    final cached = _resolvedChatEndpoint[provider.id];
    if (cached != null) {
      candidateEndpoints.add(cached);
    } else {
      if (urlStr.endsWith('/chat/completions')) {
        candidateEndpoints.add(urlStr);
      } else if (urlStr.endsWith('/v1')) {
        candidateEndpoints.add('$urlStr/chat/completions');
      } else {
        candidateEndpoints.add('$urlStr/v1/chat/completions');
        candidateEndpoints.add('$urlStr/chat/completions');
      }
    }

    http.Response? lastResp;
    for (int i = 0; i < candidateEndpoints.length; i++) {
      final endpoint = candidateEndpoints[i];
      final uri = Uri.parse(endpoint);

      AiLogger.logRequest(
        providerName: provider.name,
        protocol: 'openai',
        model: model,
        endpoint: endpoint,
        promptSummary: messages.isNotEmpty ? messages.last['content'] : '',
      );

      final sw = Stopwatch()..start();
      var resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));

      // 429 速率限制退避重试 1 次
      if (resp.statusCode == 429) {
        AiLogger.logWarning('OpenAI 供应商 ${provider.name} ($endpoint) 返回 429 Too Many Requests，等待 2000ms 后自动重试...');
        await Future.delayed(const Duration(milliseconds: 2000));
        resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
      }

      sw.stop();
      lastResp = resp;

      AiLogger.logResponse(
        providerName: provider.name,
        statusCode: resp.statusCode,
        durationMs: sw.elapsedMilliseconds,
        bodyPreview: resp.body,
      );

      if (resp.statusCode == 200) {
        _resolvedChatEndpoint[provider.id] = endpoint;
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final choices = json['choices'] as List<dynamic>? ?? [];
        if (choices.isNotEmpty) {
          final message = choices.first['message'] as Map<String, dynamic>?;
          return message?['content'] as String? ?? '';
        }
        return '';
      } else if (resp.statusCode == 404 && i < candidateEndpoints.length - 1) {
        continue;
      } else {
        throw Exception('OpenAI 对话请求失败 ($endpoint): HTTP ${resp.statusCode}, ${resp.body}');
      }
    }
    throw Exception('OpenAI 对话请求失败: HTTP ${lastResp?.statusCode}, ${lastResp?.body}');
  }

  Future<String> _chatAnthropic(
    AiProviderConfig provider,
    String apiKey,
    String model,
    List<Map<String, String>> messages, {
    int? maxTokens,
  }) async {
    var urlStr = provider.baseUrl.trim().isEmpty ? 'https://api.anthropic.com' : provider.baseUrl.trim();
    while (urlStr.endsWith('/')) {
      urlStr = urlStr.substring(0, urlStr.length - 1);
    }

    final headers = <String, String>{
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
      if (apiKey.isNotEmpty) ...{
        'x-api-key': apiKey,
        'api-key': apiKey,
      },
    };

    // 分离 system prompt 与对话消息
    String systemPrompt = '';
    final chatMsgs = <Map<String, String>>[];
    for (final m in messages) {
      if (m['role'] == 'system') {
        systemPrompt = systemPrompt.isEmpty ? (m['content'] ?? '') : '$systemPrompt\n\n${m['content']}';
      } else {
        chatMsgs.add({
          'role': m['role'] ?? 'user',
          'content': m['content'] ?? '',
        });
      }
    }

    final body = jsonEncode({
      'model': model.isEmpty ? 'claude-3-5-sonnet-20241022' : model,
      'max_tokens': maxTokens ?? 1024,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      'messages': chatMsgs,
    });

    final candidateEndpoints = <String>[];
    final cached = _resolvedChatEndpoint[provider.id];
    if (cached != null) {
      candidateEndpoints.add(cached);
    } else {
      if (urlStr.endsWith('/messages')) {
        candidateEndpoints.add(urlStr);
      } else if (urlStr.endsWith('/v1')) {
        candidateEndpoints.add('$urlStr/messages');
      } else if (urlStr.endsWith('/anthropic')) {
        candidateEndpoints.add('$urlStr/v1/messages');
        candidateEndpoints.add('$urlStr/messages');
      } else {
        // 自适应探测顺序：
        // 1. 小米/国内网关挂载点: /anthropic/v1/messages
        // 2. 原生 Claude: /v1/messages
        // 3. /messages
        candidateEndpoints.add('$urlStr/anthropic/v1/messages');
        candidateEndpoints.add('$urlStr/v1/messages');
        candidateEndpoints.add('$urlStr/messages');
      }
    }

    http.Response? lastResp;
    for (int i = 0; i < candidateEndpoints.length; i++) {
      final endpoint = candidateEndpoints[i];
      final uri = Uri.parse(endpoint);

      AiLogger.logRequest(
        providerName: provider.name,
        protocol: 'anthropic',
        model: model,
        endpoint: endpoint,
        promptSummary: chatMsgs.isNotEmpty ? chatMsgs.last['content'] : '',
      );

      final sw = Stopwatch()..start();
      var resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));

      // 429 速率限制退避重试 1 次
      if (resp.statusCode == 429) {
        AiLogger.logWarning('Anthropic 供应商 ${provider.name} ($endpoint) 返回 429 Too Many Requests，等待 2000ms 后自动重试...');
        await Future.delayed(const Duration(milliseconds: 2000));
        resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
      }

      sw.stop();
      lastResp = resp;

      AiLogger.logResponse(
        providerName: provider.name,
        statusCode: resp.statusCode,
        durationMs: sw.elapsedMilliseconds,
        bodyPreview: resp.body,
      );

      if (resp.statusCode == 200) {
        _resolvedChatEndpoint[provider.id] = endpoint;
        final json = jsonDecode(resp.body) as Map<String, dynamic>;
        final contents = json['content'] as List<dynamic>? ?? [];
        if (contents.isNotEmpty) {
          final textBlock = contents.firstWhere(
            (c) => (c as Map<String, dynamic>)['type'] == 'text',
            orElse: () => contents.first,
          );
          return (textBlock as Map<String, dynamic>)['text'] as String? ?? '';
        }
        return '';
      } else if (resp.statusCode == 404 && i < candidateEndpoints.length - 1) {
        continue;
      } else {
        throw Exception('Anthropic 对话请求失败 ($endpoint): HTTP ${resp.statusCode}, ${resp.body}');
      }
    }
    throw Exception('Anthropic 对话请求失败: HTTP ${lastResp?.statusCode}, ${lastResp?.body}');
  }

  Future<String> _chatGemini(
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    var urlStr = baseUrl.trim().isEmpty ? 'https://generativelanguage.googleapis.com' : baseUrl.trim();
    while (urlStr.endsWith('/')) {
      urlStr = urlStr.substring(0, urlStr.length - 1);
    }
    final modelName = model.isEmpty ? 'gemini-2.0-flash' : (model.startsWith('models/') ? model.substring('models/'.length) : model);
    final uri = Uri.parse('$urlStr/v1beta/models/$modelName:generateContent?key=$apiKey');
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    String systemPrompt = '';
    final contents = <Map<String, dynamic>>[];
    for (final m in messages) {
      if (m['role'] == 'system') {
        systemPrompt = systemPrompt.isEmpty ? (m['content'] ?? '') : '$systemPrompt\n\n${m['content']}';
      } else {
        contents.add({
          'role': m['role'] == 'assistant' ? 'model' : 'user',
          'parts': [{'text': m['content'] ?? ''}],
        });
      }
    }

    final body = jsonEncode({
      if (systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [{'text': systemPrompt}],
        },
      'contents': contents,
    });

    AiLogger.logRequest(
      providerName: 'Gemini',
      protocol: 'gemini',
      model: modelName,
      endpoint: uri.toString(),
      promptSummary: contents.isNotEmpty ? contents.last['parts']?.toString() : '',
    );

    final sw = Stopwatch()..start();
    final resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
    sw.stop();

    AiLogger.logResponse(
      providerName: 'Gemini',
      statusCode: resp.statusCode,
      durationMs: sw.elapsedMilliseconds,
      bodyPreview: resp.body,
    );

    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = json['candidates'] as List<dynamic>? ?? [];
      if (candidates.isNotEmpty) {
        final content = candidates.first['content'] as Map<String, dynamic>?;
        final parts = content?['parts'] as List<dynamic>? ?? [];
        if (parts.isNotEmpty) {
          return parts.first['text'] as String? ?? '';
        }
      }
      return '';
    } else {
      throw Exception('Gemini 对话请求失败: HTTP ${resp.statusCode}, ${resp.body}');
    }
  }
}
