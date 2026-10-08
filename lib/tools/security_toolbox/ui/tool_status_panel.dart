/// 工具状态面板：底部摘要 + 可展开详情。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../services/brew_install_service.dart';
import '../services/security_session_controller.dart';
import '../services/security_tool_registry.dart';
import '../services/tool_status_checker.dart';
import 'widgets.dart';

class ToolStatusPanel extends StatefulWidget {
  final SecuritySessionController controller;

  const ToolStatusPanel({super.key, required this.controller});

  @override
  State<ToolStatusPanel> createState() => _ToolStatusPanelState();
}

class _ToolStatusPanelState extends State<ToolStatusPanel> {
  String? _installingToolId;
  bool _installingAll = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final board = controller.board;
        final isBusy = _installingAll || _installingToolId != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: '工具依赖',
              subtitle: board.brewAvailable
                  ? 'Homebrew 已就绪 · 检测于 ${_time(board.checkedAt)}'
                  : '未检测到 Homebrew（brew.sh）',
              trailing: [
                SmallActionButton(
                  label: controller.probingTools ? '检测中…' : '重新检测',
                  icon: Icons.refresh,
                  onPressed: (controller.probingTools || isBusy)
                      ? null
                      : controller.refreshTools,
                ),
                const SizedBox(width: AppTheme.space8),
                if (board.missingCount > 0 || board.outdatedCount > 0)
                  SmallActionButton(
                    label: _installingAll ? '安装全部中…' : '一键安装',
                    icon: Icons.download_rounded,
                    primary: true,
                    onPressed: (board.brewAvailable && !isBusy)
                        ? () => _installAll(controller)
                        : null,
                  ),
              ],
            ),
            if (!board.brewAvailable)
              Container(
                margin: const EdgeInsets.only(bottom: AppTheme.space12),
                padding: const EdgeInsets.all(AppTheme.space12),
                decoration: BoxDecoration(
                  color: context.warningSolid.withAlpha(30),
                  borderRadius: AppTheme.borderRadiusSmall,
                  border: Border.all(color: context.warningSolid.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 16, color: context.warningSolid),
                    const SizedBox(width: AppTheme.space8),
                    Expanded(
                      child: Text(
                        '未检测到 Homebrew。请先安装 Homebrew 后再安装安全工具。',
                        style: context.fontCaption,
                      ),
                    ),
                  ],
                ),
              ),
            _buildSummaryRow(context, board),
            const SizedBox(height: AppTheme.space12),
            _buildTemplateState(context, controller),
            const SizedBox(height: AppTheme.space12),
            Expanded(
              child: ListView(
                children: [
                  for (final purpose in ToolPurpose.values)
                    if (toolsForPurpose(
                      purpose,
                    ).any((t) => board.probes.containsKey(t.id)))
                      _buildPurposeGroup(context, controller, purpose),
                  const SizedBox(height: AppTheme.space12),
                  LogConsole(
                    lines: controller.recentLogs(),
                    onClear: controller.clearLogs,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummaryRow(BuildContext context, ToolStatusBoard board) {
    return Row(
      children: [
        StatCard(
          label: '已就绪',
          value: '${board.readyCount}',
          color: context.successSolid,
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(width: AppTheme.space8),
        StatCard(
          label: '需更新',
          value: '${board.outdatedCount}',
          color: context.warningSolid,
          icon: Icons.upgrade,
        ),
        const SizedBox(width: AppTheme.space8),
        StatCard(
          label: '未安装',
          value: '${board.missingCount}',
          color: context.errorSolid,
          icon: Icons.download_outlined,
        ),
      ],
    );
  }

  Widget _buildTemplateState(
    BuildContext context,
    SecuritySessionController controller,
  ) {
    final templates = controller.templates;
    return Container(
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(Icons.article_outlined, size: 16, color: context.accentText),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Text(
              templates.installed
                  ? 'nuclei 模板库：${templates.templateCount} 个模板'
                  : 'nuclei 模板库未下载（约 200MB）',
              style: context.fontBody,
            ),
          ),
          if (templates.updating)
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            SmallActionButton(
              label: templates.installed ? '更新模板' : '下载模板',
              icon: Icons.cloud_download_outlined,
              onPressed: () => BrewInstallService.instance.updateTemplates(onLog: controller.log),
            ),
        ],
      ),
    );
  }

  Widget _buildPurposeGroup(
    BuildContext context,
    SecuritySessionController controller,
    ToolPurpose purpose,
  ) {
    final tools = toolsForPurpose(purpose);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
          child: Text(purpose.label, style: context.fontBodySecondary),
        ),
        for (final tool in tools) _buildToolRow(context, controller, tool),
      ],
    );
  }

  Widget _buildToolRow(
    BuildContext context,
    SecuritySessionController controller,
    SecurityTool tool,
  ) {
    final probe = controller.board.probes[tool.id];
    final status = probe?.status ?? ToolStatus.missing;
    final version = probe?.version;
    final isToolInstalling = _installingToolId == tool.id;
    final isBusy = _installingAll || _installingToolId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.space8),
      padding: const EdgeInsets.all(AppTheme.space12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.displayName, style: context.fontBody),
                const SizedBox(height: 2),
                Text(
                  () {
                    final channelText = switch (tool.installMethod) {
                      InstallMethod.manual => '手动安装',
                      InstallMethod.pipx => 'pipx',
                      InstallMethod.brew => 'brew: ${tool.brewName}',
                    };
                    final hint = toolHint(tool.id);
                    return hint.isNotEmpty
                        ? '$hint · $channelText'
                        : channelText;
                  }(),
                  style: context.fontCaption,
                ),
              ],
            ),
          ),
          ToolStatusBadge(status: status, version: version),
          const SizedBox(width: AppTheme.space8),
          if (isToolInstalling)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.accentSubtle,
                borderRadius: AppTheme.borderRadiusSmall,
                border: Border.all(color: context.accentSolid.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.accentSolid,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    status == ToolStatus.outdated ? '更新中…' : '安装中…',
                    style: context.fontCaption.copyWith(color: context.accentText),
                  ),
                ],
              ),
            )
          else if (status == ToolStatus.missing)
            if (tool.installMethod == InstallMethod.manual)
              SmallActionButton(
                label: '安装指引',
                icon: Icons.help_outline_rounded,
                onPressed: () => _showManualGuide(context, controller, tool),
              )
            else
              SmallActionButton(
                label: '安装',
                icon: Icons.download_rounded,
                onPressed: (controller.board.brewAvailable && !isBusy)
                    ? () => _install(controller, tool)
                    : null,
              )
          else if (status == ToolStatus.outdated)
            if (tool.installMethod == InstallMethod.manual)
              SmallActionButton(
                label: '更新指引',
                icon: Icons.help_outline_rounded,
                onPressed: () => _showManualGuide(context, controller, tool),
              )
            else
              SmallActionButton(
                label: '更新',
                icon: Icons.upgrade,
                onPressed: (controller.board.brewAvailable && !isBusy)
                    ? () => _install(controller, tool, upgrade: true)
                    : null,
              ),
        ],
      ),
    );
  }

  void _showManualGuide(
    BuildContext context,
    SecuritySessionController controller,
    SecurityTool tool,
  ) {
    controller.log('查看 ${tool.displayName} 安装指引：${tool.installNote ?? ''}');
    if (tool.manualInstallUrl != null) {
      controller.log('官方指引页面: ${tool.manualInstallUrl}');
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${tool.displayName} 安装指引', style: context.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tool.installNote ?? '该工具在当前平台需通过官方安装程序进行安装。',
              style: context.fontBody,
            ),
            if (tool.manualInstallUrl != null) ...[
              const SizedBox(height: AppTheme.space12),
              Text(
                '官方安装文档：',
                style: context.fontCaption,
              ),
              const SizedBox(height: 4),
              SelectableText(
                tool.manualInstallUrl!,
                style: context.fontCaption.copyWith(color: context.accentSolid),
              ),
            ],
          ],
        ),
        actions: [
          if (tool.manualInstallUrl != null)
            TextButton(
              onPressed: () {
                Process.run('open', [tool.manualInstallUrl!]);
                Navigator.of(ctx).pop();
              },
              child: const Text('打开官方下载页'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Future<void> _install(
    SecuritySessionController controller,
    SecurityTool tool, {
    bool upgrade = false,
  }) async {
    setState(() => _installingToolId = tool.id);
    try {
      final channelDesc = switch (tool.installMethod) {
        InstallMethod.pipx => 'pipx ${tool.executable}',
        InstallMethod.manual => '手动安装',
        InstallMethod.brew => 'brew ${tool.brewName}',
      };
      controller.log(
        '═══ 开始${upgrade ? '更新' : '安装'} ${tool.displayName}（$channelDesc）═══',
      );
      if (tool.installNote != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${tool.displayName}: ${tool.installNote}'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      final ok = await BrewInstallService.instance.install(
        tool,
        upgrade: upgrade,
        onLog: controller.log,
      );
      controller.log(
        ok ? '✓ ${tool.displayName} 安装完成' : '✗ ${tool.displayName} 安装未成功，请查看日志排查',
      );
      await controller.refreshTools();
    } finally {
      if (mounted) setState(() => _installingToolId = null);
    }
  }

  Future<void> _installAll(SecuritySessionController controller) async {
    setState(() => _installingAll = true);
    try {
      await BrewInstallService.instance.installAllMissing(
        controller.board.probes,
        onLog: controller.log,
        onToolFinished: (tool, success, current, total) async {
          await controller.refreshTools();
        },
      );
      await controller.refreshTools();
    } finally {
      if (mounted) setState(() => _installingAll = false);
    }
  }

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
