import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/ai_logger.dart';
import '../theme/app_theme.dart';

/// AI 实时调用观察器与日志模态对话框
class AiLogDialog extends StatefulWidget {
  const AiLogDialog({super.key});

  /// 唤起日志观察器模态弹窗
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => const AiLogDialog(),
    );
  }

  @override
  State<AiLogDialog> createState() => _AiLogDialogState();
}

class _AiLogDialogState extends State<AiLogDialog> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _expandedIndices = {};
  bool _autoScroll = true;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _copyAllLogs(BuildContext context) {
    final text = AiLogger.exportAsString();
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制全部 AI 日志到剪贴板'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _copySingleLog(BuildContext context, AiLogEntry entry) {
    final buffer = StringBuffer()
      ..writeln('[${entry.formattedTime}] ${entry.type.name.toUpperCase()} - Provider: ${entry.providerName}')
      ..writeln('Endpoint: ${entry.endpoint ?? 'N/A'}')
      ..writeln('Message: ${entry.message}');
    if (entry.fullContent != null) {
      buffer.writeln('Full Content: ${entry.fullContent}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制该条日志'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Container(
        width: 760,
        height: 560,
        decoration: BoxDecoration(
          color: AppTheme.bgWindow,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.borderStrong),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            _buildHeader(context),
            const Divider(height: 1, color: AppTheme.borderSubtle),
            Expanded(child: _buildLogList()),
            const Divider(height: 1, color: AppTheme.borderSubtle),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: AppTheme.space12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppTheme.space6),
            decoration: BoxDecoration(
              color: AppTheme.accentSubtle,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: const Icon(Icons.terminal_rounded, size: 20, color: AppTheme.accentLight),
          ),
          const SizedBox(width: AppTheme.space12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AI 调用实时观察器', style: AppTheme.fontTitle),
              const SizedBox(height: 2),
              ValueListenableBuilder<List<AiLogEntry>>(
                valueListenable: AiLogger.notifier,
                builder: (context, entries, _) {
                  return Text(
                    '内存缓冲实时捕获 · 最近 ${entries.length}/${AiLogger.maxEntries} 条记录',
                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                  );
                },
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            tooltip: '复制全部日志',
            icon: const Icon(Icons.copy_all_rounded, size: 18, color: AppTheme.textSecondary),
            onPressed: () => _copyAllLogs(context),
          ),
          IconButton(
            tooltip: '清空内存日志',
            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.textSecondary),
            onPressed: () {
              setState(() {
                _expandedIndices.clear();
                AiLogger.clear();
              });
            },
          ),
          const SizedBox(width: AppTheme.space4),
          IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList() {
    return ValueListenableBuilder<List<AiLogEntry>>(
      valueListenable: AiLogger.notifier,
      builder: (context, entries, _) {
        if (entries.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.receipt_long_outlined, size: 48, color: AppTheme.textTertiary),
                const SizedBox(height: AppTheme.space12),
                Text('暂无 AI 调用记录', style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary)),
                const SizedBox(height: AppTheme.space4),
                Text(
                  '当发起模型连接测试或批量诊断时，请求和响应报文将在此实时呈现。',
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                ),
              ],
            ),
          );
        }

        if (_autoScroll && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
            }
          });
        }

        return ListView.separated(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppTheme.space12),
          itemCount: entries.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppTheme.space8),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final isExpanded = _expandedIndices.contains(index);
            return _buildEntryCard(entry, index, isExpanded);
          },
        );
      },
    );
  }

  Widget _buildEntryCard(AiLogEntry entry, int index, bool isExpanded) {
    Color badgeColor;
    Color badgeBg;
    IconData badgeIcon;
    String badgeText;

    switch (entry.type) {
      case AiLogType.request:
        badgeColor = AppTheme.info;
        badgeBg = AppTheme.infoSubtle;
        badgeIcon = Icons.arrow_upward_rounded;
        badgeText = 'REQUEST';
        break;
      case AiLogType.response:
        final isOk = (entry.statusCode ?? 200) < 400;
        badgeColor = isOk ? AppTheme.success : AppTheme.error;
        badgeBg = isOk ? AppTheme.successSubtle : AppTheme.errorSubtle;
        badgeIcon = Icons.arrow_downward_rounded;
        badgeText = 'RESP ${entry.statusCode ?? 200}';
        break;
      case AiLogType.warning:
        badgeColor = AppTheme.warning;
        badgeBg = AppTheme.warningSubtle;
        badgeIcon = Icons.warning_amber_rounded;
        badgeText = 'WARNING';
        break;
      case AiLogType.error:
        badgeColor = AppTheme.error;
        badgeBg = AppTheme.errorSubtle;
        badgeIcon = Icons.error_outline_rounded;
        badgeText = 'ERROR';
        break;
    }

    final hasMore = entry.fullContent != null && entry.fullContent!.length > entry.message.length;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      padding: const EdgeInsets.all(AppTheme.space10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.formattedTime,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badgeIcon, size: 11, color: badgeColor),
                    const SizedBox(width: 3),
                    Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: badgeColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.space8),
              Text(
                entry.providerName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              if (entry.protocol != null) ...[
                const SizedBox(width: 4),
                Text(
                  '· ${entry.protocol}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ],
              if (entry.model != null) ...[
                const SizedBox(width: 4),
                Text(
                  '(${entry.model})',
                  style: const TextStyle(fontSize: 11, color: AppTheme.accentLight),
                ),
              ],
              if (entry.durationMs != null) ...[
                const Spacer(),
                Text(
                  '${entry.durationMs}ms',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ] else
                const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 14,
                tooltip: '复制此条',
                icon: const Icon(Icons.copy_rounded, color: AppTheme.textTertiary),
                onPressed: () => _copySingleLog(context, entry),
              ),
            ],
          ),
          if (entry.endpoint != null) ...[
            const SizedBox(height: 4),
            Text(
              entry.endpoint!,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: AppTheme.textTertiary,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            isExpanded && entry.fullContent != null ? entry.fullContent! : entry.message,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textSecondary,
            ),
          ),
          if (hasMore) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedIndices.remove(index);
                  } else {
                    _expandedIndices.add(index);
                  }
                });
              },
              child: Text(
                isExpanded ? '收起完整内容 ▲' : '展开查看全部 (${entry.fullContent!.length} 字符) ▼',
                style: const TextStyle(fontSize: 11, color: AppTheme.accentLight),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space16, vertical: AppTheme.space8),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _autoScroll = !_autoScroll;
              });
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _autoScroll ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                  size: 16,
                  color: _autoScroll ? AppTheme.accentLight : AppTheme.textTertiary,
                ),
                const SizedBox(width: 4),
                Text(
                  '自动滚动到底部',
                  style: AppTheme.fontCaption.copyWith(
                    color: _autoScroll ? AppTheme.textPrimary : AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '仅在本次运行会话中保留，退出后自动清空',
            style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
