import 'dart:async';

import 'package:flutter/services.dart';

/// 剪贴板卫生服务（spec：Secret reveal and clipboard hygiene）
///
/// 复制 secret 后按配置延时自动清空剪贴板。
/// 默认 20 秒；可选 10/20/30/60 秒或禁用（0）。
class ClipboardHygieneService {
  ClipboardHygieneService._();
  static final ClipboardHygieneService instance = ClipboardHygieneService._();

  static const List<int> delayOptions = [0, 10, 20, 30, 60];
  static const int defaultDelaySeconds = 20;

  int _delaySeconds = defaultDelaySeconds;
  Timer? _clearTimer;
  String? _lastCopied;

  int get delaySeconds => _delaySeconds;

  /// 设置清空延时（秒），0 表示禁用
  void setDelaySeconds(int seconds) {
    _delaySeconds = seconds;
    if (seconds <= 0) {
      _clearTimer?.cancel();
      _clearTimer = null;
    }
  }

  /// 复制 secret 并调度自动清空
  Future<void> copySecret(String secret) async {
    await Clipboard.setData(ClipboardData(text: secret));
    _lastCopied = secret;

    _clearTimer?.cancel();
    if (_delaySeconds > 0) {
      _clearTimer = Timer(Duration(seconds: _delaySeconds), _clearIfMatches);
    }
  }

  /// 立即清空（若剪贴板内容仍为我们复制的 secret）
  Future<void> clearNow() async {
    _clearTimer?.cancel();
    _clearTimer = null;
    await _clearIfMatches();
  }

  Future<void> _clearIfMatches() async {
    final last = _lastCopied;
    if (last == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      // 仅在剪贴板仍是我们的 secret 时清空，避免误删用户后续复制的内容
      if (current?.text == last) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // 读取剪贴板失败时保守清空
      await Clipboard.setData(const ClipboardData(text: ''));
    } finally {
      _lastCopied = null;
    }
  }

  /// 测试钩子
  void resetForTesting() {
    _clearTimer?.cancel();
    _clearTimer = null;
    _lastCopied = null;
    _delaySeconds = defaultDelaySeconds;
  }
}
