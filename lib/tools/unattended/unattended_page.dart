import 'dart:async';
import 'package:flutter/material.dart';

import '../../services/allowlist_consolidation_service.dart';
import '../../services/unattended_service.dart';
import '../../theme/app_theme.dart';

class UnattendedPage extends StatefulWidget {
  const UnattendedPage({super.key});

  @override
  State<UnattendedPage> createState() => _UnattendedPageState();
}

class _UnattendedPageState extends State<UnattendedPage> {
  final UnattendedService _service = UnattendedService.instance;
  ClientHookStatus? _hookStatus;
  List<AuditRecord> _auditLogs = [];
  bool _isLoadingLogs = false;
  String _filterDecision = 'all'; // 'all', 'allow', 'deny'

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _initData();
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  Future<void> _initData() async {
    await _service.init();
    await _refreshHookStatus();
    await _refreshLogs();
  }

  Future<void> _refreshHookStatus() async {
    final status = await _service.checkHookInstallation();
    if (mounted) {
      setState(() {
        _hookStatus = status;
      });
    }
  }

  Future<void> _refreshLogs() async {
    setState(() => _isLoadingLogs = true);
    final logs = await _service.loadAuditLogs(limit: 100);
    if (mounted) {
      setState(() {
        _auditLogs = logs;
        _isLoadingLogs = false;
      });
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    final s = local.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final state = _service.state;
    final isActive = state.isEffectivelyActive;

    return Scaffold(
      backgroundColor: context.bgContent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPageHeader(isActive),
            const SizedBox(height: AppTheme.space20),
            _buildHeroStatusCard(state, isActive),
            const SizedBox(height: AppTheme.space20),
            LayoutBuilder(
              builder: (ctx, constraints) {
                if (constraints.maxWidth < 800) {
                  return Column(
                    children: [
                      _buildHookDiagnosticsCard(),
                      const SizedBox(height: AppTheme.space20),
                      _buildSafetyFloorCard(state),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _buildHookDiagnosticsCard()),
                    const SizedBox(width: AppTheme.space20),
                    Expanded(flex: 5, child: _buildSafetyFloorCard(state)),
                  ],
                );
              },
            ),
            const SizedBox(height: AppTheme.space20),
            _buildAllowlistCard(state),
            const SizedBox(height: AppTheme.space24),
            _buildAuditStreamSection(),
          ],
        ),
      ),
    );
  }

  /// 页面顶部标题栏
  Widget _buildPageHeader(bool isActive) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppTheme.space10),
              decoration: BoxDecoration(
                color: isActive ? context.successText.withValues(alpha: 0x1F / 255) : context.accentSubtle,
                borderRadius: AppTheme.borderRadiusMedium,
              ),
              child: Icon(
                isActive ? Icons.verified_user_rounded : Icons.shield_outlined,
                color: isActive ? context.successText : context.accentText,
                size: 28,
              ),
            ),
            SizedBox(width: AppTheme.space16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('无人值守助手', style: AppTheme.fontHeadline),
                SizedBox(height: AppTheme.space4),
                Text(
                  '离开电脑时自动审批 AI 工具授权，内置机械安全硬地板杜绝破坏',
                  style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
                ),
              ],
            ),
          ],
        ),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('刷新状态'),
              onPressed: () async {
                await _refreshHookStatus();
                await _refreshLogs();
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 核心 Hero 状态大卡片
  Widget _buildHeroStatusCard(UnattendedState state, bool isActive) {
    return Container(
      padding: EdgeInsets.all(AppTheme.space24),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusLarge,
        border: Border.all(
          color: isActive ? context.successText.withAlpha(80) : context.borderSubtle,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive ? context.successText : context.textTertiary,
                    ),
                  ),
                  SizedBox(width: AppTheme.space8),
                  Text(
                    isActive ? '无人值守运行中 (自动放行安全操作)' : '常规人工确认模式 (自动审批已关闭)',
                    style: AppTheme.fontTitle.copyWith(
                      color: isActive ? context.successText : context.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? context.errorSolid : context.successSolid,
                  padding: const EdgeInsets.symmetric(horizontal: AppTheme.space20, vertical: AppTheme.space12),
                  shape: RoundedRectangleBorder(borderRadius: AppTheme.borderRadiusMedium),
                ),
                icon: Icon(isActive ? Icons.power_settings_new_rounded : Icons.play_arrow_rounded, color: Colors.white),
                label: Text(
                  isActive ? '关闭并恢复人审' : '一键开启无人值守',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                onPressed: () {
                  if (isActive) {
                    _service.disable();
                  } else {
                    _service.enable(ttlMinutes: state.ttlMinutes > 0 ? state.ttlMinutes : 120);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space24,
            runSpacing: AppTheme.space16,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isActive ? _formatDuration(state.remainingTime) : '--:--:--',
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: context.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                  SizedBox(height: AppTheme.space4),
                  Text(
                    isActive
                        ? '到期时间：${_formatTime(state.expiresAt!)} (超时自动关闭防遗忘)'
                        : '点击预设时长可立即开启或调节有效时限',
                    style: AppTheme.fontCaption.copyWith(color: context.textTertiary),
                  ),
                ],
              ),
              Wrap(
                spacing: AppTheme.space8,
                runSpacing: AppTheme.space8,
                children: [
                  _buildDurationChip(30, '30分钟', isActive, state.ttlMinutes),
                  _buildDurationChip(60, '1小时', isActive, state.ttlMinutes),
                  _buildDurationChip(120, '2小时', isActive, state.ttlMinutes),
                  _buildDurationChip(240, '4小时', isActive, state.ttlMinutes),
                  _buildDurationChip(480, '8小时过夜', isActive, state.ttlMinutes),
                  _buildCustomDurationButton(isActive),
                ],
              ),
            ],
          ),
          SizedBox(height: AppTheme.space16),
          Divider(color: context.borderSubtle, height: 1),
          SizedBox(height: AppTheme.space12),
          // 防休眠与屏幕常亮控制行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _service.isCaffeinateActive ? Icons.coffee_rounded : Icons.coffee_outlined,
                    size: 18,
                    color: _service.isCaffeinateActive ? context.accentText : context.textTertiary,
                  ),
                  SizedBox(width: AppTheme.space8),
                  Text(
                    isActive
                        ? (_service.isCaffeinateActive
                            ? '系统防休眠保护生效中 (caffeinate)'
                            : '防休眠保护待命中')
                        : '防休眠与防息屏策略',
                    style: AppTheme.fontCaption.copyWith(
                      color: _service.isCaffeinateActive ? context.textPrimary : context.textSecondary,
                      fontWeight: _service.isCaffeinateActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (isActive && _service.isCaffeinateActive) ...[
                    const SizedBox(width: AppTheme.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.accentSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        state.keepDisplayAwake ? '系统+屏幕常亮' : '仅保系统不休眠',
                        style: TextStyle(fontSize: 10, color: context.accentText, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Text(
                    '保持屏幕常亮 (防息屏)',
                    style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Switch(
                    value: state.keepDisplayAwake,
                    activeThumbColor: context.accentSolid,
                    onChanged: (val) {
                      _service.setKeepDisplayAwake(val);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

  }

  Widget _buildDurationChip(int minutes, String label, bool isActive, int currentTtl) {
    final isSelected = isActive && currentTtl == minutes;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        _service.enable(ttlMinutes: minutes);
      },
      selectedColor: context.accentSolid,
      backgroundColor: context.bgInput,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? context.onAccentSolid : context.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildCustomDurationButton(bool isActive) {
    return ActionChip(
      avatar: Icon(Icons.tune_rounded, size: 14, color: context.textSecondary),
      label: Text('自定义', style: TextStyle(fontSize: 12, color: context.textSecondary)),
      backgroundColor: context.bgInput,
      onPressed: () => _showCustomDurationDialog(),
    );
  }

  void _showCustomDurationDialog() {
    final controller = TextEditingController(text: '90');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('自定义有效时长'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('请输入无人值守持续时长（分钟）：', style: AppTheme.fontBody),
            const SizedBox(height: AppTheme.space12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                suffixText: '分钟',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val != null && val > 0) {
                Navigator.of(ctx).pop();
                _service.enable(ttlMinutes: val);
              }
            },
            child: const Text('开启'),
          ),
        ],
      ),
    );
  }

  /// 全局客户端 Hook 诊断卡片
  Widget _buildHookDiagnosticsCard() {
    final status = _hookStatus;
    final claudeOk = status?.claudeInstalled == true;
    final agyOk = status?.agyInstalled == true;
    final geminiOk = status?.geminiInstalled == true;

    return Container(
      padding: EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('全局客户端 Hook 接入', style: AppTheme.fontTitle),
              IconButton(
                icon: const Icon(Icons.sync_rounded, size: 18),
                onPressed: _refreshHookStatus,
                tooltip: '重新检测',
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space12),
          _buildClientStatusRow('Claude Code (PreToolUse)', claudeOk, status?.claudeSettingsPath ?? '~/.claude/settings.json'),
          const SizedBox(height: AppTheme.space8),
          _buildClientStatusRow('Antigravity CLI (PreToolUse)', agyOk, status?.agyHooksPath ?? '~/.gemini/config/hooks.json'),
          const SizedBox(height: AppTheme.space8),
          _buildClientStatusRow('Gemini / RTK 桥接 (BeforeTool)', geminiOk, status?.geminiSettingsPath ?? '~/.gemini/settings.json'),
          const SizedBox(height: AppTheme.space16),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.system_update_alt_rounded, size: 16),
                label: const Text('一键检测与自动挂载'),
                onPressed: () async {
                  final ok = await _service.installClientHooks();
                  await _refreshHookStatus();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok ? '全局 Hook 已成功挂载！跨项目立即生效。' : 'Hook 挂载失败，请检查配置权限。'),
                        backgroundColor: ok ? context.successSolid : context.errorSolid,
                      ),
                    );
                  }
                },
              ),
              OutlinedButton(
                onPressed: () async {
                  await _service.uninstallClientHooks();
                  await _refreshHookStatus();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已移除全局 Hook。')),
                    );
                  }
                },
                child: Text('卸载 Hook'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClientStatusRow(String name, bool isReady, String path) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: isReady ? context.successText : context.warningText,
          ),
          SizedBox(width: AppTheme.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
                Text(path, style: TextStyle(fontSize: 11, color: context.textTertiary, fontFamily: 'monospace')),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isReady ? context.successText.withValues(alpha: 0x1F / 255) : context.warningText.withValues(alpha: 0x1F / 255),
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Text(
              isReady ? '已挂载' : '未挂载',
              style: TextStyle(fontSize: 11, color: isReady ? context.successText : context.warningText, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// 安全机械硬地板卡片
  Widget _buildSafetyFloorCard(UnattendedState state) {
    return Container(
      padding: EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('机械安全硬地板 (绝对拦截)', style: AppTheme.fontTitle),
              TextButton.icon(
                icon: Icon(Icons.rule_rounded, size: 16),
                label: Text('规则管理'),
                onPressed: () => _showDenylistRulesDialog(state),
              ),
            ],
          ),
          SizedBox(height: AppTheme.space8),
          Text(
            '无论是否处于无人值守，命中以下模式一律阻断并触发系统告警：',
            style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
          ),
          const SizedBox(height: AppTheme.space12),
          Wrap(
            spacing: AppTheme.space8,
            runSpacing: AppTheme.space8,
            children: const [
              _SafetyBadge('rm -rf / 根目录清除'),
              _SafetyBadge('git push --force 远端覆盖'),
              _SafetyBadge('git reset --hard 历史回滚'),
              _SafetyBadge('.env / 密钥覆写'),
              _SafetyBadge('curl | bash 远程管道脚本'),
              _SafetyBadge('mkfs / dd 块设备抹除'),
            ],
          ),
        ],
      ),
    );
  }

  void _showDenylistRulesDialog(UnattendedState state) {
    final controller = TextEditingController(text: state.denylist.join('\n'));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('安全黑名单正则表达式规则'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每行一条正则匹配表达式，命中命令将无条件阻断：', style: AppTheme.fontCaption),
              const SizedBox(height: AppTheme.space8),
              TextField(
                controller: controller,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _service.resetDenylistToDefaults();
            },
            child: const Text('恢复默认预设'),
          ),
          ElevatedButton(
            onPressed: () {
              final rules = controller.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
              Navigator.of(ctx).pop();
              _service.updateDenylist(rules);
            },
            child: Text('保存修改'),
          ),
        ],
      ),
    );
  }

  /// 白名单优先放行卡片
  Widget _buildAllowlistCard(UnattendedState state) {
    final allowlist = state.allowlist;

    return Container(
      padding: EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text('白名单优先放行 (高于黑名单)', style: AppTheme.fontTitle),
                  const SizedBox(width: AppTheme.space8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.successText.withValues(alpha: 0x1F / 255),
                      borderRadius: AppTheme.borderRadiusSmall,
                    ),
                    child: Text(
                      '${allowlist.length} 条规则',
                      style: TextStyle(fontSize: 11, color: context.successText, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                icon: Icon(Icons.tune_rounded, size: 16),
                label: Text('规则管理'),
                onPressed: () => _showAllowlistRulesDialog(state),
              ),
            ],
          ),
          SizedBox(height: AppTheme.space8),
          Text(
            '处于无人值守状态时，命中白名单的命令将拥有最高优先级，绕过黑名单直接自动审批通过：',
            style: AppTheme.fontCaption.copyWith(color: context.textSecondary),
          ),
          SizedBox(height: AppTheme.space12),
          if (allowlist.isEmpty)
            Container(
              padding: EdgeInsets.symmetric(vertical: AppTheme.space8),
              child: Text(
                '暂未添加任何白名单规则。在下方实时流水中，可针对已拦截记录一键点击「加入白名单」。',
                style: TextStyle(fontSize: 12, color: context.textTertiary),
              ),
            )
          else
            Wrap(
              spacing: AppTheme.space8,
              runSpacing: AppTheme.space8,
              children: allowlist.map((rule) {
                return Chip(
                  label: Text(
                    rule,
                    style: TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                  backgroundColor: context.bgInput,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.borderRadiusSmall,
                    side: BorderSide(color: context.borderSubtle),
                  ),
                  deleteIcon: const Icon(Icons.close_rounded, size: 14),
                  onDeleted: () async {
                    await _service.removeFromAllowlist(rule);
                  },
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _showAllowlistRulesDialog(UnattendedState state) {
    final controller = TextEditingController(text: state.allowlist.join('\n'));
    bool consolidating = false;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('白名单命令/正则规则管理'),
        content: SizedBox(
          width: 540,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('每行一条规则（支持正则表达式或精确命令）。处于无人值守时优先放行：', style: AppTheme.fontCaption),
              const SizedBox(height: AppTheme.space8),
              TextField(
                controller: controller,
                maxLines: 8,
                enabled: !consolidating,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: r'^git push .*$\n^rm -rf /tmp/my-dir$',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: consolidating
                ? null
                : () {
                    Navigator.of(ctx).pop();
                    _service.clearAllowlist();
                  },
            child: Text('清空白名单', style: TextStyle(color: context.errorText)),
          ),
          TextButton.icon(
            onPressed: consolidating
                ? null
                : () async {
                    setDialogState(() => consolidating = true);
                    await _runAllowlistConsolidation(ctx, controller);
                    if (ctx.mounted) {
                      setDialogState(() => consolidating = false);
                    }
                  },
            icon: consolidating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high_rounded, size: 16),
            label: Text(consolidating ? '整理中…' : 'AI整理'),
          ),
          ElevatedButton(
            onPressed: consolidating
                ? null
                : () {
                    final rules = controller.text
                        .split('\n')
                        .map((s) => s.trim())
                        .where((s) => s.isNotEmpty)
                        .toList();
                    Navigator.of(ctx).pop();
                    _service.updateAllowlist(rules);
                  },
            child: const Text('保存修改'),
          ),
        ],
        ),
      ),
    );
  }

  /// A 路径：AI整理白名单规则（本地预整理 → 簇检测 → AI 合并 → 校验 → 预览确认 → 回填编辑框）。
  Future<void> _runAllowlistConsolidation(
    BuildContext dialogCtx,
    TextEditingController controller,
  ) async {
    final rules = controller.text
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (rules.length < 2) {
      _showSnackBar(dialogCtx, '规则不足两条，无需整理');
      return;
    }

    // 1. 本地预整理（无条件第一步）
    final tidied = AllowlistConsolidationService.localPreTidy(rules);
    final clusters = AllowlistConsolidationService.clusterRules(tidied);

    if (clusters.isEmpty) {
      // 无相似簇：本地预整理若有变化则回填，否则提示空态
      if (tidied.length < rules.length) {
        controller.text = tidied.join('\n');
        _showSnackBar(dialogCtx, '未发现相似规则簇，已完成本地去重整理（${rules.length} → ${tidied.length} 条）');
      } else {
        _showSnackBar(dialogCtx, '未发现可合并的相似规则');
      }
      return;
    }

    // 2. AI 合并（不可用/失败返回 null → 降级为本地预整理）
    final plan = await AllowlistConsolidationService.consolidateWithAi(rules);
    if (!dialogCtx.mounted) return;

    if (plan == null || !plan.hasMerges) {
      final reason = plan != null && plan.rejected.isNotEmpty
          ? '（${plan.rejected.length} 组合并未通过安全校验，已保留原规则）'
          : '';
      if (tidied.length < rules.length) {
        controller.text = tidied.join('\n');
        _showSnackBar(dialogCtx, 'AI 整理不可用，已执行本地去重整理$reason');
      } else {
        _showSnackBar(dialogCtx, 'AI 整理不可用，规则保持不变$reason');
      }
      return;
    }

    // 3. 预览确认对话框
    final confirmed = await _showConsolidationPreview(dialogCtx, plan);
    if (!dialogCtx.mounted) return;
    if (confirmed == true) {
      controller.text = AllowlistConsolidationService.applyPlan(plan).join('\n');
      _showSnackBar(
        dialogCtx,
        '已应用整理（${plan.tidiedRules.length} → ${AllowlistConsolidationService.applyPlan(plan).length} 条），确认无误后点击「保存修改」生效',
      );
    }
  }

  /// 合并预览：逐组展示「旧规则 ↔ 新宽规则」对照，返回用户是否确认应用。
  Future<bool?> _showConsolidationPreview(BuildContext parentCtx, ConsolidationPlan plan) {
    return showDialog<bool>(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('AI 整理预览'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('以下规则簇将被合并为宽规则。未列出的规则保持不变：', style: AppTheme.fontCaption),
                SizedBox(height: AppTheme.space12),
                ...plan.groups.map((g) {
                  final oldRules = g.covers.map((i) => plan.tidiedRules[i]).toList();
                  return Container(
                    margin: EdgeInsets.only(bottom: AppTheme.space12),
                    padding: EdgeInsets.all(AppTheme.space12),
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: AppTheme.borderRadiusSmall,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (g.summary.isNotEmpty)
                          Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Text('📦 ${g.summary}',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ...oldRules.map((r) => Padding(
                              padding: EdgeInsets.only(bottom: 4),
                              child: Text('－ $r',
                                  style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      color: context.textTertiary,
                                      decoration: TextDecoration.lineThrough)),
                            )),
                        const SizedBox(height: 2),
                        Text('＋ ${g.mergedRule}',
                            style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: context.accentText,
                                fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                }),
                if (plan.rejected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '⚠️ ${plan.rejected.length} 组合并未通过安全校验（回验或黑名单交叉），已保留原规则',
                      style: TextStyle(fontSize: 11, color: context.errorText),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('应用整理'),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(BuildContext ctx, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 实时审批流水展示面板
  Widget _buildAuditStreamSection() {
    final filtered = _auditLogs.where((item) {
      if (_filterDecision == 'allow') return item.isAllowed;
      if (_filterDecision == 'deny') return item.isDenied;
      return true;
    }).toList();

    return Container(
      padding: EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppTheme.space12,
            runSpacing: AppTheme.space12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('实时审批审计流水 (Audit Stream)', style: AppTheme.fontTitle),
                  SizedBox(width: AppTheme.space12),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: context.bgInput,
                      borderRadius: AppTheme.borderRadiusSmall,
                    ),
                    child: Text('${filtered.length} 条记录', style: TextStyle(fontSize: 11, color: context.textSecondary)),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'all', label: Text('全部')),
                      ButtonSegment(value: 'allow', label: Text('已放行')),
                      ButtonSegment(value: 'deny', label: Text('已拦截')),
                    ],
                    selected: {_filterDecision},
                    onSelectionChanged: (val) {
                      setState(() => _filterDecision = val.first);
                    },
                    style: ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: AppTheme.space12),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    tooltip: '清空流水',
                    onPressed: () async {
                      await _service.clearAuditLogs();
                      await _refreshLogs();
                    },
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: AppTheme.space12),
          if (_isLoadingLogs)
            Padding(padding: EdgeInsets.all(AppTheme.space32), child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(AppTheme.space32),
              alignment: Alignment.center,
              child: Text('暂无审批记录，AI 发起工具调用时将自动在此流水呈现。', style: TextStyle(color: context.textTertiary)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
              itemBuilder: (ctx, idx) {
                final item = filtered[idx];
                return _buildAuditItemRow(item);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAuditItemRow(AuditRecord item) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppTheme.space8),
      child: Row(
        children: [
          Text(
            _formatTime(item.timestamp),
            style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: context.textTertiary),
          ),
          const SizedBox(width: AppTheme.space12),
          Builder(
            builder: (context) {
              final c = item.client.toLowerCase();
              final isClaude = c.contains('claude');
              final isAgy = c.contains('agy') || c.contains('gemini');
              final label = isClaude ? 'Claude Code' : (isAgy ? 'AGY' : item.client);
              final badgeBg = isClaude
                  ? Colors.purple.withAlpha(35)
                  : (isAgy ? Colors.cyan.withAlpha(35) : Colors.blue.withAlpha(35));
              final badgeColor = isClaude
                  ? Colors.purpleAccent
                  : (isAgy ? Colors.cyanAccent : Colors.lightBlueAccent);

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: AppTheme.borderRadiusSmall,
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: badgeColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
          SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              item.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: context.textPrimary),
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: item.isAllowed ? context.successText.withValues(alpha: 0x1F / 255) : context.errorText.withValues(alpha: 0x1F / 255),
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isAllowed ? Icons.check_circle_outline : Icons.block_rounded,
                  size: 13,
                  color: item.isAllowed ? context.successText : context.errorText,
                ),
                const SizedBox(width: 4),
                Text(
                  item.isAllowed ? '自动放行' : '安全拦截',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.isAllowed ? context.successText : context.errorText,
                  ),
                ),
              ],
            ),
          ),
          if (item.isDenied) ...[
            SizedBox(width: AppTheme.space8),
            _buildAllowlistAction(item.command),
          ],
        ],
      ),
    );
  }

  Widget _buildAllowlistAction(String command) {
    final isAlreadyWhitelisted = _service.isCommandInAllowlist(command);
    if (isAlreadyWhitelisted) {
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.bgInput,
          borderRadius: AppTheme.borderRadiusSmall,
          border: Border.all(color: context.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_rounded, size: 12, color: context.textTertiary),
            SizedBox(width: 4),
            Text(
              '已在白名单',
              style: TextStyle(fontSize: 11, color: context.textTertiary),
            ),
          ],
        ),
      );
    }

    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: context.accentSolid.withAlpha(120)),
      ),
      icon: Icon(Icons.playlist_add_check_rounded, size: 14, color: context.accentText),
      label: Text(
        '加入白名单',
        style: TextStyle(fontSize: 11, color: context.accentText, fontWeight: FontWeight.bold),
      ),
      onPressed: () => _addToAllowlistSmart(command),
    );
  }

  /// B 路径：加入白名单智能合并。
  /// 覆盖检测 → 同簇检测 → AI 泛化确认 → 宽规则替换；失败静默退回精确规则。
  Future<void> _addToAllowlistSmart(String command) async {
    // 1. 已被现有规则覆盖
    final covered = _service.findMatchingAllowlistRule(command);
    if (covered != null) {
      _showSnackBar(context, '该命令已被现有规则覆盖：$covered');
      return;
    }

    // 2. 同簇检测：与现有规则明显相似才尝试 AI 合并
    final exactRule = UnattendedService.buildExactRule(command);
    final existing = _service.allowlistSnapshot;
    final newAnchors = AllowlistConsolidationService.extractAnchors(exactRule);
    final sameCluster = existing
        .where((r) => AllowlistConsolidationService.isSameCluster(
            newAnchors, AllowlistConsolidationService.extractAnchors(r)))
        .toList();

    if (sameCluster.isEmpty) {
      // 无同簇规则 → 直接走精确路径
      await _service.addToAllowlist(command);
      if (mounted) {
        _showSnackBar(context, '已将命令加入白名单，后续将优先自动审批放行：$command');
      }
      return;
    }

    // 3. AI 泛化（不可用/失败/校验未过 → null → 静默精确降级）
    final suggestion =
        await AllowlistConsolidationService.suggestMergeForCluster([exactRule, ...sameCluster]);
    if (!mounted) return;

    if (suggestion == null) {
      await _service.addToAllowlist(command);
      if (mounted) {
        _showSnackBar(context, 'AI 整理不可用，已按精确规则加入白名单：$command');
      }
      return;
    }

    // 4. 用户确认：合并为宽规则 or 只加精确规则
    final merge = await _showMergeConfirmDialog(suggestion, exactRule);
    if (!mounted) return;
    if (merge == true) {
      await _service.replaceAllowlistRules(suggestion.coveredRules, suggestion.mergedRule);
      if (mounted) {
        _showSnackBar(context,
            '已合并为宽规则（替换 ${suggestion.coveredRules.length} 条旧规则）：${suggestion.mergedRule}');
      }
    } else if (merge == false) {
      await _service.addToAllowlist(command);
      if (mounted) {
        _showSnackBar(context, '已将命令按精确规则加入白名单：$command');
      }
    }
    // merge == null（对话框被关闭）→ 不做任何改动
  }

  /// 合并确认对话框：true=合并为宽规则，false=只加精确规则，null=取消。
  Future<bool?> _showMergeConfirmDialog(MergeGroup suggestion, String newExactRule) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('发现相似白名单规则'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (suggestion.summary.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('📦 ${suggestion.summary}',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                Text('AI 建议将以下规则合并为一条宽规则：', style: AppTheme.fontCaption),
                SizedBox(height: AppTheme.space8),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(AppTheme.space12),
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ...suggestion.coveredRules.map((r) => Padding(
                            padding: EdgeInsets.only(bottom: 4),
                            child: Text(
                              r == newExactRule ? '－ $r（本次新增）' : '－ $r',
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: context.textTertiary,
                                  decoration: TextDecoration.lineThrough),
                            ),
                          )),
                      SizedBox(height: 2),
                      Text('＋ ${suggestion.mergedRule}',
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: context.accentText,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                SizedBox(height: AppTheme.space8),
                Text(
                  '宽规则已校验通过（覆盖原有命令、不触及安全黑名单）。合并后同类命令将自动放行。',
                  style: AppTheme.fontCaption.copyWith(color: context.textTertiary),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('只加精确规则'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('合并为宽规则'),
          ),
        ],
      ),
    );
  }
}

class _SafetyBadge extends StatelessWidget {
  final String label;
  const _SafetyBadge(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 12, color: context.warningText),
          SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: context.textSecondary)),
        ],
      ),
    );
  }
}
