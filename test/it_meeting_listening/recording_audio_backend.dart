import 'dart:async';

import 'package:V8WorkToolbox/tools/it_meeting_listening/services/pronunciation_audio_backend.dart';

/// 测试用假**设备**后端：只替换设备、**不替换播放编排**。
///
/// 关键点：编排（停止 → 播放 → 等待完成/超时）仍由对话框自身执行，所以这些行在
/// 测试与生产里是同一段代码——这正是把接缝放在设备边界的目的。
class RecordingAudioBackend implements PronunciationAudioBackend {
  RecordingAudioBackend({
    this.completesImmediately = true,
    this.playError,
    this.customCompleteStream,
    List<String>? played,
  }) : played = played ?? <String>[];

  /// 自定义完成流（可传入运行时类型为 Stream<Object> 等协变流，复刻生产 audioplayers 环境）。
  final Stream<dynamic>? customCompleteStream;

  /// 每次 [playFile] 收到的路径（按调用顺序）。
  final List<String> played;

  /// 为真时"播放立即完成"（模拟短词播完）；为假时永不完成，用于验证连播的
  /// **超时上限**（应当放行而不是卡死）。
  final bool completesImmediately;

  /// 非空时 [playFile] 抛出它（用于验证**播放阶段**的失败文案与不中断步进）。
  final Object? playError;

  int stopCount = 0;
  bool disposed = false;

  /// 永不发送也永不结束的流（只在 [completesImmediately] 为假时使用）。
  /// 必须是 broadcast：超时放行后上一个 `.first` 的订阅可能仍在，single-subscription
  /// 流会让下一个词的再订阅直接抛 "Stream has already been listened to"。
  final StreamController<void> _never = StreamController<void>.broadcast();

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> playFile(String path) async {
    played.add(path);
    final err = playError;
    if (err != null) throw err;
  }

  @override
  Stream<void> get onPlayerComplete {
    final custom = customCompleteStream;
    if (custom != null) {
      // 模拟 audioplayers 生产表现：真实运行时类型是 Stream<Object/AudioEvent>，
      // 但因协变而可以作为 Stream<void> 返回。
      return custom as Stream<void>;
    }
    if (!completesImmediately) return _never.stream;
    // 注意：不能在 playFile 里 add —— 订阅（.first）发生在 playFile 之后，
    // broadcast 流会丢掉提前发出的事件。用一条订阅即完成的流。
    return Future<void>.value().asStream();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _never.close();
  }
}