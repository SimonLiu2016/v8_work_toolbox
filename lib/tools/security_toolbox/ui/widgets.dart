/// UI 层共享小组件：状态徽章、日志视图、统计卡片等。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../services/tool_status_checker.dart';

/// 工具状态徽章。
class ToolStatusBadge extends StatelessWidget {
  final ToolStatus status;
  final String? version;

  const ToolStatusBadge({super.key, required this.status, this.version});

  @override
  Widget build(BuildContext context) {
    final (Color color, String text) = switch (status) {
      ToolStatus.ready => (context.successSolid, status.label),
      ToolStatus.outdated => (context.warningSolid, status.label),
      ToolStatus.missing => (context.errorSolid, status.label),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        version == null || version!.isEmpty ? text : '$text · $version',
        style: AppTheme.fontCaption.copyWith(color: color),
      ),
    );
  }
}

/// 严重等级徽章。
class SeverityBadge extends StatelessWidget {
  final Severity severity;
  final double? cvss;

  const SeverityBadge({super.key, required this.severity, this.cvss});

  static Color colorFor(BuildContext context, Severity s) => switch (s) {
    Severity.critical => context.errorSolid,
    Severity.high => const Color(0xFFF97316),
    Severity.medium => context.warningSolid,
    Severity.low => context.infoSolid,
    Severity.info => context.textTertiary,
  };

  @override
  Widget build(BuildContext context) {
    final color = colorFor(context, severity);
    final label = cvss == null
        ? severity.label
        : '${severity.label} ${cvss!.toStringAsFixed(1)}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: color.withAlpha(120)),
      ),
      child: Text(
        label,
        style: AppTheme.fontCaption.copyWith(color: color),
      ),
    );
  }
}

/// KEV 标记（情报列表用）。
class KevBadge extends StatelessWidget {
  const KevBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.errorSolid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Text(
        'KEV',
        style: AppTheme.fontCaption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// PoC 可用标记。
class PocBadge extends StatelessWidget {
  const PocBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final color = context.successSolid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(38),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Text(
        'PoC',
        style: AppTheme.fontCaption.copyWith(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// 一张统计卡片（数字 + 标题）。
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? context.accentText;
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: accent),
                const SizedBox(width: 6),
              ],
              Text(label, style: context.fontCaption),
            ],
          ),
          const SizedBox(height: AppTheme.space6),
          Text(
            value,
            style: AppTheme.fontTitle.copyWith(color: accent),
          ),
        ],
      ),
    );
  }
}

/// 等宽日志滚动视图（支持自由划词选中与一键复制全部）。
class LogConsole extends StatefulWidget {
  final List<String> lines;
  final double height;
  final String title;
  final VoidCallback? onClear;

  const LogConsole({
    super.key,
    required this.lines,
    this.height = 180,
    this.title = '控制台日志',
    this.onClear,
  });

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class _LogConsoleState extends State<LogConsole> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollToBottom();
  }

  @override
  void didUpdateWidget(covariant LogConsole oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lines.length != oldWidget.lines.length) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyAll(BuildContext context) {
    if (widget.lines.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制全部日志（共 ${widget.lines.length} 行）到剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部工具栏
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.space8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusSmall),
              ),
              border: Border(bottom: BorderSide(color: context.borderSubtle)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 14,
                  color: context.textTertiary,
                ),
                const SizedBox(width: AppTheme.space8),
                Text(
                  '${widget.title} (${widget.lines.length})',
                  style: context.fontCaption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (widget.onClear != null && widget.lines.isNotEmpty) ...[
                  InkWell(
                    borderRadius: AppTheme.borderRadiusSmall,
                    onTap: widget.onClear,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.delete_sweep_outlined,
                            size: 13,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '清空',
                            style: context.fontCaption.copyWith(
                              color: context.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                ],
                if (widget.lines.isNotEmpty)
                  InkWell(
                    borderRadius: AppTheme.borderRadiusSmall,
                    onTap: () => _copyAll(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: context.accentSolid,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '复制全部',
                            style: context.fontCaption.copyWith(
                              color: context.accentSolid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 文本区域：包裹 SelectionArea，支持划词选择与快捷键复制
          Expanded(
            child: widget.lines.isEmpty
                ? Center(
                    child: Text('暂无日志', style: context.fontCaption),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(AppTheme.space8),
                      itemCount: widget.lines.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(
                          widget.lines[index],
                          style: AppTheme.fontCaption.copyWith(
                            fontFamily: 'Menlo',
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 区块标题（带副标题）。
class SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget>? trailing;

  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.space12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.fontTitle),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!, style: context.fontCaption),
                  ),
              ],
            ),
          ),
          if (trailing != null) ...trailing!,
        ],
      ),
    );
  }
}

/// 空状态占位。
class EmptyState extends StatelessWidget {
  final String message;
  final IconData? icon;
  final Widget? action;

  const EmptyState({super.key, required this.message, this.icon, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.inbox_outlined, size: 40, color: context.textTertiary),
          const SizedBox(height: AppTheme.space12),
          Text(message, style: context.fontBodySecondary),
          if (action != null) ...[
            const SizedBox(height: AppTheme.space12),
            action!,
          ],
        ],
      ),
    );
  }
}

/// 一个小按钮（Tab 内的操作统一风格）。
class SmallActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  const SmallActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14),
          const SizedBox(width: 6),
        ],
        Text(label, style: AppTheme.fontCaption.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
    if (primary) {
      return FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: context.textSecondary,
        side: BorderSide(color: context.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: child,
    );
  }
}

/// 资产分页栏小组件。
class AssetPaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalCount;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  const AssetPaginationBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.totalCount,
    this.pageSize = 50,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) return const SizedBox.shrink();

    final start = (currentPage - 1) * pageSize + 1;
    final end = math.min(currentPage * pageSize, totalCount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: 6),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '显示 $start-$end / 共 $totalCount 条 · 第 $currentPage/$totalPages 页',
            style: context.fontCaption,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.first_page, size: 18),
                tooltip: '首页',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: currentPage > 1 ? () => onPageChanged(1) : null,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                tooltip: '上一页',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: context.accentSubtle,
                  borderRadius: AppTheme.borderRadiusSmall,
                ),
                child: Text(
                  '$currentPage / $totalPages',
                  style: AppTheme.fontCaption.copyWith(
                    color: context.accentText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                tooltip: '下一页',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.last_page, size: 18),
                tooltip: '尾页',
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                onPressed: currentPage < totalPages ? () => onPageChanged(totalPages) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

