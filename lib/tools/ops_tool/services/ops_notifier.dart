import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'argocd_service.dart';

/// 运维工具的桌面通知通道。
/// 与 `asset_reminder_service.dart` 等宿主既有先例一致：走操作系统原生通知，
/// 通知失败仅记日志，不中断业务主流程。
class OpsNotifier {
  OpsNotifier._();
  static final OpsNotifier instance = OpsNotifier._();

  /// 测试环境可覆写；默认为 `Platform.isMacOS`。
  bool isDesktopMac = Platform.isMacOS;

  bool _isRunning = false;
  StreamSubscription<ArgoCdChangeEvent>? _sub;

  bool get isRunning => _isRunning;

  /// 订阅 ArgoCD 变更事件并逐条投递为系统通知。幂等，可重复调用。
  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    _sub ??= ArgoCdService.instance.changes.listen(_dispatchArgoCdChange);
  }

  Future<void> stop() async {
    _isRunning = false;
    await _sub?.cancel();
    _sub = null;
  }

  Future<void> _dispatchArgoCdChange(ArgoCdChangeEvent e) async {
    try {
      await showNotification(
        title: 'ArgoCD Tag 变更',
        body: e.message,
        isMac: isDesktopMac,
      );
    } catch (err) {
      debugPrint('[通知] ArgoCD 变更通知发送失败: $err');
    }
  }

  /// 发送操作系统原生通知。非 macOS 环境为 no-op。
  static Future<void> showNotification({
    required String title,
    required String body,
    String? subtitle,
    bool isMac = true,
    Future<void> Function(String args)? dispatch,
  }) async {
    if (!isMac) return;

    final safeBody = body.replaceAll('"', '\\"').replaceAll('\n', ' ');
    final args = <String>[
      '-e',
      'display notification "$safeBody" with title "V8 运维工具"',
    ];
    if (subtitle != null && subtitle.trim().isNotEmpty) {
      args.add('subtitle "${_safe(subtitle)}"');
    }

    if (dispatch != null) {
      await dispatch(args.join(' '));
      return;
    }
    await Process.run('osascript', args);
  }

  static String _safe(String value) =>
      value.replaceAll('"', '\\"').replaceAll('\n', ' ');
}
