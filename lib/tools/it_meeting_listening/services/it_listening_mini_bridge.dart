/// 迷你播放窗与主进程之间的通信桥。
///
/// **播放状态在主进程**（design D7）：迷你窗只渲染状态 + 发指令。两者用
/// `desktop_multi_window` 的 `WindowMethodChannel` 通信——它是该插件
/// 提供的跨窗口双向通道（每个窗口注册一个 handler，另一侧 invokeMethod）。
///
/// 之所以不用 `MethodChannel`：普通 `MethodChannel` 是**同一引擎内**的
/// 通道，而 `desktop_multi_window` 的子窗口是**独立 Dart isolate**，
/// 跨 isolate 必须走窗口级通道。
library;

import 'package:desktop_multi_window/desktop_multi_window.dart';

/// 迷你窗 ↔ 主进程 的通信桥。
class ItListeningMiniBridge {
  ItListeningMiniBridge._();
  static final ItListeningMiniBridge instance = ItListeningMiniBridge._();

  /// 通道名。主进程与迷你窗两侧用同一个名字即可互发。
  static const String channelName = 'v8_work_toolbox/it_listening_mini';

  /// 迷你窗 → 主进程 的指令处理（仅主进程侧注册）。
  void Function(String action)? onCommand;

  /// 主进程 → 迷你窗 的状态推送（仅主进程侧注册）。
  void Function(Map<String, dynamic> state)? onStateToMini;

  WindowMethodChannel? _channel;

  /// 迷你窗侧：注册状态接收 handler。
  ///
  /// 迷你窗收到的指令以 `state` 方法名到达；主进程发的指令以 `command` 到达
  /// 主进程。
  ///
  /// **通道模式必须是 bidirectional**：unidirectional 模式下同名通道只能被
  /// 一个窗口注册（`registerUnidirectional` 遇到已注册的其它窗口直接返回
  /// `CHANNEL_LIMIT_REACHED`）。双向模式下允许两个引擎成对注册，且只有
  /// 配对双方能互相调用——正是这里需要的：一对主进程 ↔ 迷你窗。
  Future<void> attachAsMini({
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

  /// 迷你窗侧：向主进程发一条指令。
  Future<void> sendCommand(String action) async {
    await _channel?.invokeMethod('command', action);
  }

  /// 主进程侧：向迷你窗推送状态。
  Future<void> pushState(Map<String, dynamic> state) async {
    await _channel?.invokeMethod('state', state);
  }
}
