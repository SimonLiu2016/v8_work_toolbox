import 'dart:async';
import 'package:flutter/material.dart';

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
      backgroundColor: AppTheme.bgContent,
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
                color: isActive ? AppTheme.successSubtle : AppTheme.accentSubtle,
                borderRadius: AppTheme.borderRadiusMedium,
              ),
              child: Icon(
                isActive ? Icons.verified_user_rounded : Icons.shield_outlined,
                color: isActive ? AppTheme.success : AppTheme.accent,
                size: 28,
              ),
            ),
            const SizedBox(width: AppTheme.space16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('无人值守助手', style: AppTheme.fontHeadline),
                const SizedBox(height: AppTheme.space4),
                Text(
                  '离开电脑时自动审批 AI 工具授权，内置机械安全硬地板杜绝破坏',
                  style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
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
      padding: const EdgeInsets.all(AppTheme.space24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusLarge,
        border: Border.all(
          color: isActive ? AppTheme.success.withAlpha(80) : AppTheme.borderSubtle,
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
                      color: isActive ? AppTheme.success : AppTheme.textTertiary,
                    ),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    isActive ? '无人值守运行中 (自动放行安全操作)' : '常规人工确认模式 (自动审批已关闭)',
                    style: AppTheme.fontTitle.copyWith(
                      color: isActive ? AppTheme.success : AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? AppTheme.error : AppTheme.success,
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
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace',
                      color: AppTheme.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: AppTheme.space4),
                  Text(
                    isActive
                        ? '到期时间：${_formatTime(state.expiresAt!)} (超时自动关闭防遗忘)'
                        : '点击预设时长可立即开启或调节有效时限',
                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
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
          const SizedBox(height: AppTheme.space16),
          const Divider(color: AppTheme.borderSubtle, height: 1),
          const SizedBox(height: AppTheme.space12),
          // 防休眠与屏幕常亮控制行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _service.isCaffeinateActive ? Icons.coffee_rounded : Icons.coffee_outlined,
                    size: 18,
                    color: _service.isCaffeinateActive ? AppTheme.accent : AppTheme.textTertiary,
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Text(
                    isActive
                        ? (_service.isCaffeinateActive
                            ? '系统防休眠保护生效中 (caffeinate)'
                            : '防休眠保护待命中')
                        : '防休眠与防息屏策略',
                    style: AppTheme.fontCaption.copyWith(
                      color: _service.isCaffeinateActive ? AppTheme.textPrimary : AppTheme.textSecondary,
                      fontWeight: _service.isCaffeinateActive ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  if (isActive && _service.isCaffeinateActive) ...[
                    const SizedBox(width: AppTheme.space8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accentSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        state.keepDisplayAwake ? '系统+屏幕常亮' : '仅保系统不休眠',
                        style: const TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
              Row(
                children: [
                  Text(
                    '保持屏幕常亮 (防息屏)',
                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(width: AppTheme.space8),
                  Switch(
                    value: state.keepDisplayAwake,
                    activeThumbColor: AppTheme.accent,
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
      selectedColor: AppTheme.accent,
      backgroundColor: AppTheme.bgInput,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isSelected ? Colors.white : AppTheme.textSecondary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  Widget _buildCustomDurationButton(bool isActive) {
    return ActionChip(
      avatar: const Icon(Icons.tune_rounded, size: 14, color: AppTheme.textSecondary),
      label: const Text('自定义', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      backgroundColor: AppTheme.bgInput,
      onPressed: () => _showCustomDurationDialog(),
    );
  }

  void _showCustomDurationDialog() {
    final controller = TextEditingController(text: '90');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
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
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: AppTheme.borderSubtle),
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
                        backgroundColor: ok ? AppTheme.success : AppTheme.error,
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
                child: const Text('卸载 Hook'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClientStatusRow(String name, bool isReady, String path) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.space12, vertical: AppTheme.space8),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
            size: 16,
            color: isReady ? AppTheme.success : AppTheme.warning,
          ),
          const SizedBox(width: AppTheme.space8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                Text(path, style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary, fontFamily: 'monospace')),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isReady ? AppTheme.successSubtle : AppTheme.warningSubtle,
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Text(
              isReady ? '已挂载' : '未挂载',
              style: TextStyle(fontSize: 11, color: isReady ? AppTheme.success : AppTheme.warning, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// 安全机械硬地板卡片
  Widget _buildSafetyFloorCard(UnattendedState state) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('机械安全硬地板 (绝对拦截)', style: AppTheme.fontTitle),
              TextButton.icon(
                icon: const Icon(Icons.rule_rounded, size: 16),
                label: const Text('规则管理'),
                onPressed: () => _showDenylistRulesDialog(state),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space8),
          Text(
            '无论是否处于无人值守，命中以下模式一律阻断并触发系统告警：',
            style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary),
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
        backgroundColor: AppTheme.bgCard,
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
            child: const Text('保存修改'),
          ),
        ],
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
      padding: const EdgeInsets.all(AppTheme.space16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: AppTheme.borderRadiusMedium,
        border: Border.all(color: AppTheme.borderSubtle),
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
                  const Text('实时审批审计流水 (Audit Stream)', style: AppTheme.fontTitle),
                  const SizedBox(width: AppTheme.space12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      borderRadius: AppTheme.borderRadiusSmall,
                    ),
                    child: Text('${filtered.length} 条记录', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
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
          const SizedBox(height: AppTheme.space12),
          if (_isLoadingLogs)
            const Padding(padding: EdgeInsets.all(AppTheme.space32), child: Center(child: CircularProgressIndicator()))
          else if (filtered.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.space32),
              alignment: Alignment.center,
              child: const Text('暂无审批记录，AI 发起工具调用时将自动在此流水呈现。', style: TextStyle(color: AppTheme.textTertiary)),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
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
      padding: const EdgeInsets.symmetric(vertical: AppTheme.space8),
      child: Row(
        children: [
          Text(
            _formatTime(item.timestamp),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.textTertiary),
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
          const SizedBox(width: AppTheme.space12),
          Expanded(
            child: Text(
              item.command,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
          const SizedBox(width: AppTheme.space12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: item.isAllowed ? AppTheme.successSubtle : AppTheme.errorSubtle,
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  item.isAllowed ? Icons.check_circle_outline : Icons.block_rounded,
                  size: 13,
                  color: item.isAllowed ? AppTheme.success : AppTheme.error,
                ),
                const SizedBox(width: 4),
                Text(
                  item.isAllowed ? '自动放行' : '安全拦截',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: item.isAllowed ? AppTheme.success : AppTheme.error,
                  ),
                ),
              ],
            ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: AppTheme.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 12, color: AppTheme.warning),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
