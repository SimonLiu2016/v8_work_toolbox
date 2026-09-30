import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

// =============================================================================
// AppTextField - 紧凑型深色输入框
// =============================================================================

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final Widget? prefixIcon;
  final Widget? suffix;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool readOnly;
  final bool enabled;
  final int maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final bool autofocus;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.errorText,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.prefixIcon,
    this.suffix,
    this.suffixIcon,
    this.obscureText = false,
    this.readOnly = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.focusNode,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      obscureText: obscureText,
      readOnly: readOnly,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      minLines: minLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: AppTheme.fontBody.copyWith(
        color: enabled ? context.textPrimary : context.textDisabled,
      ),
      cursorColor: context.accentSolid,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        hintText: hintText,
        helperText: helperText,
        errorText: errorText,
        prefix: prefix,
        prefixIcon: prefixIcon,
        suffix: suffix,
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.space12,
          vertical: AppTheme.space8,
        ),
      ),
    );

    if (label == null) return field;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label!,
          style: AppTheme.fontCaption.copyWith(
            color: context.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: AppTheme.space4),
        field,
      ],
    );
  }
}

// =============================================================================
// AppButton - Raycast 风格统一按钮
// =============================================================================

enum AppButtonVariant { primary, secondary, ghost, danger }
enum AppButtonSize { small, regular }

class AppButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool isLoading;

  const AppButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.regular,
    this.isLoading = false,
  });

  const AppButton.primary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = AppButtonSize.regular,
    this.isLoading = false,
  }) : variant = AppButtonVariant.primary;

  const AppButton.secondary({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = AppButtonSize.regular,
    this.isLoading = false,
  }) : variant = AppButtonVariant.secondary;

  const AppButton.ghost({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = AppButtonSize.regular,
    this.isLoading = false,
  }) : variant = AppButtonVariant.ghost;

  const AppButton.danger({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.size = AppButtonSize.regular,
    this.isLoading = false,
  }) : variant = AppButtonVariant.danger;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    Color bg;
    Color fg;
    Border? border;

    switch (widget.variant) {
      case AppButtonVariant.primary:
        bg = isEnabled
            ? (_isHovered ? context.accentSolid : context.accentSolid)
            : context.accentSolid.withValues(alpha: 0.35);
        fg = Colors.white;
        border = null;
        break;
      case AppButtonVariant.secondary:
        bg = isEnabled
            ? (_isHovered ? context.bgCardHover : context.bgCard)
            : context.bgCard.withValues(alpha: 0.5);
        fg = isEnabled ? context.textPrimary : context.textDisabled;
        border = Border.all(
          color: _isHovered ? context.borderStrong : context.borderSubtle,
        );
        break;
      case AppButtonVariant.ghost:
        bg = isEnabled && _isHovered ? context.bgCardHover : Colors.transparent;
        fg = isEnabled ? context.textPrimary : context.textDisabled;
        border = null;
        break;
      case AppButtonVariant.danger:
        bg = isEnabled
            ? (_isHovered ? context.errorSolid.withValues(alpha: 0.85) : context.errorSolid)
            : context.errorSolid.withValues(alpha: 0.35);
        fg = Colors.white;
        border = null;
        break;
    }

    final isSmall = widget.size == AppButtonSize.small;
    final padding = isSmall
        ? const EdgeInsets.symmetric(horizontal: AppTheme.space8, vertical: AppTheme.space4)
        : const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8);
    final textStyle = isSmall
        ? AppTheme.fontCaption.copyWith(color: fg, fontWeight: FontWeight.w500)
        : AppTheme.fontBody.copyWith(color: fg, fontWeight: FontWeight.w500);

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppTheme.borderRadiusSmall,
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.isLoading) ...[
                SizedBox(
                  width: isSmall ? 12 : 14,
                  height: isSmall ? 12 : 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(fg),
                  ),
                ),
                const SizedBox(width: AppTheme.space8),
              ] else if (widget.icon != null) ...[
                Icon(widget.icon, size: isSmall ? 13 : 15, color: fg),
                const SizedBox(width: AppTheme.space8),
              ],
              Text(widget.label, style: textStyle),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AppCard - 深色背景卡片
