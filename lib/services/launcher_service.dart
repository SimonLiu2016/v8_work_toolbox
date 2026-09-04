import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 全局快捷键配置模型
class HotKeyConfig {
  /// Carbon modifiers: optionKey = 2048, controlKey = 4096, cmdKey = 256, shiftKey = 512
  final int modifiers;
  final int keyCode;
  final String label;

  const HotKeyConfig({
    required this.modifiers,
    required this.keyCode,
    required this.label,
  });

  /// 默认快捷键：⌥Space
  static const HotKeyConfig defaultHotKey = HotKeyConfig(
    modifiers: 2048, // optionKey
    keyCode: 49, // kVK_Space
    label: '⌥ Space',
  );

  /// 备选快捷键：⌃⌥K
  static const HotKeyConfig ctrlOptK = HotKeyConfig(
    modifiers: 4096 | 2048, // controlKey | optionKey
    keyCode: 40, // kVK_ANSI_K
    label: '⌃ ⌥ K',
  );

  /// 备选快捷键：⌥K
  static const HotKeyConfig optK = HotKeyConfig(
    modifiers: 2048,
    keyCode: 40,
    label: '⌥ K',
  );

  Map<String, dynamic> toJson() => {
        'modifiers': modifiers,
        'keyCode': keyCode,
        'label': label,
      };

  factory HotKeyConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return defaultHotKey;
    return HotKeyConfig(
      modifiers: json['modifiers'] as int? ?? defaultHotKey.modifiers,
      keyCode: json['keyCode'] as int? ?? defaultHotKey.keyCode,
      label: json['label'] as String? ?? defaultHotKey.label,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HotKeyConfig &&
          runtimeType == other.runtimeType &&
          modifiers == other.modifiers &&
          keyCode == other.keyCode;

  @override
  int get hashCode => modifiers.hashCode ^ keyCode.hashCode;
}

/// 桌面外壳与全局快捷键平台桥接服务
class LauncherService {
  LauncherService._();
  static final LauncherService instance = LauncherService._();

  static const MethodChannel _channel =
      MethodChannel('v8_work_toolbox/launcher');

  /// 注册全局快捷键
  Future<bool> registerHotKey(HotKeyConfig config) async {
    try {
      final res = await _channel.invokeMethod<bool>('registerHotKey', {
        'modifiers': config.modifiers,
        'keyCode': config.keyCode,
      });
      return res ?? false;
    } catch (e) {
      debugPrint('Error registering hotkey: $e');
      return false;
    }
  }

  /// 注销全局快捷键
  Future<bool> unregisterHotKey() async {
    try {
      final res = await _channel.invokeMethod<bool>('unregisterHotKey');
      return res ?? false;
    } catch (e) {
      debugPrint('Error unregistering hotkey: $e');
      return false;
    }
  }

  /// 显示主窗口并聚焦
  Future<void> showWindow() async {
    try {
      await _channel.invokeMethod('showWindow');
    } catch (e) {
      debugPrint('Error showing window: $e');
    }
  }

  /// 隐藏主窗口
  Future<void> hideWindow() async {
    try {
      await _channel.invokeMethod('hideWindow');
    } catch (e) {
      debugPrint('Error hiding window: $e');
    }
  }

  /// 切换主窗口显隐
  Future<void> toggleWindow() async {
    try {
      await _channel.invokeMethod('toggleWindow');
    } catch (e) {
      debugPrint('Error toggling window: $e');
    }
  }

  /// 获取主窗口是否可见
  Future<bool> isWindowVisible() async {
    try {
      final res = await _channel.invokeMethod<bool>('isWindowVisible');
      return res ?? false;
    } catch (e) {
      debugPrint('Error checking window visibility: $e');
      return false;
    }
  }
}
