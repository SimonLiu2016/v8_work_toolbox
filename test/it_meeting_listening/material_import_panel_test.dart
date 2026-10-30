import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:V8WorkToolbox/theme/app_theme.dart';

import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/ui/material_import_panel.dart';

void main() {
  testWidgets('默认收起为一行入口，不占位置', (tester) async {
    await tester.pumpWidget(_panel(expanded: false));

    expect(find.text('会议材料排练'), findsOneWidget);
    expect(find.text('导入周会 / 临时会议材料，预听自己要讲的话'), findsOneWidget);
    // 四步按钮不出现
    expect(find.text('选择文件'), findsNothing);
    expect(find.text('目标时长'), findsNothing);
  });

  testWidgets('展开后呈现四步与目标时长选择', (tester) async {
    await tester.pumpWidget(_panel(expanded: true));

    expect(find.text('导入材料'), findsOneWidget);
    expect(find.text('生成讲稿'), findsOneWidget);
    expect(find.text('生成剧本'), findsOneWidget);
    expect(find.text('合成语音'), findsOneWidget);
    expect(find.text('目标时长'), findsOneWidget);
    expect(find.text('30 分钟'), findsOneWidget);
    expect(find.text('60 分钟'), findsOneWidget);
  });

  testWidgets('前置未满足时该步按钮置灰', (tester) async {
    await tester.pumpWidget(_panel(
      expanded: true,
      canRun: (step) => step == RehearsalStep.material,
    ));

    // 只有「导入材料」可点
    final materialButton = find.widgetWithText(OutlinedButton, '选择文件');
    expect(materialButton, findsOneWidget);
    expect(tester.widget<OutlinedButton>(materialButton).onPressed, isNotNull);

    // 「生成讲稿」这一步不可点（它的按钮文案也是「生成」，按步骤行定位）
    final draftButton = _buttonFor(tester, RehearsalStep.draft);
    expect(tester.widget<OutlinedButton>(draftButton).onPressed, isNull);
  });

  testWidgets('步骤失败后按钮变重试，且显示失败原因', (tester) async {
    await tester.pumpWidget(_panel(
      expanded: true,
      onRun: (_) async => '讲稿只有 1 节，少于 3 节',
    ));
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();

    expect(find.text('讲稿只有 1 节，少于 3 节'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, '重试'), findsOneWidget);
  });

  testWidgets('步骤成功后按钮变重新生成', (tester) async {
    await tester.pumpWidget(_panel(expanded: true));
    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(OutlinedButton, '重新导入'), findsOneWidget);
  });

  testWidgets('摘要显示在步骤旁', (tester) async {
    await tester.pumpWidget(_panel(
      expanded: true,
      materialTitle: 'Q4 容量评审',
      draftSummary: '3 节 · Q4 容量评审 · 汇报讲稿',
      scriptSummary: '140 轮 · 预估 32 分钟',
      audioSummary: '已生成 32:10',
    ));

    // 标题出现在入口行与步骤摘要两处
    expect(find.text('Q4 容量评审'), findsNWidgets(2));
    expect(find.text('3 节 · Q4 容量评审 · 汇报讲稿'), findsOneWidget);
    expect(find.text('140 轮 · 预估 32 分钟'), findsOneWidget);
    expect(find.text('已生成 32:10'), findsOneWidget);
  });

  testWidgets('一次只跑一步（上一步没跑完时其它按钮不可点）', (tester) async {
    var running = false;
    await tester.pumpWidget(_panel(
      expanded: true,
      onRun: (_) async {
        running = true;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        running = false;
        return null;
      },
    ));

    await tester.tap(find.widgetWithText(OutlinedButton, '选择文件'));
    await tester.pump();
    // 第一步还在跑：出现进度指示，其它步骤按钮不可点
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(running, isTrue);

    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}

/// 某一步的按钮（按步骤标签文本找它的同一行）。
Finder _buttonFor(WidgetTester tester, RehearsalStep step) {
  final label = find.text(step.label);
  expect(label, findsOneWidget);
  final row = find.ancestor(of: label, matching: find.byType(Row));
  return find.descendant(of: row, matching: find.byType(OutlinedButton));
}

Widget _panel({
  bool expanded = true,
  String? materialTitle,
  String? draftSummary,
  String? scriptSummary,
  String? audioSummary,
  bool Function(RehearsalStep)? canRun,
  Future<String?> Function(RehearsalStep)? onRun,
}) {
  return MaterialApp(
    theme: AppTheme.darkTheme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: MaterialImportPanel(
          expanded: expanded,
          onToggleExpanded: () {},
          materialTitle: materialTitle,
          draftSummary: draftSummary,
          scriptSummary: scriptSummary,
          audioSummary: audioSummary,
          targetMinutes: 30,
          onTargetMinutesChanged: (_) {},
          canRun: canRun ?? (_) => true,
          onRun: onRun ?? (_) async => null,
        ),
      ),
    ),
  );
}
