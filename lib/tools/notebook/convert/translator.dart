import 'dart:convert';

import '../../../services/ai_service.dart';
import 'document_model.dart';

/// 文档翻译异常
class DocumentTranslationException implements Exception {
  final String message;
  final dynamic cause;

  const DocumentTranslationException(this.message, [this.cause]);

  @override
  String toString() =>
      'DocumentTranslationException: $message${cause != null ? ' (原因: $cause)' : ''}';
}

/// 文档翻译器。
///
/// 将 DocumentModel 或字符串列表送翻译。
/// 按双约束预算动态分批（每批 ≤ 30 项且 ≤ 1500 字符），失败批次重试一次。
/// 重试仍失败时抛出 [DocumentTranslationException]，严禁静默吞没假装成功。
class DocumentTranslator {
  DocumentTranslator._();

  static const int _maxBatchItems = 30;
  static const int _batchCharBudget = 1500;

  /// 翻译文档中的全部文本，返回新的 DocumentModel（图片不变）。
  ///
  /// [sourceLang] 源语言（如 "English"）。
  /// [targetLang] 目标语言（如 "Chinese"）。
  /// [onProgress] 进度回调：(已完成条数, 总条数) → void。
  static Future<DocumentModel> translate(
    DocumentModel doc, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    final texts = doc.extractTexts();
    if (texts.isEmpty) return doc;

    final translated = await translateStrings(
      texts,
      sourceLang: sourceLang,
      targetLang: targetLang,
      onProgress: onProgress,
    );

    return doc.applyTranslations(translated);
  }

  /// 翻译纯字符串列表（供各类 Rewriter 复用）。
  ///
  /// 自动跳过纯空白字符串，按双约束分批，带进度回调。
  static Future<List<String>> translateStrings(
    List<String> texts, {
    required String sourceLang,
    required String targetLang,
    void Function(int completed, int total)? onProgress,
  }) async {
    if (texts.isEmpty) return texts;

    final nonEmptyIndices = <int>[];
    final nonEmptyTexts = <String>[];
    for (var i = 0; i < texts.length; i++) {
      if (texts[i].trim().isNotEmpty) {
        nonEmptyIndices.add(i);
        nonEmptyTexts.add(texts[i]);
      }
    }

    if (nonEmptyTexts.isEmpty) return List<String>.from(texts);

    final result = List<String>.from(texts);
    final batches = _buildBatches(nonEmptyTexts);
    var completed = 0;

    for (final batch in batches) {
      final batchTexts = batch.map((e) => e.$2).toList();
      List<String> batchResult;
      try {
        batchResult = await _translateBatchWithRetry(
          batchTexts,
          sourceLang,
          targetLang,
        );
      } catch (e) {
        throw DocumentTranslationException(
          '翻译批次失败 (第 ${completed + 1} - ${completed + batch.length} 条): $e',
          e,
        );
      }

      for (var j = 0; j < batch.length; j++) {
        final originalIdx = nonEmptyIndices[batch[j].$1];
        result[originalIdx] = batchResult[j];
      }

      completed += batch.length;
      onProgress?.call(completed, nonEmptyTexts.length);
    }

    return result;
  }

  /// 将文本列表按双约束预算分批（数量 ≤ 30 且 字符数 ≤ 1500）。
  /// 返回批次列表，每批为 [(原始索引, 文本)] 对。
  static List<List<(int, String)>> _buildBatches(List<String> texts) {
    final batches = <List<(int, String)>>[];
    var currentBatch = <(int, String)>[];
    var currentChars = 0;

    for (var i = 0; i < texts.length; i++) {
      final text = texts[i];
      if (currentBatch.isNotEmpty &&
          (currentBatch.length >= _maxBatchItems ||
              currentChars + text.length > _batchCharBudget)) {
        batches.add(currentBatch);
        currentBatch = [];
        currentChars = 0;
      }
      currentBatch.add((i, text));
      currentChars += text.length;
    }

    if (currentBatch.isNotEmpty) {
      batches.add(currentBatch);
    }

    return batches;
  }

  /// 带重试的单批翻译（重试时旁路冷却锁定）。
  static Future<List<String>> _translateBatchWithRetry(
    List<String> texts,
    String sourceLang,
    String targetLang,
  ) async {
    try {
      return await _translateBatch(
        texts,
        sourceLang,
        targetLang,
        ignoreCooldown: false,
      );
    } catch (_) {
      // 首次失败，第二次重试时旁路冷却，防止单供应商网络抖动被 60s 锁死
      return await _translateBatch(
        texts,
        sourceLang,
        targetLang,
        ignoreCooldown: true,
      );
    }
  }

  /// 翻译单批文本并解析结果。
  static Future<List<String>> _translateBatch(
    List<String> texts,
    String sourceLang,
    String targetLang, {
    bool ignoreCooldown = false,
  }) async {
    final payload = jsonEncode(
      texts
          .asMap()
          .entries
          .map((e) => {'id': e.key, 'text': e.value})
          .toList(),
    );

    final systemPrompt =
        'You are a translation engine. Translate from $sourceLang to $targetLang. '
        'Respond ONLY with a JSON array in the format [{"id": <number>, "text": "<translated text>"}, ...]. '
        'Preserve the exact same number of items as the input. '
        'Do not add any explanation or commentary outside the JSON.';

    final result = await AiService.instance.chat(
      slot: 'text',
      ignoreCooldown: ignoreCooldown,
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': payload},
      ],
    );

    return _parseResponse(result.text, texts);
  }

  /// 解析翻译响应，提取 JSON 数组并按 id 映射。
  static List<String> _parseResponse(
    String response,
    List<String> originalTexts,
  ) {
    var jsonStr = response.trim();

    // 去掉 markdown 代码块包裹
    final codeBlock = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final codeMatch = codeBlock.firstMatch(jsonStr);
    if (codeMatch != null) {
      jsonStr = codeMatch.group(1)!.trim();
    }

    // 找到 [ ... ] 数组
    final arrayStart = jsonStr.indexOf('[');
    final arrayEnd = jsonStr.lastIndexOf(']');
    if (arrayStart == -1 || arrayEnd == -1) {
      throw const FormatException('模型响应中未找到有效 JSON 数组');
    }
    jsonStr = jsonStr.substring(arrayStart, arrayEnd + 1);

    final parsed = jsonDecode(jsonStr);
    if (parsed is! List) {
      throw const FormatException('模型返回的内容不是 JSON 数组结构');
    }

    final result = List<String>.from(originalTexts);
    var validItemCount = 0;

    for (final item in parsed) {
      if (item is Map) {
        final id = item['id'];
        final text = item['text'];
        final idx = id is int ? id : int.tryParse(id?.toString() ?? '');
        if (idx != null && text != null && idx >= 0 && idx < result.length) {
          result[idx] = text.toString();
          validItemCount++;
        }
      }
    }

    if (validItemCount == 0 && originalTexts.isNotEmpty) {
      throw const FormatException('模型未能正确映射返回任何翻译条目');
    }

    return result;
  }
}
