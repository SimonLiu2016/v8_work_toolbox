// 通用异步任务队列：工坊里所有长任务的调度与状态跟踪。
//
// 生图与图生视频都是分钟级、有限流的操作，所以：
// - **并发数可配**（默认 2，spec 允许 1-5）。并发 2 是实测甜点：再高
//   云端开始限流，反而更慢，而限流的报错信息读不出原因。
// - **单任务可取消**。已入队未开始的直接移除；进行中的标记取消意图，
//   由任务自身在下一个安全点退出。
// - **状态暴露为流**。UI 订阅 [tasks] 而不是轮询——分镜卡片要"生成完成
//   立即刷新"（spec 12.3），轮询做不到无刷新。

import 'dart:async';

import 'package:flutter/foundation.dart';

/// 任务状态。
enum StudioTaskStatus {
  queued('queued', '等待中'),
  running('running', '进行中'),
  completed('completed', '完成'),
  failed('failed', '失败'),
  cancelled('cancelled', '已取消');

  final String id;
  final String label;

  const StudioTaskStatus(this.id, this.label);
}

/// 任务的产能类型。UI 用它在队列面板里分组显示。
enum StudioTaskKind {
  image('image', '关键帧生成'),
  video('video', '视频生成'),

  /// 片段级视频生成（spec: 片段级视频生成任务）。
  ///
  /// 与 [video] 分开是为了让队列面板能按 kind 分组——片段任务是分钟级长
  /// 任务，和分镜级任务混在一起时用户看不出为什么看板"卡住不动了"。
  segment('segment', '片段生成');

  final String id;
  final String label;

  const StudioTaskKind(this.id, this.label);
}

/// 一个排队中的任务单元。
class StudioTask {
  final String id;

  /// 产能类型（生图 / 视频）。
  final StudioTaskKind kind;

  /// 关联键：分镜级任务存镜号，片段级任务存 [segmentKey] 的转换值。
  ///
  /// 队列面板与分镜/片段徽章都靠它对应。用同一个整数字段而不是给片段任务
  /// 单加一个可空 segmentId，是为了让 `tasksForShot` / `completedOutputFor`
  /// 这些既有查询不必为 kind 分叉。
  final int shotNumber;

  /// 人类可读的描述（如 "分镜 3 关键帧"）。
  final String label;

  /// 状态与进度是**可变**的：队列在任务生命周期内原地更新它们，再把整个
  /// 列表快照发给订阅者。不可变对象 + copyWith 会让每次进度回调都重建一串
  /// 对象，而 FFmpeg 每秒能回调十几次。
  StudioTaskStatus status;

  /// 0.0 - 1.0。云任务只能给出粗粒度进度，见 [VideoGenAdapter] 说明。
  double progress;

  String? error;

  /// 完成后的产物路径。
  String? outputPath;

  final DateTime enqueuedAt;
  DateTime? startedAt;
  DateTime? finishedAt;

  StudioTask({
    required this.id,
    required this.kind,
    required this.shotNumber,
    required this.label,
    this.status = StudioTaskStatus.queued,
    this.progress = 0,
    this.error,
    this.outputPath,
    required this.enqueuedAt,
    this.startedAt,
    this.finishedAt,
  });

  bool get isTerminal =>
      status == StudioTaskStatus.completed ||
      status == StudioTaskStatus.failed ||
      status == StudioTaskStatus.cancelled;

}

/// 可取消的执行体：队列在用户点取消时置位 [cancelled]。
abstract interface class CancellableTaskRunner {
  set cancelled(bool value);
}

/// 任务执行体。取消通过 [isCancelled] 查询。
abstract interface class StudioTaskRunner {
  /// 该执行体关联的任务 id（队列用它把任务映射回数据层）。
  String get taskId;

  /// 轮询取消意图。队列在用户点取消时置位。
  bool isCancelled();

  /// 执行任务，报告进度。
  Future<String> run(void Function(double progress) onProgress);
}

