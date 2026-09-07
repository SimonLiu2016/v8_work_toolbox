import 'package:flutter/foundation.dart';

/// 日志条目类型
enum AiLogType {
  request,
  response,
  warning,
  error,
}

/// 结构化 AI 日志条目
class AiLogEntry {
  final DateTime timestamp;
  final AiLogType type;
  final String providerName;
  final String? protocol;
  final String? model;
  final String? endpoint;
  final int? statusCode;
  final int? durationMs;
  final String message;
  final String? fullContent;

  const AiLogEntry({
    required this.timestamp,
    required this.type,
    required this.providerName,
    this.protocol,
    this.model,
    this.endpoint,
    this.statusCode,
    this.durationMs,
    required this.message,
    this.fullContent,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }
}

/// 统一结构化 AI 终端与界面调用日志记录器
class AiLogger {
  AiLogger._();

  static bool enabled = true;
  static const int maxEntries = 200;

  static final List<AiLogEntry> _entries = [];

  /// 供 UI 绑定的响应式通知器（每次变更抛出不可变列表副本）
  static final ValueNotifier<List<AiLogEntry>> notifier = ValueNotifier<List<AiLogEntry>>(const []);

  /// 获取当前内存中的日志条目只读列表
  static List<AiLogEntry> get entries => List.unmodifiable(_entries);

  static void _addEntry(AiLogEntry entry) {
    if (_entries.length >= maxEntries) {
      _entries.removeAt(0);
    }
    _entries.add(entry);
    notifier.value = List.unmodifiable(_entries);
  }

  /// 清空所有内存日志
  static void clear() {
    _entries.clear();
    notifier.value = const [];
  }

  /// 格式化导出全部日志为纯文本
  static String exportAsString() {
    final buffer = StringBuffer();
    for (final e in _entries) {
      buffer.writeln('[${e.formattedTime}] [${e.type.name.toUpperCase()}] Provider: ${e.providerName}');
      if (e.protocol != null) buffer.writeln('  Protocol: ${e.protocol} | Model: ${e.model ?? 'N/A'}');
      if (e.endpoint != null) buffer.writeln('  Endpoint: ${e.endpoint}');
      if (e.statusCode != null) buffer.writeln('  Status: ${e.statusCode} | Duration: ${e.durationMs ?? 0}ms');
      buffer.writeln('  Message: ${e.message}');
      if (e.fullContent != null && e.fullContent != e.message) {
        buffer.writeln('  Details: ${e.fullContent}');
      }
      buffer.writeln('--------------------------------------------------');
    }
    return buffer.toString();
  }

  /// 打印发出的 AI 请求概要
  static void logRequest({
    required String providerName,
    required String protocol,
    required String model,
    required String endpoint,
    String? promptSummary,
  }) {
    if (!enabled) return;
    final summary = (promptSummary ?? '').replaceAll('\n', ' ').trim();
    final truncated = summary.length > 120 ? '${summary.substring(0, 120)}...' : summary;

    final entry = AiLogEntry(
      timestamp: DateTime.now(),
      type: AiLogType.request,
      providerName: providerName,
      protocol: protocol,
      model: model,
      endpoint: endpoint,
      message: truncated,
      fullContent: promptSummary,
    );
    _addEntry(entry);

    final buffer = StringBuffer()
      ..writeln('┌── [AI Request] ──────────────────────────────────────────')
      ..writeln('│ Provider: $providerName | Protocol: $protocol | Model: $model')
      ..writeln('│ Endpoint: $endpoint')
      ..writeln('│ Prompt: "$truncated"')
      ..write('└──');
    debugPrint(buffer.toString());
  }

  /// 打印接收到的 AI 响应概要
  static void logResponse({
    required String providerName,
    required int statusCode,
    required int durationMs,
    String? bodyPreview,
  }) {
    if (!enabled) return;
    final preview = (bodyPreview ?? '').replaceAll('\n', ' ').trim();
    final truncated = preview.length > 120 ? '${preview.substring(0, 120)}...' : preview;

    final entry = AiLogEntry(
      timestamp: DateTime.now(),
      type: AiLogType.response,
      providerName: providerName,
      statusCode: statusCode,
      durationMs: durationMs,
      message: truncated,
      fullContent: bodyPreview,
    );
    _addEntry(entry);

    final buffer = StringBuffer()
      ..writeln('┌── [AI Response] ─────────────────────────────────────────')
      ..writeln('│ Provider: $providerName | Status: $statusCode | Duration: ${durationMs}ms')
      ..writeln('│ Body: "$truncated"')
      ..write('└──');
    debugPrint(buffer.toString());
  }

  /// 打印警告日志（如 429 退避重试）
  static void logWarning(String message, {String providerName = 'system'}) {
    if (!enabled) return;
    final entry = AiLogEntry(
      timestamp: DateTime.now(),
      type: AiLogType.warning,
      providerName: providerName,
      message: message,
    );
    _addEntry(entry);
    debugPrint('⚠️ [AI Warning] $message');
  }

  /// 打印错误日志
  static void logError(String message, {String providerName = 'system'}) {
    if (!enabled) return;
    final entry = AiLogEntry(
      timestamp: DateTime.now(),
      type: AiLogType.error,
      providerName: providerName,
      message: message,
    );
    _addEntry(entry);
    debugPrint('❌ [AI Error] $message');
  }
}
