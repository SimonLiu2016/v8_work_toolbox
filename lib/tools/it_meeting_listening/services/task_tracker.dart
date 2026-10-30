/// 工作区后台任务追踪器：按 `(kind, itemId)` 独立记录进度与结果。
///
/// 替代旧页面里三条管线共用的单行 `_statusMessage`：
/// - 进度直接挂在对应列表条目或分区状态区上；
/// - 用户切换选中项后后台任务继续运行，进度不丢失；
/// - 完成或失败时通过 `onNotification` 触发一次性短暂提示（SnackBar）。
library;

import 'package:flutter/foundation.dart';

/// 后台任务类别。
enum WorkspaceTaskKind {
  publicSync,
  publicBake,
  realMeetingImport,
  realMeetingBake,
  rehearsalStep,
}

/// 单个后台任务的快照。
class WorkspaceTaskEntry {
  final WorkspaceTaskKind kind;
  final String itemId;
  final String label;
  final int done;
  final int total;
  final bool running;
  final String? error;
  final String? message;

  const WorkspaceTaskEntry({
    required this.kind,
    required this.itemId,
    required this.label,
    this.done = 0,
    this.total = 0,
    this.running = false,
    this.error,
    this.message,
  });

  bool get isFailed => !running && error != null;
  bool get isCompleted => !running && error == null;

  WorkspaceTaskEntry copyWith({
    String? label,
    int? done,
    int? total,
    bool? running,
    String? error,
    String? message,
    bool clearError = false,
  }) {
    return WorkspaceTaskEntry(
      kind: kind,
      itemId: itemId,
      label: label ?? this.label,
      done: done ?? this.done,
      total: total ?? this.total,
      running: running ?? this.running,
      error: clearError ? null : (error ?? this.error),
      message: message ?? this.message,
    );
  }
}

/// 一次性通知事件（供外壳弹出 SnackBar）。
class WorkspaceToastEvent {
  final String message;
  final bool isError;

  const WorkspaceToastEvent(this.message, {this.isError = false});
}

/// 后台任务追踪器。
class TaskTracker extends ChangeNotifier {
  final Map<(WorkspaceTaskKind, String), WorkspaceTaskEntry> _entries = {};
  final List<WorkspaceToastEvent> _pendingToasts = [];

  /// 外部可选的一次性通知回调。
  void Function(WorkspaceToastEvent event)? onToast;

  /// 查询指定 `(kind, itemId)` 的任务状态。
  WorkspaceTaskEntry? entryFor(WorkspaceTaskKind kind, String itemId) =>
      _entries[(kind, itemId)];

  /// 某类（或某具体条目）是否正在运行。
  bool isRunning(WorkspaceTaskKind kind, [String? itemId]) {
    if (itemId != null) {
      return _entries[(kind, itemId)]?.running ?? false;
    }
    return _entries.values.any((e) => e.kind == kind && e.running);
  }

  /// 取出并清空积压的通知事件。
  List<WorkspaceToastEvent> takePendingToasts() {
    if (_pendingToasts.isEmpty) return const [];
    final copy = List<WorkspaceToastEvent>.from(_pendingToasts);
    _pendingToasts.clear();
    return copy;
  }

  /// 启动任务。
  void start(
    WorkspaceTaskKind kind,
    String itemId, {
    required String label,
    int done = 0,
    int total = 0,
  }) {
    _entries[(kind, itemId)] = WorkspaceTaskEntry(
      kind: kind,
      itemId: itemId,
      label: label,
      done: done,
      total: total,
      running: true,
    );
    notifyListeners();
  }

  /// 更新任务进度。
  void updateProgress(
    WorkspaceTaskKind kind,
    String itemId, {
    required int done,
    required int total,
    String? label,
  }) {
    final prev = _entries[(kind, itemId)];
    _entries[(kind, itemId)] = WorkspaceTaskEntry(
      kind: kind,
      itemId: itemId,
      label: label ?? prev?.label ?? '',
      done: done,
      total: total,
      running: true,
    );
    notifyListeners();
  }

  /// 标记任务成功完成，并发送一次性提示。
  void complete(
    WorkspaceTaskKind kind,
    String itemId, {
    String? message,
    bool notifyToast = true,
  }) {
    final prev = _entries[(kind, itemId)];
    _entries[(kind, itemId)] = WorkspaceTaskEntry(
      kind: kind,
      itemId: itemId,
      label: message ?? prev?.label ?? '已完成',
      done: prev?.total ?? 0,
      total: prev?.total ?? 0,
      running: false,
      message: message,
    );
    if (notifyToast && message != null && message.isNotEmpty) {
      _emitToast(WorkspaceToastEvent(message));
    }
    notifyListeners();
  }

  /// 标记任务失败，并发送一次性错误提示。
  void fail(
    WorkspaceTaskKind kind,
    String itemId,
    String error, {
    bool notifyToast = true,
  }) {
    final prev = _entries[(kind, itemId)];
    _entries[(kind, itemId)] = WorkspaceTaskEntry(
      kind: kind,
      itemId: itemId,
      label: prev?.label ?? '失败',
      done: prev?.done ?? 0,
      total: prev?.total ?? 0,
      running: false,
      error: error,
    );
    if (notifyToast && error.isNotEmpty) {
      _emitToast(WorkspaceToastEvent(error, isError: true));
    }
    notifyListeners();
  }

  /// 直接触发一条一次性提示。
  void emitToast(String message, {bool isError = false}) {
    _emitToast(WorkspaceToastEvent(message, isError: isError));
    notifyListeners();
  }

  /// 清除某条任务记录。
  void clear(WorkspaceTaskKind kind, String itemId) {
    if (_entries.remove((kind, itemId)) != null) {
      notifyListeners();
    }
  }

  void _emitToast(WorkspaceToastEvent event) {
    final handler = onToast;
    if (handler != null) {
      handler(event);
    } else {
      _pendingToasts.add(event);
    }
  }
}