/// 通用任务队列。
///
/// 单例：整个工坊窗口共用一个队列，页面切换不丢任务进度。
class StudioTaskQueue {
  StudioTaskQueue._();
  static final StudioTaskQueue instance = StudioTaskQueue._();

  final List<StudioTask> _tasks = <StudioTask>[];
  final Map<String, StudioTaskRunner> _runners = {};
  final Set<String> _cancelRequested = <String>{};

  /// 最大并发数。spec: 默认 2，可调 1-5。
  int _maxConcurrency = 2;
  int get maxConcurrency => _maxConcurrency;

  bool _draining = false;

  final _controller = StreamController<List<StudioTask>>.broadcast();

  /// 任务列表变化流（增删与状态变更都触发）。
  Stream<List<StudioTask>> get stream => _controller.stream;

  /// 当前任务快照。
  List<StudioTask> get tasks => List.unmodifiable(_tasks);

  /// 非终态任务数（UI 的"进行中"角标读它）。
  int get activeCount =>
      _tasks.where((t) => !t.isTerminal).length;

  List<StudioTask> tasksForShot(int shotNumber) =>
      _tasks.where((t) => t.shotNumber == shotNumber).toList();

  /// 某片段的任务（队列面板与片段卡片都用它判断"这个片段在生成中"）。
  List<StudioTask> tasksForSegment(String segmentId) => _tasks
      .where((t) => t.kind == StudioTaskKind.segment && t.shotNumber == _segmentKey(segmentId))
      .toList();

  /// 片段 id → 用于 [StudioTask.shotNumber] 的稳定整数键。
  ///
  /// [StudioTask] 用 shotNumber 做关联键（分镜级任务直接存镜号）。片段没有
  /// 镜号，这里把 `seg-N` 的 N 提出来当键；提不出就回退到 id 的哈希低位，
  /// 保证同一个片段在同一进程内键值稳定（重新入队时能对上旧任务）。
  static int segmentKey(String segmentId) => _segmentKey(segmentId);

  static int _segmentKey(String segmentId) {
    final match = RegExp(r'(\d+)$').firstMatch(segmentId);
    if (match != null) return int.parse(match.group(1)!);
    return segmentId.hashCode & 0xffff;
  }

  /// 某分镜是否已有成功的产物路径（有则 UI 直接显示缩略图）。
  String? completedOutputFor(int shotNumber) {
    final done = _tasks.where(
      (t) => t.shotNumber == shotNumber && t.status == StudioTaskStatus.completed,
    );
    if (done.isEmpty) return null;
    // 取最近完成的一次：用户可能对同一分镜重新生成过。
    return done.last.outputPath;
  }

  void setMaxConcurrency(int value) {
    _maxConcurrency = value.clamp(1, 5);
    if (!_draining) _drain();
  }

  /// 入队。返回任务 id（调用方靠它取消或等待）。
  String enqueue({
    required StudioTaskKind kind,
    required int shotNumber,
    required String label,
    required StudioTaskRunner runner,
  }) {
    // 片段任务的 shotNumber 由调用方经 [segmentKey] 转换后传入，这里不区分
    // —— 队列只关心「一个整数关联键」，它是什么语义由 kind 决定。
    final task = StudioTask(
      id: '${kind.id}-$shotNumber-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      shotNumber: shotNumber,
      label: label,
      enqueuedAt: DateTime.now(),
    );
    _tasks.add(task);
    _runners[task.id] = runner;
    _emit();
    _drain();
    return task.id;
  }

