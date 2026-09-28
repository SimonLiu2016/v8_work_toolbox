import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/slimmer/slimmer_models.dart';
import 'package:V8WorkToolbox/tools/slimmer/smart_disk_slimmer_page.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';

void main() {
  // 页面 initState 会拉 SettingsStore 的分项配置，而 SettingsStore 走惰性 init
  // 且没有注入点，只能就绪全局根目录。见 change tasks 5.2 的遗留说明。
  AppPaths.overrideRootForTesting(
    Directory.systemTemp.createTempSync('v8_slimmer_techstack_'),
  );

  testWidgets(
      '技术栈分组：勾选复选框后展开态保持（不因父级 rebuild 蒸发）',
      (tester) async {
        // 构造两条同技术栈的构建产物候选
        const items = [
          SlimCandidateItem(
            id: 'maven-1',
            title: 'target',
            subtitle: 'proj-a',
            path: '/tmp/proj-a/target',
            sizeBytes: 1024,
            category: SlimmerCategory.projectArtifacts,
            techStack: ProjectTechStack.maven,
            safety: SafetyRating.safe,
            isSelected: false,
          ),
          SlimCandidateItem(
            id: 'maven-2',
            title: 'target',
            subtitle: 'proj-b',
            path: '/tmp/proj-b/target',
            sizeBytes: 2048,
            category: SlimmerCategory.projectArtifacts,
            techStack: ProjectTechStack.maven,
            safety: SafetyRating.safe,
            isSelected: false,
          ),
        ];

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              height: 1400,
              child: SmartDiskSlimmerPage(initialItems: items),
            ),
          ),
        ));

        // 等待首帧（异步加载可能抛平台通道异常，已 ignoreOnError）
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 切到"项目构建产物"分类（filter chip 文本形如 "项目构建产物 (2)"）
        final catChip = find.textContaining('项目构建产物 (');
        await tester.ensureVisible(catChip);
        await tester.tap(catChip);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 默认收起：不应出现子项标题
        expect(find.text('proj-a'), findsNothing);

        // 展开 Maven 分组（点击分组标题行；label 为 "Maven / Java（2 个项目）"）
        final groupTitle = find.textContaining('Maven / Java（2');
        await tester.ensureVisible(groupTitle);
        await tester.tap(groupTitle);
        await tester.pumpAndSettle(const Duration(seconds: 1));
        expect(find.text('proj-a'), findsOneWidget);

        // 勾选第一个复选框——此前这会让分组收回
        final checkboxFinder = find.byType(Checkbox).first;
        await tester.ensureVisible(checkboxFinder);
        await tester.tap(checkboxFinder);
        await tester.pumpAndSettle(const Duration(seconds: 1));

        // 关键断言：展开态保留，子项仍可见
        expect(
          find.text('proj-a'),
          findsOneWidget,
          reason: '勾选复选框后分组不应收回（expanded 状态需跨父级 rebuild 保留）',
        );
      });
}
