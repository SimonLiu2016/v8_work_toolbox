import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_task_queue.dart';

/// 队列并发控制的单元测试（spec「生图任务队列」：默认 2，可调 1-5）。
///
/// 用一个记录并发峰值的假 runner：[maxConcurrent] 是整个测试文件唯一真正
/// 要断言的东西，别的状态字段只是让断言可读。
void main() {
  late StudioTaskQueue queue;

  setUp(() {
    queue = StudioTaskQueue.instance;
    queue.resetForTesting();
  });

  tearDown(() {
    queue.resetForTesting();
  });

  group('并发上限', () {
    test('默认并发 2：同一时刻最多两个任务在跑', () async {
      var concurrent = 0;
      var peak = 0;
      final gate = Completer<void>();

      Future<String> body() async {
        concurrent++;
        peak = concurrent > peak ? concurrent : peak;
        await gate.future;
        concurrent--;
        return 'out';
      }

      // 入队 5 个，用同一个 gate 卡住它们，看有多少同时进入 running。
      for (var i = 1; i <= 5; i++) {
        queue.enqueue(
          kind: StudioTaskKind.image,
          shotNumber: i,
          label: '分镜 $i',
          runner: _FakeRunner(taskId: 'r$i', body: body),
        );
      }
      // 等调度器把能起的都起来。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final running = queue.tasks
          .where((t) => t.status == StudioTaskStatus.running)
          .length;
      expect(running, 2, reason: '默认并发应为 2');
      expect(peak, 2);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final completed = queue.tasks
          .where((t) => t.status == StudioTaskStatus.completed)
          .length;
      expect(completed, 5, reason: '放行后剩余任务应全部跑完');
      expect(peak, 2, reason: '全程峰值并发不应超过 2');
    });

    test('并发调到 1 时严格串行', () async {
      var concurrent = 0;
      var peak = 0;
      final gate = Completer<void>();
      queue.setMaxConcurrency(1);
      expect(queue.maxConcurrency, 1);

      Future<String> body() async {
        concurrent++;
        peak = concurrent > peak ? concurrent : peak;
        await gate.future;
        concurrent--;
        return 'out';
      }

      for (var i = 1; i <= 4; i++) {
        queue.enqueue(
          kind: StudioTaskKind.image,
          shotNumber: i,
          label: '分镜 $i',
          runner: _FakeRunner(taskId: 'r$i', body: body),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(peak, 1, reason: '并发 1 时必须串行');
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        queue.tasks.where((t) => t.status == StudioTaskStatus.completed).length,
        4,
      );
      expect(peak, 1, reason: '放行后也不允许峰值超过配置值');
    });

    test('并发上限夹在 1-5 之间', () {
      queue.setMaxConcurrency(0);
      expect(queue.maxConcurrency, 1);
      queue.setMaxConcurrency(99);
      expect(queue.maxConcurrency, 5);
      queue.setMaxConcurrency(3);
      expect(queue.maxConcurrency, 3);
    });

    test('并发调到更高时排队任务立即开始', () async {
      final gate = Completer<void>();
      var peak = 0;
      var concurrent = 0;
      Future<String> body() async {
        concurrent++;
        peak = concurrent > peak ? concurrent : peak;
        await gate.future;
        concurrent--;
        return 'out';
      }

      for (var i = 1; i <= 4; i++) {
        queue.enqueue(
          kind: StudioTaskKind.image,
          shotNumber: i,
          label: 's$i',
          runner: _FakeRunner(taskId: 'r$i', body: body),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(peak, 2);

      queue.setMaxConcurrency(4);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(peak, 4, reason: '提高上限后排队任务应立即启动');

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  group('状态跟踪', () {
    test('任务依次经过 queued → running → completed', () async {
      final statuses = <String>[];
      final sub = queue.stream.listen((tasks) {
        final t = tasks.where((t) => t.shotNumber == 1).firstOrNull;
        // enqueue 时会先广播一次 queued，但入队与 drain 在同一微任务里，
        // queued 那一下可能在监听者订阅之前就走完了。所以断言的底线是
        // 「最终状态与产物正确」，queued 由下面单独验证。
        if (t == null) return;
        if (statuses.isEmpty || statuses.last != t.status.id) {
          statuses.add(t.status.id);
        }
      });

      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: 's1',
        runner: _FakeRunner(taskId: 'r1', body: () async => '/tmp/out.png'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(statuses, containsAllInOrder(['running', 'completed']));
      final task = queue.tasks.first;
      expect(task.status, StudioTaskStatus.completed);
      expect(task.outputPath, '/tmp/out.png');
      expect(task.progress, 1.0);
      expect(queue.completedOutputFor(1), '/tmp/out.png');
      await sub.cancel();
    });

    test('新入队的任务先以 queued 状态出现在列表里', () async {
      final gate = Completer<void>();
      // 用并发 1 + 两个任务保证第二个必然停在 queued。
      queue.setMaxConcurrency(1);
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: 'blocker',
        runner: _FakeRunner(taskId: 'b', body: () async {
          await gate.future;
          return 'x';
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: 'waiting',
        runner: _FakeRunner(taskId: 'w', body: () async => 'y'),
      );
      final waiting = queue.tasks.firstWhere((t) => t.shotNumber == 2);
      expect(waiting.status, StudioTaskStatus.queued);
      expect(queue.activeCount, 2, reason: '排队中的任务也算活跃任务');
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      queue.setMaxConcurrency(2);
    });

    test('失败任务保留 error 且可重试（重新入队即可）', () async {
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: 's2',
        runner: _FakeRunner(
          taskId: 'r2',
          body: () async => throw StateError('quota exceeded'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final task = queue.tasks.firstWhere((t) => t.shotNumber == 2);
      expect(task.status, StudioTaskStatus.failed);
      expect(task.error, contains('quota exceeded'));
      expect(queue.completedOutputFor(2), isNull);

      // 重试 = 再入队一个同分镜任务。
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: 's2 retry',
        runner: _FakeRunner(taskId: 'r2b', body: () async => '/tmp/ok.png'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(queue.completedOutputFor(2), '/tmp/ok.png');
    });

    test('进度回调到达终态任务后被忽略', () async {
      final controller = StreamController<double>.broadcast();
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 3,
        label: 's3',
        runner: _FakeRunner(
          taskId: 'r3',
          body: () async {
            // 立即失败，但之后再报一个进度——模拟云端任务失败后仍在推流。
            controller.add(0.9);
            throw StateError('boom');
          },
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      controller.add(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await controller.close();

      final task = queue.tasks.firstWhere((t) => t.shotNumber == 3);
      expect(task.status, StudioTaskStatus.failed);
      expect(task.progress, lessThan(1.0),
             reason: '失败的任务不该被迟到进度改成看起来还在跑');
    });
  });

  group('取消', () {
    test('排队中的任务可取消且不执行', () async {
      // 并发 1 + 第一个任务卡住，保证第二个一定停在 queued 状态。
      queue.setMaxConcurrency(1);
      final gate = Completer<void>();
      var ranSecond = false;

      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: 'blocker',
        runner: _FakeRunner(taskId: 'b', body: () async {
          await gate.future;
          return 'x';
        }),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: 'waiting',
        runner: _FakeRunner(taskId: 'w', body: () async {
          ranSecond = true;
          return 'y';
        }),
      );

      final queued = queue.tasks
          .where((t) => t.status == StudioTaskStatus.queued)
          .toList();
      expect(queued, hasLength(1));

      queue.cancel(queued.first.id);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final cancelled = queue.tasks.firstWhere((t) => t.id == queued.first.id);
      expect(cancelled.status, StudioTaskStatus.cancelled);
      expect(cancelled.finishedAt, isNotNull);
      expect(ranSecond, isFalse,
             reason: '排队中被取消的任务不该被执行');
      queue.setMaxConcurrency(2);
    });

    test('取消进行中的任务会把标志置到执行体上', () async {
      final gate = Completer<void>();
      final runner = _FakeRunner(
        taskId: 'c1',
        body: () async {
          await gate.future;
          return 'x';
        },
      );
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: 's1',
        runner: runner,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      queue.cancel(queue.tasks.first.id);
      expect(runner.cancelledFlag, isTrue,
             reason: '执行体要能感知取消，否则轮询循环停不下来');
      expect(runner.isCancelled(), isTrue);

      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('已取消任务不计入 activeCount', () async {
      for (var i = 1; i <= 4; i++) {
        queue.enqueue(
          kind: StudioTaskKind.video,
          shotNumber: i,
          label: 's$i',
          runner: _FakeRunner(taskId: 'r$i', body: () => Future.value('x')),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final id = queue.tasks.last.id;
      queue.cancel(id);
      expect(queue.activeCount, queue.tasks.where((t) => !t.isTerminal).length);
    });

    test('clearFinished 只清终态任务', () async {
      final gate = Completer<void>();
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: 'running one',
        runner: _FakeRunner(
          taskId: 'r1',
          body: () async {
            await gate.future;
            return 'ok';
          },
        ),
      );
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: 'fail one',
        runner: _FakeRunner(
          taskId: 'r2',
          body: () async => throw StateError('nope'),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      queue.clearFinished();
      // 失败的那个是终态，应被清掉；进行中的要留下。
      expect(queue.tasks.where((t) => t.shotNumber == 2), isEmpty);
      expect(queue.tasks.where((t) => t.shotNumber == 1), isNotEmpty);
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
  });

  group('片段任务', () {
    test('segmentKey 从 seg-N 提取 N', () {
      expect(StudioTaskQueue.segmentKey('seg-1'), 1);
      expect(StudioTaskQueue.segmentKey('seg-12'), 12);
    });

    test('segmentKey 对非 seg- 前缀的 id 给稳定值', () {
      // 同一个 id 在同一进程内必须给同一个键，否则重新入队时对不上旧任务。
      expect(StudioTaskQueue.segmentKey('custom-id'),
          StudioTaskQueue.segmentKey('custom-id'));
    });

    test('tasksForSegment 只返回该片段的任务', () {
      final runner = _FakeRunner(
        taskId: 't-seg',
        body: () async => 'seg-1.mp4',
      );
      queue.enqueue(
        kind: StudioTaskKind.segment,
        shotNumber: StudioTaskQueue.segmentKey('seg-1'),
        label: '片段 1 视频',
        runner: runner,
      );
      queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 3,
        label: '分镜 3 视频',
        runner: _FakeRunner(taskId: 't-3', body: () async => 'shot_3.mp4'),
      );

      final segTasks = queue.tasksForSegment('seg-1');
      expect(segTasks, hasLength(1));
      expect(segTasks.single.kind, StudioTaskKind.segment);
      expect(segTasks.single.label, '片段 1 视频');
    });

    test('片段任务与分镜任务共享同一并发上限', () async {
      // spec 明确：片段级任务的并发与生图任务共享同一配置。这里用 4 个
      // 任务（2 片段 + 2 分镜）验证峰值不超过 maxConcurrency。
      queue.setMaxConcurrency(2);
      var peak = 0;
      var running = 0;
      Future<String> body() async {
        running++;
        peak = running > peak ? running : peak;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        running--;
        return 'ok';
      }

      for (var i = 0; i < 2; i++) {
        queue.enqueue(
          kind: StudioTaskKind.segment,
          shotNumber: StudioTaskQueue.segmentKey('seg-$i'),
          label: '片段 $i',
          runner: _FakeRunner(taskId: 'seg-$i', body: body),
        );
      }
      for (var i = 0; i < 2; i++) {
        queue.enqueue(
          kind: StudioTaskKind.video,
          shotNumber: i + 1,
          label: '分镜 $i',
          runner: _FakeRunner(taskId: 'shot-$i', body: body),
        );
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(peak, lessThanOrEqualTo(2),
          reason: '片段与分镜任务必须共享并发上限，不能各跑各的');
      expect(queue.tasks.every((t) => t.isTerminal), isTrue);
    });

    test('片段任务可取消', () async {
      final id = queue.enqueue(
        kind: StudioTaskKind.segment,
        shotNumber: StudioTaskQueue.segmentKey('seg-1'),
        label: '片段 1 视频',
        runner: _FakeRunner(
          taskId: 'seg-cancel',
          body: () async {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            return 'seg-1.mp4';
          },
        ),
      );
      queue.cancel(id);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final task = queue.tasks.firstWhere((t) => t.id == id);
      expect(task.status, StudioTaskStatus.cancelled);
    });

    test('tasksForShot 严格排除 segment 任务，防止单镜误判转圈', () {
      // 入队一个 shotNumber 为 1 的片段视频任务
      queue.enqueue(
        kind: StudioTaskKind.segment,
        shotNumber: 1,
        label: '片段 1 视频',
        runner: _FakeRunner(
          taskId: 'seg-1',
          body: () async => 'seg-1.mp4',
        ),
      );
      // 入队一个分镜 1 关键帧任务
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: '分镜 1 关键帧',
        runner: _FakeRunner(
          taskId: 'frame-1',
          body: () async => 'frame-1.png',
        ),
      );

      final shotTasks = queue.tasksForShot(1);
      expect(shotTasks.length, 1, reason: 'tasksForShot 只能匹配分镜级任务，不应返回片段任务');
      expect(shotTasks.first.kind, StudioTaskKind.image);

      final segTasks = queue.tasksForSegment('seg-1');
      expect(segTasks.length, 1);
      expect(segTasks.first.kind, StudioTaskKind.segment);
    });
  });

  group('任务依赖（spec: 分镜视频任务等待同镜关键帧）', () {
    test('视频任务等待前置生图任务成功后才启动', () async {
      var imageStarted = false;
      var videoStarted = false;
      final order = <String>[];

      final imageId = queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 1,
        label: '分镜 1 关键帧',
        runner: _FakeRunner(
          taskId: 'img-1',
          body: () async {
            imageStarted = true;
            order.add('image-start');
            await Future<void>.delayed(const Duration(milliseconds: 40));
            order.add('image-done');
            return 'shot_1.png';
          },
        ),
      );
      queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 1,
        label: '分镜 1 视频',
        requiresTaskId: imageId,
        runner: _FakeRunner(
          taskId: 'vid-1',
          body: () async {
            videoStarted = true;
            order.add('video-start');
            return 'shot_1.mp4';
          },
        ),
      );

      // 图任务跑完之前，视频任务不得启动。
      await Future<void>.delayed(const Duration(milliseconds: 15));
      expect(imageStarted, isTrue);
      expect(videoStarted, isFalse,
          reason: '视频任务必须等关键帧生成成功，不能抢并发槽');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(videoStarted, isTrue);
      expect(order, ['image-start', 'image-done', 'video-start']);
    });

    test('前置失败时视频任务标记为前置未满足，不启动', () async {
      var videoStarted = false;
      final imageId = queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 2,
        label: '分镜 2 关键帧',
        runner: _FakeRunner(
          taskId: 'img-2',
          body: () async => throw StateError('生图引擎超时'),
        ),
      );
      queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 2,
        label: '分镜 2 视频',
        requiresTaskId: imageId,
        runner: _FakeRunner(
          taskId: 'vid-2',
          body: () async {
            videoStarted = true;
            return 'shot_2.mp4';
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(videoStarted, isFalse,
          reason: '缺首帧的视频任务跑出去只会产出与关键帧不符的片子');
      // StudioTask 没有暴露 runner 的 taskId，用 label 找。
      final videoTask = queue.tasks
          .firstWhere((t) => t.label == '分镜 2 视频');
      expect(videoTask.status, StudioTaskStatus.failed);
      expect(videoTask.error, contains('前置任务未满足'));
    });

    test('无依赖的任务不受影响，照常入队即跑', () async {
      var ran = false;
      queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 3,
        label: '分镜 3 视频',
        runner: _FakeRunner(
          taskId: 'vid-3',
          body: () async {
            ran = true;
            return 'shot_3.mp4';
          },
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(ran, isTrue);
    });

    test('isWaitingForPrerequisite 与 prerequisite 暴露等待状态', () async {
      final imageId = queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: 4,
        label: '分镜 4 关键帧',
        runner: _FakeRunner(
          taskId: 'img-4',
          body: () async {
            await Future<void>.delayed(const Duration(milliseconds: 60));
            return 'shot_4.png';
          },
        ),
      );
      queue.enqueue(
        kind: StudioTaskKind.video,
        shotNumber: 4,
        label: '分镜 4 视频',
        requiresTaskId: imageId,
        runner: _FakeRunner(
          taskId: 'vid-4',
          body: () async => 'shot_4.mp4',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 15));
      final videoTask = queue.lookup(
        queue.tasks.firstWhere((t) => t.label == '分镜 4 视频').id,
      )!;
      expect(videoTask.isWaitingForPrerequisite, isTrue);
      expect(videoTask.prerequisite?.label, '分镜 4 关键帧');

      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(videoTask.isWaitingForPrerequisite, isFalse);
    });
  });
}

class _FakeRunner implements StudioTaskRunner, CancellableTaskRunner {
  @override
  final String taskId;
  final Future<String> Function() body;
  bool cancelledFlag = false;

  _FakeRunner({required this.taskId, required this.body});

  @override
  set cancelled(bool value) => cancelledFlag = value;

  @override
  bool isCancelled() => cancelledFlag;

  @override
  Future<String> run(void Function(double progress) onProgress) {
    cancelledFlag = false;
    onProgress(0.1);
    return body();
  }
}
