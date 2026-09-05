import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config_store.dart';
import 'keychain_service.dart';

/// 统一 AI 能力服务
class AiService {
  AiService._();
  static final AiService instance = AiService._();

  http.Client _client = http.Client();

  @visibleForTesting
  void setMockHttpClient(http.Client client) {
    _client = client;
  }

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
      if (urlStr.endsWith('/')) {
        urlStr = urlStr.substring(0, urlStr.length - 1);
      }
      final uri = Uri.parse('$urlStr/models');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
      };

      final resp = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>? ?? [];
        final models = list
            .map((e) => (e as Map<String, dynamic>)['id'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toList();
        models.sort();
        return models;
      } else {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      debugPrint('OpenAI 探测模型失败: $e');
      rethrow;
    }
  }

  Future<List<String>> _discoverAnthropicModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim().isEmpty ? 'https://api.anthropic.com' : baseUrl.trim();
      if (urlStr.endsWith('/')) {
        urlStr = urlStr.substring(0, urlStr.length - 1);
      }
      if (!urlStr.endsWith('/v1')) {
        urlStr = '$urlStr/v1';
      }
      final uri = Uri.parse('$urlStr/models');
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01',
        if (apiKey.isNotEmpty) 'x-api-key': apiKey,
      };

      final resp = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
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
      } else {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
    } catch (e) {
      debugPrint('Anthropic 探测模型失败: $e');
      rethrow;
    }
  }

  Future<List<String>> _discoverGeminiModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim().isEmpty ? 'https://generativelanguage.googleapis.com' : baseUrl.trim();
      if (urlStr.endsWith('/')) {
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

  /// 测试与供应商的连通性
  Future<bool> testConnection(AiProviderConfig provider, {String? apiKey}) async {
    try {
      final models = await discoverModels(provider, apiKey: apiKey);
      return models.isNotEmpty;
    } catch (e) {
      debugPrint('连接测试失败: $e');
      return false;
    }
  }

  /// 统一文本对话能力调用
  Future<String> chat({
    String slot = 'text',
    String? explicitProviderId,
    String? explicitModel,
    required List<Map<String, String>> messages,
  }) async {
    final store = AiConfigStore.instance;

    String providerId = explicitProviderId ?? '';
    String modelName = explicitModel ?? '';

    if (providerId.isEmpty) {
      final binding = store.slotBindings[slot];
      providerId = binding?['providerId'] ?? '';
      modelName = binding?['model'] ?? '';
    }

    final provider = store.providers.firstWhere(
      (p) => p.id == providerId,
      orElse: () => throw Exception('未找到可用的 AI 供应商配置 (slot: $slot)'),
    );

    final key = await KeychainService.instance.readSecret(provider.keychainKeyId) ?? '';

    switch (provider.protocol) {
      case AiProtocolType.openai:
        return _chatOpenAi(provider.baseUrl, key, modelName, messages);
      case AiProtocolType.anthropic:
        return _chatAnthropic(provider.baseUrl, key, modelName, messages);
      case AiProtocolType.gemini:
        return _chatGemini(provider.baseUrl, key, modelName, messages);
    }
  }

  Future<String> _chatOpenAi(
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    var urlStr = baseUrl.trim().isEmpty ? 'https://api.openai.com/v1' : baseUrl.trim();
    if (urlStr.endsWith('/')) {
      urlStr = urlStr.substring(0, urlStr.length - 1);
    }
    final uri = Uri.parse('$urlStr/chat/completions');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
    };

    final body = jsonEncode({
      'model': model,
      'messages': messages,
    });

    final resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) {
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final choices = json['choices'] as List<dynamic>? ?? [];
      if (choices.isNotEmpty) {
        final message = choices.first['message'] as Map<String, dynamic>?;
        return message?['content'] as String? ?? '';
      }
      return '';
    } else {
      throw Exception('OpenAI 对话请求失败: HTTP ${resp.statusCode}, ${resp.body}');
    }
  }

  Future<String> _chatAnthropic(
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    var urlStr = baseUrl.trim().isEmpty ? 'https://api.anthropic.com' : baseUrl.trim();
    if (urlStr.endsWith('/')) {
      urlStr = urlStr.substring(0, urlStr.length - 1);
    }
    if (!urlStr.endsWith('/v1')) {
      urlStr = '$urlStr/v1';
    }
    final uri = Uri.parse('$urlStr/messages');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'anthropic-version': '2023-06-01',
      if (apiKey.isNotEmpty) 'x-api-key': apiKey,
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
      'max_tokens': 1024,
      if (systemPrompt.isNotEmpty) 'system': systemPrompt,
      'messages': chatMsgs,
    });

    final resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
    if (resp.statusCode == 200) {
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
    } else {
      throw Exception('Anthropic 对话请求失败: HTTP ${resp.statusCode}, ${resp.body}');
    }
  }

  Future<String> _chatGemini(
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    var urlStr = baseUrl.trim().isEmpty ? 'https://generativelanguage.googleapis.com' : baseUrl.trim();
    if (urlStr.endsWith('/')) {
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

    final resp = await _client.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
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
