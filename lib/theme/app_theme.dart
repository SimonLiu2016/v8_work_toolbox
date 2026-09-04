import 'package:flutter/material.dart';

/// Raycast 风格深色主题设计 Token 与全局 ThemeData
class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // 色板 (Color Palette)
  // ---------------------------------------------------------------------------

  // 背景分层 (中性深灰层次)
  static const Color bgWindow = Color(0xFF1E1E1E); // 窗口底层背景
  static const Color bgActivityBar = Color(0xFF333333); // 活动栏背景
  static const Color bgSidebar = Color(0xFF252526); // 侧边面板背景
  static const Color bgContent = Color(0xFF1E1E1E); // 内容区主背景
  static const Color bgCard = Color(0xFF2D2D30); // 卡片/容器背景
  static const Color bgCardHover = Color(0xFF383838); // 卡片/容器悬停态
  static const Color bgInput = Color(0xFF3C3C3C); // 输入框底色
  static const Color bgSelected = Color(0xFF37373D); // 选中项背景

  // 边框分层
  static const Color borderSubtle = Color(0xFF3C3C3C); // 细微弱边框
  static const Color borderStrong = Color(0xFF505054); // 明显边框
  static const Color borderFocused = Color(0xFF6366F1); // 聚焦边框（强调色）

  // 文字分级 (三级中性灰阶)
  static const Color textPrimary = Color(0xFFD4D4D4); // 主文字
  static const Color textSecondary = Color(0xFFA0A0A0); // 次级文字
  static const Color textTertiary = Color(0xFF6A6A6E); // 弱文字 / 占位符
  static const Color textDisabled = Color(0xFF505050); // 禁用文字

  // 强调色 (蓝紫系 Raycast 风格)
  static const Color accent = Color(0xFF6366F1); // 主强调色 (Indigo 500)
  static const Color accentLight = Color(0xFF818CF8); // 强调色悬浮/亮态
  static const Color accentDark = Color(0xFF4F46E5); // 强调色按下态
  static const Color accentSubtle = Color(0x1F6366F1); // 弱强调半透明背景

  // 语义色
  static const Color success = Color(0xFF22C55E);
  static const Color successSubtle = Color(0x1F22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color warningSubtle = Color(0x1FF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorSubtle = Color(0x1FEF4444);
  static const Color info = Color(0xFF3B82F6);
  static const Color infoSubtle = Color(0x1F3B82F6);

  // ---------------------------------------------------------------------------
  // 间距阶梯 (4 为基数)
  // ---------------------------------------------------------------------------
  static const double space2 = 2.0;
  static const double space4 = 4.0;
  static const double space6 = 6.0;
  static const double space8 = 8.0;
  static const double space10 = 10.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;

  // ---------------------------------------------------------------------------
  // 圆角规范
  // ---------------------------------------------------------------------------
  static const double radiusSmall = 6.0;
  static const double radiusMedium = 10.0;
  static const double radiusLarge = 14.0;

  static final BorderRadius borderRadiusSmall = BorderRadius.circular(radiusSmall);
  static final BorderRadius borderRadiusMedium = BorderRadius.circular(radiusMedium);
  static final BorderRadius borderRadiusLarge = BorderRadius.circular(radiusLarge);

  // ---------------------------------------------------------------------------
  // 字体层级 (SF Pro / 桌面默认，四档规格)
  // ---------------------------------------------------------------------------
  static const TextStyle fontHeadline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle fontTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: textPrimary,
    letterSpacing: -0.1,
  );

  static const TextStyle fontBody = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.45,
    color: textPrimary,
  );

  static const TextStyle fontBodySecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.45,
    color: textSecondary,
  );

  static const TextStyle fontCaption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    height: 1.35,
    color: textTertiary,
  );

  static const TextStyle fontMono = TextStyle(
    fontSize: 12,
    fontFamily: 'SF Mono',
    fontFamilyFallback: ['Menlo', 'Monaco', 'Courier New', 'monospace'],
    fontWeight: FontWeight.normal,
    height: 1.4,
    color: textPrimary,
  );

  // ---------------------------------------------------------------------------
  // 全局 ThemeData
  // ---------------------------------------------------------------------------
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgWindow,
      canvasColor: bgSidebar,
      dialogTheme: const DialogThemeData(backgroundColor: bgCard),
      dividerColor: borderSubtle,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        onPrimary: Colors.white,
        secondary: accentLight,
        onSecondary: Colors.white,
        surface: bgCard,
        onSurface: textPrimary,
        error: error,
        onError: Colors.white,
      ),
      textTheme: const TextTheme(
        headlineMedium: fontHeadline,
        titleMedium: fontTitle,
        bodyMedium: fontBody,
        bodySmall: fontCaption,
      ),
      cardTheme: CardThemeData(
        color: bgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusMedium,
          side: const BorderSide(color: borderSubtle, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bgInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space12,
          vertical: space8,
        ),
        hintStyle: fontBody.copyWith(color: textTertiary),
        border: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: borderFocused, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: error),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(borderStrong),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: bgCardHover,
          borderRadius: borderRadiusSmall,
          border: Border.all(color: borderSubtle),
        ),
        textStyle: fontCaption.copyWith(color: textPrimary),
      ),
    );
  }
}
