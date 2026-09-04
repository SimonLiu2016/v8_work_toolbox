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
        color: enabled ? AppTheme.textPrimary : AppTheme.textDisabled,
      ),
      cursorColor: AppTheme.accent,
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
            color: AppTheme.textSecondary,
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
            ? (_isHovered ? AppTheme.accentLight : AppTheme.accent)
            : AppTheme.accent.withValues(alpha: 0.35);
        fg = Colors.white;
        border = null;
        break;
      case AppButtonVariant.secondary:
        bg = isEnabled
            ? (_isHovered ? AppTheme.bgCardHover : AppTheme.bgCard)
            : AppTheme.bgCard.withValues(alpha: 0.5);
        fg = isEnabled ? AppTheme.textPrimary : AppTheme.textDisabled;
        border = Border.all(
          color: _isHovered ? AppTheme.borderStrong : AppTheme.borderSubtle,
        );
        break;
      case AppButtonVariant.ghost:
        bg = isEnabled && _isHovered ? AppTheme.bgCardHover : Colors.transparent;
        fg = isEnabled ? AppTheme.textPrimary : AppTheme.textDisabled;
        border = null;
        break;
      case AppButtonVariant.danger:
        bg = isEnabled
            ? (_isHovered ? AppTheme.error.withValues(alpha: 0.85) : AppTheme.error)
            : AppTheme.error.withValues(alpha: 0.35);
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
      color: backgroundColor ?? AppTheme.bgCard,
      borderRadius: AppTheme.borderRadiusMedium,
      border: border ?? Border.all(color: AppTheme.borderSubtle, width: 1),
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
        hoverColor: AppTheme.bgCardHover,
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
    Color bg;
    if (widget.isSelected) {
      bg = AppTheme.bgSelected;
    } else if (_isHovered) {
      bg = AppTheme.bgCardHover;
    } else {
      bg = Colors.transparent;
    }

    return MouseRegion(
      cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: AppTheme.borderRadiusSmall,
            border: widget.isSelected
                ? Border.all(color: AppTheme.accent.withValues(alpha: 0.35), width: 1)
                : Border.all(color: Colors.transparent, width: 1),
          ),
          child: Row(
            children: [
              if (widget.leading != null) ...[
                widget.leading!,
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
                        color: widget.isSelected ? Colors.white : AppTheme.textPrimary,
                        fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: AppTheme.space2),
                      Text(
                        widget.subtitle!,
                        style: AppTheme.fontCaption.copyWith(
                          color: AppTheme.textTertiary,
                        ),
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
        bg = AppTheme.infoSubtle;
        border = AppTheme.info.withValues(alpha: 0.3);
        iconColor = AppTheme.info;
        iconData = Icons.info_outline;
        break;
      case AppBannerType.success:
        bg = AppTheme.successSubtle;
        border = AppTheme.success.withValues(alpha: 0.3);
        iconColor = AppTheme.success;
        iconData = Icons.check_circle_outline;
        break;
      case AppBannerType.warning:
        bg = AppTheme.warningSubtle;
        border = AppTheme.warning.withValues(alpha: 0.3);
        iconColor = AppTheme.warning;
        iconData = Icons.warning_amber_outlined;
        break;
      case AppBannerType.error:
        bg = AppTheme.errorSubtle;
        border = AppTheme.error.withValues(alpha: 0.3);
        iconColor = AppTheme.error;
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
                color: AppTheme.textPrimary,
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
              color: AppTheme.textTertiary,
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
    final bg = color ?? AppTheme.bgCardHover;
    final fg = textColor ?? AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.borderSubtle, width: 1),
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
              color: AppTheme.textTertiary,
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
