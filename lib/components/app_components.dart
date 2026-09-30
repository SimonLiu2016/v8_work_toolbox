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
    final fg = textColor ?? context.textSecondary;

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
