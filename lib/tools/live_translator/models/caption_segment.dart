/// 字幕单元模型
///
/// 承载一条已定稿（或识别中）的字幕：说话人、原文、译文、起止时间与译文状态。
/// 译文状态用于"原文先显、译文补登"的流程（design D6）。
library;

/// 译文状态。
enum TranslationStatus {
  /// 未开启翻译，不需要译文。
  disabled,

  /// 翻译进行中（原文已显示，译文待返回）。
  pending,

  /// 译文已返回。
  done,

  /// 翻译失败（原文与导出不受影响）。
  failed,
}

/// 一条字幕单元。
class CaptionSegment {
  CaptionSegment({
    required this.id,
    required this.text,
    required this.speakerSlot,
    required this.startMs,
    required this.endMs,
    this.translation,
    this.translationStatus = TranslationStatus.disabled,
    this.isFinal = false,
  });

  /// 唯一标识。
  final String id;

  /// 识别原文。
  String text;

  /// 所属说话人槽位索引（0-based）。
  final int speakerSlot;

  /// 起始时间（毫秒，相对记录起点的时间基准）。
  final int startMs;

  /// 结束时间（毫秒）。识别中的句子 endMs 可能为 0 或随时间推进。
  int endMs;

  /// 译文；未返回时为 null。
  String? translation;

  /// 译文状态。
  TranslationStatus translationStatus;

  /// 是否已定稿（ASR done 事件到达）。false 表示识别中（增量刷新）。
  bool isFinal;

  CaptionSegment copyWith({
    String? text,
    int? speakerSlot,
    String? translation,
    TranslationStatus? translationStatus,
    int? endMs,
    bool? isFinal,
  }) {
    return CaptionSegment(
      id: id,
      text: text ?? this.text,
      speakerSlot: speakerSlot ?? this.speakerSlot,
      startMs: startMs,
      endMs: endMs ?? this.endMs,
      translation: translation ?? this.translation,
      translationStatus: translationStatus ?? this.translationStatus,
      isFinal: isFinal ?? this.isFinal,
    );
  }
}