// =============================================================================

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppTheme.space16),
    this.onTap,
    this.backgroundColor,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: backgroundColor ?? context.bgCard,
      borderRadius: AppTheme.borderRadiusMedium,
      border: border ?? Border.all(color: context.borderSubtle, width: 1),
    );

    if (onTap == null) {
      return Container(
        decoration: decoration,
        padding: padding,
        child: child,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusMedium,
        hoverColor: context.bgCardHover,
        child: Ink(
          decoration: decoration,
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}

// =============================================================================
// AppListItem - 列表项 / 侧边栏项
// =============================================================================

class AppListItem extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool isSelected;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.isSelected = false,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: AppTheme.space8,
      vertical: AppTheme.space8,
    ),
  });

  @override
  State<AppListItem> createState() => _AppListItemState();
}

class _AppListItemState extends State<AppListItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;

    // 悬停背景与选中背景（确保浅色与深色模式下均具有舒适、清晰的对比度）
    final Color hoverColor = isDark
        ? Colors.white.withValues(alpha: 0.065)
        : Colors.black.withValues(alpha: 0.05);

    final Color selectedColor = isDark
        ? context.bgSelected
        : const Color(0xFFE2E8F0);

    Color bg;
    if (widget.isSelected) {
      bg = selectedColor;
    } else if (_isHovered) {
      bg = hoverColor;
    } else {
      bg = Colors.transparent;
    }

    final Color titleColor = widget.isSelected
        ? (isDark ? Colors.white : context.accentSolid)
        : (_isHovered ? context.textPrimary : context.textPrimary);

    final Color subtitleColor = widget.isSelected
        ? (isDark ? context.textSecondary : context.textSecondary)
        : (_isHovered ? context.textSecondary : context.textTertiary);

    final Color iconColor = widget.isSelected
        ? context.accentText
        : (_isHovered ? context.textPrimary : context.textSecondary);

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          // 即时切换无延迟，消除快速划过时的残影频闪
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppTheme.borderRadiusSmall,
            border: widget.isSelected
                ? Border.all(
                    color: context.accentSolid.withValues(alpha: isDark ? 0.35 : 0.25),
                    width: 1,
                  )
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Stack(
            children: [
              // 选中项左侧 Accent 指示条 (macOS 原生侧栏风格)
              if (widget.isSelected)
                Positioned(
                  left: 0,
                  top: 2,
                  bottom: 2,
                  child: Container(
                    width: 3,
                    decoration: BoxDecoration(
                      color: context.accentSolid,
                      borderRadius: BorderRadius.circular(1.5),
                    ),
                  ),
                ),
              Padding(
                // 当处于选中态有左指示条时，微调内容左边距避开指示条
                padding: EdgeInsets.only(left: widget.isSelected ? 4.0 : 0.0),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      IconTheme(
                        data: IconThemeData(
                          color: iconColor,
                          size: 16,
                        ),
                        child: widget.leading!,
                      ),
                      const SizedBox(width: AppTheme.space8),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: AppTheme.fontBody.copyWith(
                              color: titleColor,
                              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: AppTheme.space2),
                            Text(
                              widget.subtitle!,
                              style: AppTheme.fontCaption.copyWith(color: subtitleColor),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: AppTheme.space8),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// AppBanner - 提示条 (Info / Success / Warning / Error)
// =============================================================================

enum AppBannerType { info, success, warning, error }

class AppBanner extends StatelessWidget {
  final String message;
  final AppBannerType type;
  final Widget? action;
  final VoidCallback? onClose;

  const AppBanner({
    super.key,
    required this.message,
    this.type = AppBannerType.info,
    this.action,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color border;
    Color iconColor;
    IconData iconData;

    switch (type) {
      case AppBannerType.info:
        // 弱强调底：半透明派生而非实底。实底配深色正文对比度仅 2.05。
        bg = context.infoText.withValues(alpha: 0x1F / 255);
        border = context.infoText.withValues(alpha: 0x1F / 255);
        iconColor = context.infoText;
        iconData = Icons.info_outline;
        break;
      case AppBannerType.success:
        bg = context.successText.withValues(alpha: 0x1F / 255);
        border = context.successText.withValues(alpha: 0x1F / 255);
        iconColor = context.successText;
        iconData = Icons.check_circle_outline;
        break;
      case AppBannerType.warning:
        bg = context.warningText.withValues(alpha: 0x1F / 255);
        border = context.warningText.withValues(alpha: 0x1F / 255);
        iconColor = context.warningText;
        iconData = Icons.warning_amber_outlined;
        break;
      case AppBannerType.error:
        bg = context.errorText.withValues(alpha: 0x1F / 255);
        border = context.errorText.withValues(alpha: 0x1F / 255);
        iconColor = context.errorText;
        iconData = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space12,
        vertical: AppTheme.space8,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        children: [
          Icon(iconData, size: 16, color: iconColor),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              message,
              style: AppTheme.fontBody.copyWith(
                color: context.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppTheme.space8),
            action!,
          ],
          if (onClose != null) ...[
            const SizedBox(width: AppTheme.space4),
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: context.textTertiary,
              splashRadius: 12,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// AppBadge - 状态标签
// =============================================================================

// =============================================================================
// AppBadge - 徽标
//
// 前景自动推导：调用方只给底色，字色由本组件按底色语义决定。
//
// 为什么不让调用方同时传两个颜色：浅色主题下 accentSolid / successSolid /
// errorSolid 等实底都是深档，而默认前景是 textSecondary（深灰）——深底深字
// 就成了一个看不见字的色块。这类错配曾出现在 3 个调用点上（资讯 NEW 标签、
// AI 配置页「已连通/连通异常」），其中两处不是用户报告的，是同一种写法在
// 别处复发。逐个修调用点治的是今天，治不了下一次；因此把「能配错」从 API
// 表面拿掉——传实底就不必再想前景。
//
// 例外保留：textColor 显式传入时以调用方为准（用于在半透明弱强调底上配
// 对应的深色字，如 settings_dialog 的「默认」徽标）。
// =============================================================================
class AppBadge extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;

  const AppBadge({
    super.key,
    required this.label,
    this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color ?? context.bgCardHover;
    final fg = textColor ?? _foregroundFor(context, bg);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.borderSubtle, width: 1),
      ),
      child: Text(
        label,
        style: AppTheme.fontCaption.copyWith(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 按底色语义选前景。只认主题实底色 token，其余（半透明底、bgCardHover、
  /// bgInput 等中性面）沿用默认深灰字——那 19 个中性调用点外观零变化。
  Color _foregroundFor(BuildContext context, Color bg) {
    if (bg == context.accentSolid) return context.onAccentSolid;
    if (bg == context.successSolid ||
        bg == context.warningSolid ||
        bg == context.errorSolid ||
        bg == context.infoSolid) {
      // 语义实底在深浅两模式同取深档（白字 4.92~8.31），白色即其前景，
      // 与 AppButton.danger 的 fg = Colors.white 一致。
      return Colors.white;
    }
    return context.textSecondary;
  }
}

// =============================================================================
// AppSectionHeader - 分区标题
// =============================================================================

class AppSectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.space8,
        vertical: AppTheme.space4,
      ),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: AppTheme.fontCaption.copyWith(
              color: context.textTertiary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

// =============================================================================
// AppSwitch - 主题感知的开关
//
// 为什么不用裸 Switch：Material 的 Switch 在 activeTrackColor 非空时以 m3 默认
// 画法涂轨道，圆饼只靠 track 与 thumb 的明度差显形。调用方写
// activeColor: accentText, activeTrackColor: accentSolid 时，浅色主题下两者同为
// #4F46E5——圆饼与轨道同色，开关看上去是一枚纯色胶囊。深色模式凑巧能看（其
// thumb 由 MaterialStateProperty 推导出较亮值），所以这个 bug 只在浅色暴露。
//
// 本组件把 thumb / track 的配对收在一处：调用方只说「开启主色」，其余按主题
// 推导，使「轨道与圆饼同色」在 API 表面无法表达。
// =============================================================================
class AppSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  /// 开启态主色。默认取强调色实底；调用方传语义色（如 warningSolid）时，
  /// 圆饼仍由本组件按对比度推导，不会与轨道同色。
  final Color? activeColor;

  const AppSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = activeColor ?? context.accentSolid;

    // 圆饼取与轨道反相的一侧：深色主题用近白（维持该模式下既有的可见外观），
    // 浅色主题用近黑——两者都与深档实底形成足够明度差。
    final thumb = isDark ? Colors.white : const Color(0xFF0F172A);

    return Switch(
      value: value,
      onChanged: onChanged,
      // Flutter 3.35 起 activeColor 更名为 activeThumbColor。
      activeThumbColor: thumb,
      activeTrackColor: track,
      inactiveThumbColor: isDark ? context.textSecondary : context.textTertiary,
      inactiveTrackColor: context.bgCardHover,
      trackOutlineColor: WidgetStatePropertyAll(context.borderSubtle),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
