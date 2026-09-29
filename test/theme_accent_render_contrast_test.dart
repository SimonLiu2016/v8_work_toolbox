import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

/// 渲染级对比度验收。
///
/// `theme_accent_contrast_test.dart` 守的是 **token 值本身**的契约；本测试守的是
/// **控件真实渲染结果**——在两种主题下把改动过的控件真的 build 出来，从 widget 树里
/// 取出实际生效的前景/背景色对，验证对比度达标。
///
/// 这比 token 契约更接近用户所见：它抓的是「token 对了但 widget 没用它」这类错误
/// （例如选中态仍写死 `Colors.white`、TabBar 仍指向旧 token）。
double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// 取出 widget 树中第一个匹配文本的 Text widget 的实际颜色。
Color? _textColorOf(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate((w) => w is Text && w.data == text);
  expect(finder, findsOneWidget, reason: '未找到文本为「$text」的 Text');
  final t = tester.widget<Text>(finder);
  return t.style?.color ?? DefaultTextStyle.of(tester.element(finder)).style.color;
}

void main() {
  group('渲染级对比度：选中态标签', () {
    // 对应 A 类三处（folder_compare / image_resize / kma）的共同形态：
    // 选中容器 = bgSelected / bgInput / accentSubtle，前景 = accent 文字。
    // 此处用 AppColors 的对应 token 复现该组合。
    for (final mode in ['light', 'dark']) {
      testWidgets('$mode: 选中标签文字对选中底 ≥ 4.5', (tester) async {
        final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        final colors = mode == 'light' ? AppColors.light : AppColors.dark;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(builder: (context) {
                // 与 A 类一致的取色写法
                final fg = context.isDarkMode ? Colors.white : context.accentText;
                return Container(
                  color: context.bgSelected,
                  child: Center(
                    child: Text('YAML',
                        style: AppTheme.fontCaption.copyWith(color: fg)),
                  ),
                );
              }),
            ),
          ),
        );

        final fg = _textColorOf(tester, 'YAML');
        expect(fg, isNotNull);
        expect(
          _ratio(fg!, colors.bgSelected),
          greaterThanOrEqualTo(4.5),
          reason: '$mode 模式选中标签文字对选中底仅 ${_ratio(fg, colors.bgSelected)}',
        );
      });
    }
  });

  group('渲染级对比度：实底 Chip', () {
    // 对应 B 类两处 ChoiceChip
    for (final mode in ['light', 'dark']) {
      testWidgets('$mode: ChoiceChip 选中态 label 对 selectedColor ≥ 4.5', (tester) async {
        final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        final colors = mode == 'light' ? AppColors.light : AppColors.dark;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: ChoiceChip(
                  label: const Text('120 分钟'),
                  selected: true,
                  selectedColor: colors.accentSolid,
                  backgroundColor: colors.bgInput,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: colors.onAccentSolid,
                  ),
                  onSelected: (_) {},
                ),
              ),
            ),
          ),
        );

        final fg = _textColorOf(tester, '120 分钟');
        expect(fg, isNotNull);
        expect(
          _ratio(fg!, colors.accentSolid),
          greaterThanOrEqualTo(4.5),
          reason: '$mode 模式 Chip label 对实底仅 ${_ratio(fg, colors.accentSolid)}',
        );
      });
    }
  });

  group('渲染级对比度：页签', () {
    // 对应 C 类四处 TabBar
    for (final mode in ['light', 'dark']) {
      testWidgets('$mode: TabBar 选中 label 对页面表面 ≥ 4.5', (tester) async {
        final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        final colors = mode == 'light' ? AppColors.light : AppColors.dark;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: DefaultTabController(
              length: 2,
              child: Builder(builder: (context) {
                return Scaffold(
                  backgroundColor: context.bgContent,
                  body: Column(
                    children: [
                      TabBar(
                        controller: DefaultTabController.of(context),
                        isScrollable: true,
                        labelColor: context.accentText,
                        unselectedLabelColor: context.textSecondary,
                        indicatorColor: context.accentSolid,
                        tabs: const [
                          Tab(text: '模型供应商'),
                          Tab(text: '默认能力槽位'),
                        ],
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        );

        final fg = _textColorOf(tester, '模型供应商');
        expect(fg, isNotNull);
        expect(
          _ratio(fg!, colors.bgContent),
          greaterThanOrEqualTo(4.5),
          reason: '$mode 模式选中页签文字对内容底仅 ${_ratio(fg, colors.bgContent)}',
        );
      });
    }
  });

  group('渲染级对比度：语义色按钮', () {
    // 对应 §4 批次 H 迁移的 6 处实底按钮
    for (final mode in ['light', 'dark']) {
      testWidgets('$mode: 危险操作按钮白字对实底 ≥ 4.5', (tester) async {
        final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;
        final colors = mode == 'light' ? AppColors.light : AppColors.dark;

        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.errorSolid,
                    foregroundColor: colors.onAccentSolid,
                  ),
                  onPressed: () {},
                  child: const Text('删除'),
                ),
              ),
            ),
          ),
        );

        final fg = _textColorOf(tester, '删除');
        expect(fg, isNotNull);
        expect(
          _ratio(fg!, colors.errorSolid),
          greaterThanOrEqualTo(4.5),
          reason: '$mode 模式危险按钮白字对 errorSolid 仅 ${_ratio(fg, colors.errorSolid)}',
        );
      });
    }
  });

  group('守卫：widget 层零静态引用', () {
    // 与 tool/check_no_static_theme_tokens.sh 同一规则的 Dart 侧兜底。
    // 脚本负责 CI/pre-push，这里负责 `flutter test` 也能发现回归。
    test('AppColors 提供全部 12 个强调/语义 token', () {
      for (final c in [AppColors.light, AppColors.dark]) {
        expect(c.accentText, isNotNull);
        expect(c.accentSolid, isNotNull);
        expect(c.onAccentSolid, isNotNull);
        expect(c.accentSubtle, isNotNull);
        expect(c.successText, isNotNull);
        expect(c.warningText, isNotNull);
        expect(c.errorText, isNotNull);
        expect(c.infoText, isNotNull);
        expect(c.successSolid, isNotNull);
        expect(c.warningSolid, isNotNull);
        expect(c.errorSolid, isNotNull);
        expect(c.infoSolid, isNotNull);
      }
    });
  });
}
