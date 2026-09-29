import 'package:flutter/foundation.dart';
import '../../../services/ai_service.dart';
import 'dictionary_service.dart';
import 'youdao_service.dart';

// ---------------------------------------------------------------------------
// 查词结果数据类
// ---------------------------------------------------------------------------

/// 查词模式
enum LookupMode { dictionary, aiTranslation }

/// 统一查词结果
class LookupResult {
  final String query;
  final LookupMode mode;
  final DictionaryResult? dictionaryResult;
  final String? aiTranslation;
  final String? youdaoTranslation;
  final bool isLoading;
  final String? error;

  const LookupResult({
    required this.query,
    required this.mode,
    this.dictionaryResult,
    this.aiTranslation,
    this.youdaoTranslation,
    this.isLoading = false,
    this.error,
  });

  LookupResult copyWith({
    String? query,
    LookupMode? mode,
    DictionaryResult? dictionaryResult,
    String? aiTranslation,
    String? youdaoTranslation,
    bool? isLoading,
    String? error,
  }) {
    return LookupResult(
      query: query ?? this.query,
      mode: mode ?? this.mode,
      dictionaryResult: dictionaryResult ?? this.dictionaryResult,
      aiTranslation: aiTranslation ?? this.aiTranslation,
      youdaoTranslation: youdaoTranslation ?? this.youdaoTranslation,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

// ---------------------------------------------------------------------------
// 查词路由协调器
// ---------------------------------------------------------------------------

/// 查词路由协调器
///
/// 路由规则：
/// - ≤3 个英文词（仅含 a-z、空格、连字符、撇号） → 先走 Free Dictionary API
///   - 词典有结果 → 并行补充有道中文，返回 [LookupMode.dictionary]
///   - 词典无结果  → 自动降级至 AI 翻译
/// - >3 个词，或含非 ASCII 字符（中文/日文等）→ 直接走 AI 翻译
class LookupCoordinator {
  /// 自动路由查询（推荐入口）
  static Future<LookupResult> lookup(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return LookupResult(
        query: trimmed,
        mode: LookupMode.dictionary,
        error: '查询词不能为空',
      );
    }

    final tokenCount = trimmed
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .length;
    final isShortEnglish =
        tokenCount <= 3 &&
        RegExp(r"^[a-zA-Z\s\-']+$").hasMatch(trimmed);

    if (isShortEnglish) {
      return _dictionaryLookup(trimmed);
    } else {
      return _aiTranslation(trimmed);
    }
  }

  /// 强制使用 AI 翻译（用户手动切换模式时调用）
  static Future<LookupResult> forceAi(String text) =>
      _aiTranslation(text.trim());

  /// 强制使用词典查询（用户手动切换模式时调用）
  static Future<LookupResult> forceDictionary(String text) =>
      _dictionaryLookup(text.trim());

  // -------------------------------------------------------------------------
  // 内部实现
  // -------------------------------------------------------------------------

  static Future<LookupResult> _dictionaryLookup(String word) async {
    try {
      final dict = await DictionaryService.lookup(word);
      if (dict != null && dict.meanings.isNotEmpty) {
        // 如果 dict 本身没有中文（例如来自 Free Dictionary API），补充有道中文
        String? youdao;
        final hasChinese = dict.allDefinitions.any((d) => RegExp(r'[\u4e00-\u9fa5]').hasMatch(d));
        if (!hasChinese) {
          youdao = await YoudaoService.translateToZh(word).catchError((_) => null);
        }
        return LookupResult(
          query: word,
          mode: LookupMode.dictionary,
          dictionaryResult: dict,
          youdaoTranslation: youdao,
        );
      }
      // 词典无结果：绝不自动发起慢速 AI 翻译，由用户自主决定是否点击 AI 深度解析
      return LookupResult(
        query: word,
        mode: LookupMode.dictionary,
        error: '词典中未收录此词',
      );
    } catch (e) {
      debugPrint('[LookupCoordinator] dictionary error for "$word": $e');
      return LookupResult(
        query: word,
        mode: LookupMode.dictionary,
        error: '词典查询出错：$e',
      );
    }
  }

  /// AI 翻译调用（复用 ai_service.dart）
  ///
  /// 构建结构化 prompt，根据输入类型（单词/短语/句子）返回中文解析。
  static Future<LookupResult> _aiTranslation(String text) async {
    try {
      final prompt = '''
请对以下英文进行解析（用中文回答）：

"$text"

如果是单词或短语，提供：音标、词性、中文释义、英文例句（2条）。
如果是句子，提供：中文翻译、关键词解析。

格式简洁，直接给出内容，不要加「当然」等废话。''';

      final result = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );

      return LookupResult(
        query: text,
        mode: LookupMode.aiTranslation,
        aiTranslation: result.text,
      );
    } catch (e) {
      debugPrint('[LookupCoordinator] AI translation error for "$text": $e');
      return LookupResult(
        query: text,
        mode: LookupMode.aiTranslation,
        error: 'AI 服务暂时不可用：$e',
      );
    }
  }
}
