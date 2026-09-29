import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'dictionary_service.dart';

/// 有道词典查询服务（高可用国内直连，响应通常 < 300ms）
/// 使用有道词典公开接口，无需 AppKey
class YoudaoService {
  static const _timeout = Duration(seconds: 4);

  /// 简单内存缓存（LRU-ish: 超过 100 条时整体清空）
  static final Map<String, String?> _cache = {};
  static final Map<String, DictionaryResult?> _fullCache = {};

  /// 获取完整词典数据（音标、发音音频、词性分组释义、双语例句）
  static Future<DictionaryResult?> lookupFull(String word) async {
    final key = word.trim();
    if (key.isEmpty) return null;
    final lowerKey = key.toLowerCase();

    if (_fullCache.containsKey(lowerKey)) return _fullCache[lowerKey];
    if (_fullCache.length >= 100) _fullCache.clear();

    try {
      final uri = Uri.parse('https://dict.youdao.com/jsonapi').replace(
        queryParameters: {
          'q': key,
          'le': 'en',
        },
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)',
              'Referer': 'https://dict.youdao.com/',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        _fullCache[lowerKey] = null;
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>?;
      if (data == null) {
        _fullCache[lowerKey] = null;
        return null;
      }

      String? phonetic;
      String? audioUrl;
      final List<DictionaryMeaning> meanings = [];

      // 提取双语例句
      final List<String> examples = [];
      final blng = data['blng_sents_part'] as Map<String, dynamic>?;
      final sentencePairs = blng?['sentence-pair'] as List?;
      if (sentencePairs != null) {
        for (final pair in sentencePairs.take(3)) {
          if (pair is Map) {
            final sEng = pair['sentence'] as String?;
            final sZh = pair['sentence-translation'] as String?;
            if (sEng != null && sEng.isNotEmpty) {
              if (sZh != null && sZh.isNotEmpty) {
                examples.add('$sEng\n$sZh');
              } else {
                examples.add(sEng);
              }
            }
          }
        }
      }

      // 1. 尝试从 ec（英汉词典）解析结构化数据
      final ec = data['ec'] as Map<String, dynamic>?;
      final wordArr = ec?['word'] as List?;
      if (wordArr != null && wordArr.isNotEmpty) {
        final w = wordArr.first as Map<String, dynamic>?;
        final usphone = w?['usphone'] as String?;
        final ukphone = w?['ukphone'] as String?;
        if (usphone != null && usphone.isNotEmpty) {
          phonetic = '/$usphone/';
        } else if (ukphone != null && ukphone.isNotEmpty) {
          phonetic = '/$ukphone/';
        }

        // 音频发音（美音优先）
        audioUrl = 'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(key)}&type=2';

        final trsArr = w?['trs'] as List?;
        if (trsArr != null && trsArr.isNotEmpty) {
          for (final trItem in trsArr) {
            final tr = (trItem as Map<String, dynamic>?)?['tr'] as List?;
            if (tr == null || tr.isEmpty) continue;
            final l = (tr.first as Map<String, dynamic>?)?['l'] as Map<String, dynamic>?;
            final iList = l?['i'] as List?;
            if (iList == null || iList.isEmpty) continue;

            final rawText = iList.first as String? ?? '';
            if (rawText.trim().isEmpty) continue;

            // 格式通常形如: "adj. 短暂的；短生的" 或 "vt. 离开"
            final match = RegExp(r'^([a-zA-Z]+\.)\s*(.*)$').firstMatch(rawText.trim());
            String pos = '';
            String def = rawText.trim();
            if (match != null) {
              pos = match.group(1) ?? '';
              def = match.group(2) ?? '';
            }

            meanings.add(DictionaryMeaning(
              partOfSpeech: pos,
              definitions: [def],
              examples: meanings.isEmpty ? examples : const [],
            ));
          }
        }
      }

      // 2. 如果 ec 为空，尝试 simple 获取音标
      if (meanings.isEmpty) {
        final simple = data['simple'] as Map<String, dynamic>?;
        final simpleWordArr = simple?['word'] as List?;
        if (simpleWordArr != null && simpleWordArr.isNotEmpty) {
          final sw = simpleWordArr.first as Map<String, dynamic>?;
          final usphone = sw?['usphone'] as String?;
          final ukphone = sw?['ukphone'] as String?;
          if (phonetic == null) {
            if (usphone != null && usphone.isNotEmpty) {
              phonetic = '/$usphone/';
            } else if (ukphone != null && ukphone.isNotEmpty) {
              phonetic = '/$ukphone/';
            }
          }
        }
      }

      // 3. 如果仍无释义，尝试 fanyi 整句/短语翻译
      if (meanings.isEmpty) {
        final fanyi = data['fanyi'] as Map<String, dynamic>?;
        final trs = fanyi?['trs'] as String?;
        if (trs != null && trs.trim().isNotEmpty) {
          meanings.add(DictionaryMeaning(
            partOfSpeech: '',
            definitions: [trs.trim()],
            examples: examples,
          ));
        }
      }

      if (meanings.isEmpty) {
        _fullCache[lowerKey] = null;
        return null;
      }

      final result = DictionaryResult(
        word: key,
        phonetic: phonetic,
        audioUrl: audioUrl ?? 'https://dict.youdao.com/dictvoice?audio=${Uri.encodeComponent(key)}&type=2',
        meanings: meanings,
      );

      _fullCache[lowerKey] = result;
      return result;
    } catch (e) {
      debugPrint('[YoudaoService] lookupFull error for "$word": $e');
      _fullCache[lowerKey] = null;
      return null;
    }
  }

