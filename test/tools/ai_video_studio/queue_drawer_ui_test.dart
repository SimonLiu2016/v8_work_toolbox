import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/studio_task_queue.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/ui/storyboard_board.dart';

class _MockRunner implements StudioTaskRunner {
  final Completer<String> completer = Completer<String>();

  @override
  String get taskId => 'mock_task';

  @override
  bool isCancelled() => false;

  @override
  Future<String> run(void Function(double progress) onProgress) =>
      completer.future;
}

void main() {
  late Directory tempDir;
  late StudioTaskQueue queue;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('queue_drawer_test_');
    AppPaths.overrideRootForTesting(tempDir);
    queue = StudioTaskQueue.instance;
    queue.resetForTesting();
  });

  tearDown(() async {
    queue.resetForTesting();
    AppPaths.resetForTesting();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets(
      'QueueDrawer renders ConstrainedBox, Scrollbar, ListView and Filter Chips without overflow',
      (tester) async {
    // 注入 15 个任务
    for (var i = 1; i <= 15; i++) {
      queue.enqueue(
        kind: StudioTaskKind.image,
        shotNumber: i,
        label: '分镜 #$i 关键帧生图',
        runner: _MockRunner(),
      );
    }

    // 设置固定屏幕视口模拟桌面抽屉
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QueueDrawer(queue: queue),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证存在 Scrollbar 与 ListView
    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);

    // 2. 验证筛选标签与数量
    expect(find.widgetWithText(ChoiceChip, '全部 (15)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '进行中 (15)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '已完成 (0)'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '失败 (0)'), findsOneWidget);

    // 3. 点击「已完成」过滤芯片
    await tester.tap(find.widgetWithText(ChoiceChip, '已完成 (0)'));
    await tester.pumpAndSettle();

    // 无已完成任务时，显示空状态提示
    expect(find.textContaining('没有 已完成 的任务'), findsOneWidget);

    // 4. 点击「全部」恢复全部展示
    await tester.tap(find.widgetWithText(ChoiceChip, '全部 (15)'));
    await tester.pumpAndSettle();
    expect(find.textContaining('分镜 #1 关键帧生图'), findsOneWidget);

    // 验证未抛出 RenderFlex 溢出异常
    expect(tester.takeException(), isNull);
  });
}
