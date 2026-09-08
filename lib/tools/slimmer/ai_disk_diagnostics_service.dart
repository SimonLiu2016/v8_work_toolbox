import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../services/ai_logger.dart';
import '../../services/ai_service.dart';
import 'slimmer_models.dart';

class AiDiagnosticResult {
  final String itemId;
  final String inferredApp;
  final SafetyRating safety;
  final String advice;
  final bool canDelete;

  const AiDiagnosticResult({
    required this.itemId,
    required this.inferredApp,
    required this.safety,
    required this.advice,
    required this.canDelete,
  });
}

/// AI 诊断进度回调
/// [current] 串行模式: 当前第几个 (1-based); 并发模式: 已完成数
/// [total] 总数
/// [itemName] 当前条目名称 (并发模式下为最后完成的条目)
/// [completed] 已完成的结果列表
typedef AiProgressCallback = void Function(int current, int total, String itemName, List<AiDiagnosticResult> completed);

/// AI 驱动的磁盘智能研判服务
class AiDiskDiagnosticsService {
  AiDiskDiagnosticsService._();
  static final AiDiskDiagnosticsService instance = AiDiskDiagnosticsService._();

  String? lastError;

  /// 批量诊断条目间的步频间隔（串行模式下避免触发服务商 QPS 限流）
  static const _pacingDuration = Duration(milliseconds: 800);

  /// 指数退避基础延迟
  static const _baseRetryDelay = Duration(seconds: 3);

  /// 指数退避最大延迟
  static const _maxRetryDelay = Duration(seconds: 60);

