import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'keychain_service.dart';

typedef PlaybackInhibitor = bool Function();

/// 隐私空间安全服务（负责 6 位 PIN 码管理、哈希验证、会话状态与闲置自动锁定）
class PrivacySecurityService {
  PrivacySecurityService._();
  static final PrivacySecurityService instance = PrivacySecurityService._();

  static const String _pinHashKey = 'privacy_pin_hash';
  static const String _pinSaltKey = 'privacy_pin_salt';
  static const String _autoLockKey = 'privacy_auto_lock_minutes';

  final KeychainService _keychain = KeychainService.instance;

  final List<PlaybackInhibitor> _playbackInhibitors = [];

  /// 注册播放状态抑制器（返回 true 时阻止自动锁屏）
  void registerPlaybackInhibitor(PlaybackInhibitor inhibitor) {
    if (!_playbackInhibitors.contains(inhibitor)) {
      _playbackInhibitors.add(inhibitor);
    }
  }

  /// 注销播放状态抑制器
  void unregisterPlaybackInhibitor(PlaybackInhibitor inhibitor) {
    _playbackInhibitors.remove(inhibitor);
  }

  /// 检查是否有任何媒体正在播放
  bool isPlaybackActive() {
    return _playbackInhibitors.any((fn) {
      try {
        return fn();
      } catch (_) {
        return false;
      }
    });
  }

  /// 内存解锁状态通知器（UI 响应式监听）
  final ValueNotifier<bool> isUnlockedNotifier = ValueNotifier<bool>(false);
  bool get isUnlocked => isUnlockedNotifier.value;

  DateTime? _lastActiveTime;
  Timer? _idleCheckTimer;
  int _autoLockMinutes = 5; // 默认闲置 5 分钟锁定，0 表示禁用
  int get autoLockMinutes => _autoLockMinutes;

  /// 初始化服务
  Future<void> init() async {
    final autoLockStr = await _keychain.readSecret(_autoLockKey);
    if (autoLockStr != null && autoLockStr.isNotEmpty) {
      _autoLockMinutes = int.tryParse(autoLockStr) ?? 5;
    }
    _startIdleTimer();
  }

  /// 检查是否已设置 6 位 PIN 码
  Future<bool> hasPin() async {
    final hash = await _keychain.readSecret(_pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// 设置新的 6 位 PIN 码
  Future<bool> setupPin(String pin) async {
    final trimmed = pin.trim();
    if (!_isValidPin(trimmed)) return false;

    final salt = _generateSalt();
    final hash = hashPin(trimmed, salt);

    try {
      await _keychain.writeSecret(_pinSaltKey, salt);
      await _keychain.writeSecret(_pinHashKey, hash);
    } catch (e) {
      debugPrint('保存 PIN 码失败: $e');
      return false;
    }

    isUnlockedNotifier.value = true;
    recordActivity();
    return true;
  }

  /// 校验 6 位 PIN 码并解锁
  Future<bool> verifyAndUnlock(String pin) async {
    final trimmed = pin.trim();
    if (!_isValidPin(trimmed)) return false;

    final salt = await _keychain.readSecret(_pinSaltKey);
    final storedHash = await _keychain.readSecret(_pinHashKey);

    if (salt == null || storedHash == null || salt.isEmpty || storedHash.isEmpty) {
      return false;
    }

    final computedHash = hashPin(trimmed, salt);
    if (computedHash == storedHash) {
      isUnlockedNotifier.value = true;
      recordActivity();
      return true;
    }
    return false;
  }

  /// 立即锁定隐私空间
  void lock() {
    isUnlockedNotifier.value = false;
    _lastActiveTime = null;
  }

  /// 记录隐私空间内的用户活跃时间
  void recordActivity() {
    _lastActiveTime = DateTime.now();
  }

  /// 设置闲置自动锁定分钟数
  Future<void> setAutoLockMinutes(int minutes) async {
    _autoLockMinutes = minutes;
    await _keychain.writeSecret(_autoLockKey, minutes.toString());
  }

  /// 计算 PIN 码哈希（加盐 SHA-256）
  static String hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin::$salt::v8_privacy_space_2026');
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  bool _isValidPin(String pin) {
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// 执行一次闲置超时检测（支持定时器与单元测试快速验证）
  bool checkIdleTimeout({DateTime? currentTime}) {
    if (!isUnlocked || _autoLockMinutes <= 0) return false;

    if (isPlaybackActive()) {
      // 正在播放中，抑制自动锁定并持续保持活跃时间
      recordActivity();
      return false;
    }

    if (_lastActiveTime == null) return false;
    final now = currentTime ?? DateTime.now();
    final elapsed = now.difference(_lastActiveTime!);
    if (elapsed.inMinutes >= _autoLockMinutes) {
      lock();
      return true;
    }
    return false;
  }

  void _startIdleTimer() {
    _idleCheckTimer?.cancel();
    _idleCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      checkIdleTimeout();
    });
  }

  void dispose() {
    _idleCheckTimer?.cancel();
    isUnlockedNotifier.dispose();
  }
}