  /// 将英文单词/短语翻译为中文释义
  /// 返回 null 表示查询失败或无结果
  static Future<String?> translateToZh(String text) async {
    final key = text.trim();
    if (key.isEmpty) return null;
    if (_cache.containsKey(key)) return _cache[key];
    if (_cache.length >= 100) _cache.clear();

    try {
      // 有道词典公开 JSON API（无需 AppKey 的基础查询）
      final uri = Uri.parse('https://dict.youdao.com/jsonapi').replace(
        queryParameters: {
          'q': key,
          'le': 'en',
          'dicts':
              '{"count":99,"dicts":[["ec","ce","newcj"],["fanyi"]]}',
        },
      );
      final response = await http
          .get(
            uri,
            headers: {
              'User-Agent': 'Mozilla/5.0',
              'Referer': 'https://dict.youdao.com/',
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        _cache[key] = null;
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>?;

      // 优先取 fanyi（整句翻译）字段
      final fanyi = data?['fanyi'] as Map<String, dynamic>?;
      final trs = fanyi?['trs'] as String?;
      if (trs != null && trs.isNotEmpty) {
        _cache[key] = trs;
        return trs;
      }

      // 次选：从 ec（英汉词典）取第一条释义
      final ec = data?['ec'] as Map<String, dynamic>?;
      final wordArr = ec?['word'] as List?;
      if (wordArr != null && wordArr.isNotEmpty) {
        final trsArr =
            (wordArr.first as Map<String, dynamic>?)?['trs'] as List?;
        if (trsArr != null && trsArr.isNotEmpty) {
          final tr =
              (trsArr.first as Map<String, dynamic>?)?['tr'] as List?;
          if (tr != null && tr.isNotEmpty) {
            final l =
                (tr.first as Map<String, dynamic>?)?['l'] as Map<String, dynamic>?;
            final i = l?['i'] as List?;
            if (i != null && i.isNotEmpty) {
              final result = i.first as String?;
              _cache[key] = result;
              return result;
            }
          }
        }
      }

      _cache[key] = null;
      return null;
    } catch (e) {
      debugPrint('[YoudaoService] translateToZh error for "$text": $e');
      _cache[key] = null;
      return null;
    }
  }

  /// 清空内存缓存
  static void clearCache() => _cache.clear();
}
