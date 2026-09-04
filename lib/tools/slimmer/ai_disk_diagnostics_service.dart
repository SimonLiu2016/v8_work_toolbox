import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
/// [current] 当前正在分析第几个 (1-based)
/// [total] 总数
/// [itemName] 当前条目名称
/// [completed] 已完成的结果列表
typedef AiProgressCallback = void Function(int current, int total, String itemName, List<AiDiagnosticResult> completed);

/// AI 驱动的磁盘智能研判服务
class AiDiskDiagnosticsService {
  AiDiskDiagnosticsService._();
  static final AiDiskDiagnosticsService instance = AiDiskDiagnosticsService._();

  /// 逐条研判，带进度回调
  Future<List<AiDiagnosticResult>> diagnoseBatch(
    List<SlimCandidateItem> items, {
    AiProgressCallback? onProgress,
  }) async {
    if (items.isEmpty) return [];

    final results = <AiDiagnosticResult>[];
    final home = Platform.environment['HOME'] ?? '';

    for (int i = 0; i < items.length; i++) {
      final item = items[i];
      onProgress?.call(i + 1, items.length, item.title, List.unmodifiable(results));

      try {
        final result = await _diagnoseOne(item, home);
        if (result != null) {
          results.add(result);
        }
      } catch (e) {
        debugPrint('AI 研判 "${item.title}" 失败: $e');
        // 单条失败继续下一条
      }
    }

    onProgress?.call(items.length, items.length, '', List.unmodifiable(results));
    return results;
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

    final responseText = await AiService.instance.chat(
      slot: 'text',
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
    );

    return _parseJsonObject(responseText, item.id);
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
      final advice = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      return advice;
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

  /// 兼容旧的批量解析（保留用于可能的批量场景）
  List<AiDiagnosticResult> _parseJsonArray(String raw) {
    final results = <AiDiagnosticResult>[];
    try {
      String jsonStr = raw.trim();
      final start = jsonStr.indexOf('[');
      final end = jsonStr.lastIndexOf(']');
      if (start != -1 && end != -1 && end > start) {
        jsonStr = jsonStr.substring(start, end + 1);
      }

      final dynamic decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        for (final obj in decoded) {
          if (obj is Map) {
            final id = obj['id']?.toString() ?? '';
            final app = obj['inferredApp']?.toString() ?? '未知应用';
            final safetyStr = obj['safety']?.toString().toLowerCase() ?? 'safe';
            final canDel = obj['canDelete'] == true;
            final advice = obj['advice']?.toString() ?? '建议清理';

            SafetyRating rating;
            if (safetyStr == 'danger') {
              rating = SafetyRating.danger;
            } else if (safetyStr == 'caution') {
              rating = SafetyRating.caution;
            } else {
              rating = SafetyRating.safe;
            }

            results.add(AiDiagnosticResult(
              itemId: id,
              inferredApp: app,
              safety: rating,
              advice: advice,
              canDelete: canDel,
            ));
          }
        }
      }
    } catch (_) {}

    return results;
  }
}
