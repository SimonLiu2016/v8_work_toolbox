/// 安全工具箱主页面：左侧导航 + Tab 内容区 + 右侧 AI 面板。
///
/// 布局照 `OpsToolMainPage`：`Row[侧导航 | 内容区 | AI 面板]`。差异在于安全
/// 工具箱的 Tab 是「会话内工作流」（侦察→扫描→利用→报告）而不是并列功能，
/// 所以会话工具条常驻在内容区顶部，切 Tab 不丢当前会话。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/intel_digest_scheduler.dart';
import '../services/intel_store.dart' show ThreatIntelRepository;
import '../services/threat_intel_services.dart';
import '../services/security_session_controller.dart';
import 'exploit_view.dart';
import 'lan_recon_view.dart';
import 'report_view.dart';
import 'script_generator_view.dart';
import 'security_ai_panel.dart';
import 'security_agent_view.dart';
import 'session_bar.dart';
import 'threat_intel_view.dart';
import 'tool_status_panel.dart';
import 'vuln_scan_view.dart';
import 'web_recon_view.dart';
import 'widgets.dart';

class SecurityToolboxMainPage extends StatefulWidget {
  const SecurityToolboxMainPage({super.key});

  @override
  State<SecurityToolboxMainPage> createState() => _SecurityToolboxMainPageState();
}

