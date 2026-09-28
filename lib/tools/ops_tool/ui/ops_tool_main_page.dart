import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../models/ops_models.dart';
import '../services/scheduler_service.dart';
import 'ops_dashboard_view.dart';
import 'ops_datasource_view.dart';
import 'ops_devops_view.dart';
import 'ops_email_view.dart';
import 'ops_excel_template_view.dart';
import 'ops_report_editor_view.dart';
import 'ops_scheduler_view.dart';

class OpsToolMainPage extends StatefulWidget {
  const OpsToolMainPage({super.key});

  @override
  State<OpsToolMainPage> createState() => _OpsToolMainPageState();
}

class _OpsToolMainPageState extends State<OpsToolMainPage> {
  String _activeTab = 'dashboard';
  Report? _pendingReport;
  String? _pendingEmailHtml;
  String? _pendingEmailSubject;

  @override
  void initState() {
    super.initState();
    // 启动定时任务调度服务
    SchedulerService.instance.start();
  }

  void _navigateTo(String tabKey) {
    setState(() => _activeTab = tabKey);
  }

  void _onReportGeneratedFromExcel(Report report) {
    setState(() {
      _pendingReport = report;
      _activeTab = 'report';
    });
  }

  void _onSendEmailFromReport(String html, String subject) {
    setState(() {
      _pendingEmailHtml = html;
      _pendingEmailSubject = subject;
      _activeTab = 'email';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgWindow,
      body: Row(
        children: [
          // 左侧主导航侧边栏
          Container(
            width: 200,
            color: AppTheme.bgSidebar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withAlpha(40),
                          borderRadius: AppTheme.borderRadiusSmall,
                        ),
                        child: const Icon(Icons.cloud_sync_rounded,
                            color: AppTheme.accent, size: 20),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        '磐石运维',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.borderSubtle),
                const SizedBox(height: 8),
                _buildNavItem(
                  keyId: 'dashboard',
                  label: '仪表盘',
                  icon: Icons.dashboard_rounded,
                ),
                _buildNavItem(
                  keyId: 'devops',
                  label: 'DevOps 流水线',
                  icon: Icons.alt_route_rounded,
                ),
                _buildNavItem(
                  keyId: 'datasource',
                  label: '数据源管理',
                  icon: Icons.storage_rounded,
                ),
                _buildNavItem(
                  keyId: 'excel',
                  label: '模板与 Excel',
                  icon: Icons.table_chart_outlined,
                ),
                _buildNavItem(
                  keyId: 'report',
                  label: '报告中心',
                  icon: Icons.article_outlined,
                ),
                _buildNavItem(
                  keyId: 'scheduler',
                  label: '定时调度',
                  icon: Icons.schedule_rounded,
                ),
                _buildNavItem(
                  keyId: 'email',
                  label: '邮件服务',
                  icon: Icons.email_outlined,
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome_rounded,
                          size: 14, color: AppTheme.accent),
                      const SizedBox(width: 6),
                      Text('已连接宿主全局 AI',
                          style: AppTheme.fontCaption
                              .copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1, color: AppTheme.borderSubtle),

          // 右侧内容工作区
          Expanded(
            child: Container(
              color: AppTheme.bgContent,
              child: _buildCurrentView(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentView() {
    switch (_activeTab) {
      case 'dashboard':
        return OpsDashboardView(onNavigate: _navigateTo);
      case 'devops':
        return const OpsDevOpsView();
      case 'datasource':
        return const OpsDataSourceView();
      case 'excel':
        return OpsExcelTemplateView(
          onReportGenerated: _onReportGeneratedFromExcel,
        );
      case 'report':
        return OpsReportEditorView(
          initialReport: _pendingReport,
          onInitialReportConsumed: () => _pendingReport = null,
          onSendEmail: _onSendEmailFromReport,
        );
      case 'scheduler':
        return const OpsSchedulerView();
      case 'email':
        return OpsEmailView(
          initialHtml: _pendingEmailHtml,
          initialSubject: _pendingEmailSubject,
        );
      default:
        return OpsDashboardView(onNavigate: _navigateTo);
    }
  }

  Widget _buildNavItem({
    required String keyId,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _activeTab == keyId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _activeTab = keyId),
        borderRadius: AppTheme.borderRadiusSmall,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.bgSelected : Colors.transparent,
            borderRadius: AppTheme.borderRadiusSmall,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
              ),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
