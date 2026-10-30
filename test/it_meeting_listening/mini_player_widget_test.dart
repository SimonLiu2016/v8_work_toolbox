import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/it_listening_mini_player.dart';

/// 迷你播放窗的 widget 测试。
///
/// 重点验两件事：
/// 1. 关闭按钮存在且可点（**没有它，用户只能重启应用才能关掉常驻置顶的窗口**）
/// 2. 关闭动作是「隐藏」而非「销毁」——销毁会断开 `WindowMethodChannel` 的
///    双向配对，重开时通道要重新注册；而播放状态在主进程，隐藏才与
///    「关闭不终止播放」一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final invoked = <String>[];

  setUp(() {
    invoked.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async {
        invoked.add(call.method);
        return call.method == 'isMinimized' ? false : null;
      },
    );
  });

  Widget app() => const ItListeningMiniPlayerApp();

  testWidgets('迷你窗提供显式关闭入口', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 50));

    // 关闭按钮的 tooltip 文案
    expect(find.byTooltip('关闭悬浮窗（播放继续）'), findsOneWidget);
  });

  testWidgets('点击关闭只隐藏窗口，不销毁', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byTooltip('关闭悬浮窗（播放继续）'));
    await tester.pump();

    expect(invoked, contains('hide'));
    expect(invoked, isNot(contains('close')),
        reason: '销毁窗口会断开跨窗口通道配对；关闭必须是隐藏');
    expect(invoked, isNot(contains('destroy')));
  });

  testWidgets('迷你窗常驻置顶且不抢任务栏', (tester) async {
    await tester.pumpWidget(app());
    // 窗口初始化是一串 await，每步之间需要 pump 让 microtask 跑完
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(invoked, contains('setAlwaysOnTop'));
    expect(invoked, contains('setSkipTaskbar'));
  });

  testWidgets('播放控件齐备：播放/暂停、上一段、下一段、变速', (tester) async {
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byTooltip('播放/暂停'), findsOneWidget);
    expect(find.byTooltip('上一段'), findsOneWidget);
    expect(find.byTooltip('下一段'), findsOneWidget);
    expect(find.byTooltip('播放速度'), findsOneWidget);
  });
}