  /// 批量诊断，支持可配置并发与重试
  Future<List<AiDiagnosticResult>> diagnoseBatch(
    List<SlimCandidateItem> items, {
    AiProgressCallback? onProgress,
    int concurrency = 1,
    int maxRetries = 10,
  }) async {
    if (items.isEmpty) return [];

    lastError = null;
    final home = Platform.environment['HOME'] ?? '';
    final isParallel = concurrency > 1;

    // 结果数组，按输入顺序索引赋值，保证顺序一致
    final results = List<AiDiagnosticResult?>.filled(items.length, null);
    int completedCount = 0;
    int nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final i = nextIndex++;
        if (i >= items.length) return;

        final item = items[i];

        // 串行模式: 逐条报告当前条目名
        if (!isParallel) {
          onProgress?.call(i + 1, items.length, item.title, List.unmodifiable(results.whereType<AiDiagnosticResult>()));
        }

        results[i] = await _diagnoseWithRetry(item, home, maxRetries: maxRetries);

        completedCount++;

        // 并发模式: 报告已完成数
        if (isParallel) {
          onProgress?.call(completedCount, items.length, item.title, List.unmodifiable(results.whereType<AiDiagnosticResult>()));
        }

        // 串行步频控制
        if (!isParallel && i < items.length - 1 && _pacingDuration > Duration.zero) {
          await Future.delayed(_pacingDuration);
        }
      }
    }

    final poolSize = math.min(concurrency, items.length);
    final workers = List.generate(poolSize, (_) => worker());
    await Future.wait(workers);

    final finalResults = results.whereType<AiDiagnosticResult>().toList();
    onProgress?.call(items.length, items.length, '', List.unmodifiable(finalResults));
    return finalResults;
  }

  /// 带指数退避的重试包装
  Future<AiDiagnosticResult?> _diagnoseWithRetry(
    SlimCandidateItem item,
    String home, {
    required int maxRetries,
  }) async {
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final result = await _diagnoseOne(item, home);
        if (result != null) return result;
        // 解析结果为空，非网络错误，不重试
        lastError ??= '条目 "${item.title}" AI 解析结果为空或格式不匹配';
        return null;
      } on SlotUnavailableException catch (e) {
        // 槽位级别错误，不重试
        lastError = e.toString();
        debugPrint('AI 槽位不可用，终止该条目诊断: $e');
        return null;
      } catch (e) {
        if (!isRetryable(e) || attempt == maxRetries - 1) {
          lastError = e.toString();
          debugPrint('AI 研判 "${item.title}" 失败 (attempt ${attempt + 1}/$maxRetries): $e');
          return null;
        }
        // 指数退避: 3s, 6s, 12s, 24s, 48s, 60s, 60s, ...
        final delayMs = math.min(
          _baseRetryDelay.inMilliseconds * (1 << attempt),
          _maxRetryDelay.inMilliseconds,
        );
        final delay = Duration(milliseconds: delayMs);
        AiLogger.logWarning(
          'AI 研判 "${item.title}" 遇到可重试错误 (attempt ${attempt + 1}/$maxRetries): '
          '${e.toString().substring(0, math.min(80, e.toString().length))}... '
          '等待 ${delay.inSeconds}s 后重试',
          providerName: 'disk-diagnostics',
        );
        await Future.delayed(delay);
      }
    }
    return null;
  }

  /// 判断错误是否值得重试 (429, 超时, 网络错误, 5xx)
  @visibleForTesting
  static bool isRetryable(Object e) {
    final msg = e.toString().toLowerCase();
    return msg.contains('429') ||
        msg.contains('too many requests') ||
        msg.contains('timeout') ||
        msg.contains('connection') ||
        msg.contains('502') ||
        msg.contains('503') ||
        msg.contains('520') ||
        msg.contains('521') ||
        msg.contains('522') ||
        msg.contains('523') ||
        msg.contains('524');
  }

  /// 单条研判
  Future<AiDiagnosticResult?> _diagnoseOne(SlimCandidateItem item, String home) async {
    final relPath = item.path.startsWith(home) ? item.path.replaceFirst(home, '~') : item.path;
    final daysAgo = item.lastModified != null ? DateTime.now().difference(item.lastModified!).inDays : null;

    final systemPrompt = '''
你是一名 macOS 系统存储与文件架构专家。用户正在进行系统瘦身，但以下文件/目录的来源或删除安全性存疑。
请分析这些路径的元数据，推断其所属应用、作用、清理安全性，并给出中肯的处理建议。
严格返回符合以下 JSON 格式的对象，不要包含任何 markdown 代码块外部的文字：
{
  "id": "${item.id}",
  "inferredApp": "推断应用名称或框架名",
  "safety": "safe" 或 "caution" 或 "danger",
  "canDelete": true 或 false,
  "advice": "简短有说服力的建议（30字以内）"
}
''';

    final userPrompt = '''
请分析以下条目：
- 路径: $relPath
- 名称: ${item.title}
- 体积: ${item.formattedSize}
- 最后修改: ${daysAgo != null ? "$daysAgo 天前" : "未知"}
- 分类: ${item.category.label}
''';

    final result = await AiService.instance.chat(
      slot: 'text',
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    );

    return _parseJsonObject(result.text, item.id);
  }

  /// 单个条目深度研判会诊（详情弹窗用）
  Future<String> diagnoseSingle(SlimCandidateItem item) async {
    final home = Platform.environment['HOME'] ?? '';
    final relPath = item.path.startsWith(home) ? item.path.replaceFirst(home, '~') : item.path;
    final daysAgo = item.lastModified != null ? DateTime.now().difference(item.lastModified!).inDays : null;

    final prompt = '''
你是一名 macOS 系统专家。用户想清理位于以下路径的文件/目录：
- 路径: $relPath
- 名称: ${item.title}
- 体积: ${item.formattedSize}
- 最后修改: ${daysAgo != null ? "$daysAgo 天前" : "未知"}
- 当前分类: ${item.category.label}

请给出深度分析报告，涵盖：
1. 【归属分析】：它具体是哪个应用或系统的什么组件产生的？
2. 【存在意义】：它存放的是缓存、日志、配置、还是运行时数据？
3. 【删除后果】：如果移至废纸篓，会不会导致软件无法使用或丢失关键资产？
4. 【行动建议】：是否建议删除？
请用清晰、专业的中文回答，排版精美。
''';

    try {
      final result = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      return result.text;
    } on SlotUnavailableException catch (e) {
      return '⚠️ AI 槽位不可用\n\n$e\n\n请在左侧「AI能力配置」→「默认能力槽位」中为 Text 槽位添加至少一个供应商候选。';
    } catch (e) {
      return 'AI 诊断请求失败: $e\n请检查左侧「AI能力配置」中的供应商与模型设置是否正常。';
    }
  }

  AiDiagnosticResult? _parseJsonObject(String raw, String expectedId) {
    try {
      String jsonStr = raw.trim();
      // 尝试提取 JSON 对象
      final start = jsonStr.indexOf('{');
      final end = jsonStr.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        jsonStr = jsonStr.substring(start, end + 1);
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is Map) {
        final id = decoded['id']?.toString() ?? expectedId;
        final app = decoded['inferredApp']?.toString() ?? '未知应用';
        final safetyStr = decoded['safety']?.toString().toLowerCase() ?? 'safe';
        final canDel = decoded['canDelete'] == true;
        final advice = decoded['advice']?.toString() ?? '建议清理';

        SafetyRating rating;
        if (safetyStr == 'danger') {
          rating = SafetyRating.danger;
        } else if (safetyStr == 'caution') {
          rating = SafetyRating.caution;
        } else {
          rating = SafetyRating.safe;
        }

        return AiDiagnosticResult(
          itemId: id,
          inferredApp: app,
          safety: rating,
          advice: advice,
          canDelete: canDel,
        );
      }
    } catch (_) {}

    return null;
  }
}
