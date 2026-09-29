import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'youdao_service.dart';

// ---------------------------------------------------------------------------
// 词典查询数据模型
// ---------------------------------------------------------------------------

/// 词义分组（按词性）
class DictionaryMeaning {
  final String partOfSpeech;
  final List<String> definitions;
  final List<String> examples;

  const DictionaryMeaning({
    required this.partOfSpeech,
    required this.definitions,
    required this.examples,
  });

  factory DictionaryMeaning.fromJson(Map<String, dynamic> json) {
    final defs =
        (json['definitions'] as List? ?? []).cast<Map<String, dynamic>>();
    return DictionaryMeaning(
      partOfSpeech: json['partOfSpeech'] as String? ?? '',
      definitions: defs
          .map((d) => d['definition'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
      examples: defs
          .map((d) => d['example'] as String? ?? '')
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }
}

/// Free Dictionary API 查词结果
class DictionaryResult {
  final String word;
  final String? phonetic;
  final String? audioUrl;
  final List<DictionaryMeaning> meanings;

  const DictionaryResult({
    required this.word,
    this.phonetic,
    this.audioUrl,
    required this.meanings,
  });

  /// 所有释义（flat list）
  List<String> get allDefinitions =>
      meanings.expand((m) => m.definitions).toList();

  /// 所有例句（flat list）
  List<String> get allExamples =>
      meanings.expand((m) => m.examples).toList();

  /// 主词性（第一个非空）
  String? get primaryPartOfSpeech => meanings
      .firstWhere(
        (m) => m.partOfSpeech.isNotEmpty,
        orElse: () => const DictionaryMeaning(
          partOfSpeech: '',
          definitions: [],
          examples: [],
        ),
      )
      .partOfSpeech;
}

// ---------------------------------------------------------------------------
// 词典查询服务
// ---------------------------------------------------------------------------

/// 封装 Free Dictionary API 调用
/// API 文档：https://dictionaryapi.dev/
class DictionaryService {
  static const _baseUrl = 'https://api.dictionaryapi.dev/api/v2/entries/en';
  static const _timeout = Duration(seconds: 3);

  /// 简单内存缓存（LRU-ish: 超过 100 条时整体清空）
  static final Map<String, DictionaryResult?> _cache = {};

  /// 查询单词或短语（英语）
  static Future<DictionaryResult?> lookup(String word) async {
    final key = word.trim().toLowerCase();
    if (key.isEmpty) return null;

    if (_cache.containsKey(key)) return _cache[key];
    if (_cache.length >= 100) _cache.clear();

    // 1. 优先走国内高可用有道词典，响应一般在 150-300ms
    try {
      final youdaoResult = await YoudaoService.lookupFull(key);
      if (youdaoResult != null && youdaoResult.meanings.isNotEmpty) {
        _cache[key] = youdaoResult;
        return youdaoResult;
      }
    } catch (e) {
      debugPrint('[DictionaryService] Youdao lookup failed: $e');
    }

    // 2. 备选：Free Dictionary API（超时缩减至 3s）
    try {
      final uri = Uri.parse('$_baseUrl/${Uri.encodeComponent(key)}');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) {
        _cache[key] = null;
        return null;
      }

      final data = jsonDecode(response.body);
      if (data is! List || data.isEmpty) {
        _cache[key] = null;
        return null;
      }

      final entry = data.first as Map<String, dynamic>;

      // 找最好的音频 URL（优先 https）
      String? audioUrl;
      final phonetics =
          (entry['phonetics'] as List? ?? []).cast<Map<String, dynamic>>();
      for (final p in phonetics) {
        final au = p['audio'] as String?;
        if (au != null && au.isNotEmpty) {
          audioUrl = au.startsWith('http') ? au : 'https:$au';
          break;
        }
      }

      // 音标（entry 顶层 → phonetics 数组第一个）
      String? phonetic = entry['phonetic'] as String?;
      if ((phonetic == null || phonetic.isEmpty) && phonetics.isNotEmpty) {
        phonetic = phonetics.first['text'] as String?;
      }

      final meanings = (entry['meanings'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(DictionaryMeaning.fromJson)
          .toList();

      final result = DictionaryResult(
        word: entry['word'] as String? ?? key,
        phonetic: phonetic,
        audioUrl: audioUrl,
        meanings: meanings,
      );

      _cache[key] = result;
      return result;
    } catch (e) {
      debugPrint('[DictionaryService] lookup error for "$word": $e');
      _cache[key] = null;
      return null;
    }
  }

  /// 清空内存缓存
  static void clearCache() => _cache.clear();
}
