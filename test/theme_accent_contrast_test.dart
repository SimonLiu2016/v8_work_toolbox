import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

/// 强调色与语义色的对比度契约。
///
/// 这两个系列此前是 `AppTheme` 的 static const，浅深共用同一组值，导致浅色模式下
/// 出现白字落浅底（选中标签对比度 1.10）与 500 档语义色文字压浅底（success 仅
/// 1.85）。本测试把每个角色的最低对比度固化为断言，任何调色若让某个组合跌破阈值，
/// 这里会带上 token 名与模式名失败，而不是等用户在浅色模式下肉眼发现。
///
/// 阈值依据：
///   - 文字前景、实底之上的前景  WCAG AA 正文  4.5:1
///   - 图标 / 装饰条             WCAG 1.4.11 非文字  3.0:1
double _relativeLuminance(Color c) {
  double channel(double v) {
    return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// 四种表面：窗口、卡片、输入、选中。控件实际落座的四类底色。
List<Color> _surfaces(AppColors c) => [
      c.bgWindow,
      c.bgCard,
      c.bgInput,
      c.bgSelected,
    ];

void main() {
  group('强调色对比度契约', () {
    for (final entry in {
      'light': AppColors.light,
      'dark': AppColors.dark,
    }.entries) {
      final mode = entry.key;
      final colors = entry.value;
      final surfaces = _surfaces(colors);

      test('$mode: accentText 对四种表面 ≥ 4.5', () {
        for (final bg in surfaces) {
          final ratio = _contrast(colors.accentText, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: 'accentText 在 $mode 模式下对比度 $ratio 低于 4.5',
          );
        }
      });

      test('$mode: onAccentSolid 对 accentSolid ≥ 4.5', () {
        final ratio = _contrast(colors.onAccentSolid, colors.accentSolid);
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'onAccentSolid 在 $mode 模式下压 accentSolid 仅 $ratio',
        );
      });

      test('$mode: accentText 作图标前景 ≥ 3.0', () {
        for (final bg in surfaces) {
          final ratio = _contrast(colors.accentText, bg);
          expect(
            ratio,
            greaterThanOrEqualTo(3.0),
            reason: 'accentText 作图标在 $mode 模式下对比度 $ratio 低于 3.0',
          );
        }
      });

      for (final name in ['success', 'warning', 'error', 'info']) {
        test('$mode: ${name}Text 对四种表面 ≥ 4.5', () {
          final fg = switch (name) {
            'success' => colors.successText,
            'warning' => colors.warningText,
            'error' => colors.errorText,
            _ => colors.infoText,
          };
          for (final bg in surfaces) {
            final ratio = _contrast(fg, bg);
            expect(
              ratio,
              greaterThanOrEqualTo(4.5),
              reason: '${name}Text 在 $mode 模式下对比度 $ratio 低于 4.5',
            );
          }
        });

        test('$mode: ${name}Solid 实底上的前景可读 ≥ 4.5', () {
          // 实底之上的文字统一用 onAccentSolid（白）。语义色实底保持 500 档，
          // 需确认白字在其上仍达标。
          final solid = switch (name) {
            'success' => colors.successSolid,
            'warning' => colors.warningSolid,
            'error' => colors.errorSolid,
            _ => colors.infoSolid,
          };
          final ratio = _contrast(colors.onAccentSolid, solid);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '白字压 ${name}Solid 在 $mode 模式下仅 $ratio',
          );
        });
      }
    }
  });

  group('中性色与强调色底 = 零变化守卫', () {
    // accentSolid / accentSubtle 的深色值必须逐位等于迁移前的 static const，
    // 否则视为改变了深色视觉。语义色 *Solid 例外——它被有意加深到 600 档
    // （500 档上白字仅 2.15~3.76，见 design 决策 9），由上面的 4.5 断言看守。
    // 深色下刻意改变的两处（都为了让对比度达标，见 design 决策 2/9）：
    //   accentText  accentLight(400) → Indigo 300（400 在深输入底仅 3.70）
    //   accentSolid  accent(500)     → accentDark（白字 4.47 → 6.29）
    // 二者均在上面的 4.5 断言看守内，此组只守护「本应逐位不变」的项。
    test('dark: 弱强调底等于 static const', () {
      expect(AppColors.dark.accentSubtle, AppTheme.accentSubtle);
    });

    test('light: 弱强调底等于 static const', () {
      expect(AppColors.light.accentSubtle, AppTheme.accentSubtle);
    });
  });
}