  /// 请求取消。
  ///
  /// 排队中的：直接终态，执行体从没被调起。
  /// 进行中的：置取消意图。**执行体要自己在安全点检查 [StudioTaskRunner
  /// .isCancelled]**——已经发出去的 HTTP 或 FFmpeg 进程撤不回来，但轮询
  /// 循环、批量合成的下一句、写回 storyboard 这三处都能停。
  void cancel(String taskId) {
    final task = _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => throw StateError('任务不存在: $taskId'),
    );
    if (task.status == StudioTaskStatus.queued) {
      _replace(task, status: StudioTaskStatus.cancelled);
      _runners.remove(taskId);
      return;
    }
    if (task.status == StudioTaskStatus.running) {
      _cancelRequested.add(taskId);
      // 同步置位执行体的取消标志：KenBurns/Kling 这类要跑几十秒到几分钟的
      // 任务，只有它们的轮询循环能真正提前退出。不实现该接口的执行体
      // （通常是同步完成的短任务）忽略这一步即可。
      final runner = _runners[taskId];
      if (runner != null && runner is CancellableTaskRunner) {
        // 上面 is 检查已提升类型；这里 Runner 是可空 map 值，所以先判空。
        (runner as CancellableTaskRunner).cancelled = true;
      }
    }
  }

  void clearFinished() {
    _tasks.removeWhere((t) => t.isTerminal);
    _emit();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(List.unmodifiable(_tasks));
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final running =
            _tasks.where((t) => t.status == StudioTaskStatus.running).length;
        if (running >= _maxConcurrency) return;
        final next = _tasks.firstWhere(
          (t) => t.status == StudioTaskStatus.queued,
          orElse: () => throw StateError('empty'),
        );
        // 排到队头但在启动前被取消了的，直接跳过。
        if (_cancelRequested.contains(next.id)) {
          _replace(next, status: StudioTaskStatus.cancelled);
          _cancelRequested.remove(next.id);
          continue;
        }
        unawaited(_runTask(next));
      }
    } on StateError {
      // 没有排队中的任务了，正常退出。
    } finally {
      _draining = false;
    }
  }

  Future<void> _runTask(StudioTask task) async {
    final runner = _runners[task.id];
    if (runner == null) {
      _replace(task, status: StudioTaskStatus.failed, error: '执行体缺失');
      return;
    }
    _replace(
      task,
      status: StudioTaskStatus.running,
      startedAt: DateTime.now(),
      progress: 0,
    );

    try {
      final output = await runner.run((progress) {
        final current = _tasks.firstWhereOrNull((t) => t.id == task.id);
        // 终态后到的进度回调直接忽略：任务失败后 runner 可能还在报进度，
        // 不拦的话失败的任务会在面板上闪回"进行中"。
        if (current == null || current.isTerminal) return;
        current.progress = progress;
        _emit();
      });
      // run 返回后可能已被取消：以取消为准，不显示成功。
      if (_cancelRequested.remove(task.id)) {
        _replace(task, status: StudioTaskStatus.cancelled);
      } else {
        _replace(
          task,
          status: StudioTaskStatus.completed,
          progress: 1,
          outputPath: output,
        );
      }
    } catch (e) {
      _replace(task, status: StudioTaskStatus.failed, error: e.toString());
    } finally {
      _runners.remove(task.id);
      _drain();
    }
  }

  /// 原地更新任务并广播快照。
  void _replace(
    StudioTask task, {
    required StudioTaskStatus status,
    double? progress,
    String? error,
    String? outputPath,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    if (!_tasks.any((t) => t.id == task.id)) return;
    task.status = status;
    if (progress != null) task.progress = progress;
    if (error != null) task.error = error;
    if (outputPath != null) task.outputPath = outputPath;
    if (startedAt != null) task.startedAt = startedAt;
    // 进入终态时自动补完成时间，省得每个调用点都传。
    final terminal = status == StudioTaskStatus.completed ||
        status == StudioTaskStatus.failed ||
        status == StudioTaskStatus.cancelled;
    if (terminal && task.finishedAt == null) {
      task.finishedAt = finishedAt ?? DateTime.now();
    } else if (finishedAt != null) {
      task.finishedAt = finishedAt;
    }
    _emit();
  }

  @visibleForTesting
  void resetForTesting() {
    _tasks.clear();
    _runners.clear();
    _cancelRequested.clear();
    _maxConcurrency = 2;
    _controller.add(const []);
  }

  void dispose() {
    _controller.close();
  }
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
