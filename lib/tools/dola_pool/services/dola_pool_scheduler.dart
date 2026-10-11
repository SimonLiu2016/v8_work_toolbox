import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/dola_account.dart';
import 'dola_account_store.dart';

/// Dola 号池多账号七状态智能调度器。
class DolaPoolScheduler extends ChangeNotifier {
  DolaPoolScheduler._() {
    _startResetWatcher();
  }
  static final DolaPoolScheduler instance = DolaPoolScheduler._();

  Timer? _resetTimer;
  final Set<String> _busyAccountIds = {};

  /// 启动东九区（东京时间 0 点，对应北京时间 23 点）自动重置看门狗
  void _startResetWatcher() {
    _resetTimer?.cancel();
    _resetTimer = Timer.periodic(const Duration(minutes: 5), (_) => _checkDailyReset());
  }

  DateTime _lastResetDate = DateTime.fromMillisecondsSinceEpoch(0);

  void _checkDailyReset() {
    // 获取当前东京时间 (UTC+9)
    final nowUtc = DateTime.now().toUtc();
    final tokyoTime = nowUtc.add(const Duration(hours: 9));

    // 如果东京时间日期变更且已过 0 点
    if (tokyoTime.day != _lastResetDate.day) {
      _lastResetDate = tokyoTime;
      debugPrint('[DolaPoolScheduler] 东京时间 0 点已到，自动重置号池配额');
      DolaAccountStore.instance.resetAllQuotas();
    }
  }

  /// 租借一个适合指定模型的空闲账号
  ///
  /// - `seedance-2.0`：每次消耗 3 点，需满额账号（points >= 3）
  /// - `seedance-2.5`：每次消耗 2 点，半额或满额账号均可（points >= 2）
  Future<DolaAccount?> acquireAccount({required String model}) async {
    final store = DolaAccountStore.instance;
    await store.init();

    final requiredPoints = model.contains('2.0') ? 3 : 2;
    final now = DateTime.now();

    // 1. 过滤所有可用候选账号
    final candidates = store.accounts.where((a) {
      if (_busyAccountIds.contains(a.id)) return false;
      if (a.points < requiredPoints) return false;

      // 检查冷却
      if (a.cooldownUntil != null && now.isBefore(a.cooldownUntil!)) {
        return false;
      }

      if (a.status == DolaAccountStatus.abnormal ||
          a.status == DolaAccountStatus.risk ||
          a.status == DolaAccountStatus.cooling) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return null;
    }

    // 2. 调度策略：如果是 2.5，优先使用点数为 2 的半额账号（拼单出片，保护满额账号留给 2.0）
    if (requiredPoints == 2) {
      candidates.sort((a, b) {
        // 点数升序排列，2点优先于4点
        final pCompare = a.points.compareTo(b.points);
        if (pCompare != 0) return pCompare;
        // 点数相同时，优先使用最久未使用的
        final aTime = a.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
    } else {
      // 2.0 只能找 >= 3 点的满额账号，按使用时间最久未用排
      candidates.sort((a, b) {
        final aTime = a.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.lastUsedAt?.millisecondsSinceEpoch ?? 0;
        return aTime.compareTo(bTime);
      });
    }

    final selected = candidates.first;
    _busyAccountIds.add(selected.id);

    // 标记状态为生成中
    await store.updateAccount(selected.copyWith(
      status: DolaAccountStatus.busy,
      lastUsedAt: now,
    ));

    notifyListeners();
    return selected;
  }

  /// 归还账号并更新额度扣减与状态
  Future<void> releaseAccount(
    String accountId, {
    required int usedPoints,
    int? realPointsLeft,
    String? error,
    bool isRisk = false,
  }) async {
    _busyAccountIds.remove(accountId);
    final store = DolaAccountStore.instance;
    await store.init();

    final account = store.accounts.firstWhere(
      (a) => a.id == accountId,
      orElse: () => const DolaAccount(id: '', name: '', sessionid: ''),
    );
    if (account.id.isEmpty) return;

    final now = DateTime.now();

    if (isRisk) {
      // 标记风控，冷却 30 分钟
      await store.updateAccount(account.copyWith(
        status: DolaAccountStatus.risk,
        cooldownUntil: now.add(const Duration(minutes: 30)),
        lastError: error ?? '触发上游风控拦截',
      ));
    } else if (error != null && error.isNotEmpty) {
      // 标记常规失败冷却 2 分钟
      await store.updateAccount(account.copyWith(
        status: DolaAccountStatus.full,
        cooldownUntil: now.add(const Duration(minutes: 2)),
        lastError: error,
      ));
    } else {
      // 正常成功：更新剩余点数
      final finalPoints = realPointsLeft ?? (account.points - usedPoints).clamp(0, account.dailyLimit);
      DolaAccountStatus newStatus = DolaAccountStatus.full;
      if (finalPoints <= 1) {
        newStatus = DolaAccountStatus.cooling;
      } else if (finalPoints < account.dailyLimit) {
        newStatus = DolaAccountStatus.half;
      }

      await store.updateAccount(account.copyWith(
        points: finalPoints,
        status: newStatus,
        lastError: null,
        cooldownUntil: null,
      ));
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}
