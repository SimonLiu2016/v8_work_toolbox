/// 实时语音识别 (ASR) 通用客户端抽象。
///
/// 定义面向音频切片的统一转录接口，屏蔽 StepFun SSE、OpenRouter REST 等各供应商底层差异。
library;

/// ASR 事件类型。
enum AsrEventType { delta, done, error }

/// 一次识别事件。
class AsrEvent {
  AsrEvent.delta(this.text, {this.startMs, this.endMs})
      : type = AsrEventType.delta,
        message = null;
  AsrEvent.done(this.text, {this.startMs, this.endMs})
      : type = AsrEventType.done,
        message = null;
  AsrEvent.error(this.message)
      : type = AsrEventType.error,
        text = '',
        startMs = null,
        endMs = null;

  final AsrEventType type;

  /// 增量文本（delta）或完整文本（done）。
  final String text;

  /// 起始毫秒（仅 enable_timestamp 时非空）。
  final int? startMs;

  /// 结束毫秒（仅 enable_timestamp 时非空）。
  final int? endMs;

  /// 错误信息（仅 error 事件）。
  final String? message;
}

/// 可归因的识别错误。
class AsrException implements Exception {
  AsrException(this.kind, this.detail);
  final AsrErrorKind kind;
  final String detail;
  @override
  String toString() => 'AsrException($kind): $detail';
}

enum AsrErrorKind {
  /// 鉴权失败（API Key 无效/过期）。
  auth,

  /// 端点不可用 / 404。
  endpoint,

  /// 配额不足。
  quota,

  /// 网络中断。
  network,

  /// 其它。
  unknown,
}

/// 实时 ASR 通用客户端统一接口。
abstract interface class LiveAsrClient {
  /// 识别一个音频块（16-bit 小端 PCM），产出 ASR 事件流。
  Stream<AsrEvent> transcribe(
    List<int> pcm, {
    String language = 'zh',
    List<String> hotwords = const [],
    bool enableTimestamp = true,
    String? model,
  });
}
