/// 实时字幕悬浮窗 ↔ 主进程 的双向通道（design D4）。
///
/// 主进程持有全部状态（识别、翻译、记录），悬浮窗只渲染状态 + 发指令。
/// 与 it-listening 的桥同构：用 `desktop_multi_window` 的 `WindowMethodChannel`
/// 双向模式，两侧同名通道成对注册。
library;

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 实时字幕的跨窗口桥。
class LiveCaptionBridge {
  LiveCaptionBridge._();
  static final LiveCaptionBridge instance = LiveCaptionBridge._();

  static const String channelName = 'v8_work_toolbox/live_caption';

  /// 悬浮窗 → 主进程 的指令处理（仅主进程侧注册）。
  void Function(String action)? onCommand;

  /// 主进程 → 悬浮窗 的指令处理（仅悬浮窗侧注册，用于让子窗口执行自身动作）。
  void Function(String action)? onCommandFromHost;

  /// 主进程 → 悬浮窗 的状态推送（仅主进程侧注册）。
  void Function(Map<String, dynamic> state)? onStateToCaption;

  WindowMethodChannel? _channel;

  /// 悬浮窗侧：注册状态接收 handler。
  Future<void> attachAsCaption({
    required void Function(Map<String, dynamic> state) onState,
  }) async {
    final channel =
        WindowMethodChannel(channelName, mode: ChannelMode.bidirectional);
    _channel = channel;
    await channel.setMethodCallHandler((call) async {
      if (call.method == 'state') {
        final args =
            Map<String, dynamic>.from((call.arguments as Map?) ?? const {});
        onState(args);
      } else if (call.method == 'command') {
        // 主进程 → 悬浮窗的指令（如 close 让子窗口自关进程）。
        onCommandFromHost?.call((call.arguments as String?) ?? '');
      }
      return null;
    });
  }

  /// 主进程侧：注册指令处理 handler。
  Future<void> attachAsHost() async {
    final channel =
        WindowMethodChannel(channelName, mode: ChannelMode.bidirectional);
    _channel = channel;
    await channel.setMethodCallHandler((call) async {
      if (call.method == 'command') {
        final action = (call.arguments as String?) ?? '';
        onCommand?.call(action);
      }
      return null;
    });
  }

  /// 悬浮窗侧：向主进程发一条指令。
  Future<void> sendCommand(String action) async {
    await _channel?.invokeMethod('command', action);
  }

  /// 主进程侧：向悬浮窗发一条指令（用于让子窗口执行自身动作如关闭进程）。
  Future<void> pushCommand(String action) async {
    await _channel?.invokeMethod('command', action);
  }

  /// 主进程侧：向悬浮窗推送状态。
  Future<void> pushState(Map<String, dynamic> state) async {
    await _channel?.invokeMethod('state', state);
  }
}