class _SecurityToolboxMainPageState extends State<SecurityToolboxMainPage>
    with WidgetsBindingObserver {
  late final SecuritySessionController _controller =
      SecuritySessionController();
  /// 复用 controller 持有的同一个仓储与数据库连接——另开会开出第二个 SQLite
  /// 连接，两个连接的写入缓存会互相覆盖。
  late final ThreatIntelRepository _intelRepo = _controller.intelRepo;

  bool _aiCollapsed = false;

  @override
  void initState() {
    super.initState();
    _controller.init();
    // 每日 09:00 的 AI 情报日报（spec 8.5）。生成时带上当前会话资产，
    // 这样日报里的「资产命中」段才有内容。
    IntelDigestScheduler.instance.currentAssets =
        () => _controller.assetList;
    IntelDigestScheduler.instance.generate = (input) async {
      final prompt = buildDailyDigestPrompt(input);
      try {
        return await _controller.askAi(prompt);
      } catch (_) {
        return '';
      }
    };
    IntelDigestScheduler.instance.start();
  }

  @override
  void dispose() {
    IntelDigestScheduler.instance.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => Scaffold(
        backgroundColor: context.bgWindow,
        body: Row(
          children: [
            _buildSidebar(context),
            VerticalDivider(width: 1, color: context.borderSubtle),
            Expanded(
              child: Container(
                color: context.bgContent,
                child: Column(
                  children: [
                    SessionBar(
                      controller: _controller,
                      onCreateLan: () => showNewSessionDialog(
                        context,
                        _controller,
                        'lan',
                      ),
                      onCreateWeb: () => showNewSessionDialog(
                        context,
                        _controller,
                        'web',
                      ),
                    ),
                    Expanded(
                      child: _buildActiveView(),
                    ),
                  ],
                ),
              ),
            ),
            SecurityAiPanel(
              controller: _controller,
              collapsed: _aiCollapsed,
              onToggleCollapsed: () =>
                  setState(() => _aiCollapsed = !_aiCollapsed),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 176,
      color: context.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: context.accentText.withAlpha(40),
                    borderRadius: AppTheme.borderRadiusSmall,
                  ),
                  child: Icon(
                    Icons.security_outlined,
                    color: context.accentText,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '安全工具箱',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderSubtle),
          const SizedBox(height: 8),
          _navItem('session', '会话', Icons.folder_outlined),
          _navItem('recon', '侦察', Icons.radar_rounded),
          _navItem('agent', 'Security Agent', Icons.psychology_outlined),
          _navItem('vuln', '漏洞扫描', Icons.bug_report_outlined),
          _navItem('exploit', '漏洞利用', Icons.bolt_outlined),
          _navItem('intel', '威胁情报', Icons.campaign_outlined),
          _navItem('script', '脚本生成', Icons.code_rounded),
          _navItem('report', '报告', Icons.article_outlined),
          _navItem('tools', '工具依赖', Icons.build_outlined),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: context.warningSolid,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '仅用于授权测试',
                    style: AppTheme.fontCaption.copyWith(
                      color: context.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 会话 Tab：时间线 + 会话操作（标记完成/删除）。
  Widget _buildSessionView(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final session = _controller.current;
        if (session == null) {
          return EmptyState(
            message: '请先创建会话',
            icon: Icons.folder_outlined,
          );
        }
        final events = _controller.timelineList;
        return ListView(
          padding: const EdgeInsets.all(AppTheme.space12),
          children: [
            SectionHeader(
              title: session.name,
              subtitle: '${SessionType.labelOf(session.type)} · '
                  '${_controller.assetList.length} 资产 · '
                  '${_controller.findingList.length} 发现',
              trailing: [
                SmallActionButton(
                  label: '标记完成',
                  icon: Icons.check_circle_outline,
                  onPressed: () =>
                      _controller.setSessionStatus(SessionStatus.complete),
                ),
                const SizedBox(width: AppTheme.space8),
                SmallActionButton(
                  label: '删除会话',
                  icon: Icons.delete_outline,
                  onPressed: () => _confirmDelete(context, session),
                ),
              ],
            ),
            for (final event in events)
              ListTile(
                dense: true,
                leading: Icon(
                  Icons.circle,
                  size: 8,
                  color: context.accentText,
                ),
                title: Text(event.title, style: context.fontBody),
                subtitle: Text(
                  '${event.timeLabel} · '
                  '${TimelineEventType.labelOf(event.eventType)}',
                  style: context.fontCaption,
                ),
              ),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 24),
                child: EmptyState(
                  message: '还没有操作记录，先去侦察或扫描',
                  icon: Icons.timeline_outlined,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    PentestSession session,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('删除会话', style: context.fontTitle),
        content: Text(
          '将删除「${session.name}」及其全部资产、发现物与时间线，不可恢复。',
          style: context.fontBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.errorSolid,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _controller.deleteSession(session.id);
    }
  }

  Widget _navItem(String keyId, String label, IconData icon) {
    final isSelected = _controller.activeTab == keyId;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => _controller.setActiveTab(keyId),
        borderRadius: AppTheme.borderRadiusSmall,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? context.bgSelected : Colors.transparent,
            borderRadius: AppTheme.borderRadiusSmall,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? context.accentText : context.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? context.textPrimary : context.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveView() {
    switch (_controller.activeTab) {
      case 'session':
        return _buildSessionView(context);
      case 'agent':
        return SecurityAgentView(controller: _controller);
      case 'recon':
        // 会话类型决定侦察 Tab 显示 LAN 还是 Web 面板——两种侦察的目标模型完全不同，
        // 缝在一个视图里会让用户面对一堆用不上的输入。
        // 通过 key 保证切换会话时输入框与状态按会话生命周期完全重建。
        return _controller.current?.isLan == false
            ? WebReconView(
                key: ValueKey('web_recon_${_controller.current?.id}'),
                controller: _controller,
              )
            : LanReconView(
                key: ValueKey('lan_recon_${_controller.current?.id}'),
                controller: _controller,
              );
      case 'vuln':
        return VulnScanView(controller: _controller);
      case 'exploit':
        return ExploitView(controller: _controller);
      case 'intel':
        return ThreatIntelView(controller: _controller, intelRepo: _intelRepo);
      case 'script':
        return ScriptGeneratorView(controller: _controller);
      case 'report':
        return ReportView(controller: _controller);
      case 'tools':
        return ToolStatusPanel(controller: _controller);
      default:
        return LanReconView(controller: _controller);
    }
  }
}
