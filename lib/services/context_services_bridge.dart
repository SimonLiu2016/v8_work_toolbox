import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 上下文服务桥接（macOS Services + 全局热键 → Flutter）
///
/// 监听 v8_work_toolbox/context_services 通道，分发查词和保存笔记事件。
class ContextServicesBridge {
  ContextServicesBridge._();
  static final ContextServicesBridge instance = ContextServicesBridge._();

  static const _channel = MethodChannel('v8_work_toolbox/context_services');

  /// 查词回调：text 为查询词
  void Function(String text)? onLookup;

  /// 保存笔记回调：text 为正文，html 为富文本，sourceApp 为来源 bundle ID
  void Function({
    required String text,
    required String html,
    required String sourceApp,
    String? url,
    String? title,
  })? onSaveNote;

  /// 初始化，监听来自原生层的方法调用
  void init() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'lookup':
          final text = call.arguments is String
              ? call.arguments as String
              : (call.arguments as Map?)?['text'] as String? ?? '';
          if (text.isNotEmpty) onLookup?.call(text);
          return null;

        case 'saveNote':
          final args = call.arguments is Map
              ? Map<String, dynamic>.from(call.arguments as Map)
              : <String, dynamic>{};
          onSaveNote?.call(
            text: args['text'] as String? ?? '',
            html: args['html'] as String? ?? '',
            sourceApp: args['sourceApp'] as String? ?? '',
            url: args['url'] as String?,
            title: args['title'] as String?,
          );
          return null;

        default:
          throw PlatformException(code: 'NOT_IMPLEMENTED');
      }
    } catch (e) {
      debugPrint('[ContextServicesBridge] error: $e');
      rethrow;
    }
  }

  /// 调用原生层获取前台浏览器 URL（AppleScript 路径）
  Future<String?> getBrowserUrl() async {
    try {
      final result = await _channel.invokeMethod<String>('getBrowserUrl');
      return result;
    } catch (e) {
      debugPrint('[ContextServicesBridge] getBrowserUrl error: $e');
      return null;
    }
  }

  /// 请求原生层将查词子窗口重定位到鼠标光标旁并隐藏系统红绿灯
  Future<void> styleLookupWindow() async {
    try {
      await _channel.invokeMethod('styleLookupWindow');
    } catch (e) {
      debugPrint('[ContextServicesBridge] styleLookupWindow error: $e');
    }
  }

  /// 获取当前鼠标屏幕绝对坐标
  Future<Map<String, double>?> getMouseLocation() async {
    try {
      final res = await _channel.invokeMethod<Map>('getMouseLocation');
      if (res != null) {
        return {
          'x': (res['x'] as num).toDouble(),
          'y': (res['y'] as num).toDouble(),
          'screenHeight': (res['screenHeight'] as num).toDouble(),
        };
      }
    } catch (e) {
      debugPrint('[ContextServicesBridge] getMouseLocation error: $e');
    }
    return null;
  }

  /// 发送 macOS 原生横幅通知
  Future<void> showNotification({required String title, required String notebook}) async {
    try {
      await _channel.invokeMethod('showNotification', {
        'title': title,
        'notebook': notebook,
      });
    } catch (e) {
      debugPrint('[ContextServicesBridge] showNotification error: $e');
    }
  }
}
