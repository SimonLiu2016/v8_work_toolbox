import 'package:flutter/material.dart';

/// 笔记本内浅色面板的共享主题边界。
///
/// 应用全局主题是暗色的（`app_theme.dart` 的 `inputDecorationTheme` 是
/// `filled: true, fillColor: bgInput`），而笔记本是刻意的浅色孤岛。若不隔离，
/// 深灰填充会盖在浅色容器上，叠加近黑字色后输入内容难以辨认。
///
/// **笔记本内新增浅色面板一律用它包裹根节点**，不要逐个 TextField 补
/// `filled: false`——隔离责任必须落在面板边界，新增字段才能被默认覆盖。
class NotebookLightScope extends StatelessWidget {
  const NotebookLightScope({super.key, required this.child});

  final Widget child;

  /// 浅色画布的背景色，与笔记本既有面板保持一致。
  static const Color surface = Colors.white;

  /// 浅色面板的次级底色（元数据栏、输入框容器、卡片底）。
  static const Color surfaceMuted = Color(0xFFF8FAFC);

  /// 浅色面板中 markdown 代码块/内联 code 的底色。
  ///
  /// 比 [surface] 深一档，保证代码在浅色画布上有可见边界（而非与背景同色）。
  /// 与 [context.bgCardHover] 在暗色主题中承担同一职责——`AppMarkdownView`
  /// 在浅色主题下会自动取同族色，此处供浅色面板显式传参（design D2）。
  static const Color codeSurface = Color(0xFFF1F5F9);

  /// 主文字色。
  static const Color textPrimary = Color(0xFF0F172A);

  /// 次级文字色（标签、占位、说明）。
  static const Color textSecondary = Color(0xFF64748B);

  /// 浅色描边。
  static const Color border = Color(0xFFE5E7EB);

  /// 强调色（与全局 accent 一致）。
  static const Color accent = Color(0xFF3B82F6);

  /// 笔记本内浅色表单字段共用的输入装饰：无填充、无边框，由容器负责视觉边界。
  static const InputDecorationTheme inputDecorationTheme = InputDecorationTheme(
    filled: false,
    fillColor: Colors.transparent,
  );

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.light().copyWith(
        scaffoldBackgroundColor: surface,
        inputDecorationTheme: inputDecorationTheme,
      ),
      child: child,
    );
  }
}
