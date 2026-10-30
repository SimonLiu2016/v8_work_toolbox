/// 逐句流式翻译服务
///
/// 复用系统 AI 配置的 text 槽位翻译单句（design D6）。工具级覆盖由调用方
/// 传入 [TranslationService] 实例时指定；此处默认走系统 text 槽位。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../services/ai_config_store.dart';
import '../../../services/keychain_service.dart';

/// 翻译失败异常。
class TranslationException implements Exception {
  TranslationException(this.message);
  final String message;
  @override
  String toString() => 'TranslationException: $message';
}

/// 语言代码。
class TranslateLang {
  static const zh = 'zh';
  static const en = 'en';
  static const ja = 'ja';
  static const ko = 'ko';

  static const labels = {
    zh: '中文',
    en: '英语',
    ja: '日语',
    ko: '韩语',
  };
}

/// 翻译服务。
class TranslationService {
  TranslationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 可选：工具级覆盖的供应商 id（design D6）。null 表示沿用系统 text 槽位。
  String? overrideProviderId;

  /// 翻译单句文本到目标语言。
  Future<String> translate({
    required String text,
    required String targetLang,
  }) async {
    if (text.trim().isEmpty) return '';
    final store = AiConfigStore.instance;

    // 解析 text 槽位供应商（可被 overrideProviderId 覆盖）。
    final provider = _resolveProvider(store, overrideProviderId) ??
        _resolveTextSlotProvider(store);
    if (provider == null) {
      throw TranslationException('未配置可用的翻译模型（text 槽位为空）');
    }

    final key =
        await KeychainService.instance.readSecret(provider.keychainKeyId);
    if (key == null || key.isEmpty) {
      throw TranslationException('翻译供应商未配置 API Key');
    }

    final base = provider.baseUrl;
    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final endpoint = root.endsWith('/v1')
        ? '$root/chat/completions'
        : '$root/v1/chat/completions';

    // 从供应商的 textModels 里取一个模型。
    final model = provider.textModels.isNotEmpty
        ? provider.textModels.first
        : 'step-5-preview';

    final langName = TranslateLang.labels[targetLang] ?? targetLang;
    final prompt = '把下面的内容翻译成$langName，只输出译文，不要解释：\n$text';

    final resp = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $key',
      },
      body: jsonEncode({
        'model': model,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'temperature': 0.2,
      }),
    );

    if (resp.statusCode != 200) {
      throw TranslationException('翻译请求失败：HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw TranslationException('翻译响应无内容');
    }
    final content =
        (choices.first['message']['content'] as String?) ?? '';
    return content.trim();
  }

  dynamic _resolveTextSlotProvider(AiConfigStore store) {
    final candidates = store.slotBindings['text'] ?? [];
    for (final cand in candidates) {
      final p = store.providers
          .cast<dynamic>()
          .firstWhere((x) => x?.id == cand.providerId, orElse: () => null);
      if (p != null && p.enabled == true) return p;
    }
    return null;
  }

  dynamic _resolveProvider(AiConfigStore store, String? id) {
    if (id == null || id.isEmpty) return null;
    return store.providers
        .cast<dynamic>()
        .firstWhere((x) => x?.id == id, orElse: () => null);
  }

  void close() => _client.close();
}
