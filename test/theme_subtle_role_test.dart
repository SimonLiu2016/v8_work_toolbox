import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/components/app_components.dart';
import 'package:V8WorkToolbox/main.dart' show WindowKind, WindowServices;
import 'package:V8WorkToolbox/theme/app_theme.dart';

/// 弱强调底（subtle wash）角色契约。
///
/// 背景：`unify-accent-tokens-and-fix-light-mode-contrast` 的批量迁移只识别了
/// 「实底」与「前景」两个角色，把 `*Subtle`（12% 半透明底）也当成了二者之一。
/// 结果是底色与文字被映射到同一个实色——用户看到"只有一个色块、看不见文字"。
///
/// 本测试守三类事：
///   1. wash 底必须与同名前景相异；
///   2. wash 底 + 文字色对比度 ≥ 4.5（两种模式）；
///   3. 每个渲染 themed `MaterialApp` 的窗口都必须初始化 SettingsStore。
double _luminance(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

/// 半透明色合成到不透明基底上，得到最终显示的像素颜色。
Color _over(Color fg, Color bg) =>
    fg.a >= 1.0 ? fg : Color.alphaBlend(fg, bg);

double _ratio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

/// wash 的原始 alpha（`0x1F` / 255 ≈ 0.1216）。全部误映射处的原值均为它。
const double _kWashAlpha = 0x1F / 255;

void main() {
  group('弱强调底角色契约', () {
    for (final mode in ['light', 'dark']) {
      final colors = mode == 'light' ? AppColors.light : AppColors.dark;
      final surfaces = [colors.bgWindow, colors.bgCard, colors.bgInput, colors.bgSelected];

      for (final name in ['success', 'warning', 'error', 'info']) {
        final solid = switch (name) {
          'success' => colors.successSolid,
          'warning' => colors.warningSolid,
          'error' => colors.errorSolid,
          _ => colors.infoSolid,
        };
        final text = switch (name) {
          'success' => colors.successText,
          'warning' => colors.warningText,
          'error' => colors.errorText,
          _ => colors.infoText,
        };

        test('$mode: ${name}Text 派生的 wash 底 ≠ 同名前景', () {
          // wash = text.withValues(alpha: 0.1216)，叠在各表面上取近似合成色。
          for (final bg in surfaces) {
            final wash = Color.alphaBlend(
              text.withValues(alpha: _kWashAlpha),
              bg,
            );
            expect(
              wash.toARGB32(),
              isNot(text.toARGB32()),
              reason: '$mode 模式 ${name}Text 被直接当作底色，未做半透明派生',
            );
          }
        });

        test('$mode: ${name}Text 派生的 wash 底 + 前景 ≥ 4.5', () {
          for (final bg in surfaces) {
            final wash = Color.alphaBlend(text.withValues(alpha: _kWashAlpha), bg);
            final r = _ratio(text, wash);
            expect(
              r,
              greaterThanOrEqualTo(4.5),
              reason: '$mode 模式 ${name}Text 压在自己的 wash 上仅 $r',
            );
          }
        });
      }
    }
  });

  group('AppBanner 四分支', () {
    for (final mode in ['light', 'dark']) {
      final colors = mode == 'light' ? AppColors.light : AppColors.dark;
      final body = colors.textPrimary;

      for (final entry in {
        'info': AppBannerType.info,
        'success': AppBannerType.success,
        'warning': AppBannerType.warning,
        'error': AppBannerType.error,
      }.entries) {
        testWidgets('$mode: ${entry.key} banner 底 + 正文 ≥ 4.5', (tester) async {
          final theme = mode == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme;

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(
                body: AppBanner(
                  message: '这是一条用于对比度验证的提示文案',
                  type: entry.value,
                ),
              ),
            ),
          );

          // 取出 banner 实际渲染出的容器底色与正文颜色。
          final container = tester.widget<Container>(
            find.descendant(
              of: find.byType(AppBanner),
              matching: find.byType(Container).first,
            ),
          );
          final boxDecoration = container.decoration as BoxDecoration;
          final bg = boxDecoration.color!;
          final textColor = tester.widget<Text>(
            find.text('这是一条用于对比度验证的提示文案'),
          ).style?.color;

          expect(textColor, isNotNull, reason: '未取到 banner 正文颜色');
          // banner 底色半透明，须先与 Scaffold 背景合成才是最终显示像素。
          final bgOpaque = _over(bg, theme.scaffoldBackgroundColor);
          final r = _ratio(textColor!, bgOpaque);
          expect(
            r,
            greaterThanOrEqualTo(4.5),
            reason:
                '$mode 模式 ${entry.key} banner 正文($textColor)对底色($bg)仅 $r',
          );
        });
      }
    }
  });

  group('窗口服务清单完整性', () {
    // 凡渲染 themed MaterialApp 的窗口，都必须能读到持久化 themeMode。
    test('所有窗口 kind 都声明 SettingsStore', () {
      for (final kind in WindowKind.values) {
        final names = WindowServices.requiredNames(kind);
        expect(
          names,
          contains('SettingsStore'),
          reason: '$kind 渲染 themed MaterialApp 但未初始化 SettingsStore，'
              'themeModeNotifier 会停在 ThemeMode.system',
        );
      }
    });
  });
}
