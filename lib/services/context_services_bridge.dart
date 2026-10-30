import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 上下文服务桥接（macOS Services + 全局热键 + 浏览器深链 → Flutter）
///
/// 监听 v8_work_toolbox/context_services 通道，分发查词、保存笔记、加生词三类事件。
/// 深链协议（`v8toolbox://`）的全部入口都在这里落地 —— 本文件是桌面端唯一
/// 知道"深链能表达什么"的地方。
class ContextServicesBridge {
  ContextServicesBridge._();
  static final ContextServicesBridge instance = ContextServicesBridge._();

  static const _channel = MethodChannel('v8_work_toolbox/context_services');

  /// 查词回调：[text] 为查询词，[mode] 为 `'dict'`（词典优先）或 `'ai'`
  /// （跳过词典直接问 AI）。
  ///
  /// mode 从深链一路带到这里：用户已经在浏览器里点过「问 AI 深度解析」，
  /// 丢掉它就等于把那次点击当作没发生。
  void Function(String text, String mode)? onLookup;

  /// 加生词回调：text 为要加入生词本的词。只加词，不开窗口、不查词典。
  void Function(String text)? onAddToVocab;

  /// 保存笔记回调：text 为正文，html 为富文本，sourceApp 为来源 bundle ID
  void Function({
    required String text,
    required String html,
    required String sourceApp,
    String? url,
    String? title,
  })? onSaveNote;

  /// 原生通知点击回调：actionType 为业务动作类型（如 'news'），payload 为关联数据
  void Function(String actionType, Map<String, dynamic> payload)? onNotificationAction;

  /// 初始化，监听来自原生层的方法调用
  void init() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  @visibleForTesting
  Future<dynamic> handleMethodCallForTest(MethodCall call) => _handleMethodCall(call);

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'lookup':
          // 两种历史形态都要认：纯 String（早期）与 Map（带 mode 的版本）。
          // 契约变更不能把还没升级的原生层挡死。
          late final String text;
          late final String mode;
          if (call.arguments is String) {
            text = call.arguments as String;
            mode = 'dict';
          } else {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            text = args['text'] as String? ?? '';
            // 缺省 dict：既有调用方不带 mode，必须保持词典优先。
            mode = (args['mode'] as String?)?.trim().toLowerCase() ?? 'dict';
          }
          if (text.isNotEmpty) onLookup?.call(text, mode.isEmpty ? 'dict' : mode);
          return null;

        case 'addToVocab':
          final text = call.arguments is String
              ? call.arguments as String
              : (call.arguments as Map?)?['text'] as String? ?? '';
          if (text.isNotEmpty) onAddToVocab?.call(text);
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

        case 'notificationAction':
          final args = call.arguments is Map
              ? Map<String, dynamic>.from(call.arguments as Map)
              : <String, dynamic>{};
          final actionType = args['actionType'] as String? ?? '';
          final payload = args['payload'] is Map
              ? Map<String, dynamic>.from(args['payload'] as Map)
              : <String, dynamic>{};
          onNotificationAction?.call(actionType, payload);
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

  /// 请求原生层将实时字幕子窗口配置为真透明底色、浮动置顶并隐藏系统红绿灯
  Future<void> styleLiveCaptionWindow() async {
    try {
      await _channel.invokeMethod('styleLiveCaptionWindow');
    } catch (e) {
      debugPrint('[ContextServicesBridge] styleLiveCaptionWindow error: $e');
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
  Future<void> showNotification({
    required String title,
    String? subtitle,
    String? body,
    String? notebook,
    String? actionType,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final args = <String, dynamic>{
        'title': title,
      };
      if (subtitle != null) args['subtitle'] = subtitle;
      if (body != null) args['body'] = body;
      if (notebook != null) args['notebook'] = notebook;
      if (actionType != null) args['actionType'] = actionType;
      if (payload != null) args['payload'] = payload;

      await _channel.invokeMethod('showNotification', args);
    } catch (e) {
      debugPrint('[ContextServicesBridge] showNotification error: $e');
    }
  }
}
