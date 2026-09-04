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
        return [
          'claude-3-7-sonnet-20250219',
          'claude-3-5-sonnet-20241022',
          'claude-3-5-haiku-20241022',
          'claude-3-opus-20240229',
        ];
      case AiProtocolType.gemini:
        return [
          'gemini-2.5-pro',
          'gemini-2.5-flash',
          'gemini-2.0-flash',
          'gemini-1.5-pro',
        ];
    }
  }

  Future<List<String>> _discoverOpenAiModels(String baseUrl, String apiKey) async {
    try {
      var urlStr = baseUrl.trim();
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
      debugPrint('探测模型失败: $e');
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

    if (provider.protocol == AiProtocolType.openai) {
      return _chatOpenAi(provider.baseUrl, key, modelName, messages);
    } else {
      throw UnsupportedError('当前协议 [${provider.protocol.label}] 即将支持');
    }
  }

  Future<String> _chatOpenAi(
    String baseUrl,
    String apiKey,
    String model,
    List<Map<String, String>> messages,
  ) async {
    var urlStr = baseUrl.trim();
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
}
