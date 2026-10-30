/// 实时会议翻译的全局热键。
///
/// 热键必须在**任意前台应用**中生效——用户在 IDE/浏览器里工作时，手不离开键盘
/// 就能切说话人、开关字幕窗（spec: live-caption-overlay 说话人手动切换）。
/// macOS 上这必须走 Carbon 的 `RegisterEventHotKey`（见 AppDelegate.swift）。
library;

import 'package:flutter/services.dart';

/// 实时会议翻译动作。
class LiveCaptionAction {
  static const String speaker0 = 'speaker:0';
  static const String speaker1 = 'speaker:1';
  static const String speaker2 = 'speaker:2';
  static const String toggle = 'toggle';
}

/// 实时会议翻译的全局热键管理（单例）。
///
/// 固定键位：⌥1/⌥2/⌥3 切说话人，⌥T 开关字幕窗。原生侧 id 20-23。
class LiveCaptionHotKeyService {
  LiveCaptionHotKeyService._();
  static final LiveCaptionHotKeyService instance = LiveCaptionHotKeyService._();

  static const MethodChannel _channel =
      MethodChannel('v8_work_toolbox/live_caption_hotkeys');

  static const int optionKey = 2048;

  /// 热键按下时的回调（原生侧调用）。
  void Function(String action)? onAction;

  /// 注册固定热键（⌥1/⌥2/⌥3 + ⌥T）。
  Future<void> register() async {
    try {
      await _channel.invokeMethod('registerLiveCaptionHotKeys');
    } catch (_) {
      // 注册失败（原生通道不可用，如在非 macOS 平台）时静默——本工具仅桌面。
    }
  }

  /// 注销热键。
  Future<void> unregister() async {
    try {
      await _channel.invokeMethod('unregisterLiveCaptionHotKeys');
    } catch (_) {}
  }

  /// 初始化：注册通道 handler。
  void init() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'liveCaptionHotKey') {
        final action = (call.arguments as String?) ?? '';
        onAction?.call(action);
      }
      return null;
    });
  }
}
