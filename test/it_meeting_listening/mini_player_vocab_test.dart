import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/it_listening_mini_player.dart';

/// 迷你窗**词汇模式**渲染与关闭语义测试。
///
/// 词汇模式（`mode=vocab`）下：
/// - 显示当前词文本与 `n/N` 词序进度；
/// - 隐藏变速控件（词汇走 TTS 固定语速）；
/// - 关闭仍是隐藏（不销毁窗口），宿主按模式分流停播。
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

  Future<void> pumpAppWithState(
    WidgetTester tester,
    Map<dynamic, dynamic> map,
  ) async {
    await tester.pumpWidget(const ItListeningMiniPlayerApp());
    await tester.pump(const Duration(milliseconds: 50));
    // applyState 是公开方法，State 是私有类——用 dynamic 分发注入词汇状态。
    final state = tester.state(find.byType(ItListeningMiniPlayerApp));
    (state as dynamic).applyState(map);
    await tester.pump();
  }

  testWidgets('MiniPlayerState 模型：vocab 模式解析与词序文本', (tester) async {
    final s = MiniPlayerState.fromMap(const {
      'mode': 'vocab',
      'sceneLabel': '词汇',
      'clipTitle': 'governance',
      'positionMs': 2,
      'durationMs': 24,
      'playing': true,
      'continuous': true,
    });
    expect(s.isVocab, isTrue);
    expect(s.sceneLabel, '词汇');
    expect(s.clipTitle, 'governance');
    expect(s.wordProgressText, '2/24');

    final clip = MiniPlayerState.fromMap(const {'mode': 'clip'});
    expect(clip.isVocab, isFalse);
    expect(clip.wordProgressText, isEmpty);

    // 往返序列化。
    final roundTrip = MiniPlayerState.fromMap(s.toMap());
    expect(roundTrip.isVocab, isTrue);
    expect(roundTrip.wordProgressText, '2/24');
  });

  testWidgets('vocab 模式：显示当前词与词序、隐藏变速控件', (tester) async {
    await pumpAppWithState(tester, const {
      'mode': 'vocab',
      'sceneLabel': '词汇',
      'clipTitle': 'governance',
      'positionMs': 2,
      'durationMs': 24,
      'playing': true,
      'continuous': true,
    });

    expect(find.text('词汇'), findsOneWidget);
    expect(find.text('governance'), findsOneWidget);
    expect(find.text('2/24'), findsOneWidget);
    // 词汇模式不显示变速控件。
    expect(find.byTooltip('播放速度'), findsNothing);
    // 控件仍在：播放/暂停、上一词、下一词、连续播放。
    expect(find.byTooltip('播放/暂停'), findsOneWidget);
    expect(find.byTooltip('上一段'), findsOneWidget);
    expect(find.byTooltip('下一段'), findsOneWidget);
    expect(find.byTooltip('连续播放'), findsOneWidget);
  });

  testWidgets('vocab 模式关闭：窗口隐藏、不销毁', (tester) async {
    await pumpAppWithState(tester, const {
      'mode': 'vocab',
      'sceneLabel': '词汇',
      'clipTitle': 'governance',
      'positionMs': 0,
      'durationMs': 24,
      'playing': true,
      'continuous': false,
    });

    await tester.tap(find.byTooltip('关闭悬浮窗（播放继续）'));
    await tester.pump();

    expect(invoked, contains('hide'));
    expect(invoked, isNot(contains('close')),
        reason: '销毁窗口会断开跨窗口通道配对；关闭必须是隐藏');
    expect(invoked, isNot(contains('destroy')));
  });
}
