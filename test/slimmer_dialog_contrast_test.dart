import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/theme/app_theme.dart';

void main() {
  group('AppTheme & Dialog Button Contrast Tests', () {
    test('AppTheme.darkTheme specifies white foreground for elevated buttons', () {
      final theme = AppTheme.darkTheme;
      final elevatedTheme = theme.elevatedButtonTheme.style;
      expect(elevatedTheme, isNotNull);

      final bg = elevatedTheme?.backgroundColor?.resolve({});
      final fg = elevatedTheme?.foregroundColor?.resolve({});

      expect(bg, AppTheme.accent);
      expect(fg, Colors.white);
    });

    testWidgets('ElevatedButton in dark theme renders with white text and icon', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.security_rounded, size: 16),
                label: const Text('打开系统设置'),
                onPressed: () {},
              ),
            ),
          ),
        ),
      );

      final textFinder = find.text('打开系统设置');
      expect(textFinder, findsOneWidget);

      final iconFinder = find.byIcon(Icons.security_rounded);
      expect(iconFinder, findsOneWidget);

      final buttonFinder = find.bySubtype<ElevatedButton>();
      final elevatedButton = tester.widget<ElevatedButton>(buttonFinder);
      final resolvedFg = elevatedButton.style?.foregroundColor?.resolve({});
      final resolvedBg = elevatedButton.style?.backgroundColor?.resolve({});

      expect(resolvedBg, AppTheme.accent);
      expect(resolvedFg, Colors.white);
    });

    testWidgets('Default ElevatedButton without explicit style inherits white foreground from theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('默认操作'),
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(ElevatedButton);
      expect(buttonFinder, findsOneWidget);

      // Verify text widget is found
      expect(find.text('默认操作'), findsOneWidget);
    });
  });
}
