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

  // 浅色模式分层 (Apple 词典 / macOS 清爽明亮风格)
  static const Color lightBgWindow = Color(0xFFF8FAFC);
  static const Color lightBgSidebar = Color(0xFFF1F5F9);
  static const Color lightBgContent = Color(0xFFFFFFFF);
  static const Color lightBgCard = Color(0xFFFFFFFF);
  static const Color lightBgCardHover = Color(0xFFF8FAFC);
  static const Color lightBgInput = Color(0xFFF1F5F9);
  static const Color lightBgSelected = Color(0xFFE2E8F0);

  static const Color lightBorderSubtle = Color(0xFFE2E8F0);
  static const Color lightBorderStrong = Color(0xFFCBD5E1);

  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextTertiary = Color(0xFF94A3B8);
  static const Color lightTextDisabled = Color(0xFFCBD5E1);

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
  // 字体层级 (SF Pro / 桌面默认，四档规格 - 颜色自适应 ambient DefaultTextStyle)
  // ---------------------------------------------------------------------------
  static const TextStyle fontHeadline = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.2,
  );

  static const TextStyle fontTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    height: 1.3,
    letterSpacing: -0.1,
  );

  static const TextStyle fontBody = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.45,
  );

  static const TextStyle fontBodySecondary = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.normal,
    height: 1.45,
  );

  static const TextStyle fontCaption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.normal,
    height: 1.35,
  );

  static const TextStyle fontMono = TextStyle(
    fontSize: 12,
    fontFamily: 'SF Mono',
    fontFamilyFallback: ['Menlo', 'Monaco', 'Courier New', 'monospace'],
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  // ---------------------------------------------------------------------------
  // 全局 ThemeData
  // ---------------------------------------------------------------------------
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      extensions: const [AppColors.dark],
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
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: Color(0x666366F1),
        selectionHandleColor: accent,
      ),
      textTheme: TextTheme(
        headlineMedium: fontHeadline.copyWith(color: textPrimary),
        titleMedium: fontTitle.copyWith(color: textPrimary),
        bodyMedium: fontBody.copyWith(color: textPrimary),
        bodySmall: fontCaption.copyWith(color: textTertiary),
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
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
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

  // ---------------------------------------------------------------------------
  // 全局浅色 ThemeData (Apple 词典 / macOS 清爽白底风格)
  // ---------------------------------------------------------------------------
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      extensions: const [AppColors.light],
      scaffoldBackgroundColor: lightBgWindow,
      canvasColor: lightBgSidebar,
      dialogTheme: const DialogThemeData(backgroundColor: lightBgCard),
      dividerColor: lightBorderSubtle,
      colorScheme: const ColorScheme.light(
        primary: accent,
        onPrimary: Colors.white,
        secondary: accentDark,
        onSecondary: Colors.white,
        surface: lightBgCard,
        onSurface: lightTextPrimary,
        error: error,
        onError: Colors.white,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: accent,
        selectionColor: Color(0x336366F1),
        selectionHandleColor: accent,
      ),
      textTheme: TextTheme(
        headlineMedium: fontHeadline.copyWith(color: lightTextPrimary),
        titleMedium: fontTitle.copyWith(color: lightTextPrimary),
        bodyMedium: fontBody.copyWith(color: lightTextPrimary),
        bodySmall: fontCaption.copyWith(color: lightTextTertiary),
      ),
      cardTheme: CardThemeData(
        color: lightBgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadiusMedium,
          side: const BorderSide(color: lightBorderSubtle, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightBgInput,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: space12,
          vertical: space8,
        ),
        hintStyle: fontBody.copyWith(color: lightTextTertiary),
        border: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: lightBorderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: borderRadiusSmall,
          borderSide: const BorderSide(color: lightBorderSubtle),
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
        thumbColor: WidgetStateProperty.all(lightBorderStrong),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(6),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadiusSmall,
          border: Border.all(color: lightBorderSubtle),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        textStyle: fontCaption.copyWith(color: lightTextPrimary),
      ),
    );
  }
}

