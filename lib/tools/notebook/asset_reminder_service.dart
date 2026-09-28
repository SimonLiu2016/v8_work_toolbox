import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'note_store.dart';
import '../../../services/app_paths.dart';

/// 资产到期提醒服务。
///
/// 每 30 秒扫描资产笔记的到期日（[NoteStore.assetsDueSoon]），在到期前
/// [leadWindowDays] 天内发 macOS 系统通知。复用 [ScheduledNewsService] 的
/// 定时器 + osascript 通知模式，但扫描领域不同（资产 vs 资讯任务），
/// 故独立服务而非复用其实例。
///
/// 提醒状态（已提醒 / 已 dismiss）持久化到 `asset_reminders.json`，
/// 跨重启保留，避免重复打扰。
class AssetReminderService extends ChangeNotifier {
  AssetReminderService._();
  static final AssetReminderService instance = AssetReminderService._();

  /// 到期前提醒窗口（天）。可在 UI 配置，默认 30。
  int _leadWindowDays = 30;
  int get leadWindowDays => _leadWindowDays;

  /// dismiss 冷却：用户手动关闭后，多久内不再对同一资产发通知。
  static const Duration _dismissCooldown = Duration(days: 7);

  Timer? _timer;
  File? _stateFile;
  bool _initialized = false;

  /// noteId -> 上次发通知时间
  final Map<String, DateTime> _lastNotified = {};
  /// noteId -> dismiss 时间
  final Map<String, DateTime> _dismissedAt = {};

  Future<void> init({Directory? customRootDir}) async {
    if (_initialized) return;
    try {
      final dir = customRootDir ?? AppPaths.root;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _stateFile = customRootDir == null
          ? AppPaths.assetRemindersFile
          : File(p.join(dir.path, 'asset_reminders.json'));
      await _loadState();
      _initialized = true;
      _startTimer();
    } catch (e) {
      debugPrint('初始化 AssetReminderService 失败: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _scan());
  }

  /// 立即执行一次扫描（供手动触发与测试）。
  Future<List<String>> scanNow() => _scan();

  Future<List<String>> _scan() async {
    if (!_initialized) return const [];
    final notified = <String>[];
    try {
      final due = await NoteStore.instance.assetsDueSoon(_leadWindowDays);
      for (final note in due) {
        if (!_shouldNotify(note.id)) continue;
        _lastNotified[note.id] = DateTime.now();
        _dispatchMacNotification(
          note.title,
          '资产将于 ${_formatDate(note.assetExpiryDate!)} 到期'
          '${note.assetCategory != null ? '（${note.assetCategory}）' : ''}',
        );
        notified.add(note.id);
      }
      if (notified.isNotEmpty) {
        await _saveState();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('资产到期扫描失败: $e');
    }
    return notified;
  }

  bool _shouldNotify(String noteId) {
    final dismissed = _dismissedAt[noteId];
    if (dismissed != null &&
        DateTime.now().difference(dismissed) < _dismissCooldown) {
      return false;
    }
    final last = _lastNotified[noteId];
    // 同一资产当天只提醒一次。
    if (last != null && _isSameDay(last, DateTime.now())) return false;
    return true;
  }

  /// 用户 dismiss 某资产的提醒，进入冷却期。
  Future<void> dismiss(String noteId) async {
    _dismissedAt[noteId] = DateTime.now();
    await _saveState();
    notifyListeners();
  }

  /// 即将到期的资产（供 UI 列表展示，不受 dismiss 影响）。
  Future<List<AssetDueItem>> dueList() async {
    if (!_initialized) return const [];
    final due = await NoteStore.instance.assetsDueSoon(_leadWindowDays);
    return due
        .map((n) => AssetDueItem(
              noteId: n.id,
              title: n.title,
              category: n.assetCategory,
              expiryDate: n.assetExpiryDate!,
              dismissed: _dismissedAt.containsKey(n.id),
            ))
        .toList();
  }

  void _dispatchMacNotification(String title, String body) {
    if (!Platform.isMacOS) return;
    try {
      final safeTitle = title.replaceAll('"', '\\"');
      final safeBody = body.replaceAll('"', '\\"').replaceAll('\n', ' ');
      Process.run('osascript', [
        '-e',
        'display notification "$safeBody" with title "V8 资产提醒" subtitle "$safeTitle"',
      ]);
    } catch (_) {}
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // ---------------------------------------------------------------------------

  Future<void> _loadState() async {
    final f = _stateFile;
    if (f == null || !await f.exists()) return;
    try {
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _leadWindowDays = raw['leadWindowDays'] as int? ?? 30;
      for (final e in (raw['notified'] as Map<String, dynamic>? ?? {}).entries) {
        final t = DateTime.tryParse(e.value as String? ?? '');
        if (t != null) _lastNotified[e.key] = t;
      }
      for (final e in (raw['dismissed'] as Map<String, dynamic>? ?? {}).entries) {
        final t = DateTime.tryParse(e.value as String? ?? '');
        if (t != null) _dismissedAt[e.key] = t;
      }
    } catch (e) {
      debugPrint('读取 asset_reminders.json 失败: $e');
    }
  }

  Future<void> _saveState() async {
    final f = _stateFile;
    if (f == null) return;
    try {
      final data = {
        'leadWindowDays': _leadWindowDays,
        'notified': _lastNotified.map((k, v) => MapEntry(k, v.toIso8601String())),
        'dismissed': _dismissedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
      };
      await f.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    } catch (e) {
      debugPrint('保存 asset_reminders.json 失败: $e');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// 即将到期的资产条目（供 UI 列表）。
class AssetDueItem {
  final String noteId;
  final String title;
  final String? category;
  final DateTime expiryDate;
  final bool dismissed;

  const AssetDueItem({
    required this.noteId,
    required this.title,
    required this.category,
    required this.expiryDate,
    required this.dismissed,
  });

  int get daysLeft => expiryDate.difference(DateTime.now()).inDays;
}