/// 实底之上的前景色。独立常量以便 lerp 引用（`Colors.white` 亦可用，但
/// AppColors 内部不应依赖 material 常量，keep token 自洽）。
const Color _white = Color(0xFFFFFFFF);

/// 自定义设计 Token 的 ThemeExtension，支持暗色和浅色
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bgWindow;
  final Color bgActivityBar;
  final Color bgSidebar;
  final Color bgContent;
  final Color bgCard;
  final Color bgCardHover;
  final Color bgInput;
  final Color bgSelected;
  final Color borderSubtle;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  // 强调色系列。static const 的 accent* 是浅深共用的单一取值，无法同时满足
  // 两种模式的对比度（accentDark 浅色 6.01 / 深色 2.65；accentLight 反之），
  // 故拆成「前景」与「实底」两个角色按模式取值。
  /// 强调色前景：选中态标签文字、页签 label、accent 色的正文与图标。
  final Color accentText;
  /// 强调色实底：Chip / 指示条的填充。
  final Color accentSolid;
  /// 实底之上的前景（文字与图标）。
  final Color onAccentSolid;
  /// 弱强调底：半透明靛蓝，用于选中态容器、徽标底。
  final Color accentSubtle;

  // 语义色系列，同 accent 的理由：500 档在浅色下 success 仅 1.85，
  // 在深色下 error 仅 3.65，两头都不达标，故 *Text 按模式取 700/300 档。
  final Color successText;
  final Color warningText;
  final Color errorText;
  final Color infoText;
  final Color successSolid;
  final Color warningSolid;
  final Color errorSolid;
  final Color infoSolid;

  const AppColors({
    required this.bgWindow,
    required this.bgActivityBar,
    required this.bgSidebar,
    required this.bgContent,
    required this.bgCard,
    required this.bgCardHover,
    required this.bgInput,
    required this.bgSelected,
    required this.borderSubtle,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.accentText,
    required this.accentSolid,
    required this.onAccentSolid,
    required this.accentSubtle,
    required this.successText,
    required this.warningText,
    required this.errorText,
    required this.infoText,
    required this.successSolid,
    required this.warningSolid,
    required this.errorSolid,
    required this.infoSolid,
  });

  static const dark = AppColors(
    bgWindow: AppTheme.bgWindow,
    bgActivityBar: AppTheme.bgActivityBar,
    bgSidebar: AppTheme.bgSidebar,
    bgContent: AppTheme.bgContent,
    bgCard: AppTheme.bgCard,
    bgCardHover: AppTheme.bgCardHover,
    bgInput: AppTheme.bgInput,
    bgSelected: AppTheme.bgSelected,
    borderSubtle: AppTheme.borderSubtle,
    borderStrong: AppTheme.borderStrong,
    textPrimary: AppTheme.textPrimary,
    textSecondary: AppTheme.textSecondary,
    textTertiary: AppTheme.textTertiary,
    textDisabled: AppTheme.textDisabled,
    // 强调色：深色下用 Indigo 300 作前景。accentLight(400) 在深输入底 #3C3C3C
    // 上仅 3.70，四底不达标；300 档五底 min 5.53。
    // 实底两模式统一取 accentDark——白字在其上 6.29；accent(500) 只有 4.47。
    accentText: Color(0xFFA5B4FC),
    accentSolid: AppTheme.accentDark,
    onAccentSolid: _white,
    accentSubtle: AppTheme.accentSubtle,
    // 语义色：*Text 用 300 档（深底 min 5.81~7.86）
    successText: Color(0xFF86EFAC),
    warningText: Color(0xFFFCD34D),
    errorText: Color(0xFFFCA5A5),
    infoText: Color(0xFF93C5FD),
    // *Solid 取 700 档——600 档白字仅 2.94~5.17，700 档全部 ≥4.92
    successSolid: Color(0xFF15803D),
    warningSolid: Color(0xFFA16207),
    errorSolid: Color(0xFFB91C1C),
    infoSolid: Color(0xFF1D4ED8),
  );

  static const light = AppColors(
    bgWindow: AppTheme.lightBgWindow,
    bgActivityBar: Color(0xFFE2E8F0),
    bgSidebar: AppTheme.lightBgSidebar,
    bgContent: AppTheme.lightBgContent,
    bgCard: AppTheme.lightBgCard,
    bgCardHover: AppTheme.lightBgCardHover,
    bgInput: AppTheme.lightBgInput,
    bgSelected: AppTheme.lightBgSelected,
    borderSubtle: AppTheme.lightBorderSubtle,
    borderStrong: AppTheme.lightBorderStrong,
    textPrimary: AppTheme.lightTextPrimary,
    textSecondary: AppTheme.lightTextSecondary,
    textTertiary: AppTheme.lightTextTertiary,
    textDisabled: AppTheme.lightTextDisabled,
    // 强调色：浅色下用 accentDark 作前景（四底 min 5.10）；实底同值，白字 6.29
    accentText: AppTheme.accentDark,
    accentSolid: AppTheme.accentDark,
    onAccentSolid: _white,
    accentSubtle: AppTheme.accentSubtle,
    // 语义色：*Text 用 800 档——700 档在浅选中底 #E2E8F0 上 success 4.07 /
    // warning 3.99，均不达 4.5；800 档四底 min 5.56
    successText: Color(0xFF166534),
    warningText: Color(0xFF854D0E),
    errorText: Color(0xFF991B1B),
    infoText: Color(0xFF1E40AF),
    // *Solid 同取 800 档（白字 6.85~8.31），深浅统一
    successSolid: Color(0xFF166534),
    warningSolid: Color(0xFF854D0E),
    errorSolid: Color(0xFF991B1B),
    infoSolid: Color(0xFF1E40AF),
  );

  @override
  AppColors copyWith({
    Color? bgWindow,
    Color? bgActivityBar,
    Color? bgSidebar,
    Color? bgContent,
    Color? bgCard,
    Color? bgCardHover,
    Color? bgInput,
    Color? bgSelected,
    Color? borderSubtle,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? accentText,
    Color? accentSolid,
    Color? onAccentSolid,
    Color? accentSubtle,
    Color? successText,
    Color? warningText,
    Color? errorText,
    Color? infoText,
    Color? successSolid,
    Color? warningSolid,
    Color? errorSolid,
    Color? infoSolid,
  }) {
    return AppColors(
      bgWindow: bgWindow ?? this.bgWindow,
      bgActivityBar: bgActivityBar ?? this.bgActivityBar,
      bgSidebar: bgSidebar ?? this.bgSidebar,
      bgContent: bgContent ?? this.bgContent,
      bgCard: bgCard ?? this.bgCard,
      bgCardHover: bgCardHover ?? this.bgCardHover,
      bgInput: bgInput ?? this.bgInput,
      bgSelected: bgSelected ?? this.bgSelected,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      accentText: accentText ?? this.accentText,
      accentSolid: accentSolid ?? this.accentSolid,
      onAccentSolid: onAccentSolid ?? this.onAccentSolid,
      accentSubtle: accentSubtle ?? this.accentSubtle,
      successText: successText ?? this.successText,
      warningText: warningText ?? this.warningText,
      errorText: errorText ?? this.errorText,
      infoText: infoText ?? this.infoText,
      successSolid: successSolid ?? this.successSolid,
      warningSolid: warningSolid ?? this.warningSolid,
      errorSolid: errorSolid ?? this.errorSolid,
      infoSolid: infoSolid ?? this.infoSolid,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      bgWindow: Color.lerp(bgWindow, other.bgWindow, t)!,
      bgActivityBar: Color.lerp(bgActivityBar, other.bgActivityBar, t)!,
      bgSidebar: Color.lerp(bgSidebar, other.bgSidebar, t)!,
      bgContent: Color.lerp(bgContent, other.bgContent, t)!,
      bgCard: Color.lerp(bgCard, other.bgCard, t)!,
      bgCardHover: Color.lerp(bgCardHover, other.bgCardHover, t)!,
      bgInput: Color.lerp(bgInput, other.bgInput, t)!,
      bgSelected: Color.lerp(bgSelected, other.bgSelected, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      accentSolid: Color.lerp(accentSolid, other.accentSolid, t)!,
      onAccentSolid: Color.lerp(onAccentSolid, other.onAccentSolid, t)!,
      accentSubtle: Color.lerp(accentSubtle, other.accentSubtle, t)!,
      successText: Color.lerp(successText, other.successText, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
      errorText: Color.lerp(errorText, other.errorText, t)!,
      infoText: Color.lerp(infoText, other.infoText, t)!,
      successSolid: Color.lerp(successSolid, other.successSolid, t)!,
      warningSolid: Color.lerp(warningSolid, other.warningSolid, t)!,
      errorSolid: Color.lerp(errorSolid, other.errorSolid, t)!,
      infoSolid: Color.lerp(infoSolid, other.infoSolid, t)!,
    );
  }
}

/// 语义化上下文主题扩展：根据当前亮暗模式自动解析语义颜色与字体
extension ThemeContextExtension on BuildContext {
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;

  /// 语义 Token 统一入口。
  ///
  /// 必须经 `ThemeData.extensions` 提供（见 `lightTheme` / `darkTheme`）。
  /// 若取不到扩展，说明当前 `MaterialApp` 漏接了主题（历史上
  /// `_SingleNoteWindowApp` 曾用裸 `ThemeData.light()` 导致暗色模式静默失效）。
  /// 这里用 assert 让漏接在开发期立即暴露，而不是靠兜底把 bug 藏起来；
  /// release 下仍退回按亮度推断，保证不会崩溃。
  AppColors get colors {
    final ext = Theme.of(this).extension<AppColors>();
    if (ext == null) {
      // 取不到扩展说明当前 MaterialApp 未用 AppTheme.lightTheme / darkTheme
      // （历史上 _SingleNoteWindowApp 曾用裸 ThemeData.light()，导致暗色模式
      // 静默失效）。这里按亮度兜底保证不崩，同时在 debug 期告警。
      assert(() {
        debugPrint(
          'AppColors ThemeExtension 缺失：该 MaterialApp 未使用 '
          'AppTheme.lightTheme / AppTheme.darkTheme。'
          '窗口会按亮度兜底，浅色模式下暗色组件将显示异常。',
        );
        return true;
      }());
    }
    return ext ?? (isDarkMode ? AppColors.dark : AppColors.light);
  }

  Color get bgWindow => colors.bgWindow;
  Color get bgActivityBar => colors.bgActivityBar;
  Color get bgSidebar => colors.bgSidebar;
  Color get bgContent => colors.bgContent;
  Color get bgCard => colors.bgCard;
  Color get bgCardHover => colors.bgCardHover;
  Color get bgInput => colors.bgInput;
  Color get bgSelected => colors.bgSelected;
  Color get borderSubtle => colors.borderSubtle;
  Color get borderStrong => colors.borderStrong;
  Color get textPrimary => colors.textPrimary;
  Color get textSecondary => colors.textSecondary;
  Color get textTertiary => colors.textTertiary;
  Color get textDisabled => colors.textDisabled;

  // 强调色与语义色。命名规则与中性色 getter 一致：widget 层一律经此取色，
  // 不再直接引用 AppTheme.<颜色> 字面量。
  Color get accentText => colors.accentText;
  Color get accentSolid => colors.accentSolid;
  Color get onAccentSolid => colors.onAccentSolid;
  Color get accentSubtle => colors.accentSubtle;

  Color get successText => colors.successText;
  Color get warningText => colors.warningText;
  Color get errorText => colors.errorText;
  Color get infoText => colors.infoText;
  Color get successSolid => colors.successSolid;
  Color get warningSolid => colors.warningSolid;
  Color get errorSolid => colors.errorSolid;
  Color get infoSolid => colors.infoSolid;

  TextStyle get fontHeadline => AppTheme.fontHeadline.copyWith(color: textPrimary);
  TextStyle get fontTitle => AppTheme.fontTitle.copyWith(color: textPrimary);
  TextStyle get fontBody => AppTheme.fontBody.copyWith(color: textPrimary);
  TextStyle get fontBodySecondary => AppTheme.fontBodySecondary.copyWith(color: textSecondary);
  TextStyle get fontCaption => AppTheme.fontCaption.copyWith(color: textTertiary);
}
