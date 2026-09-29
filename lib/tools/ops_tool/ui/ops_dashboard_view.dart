import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';

class OpsDashboardView extends StatefulWidget {
  final Function(String tabKey) onNavigate;

  const OpsDashboardView({super.key, required this.onNavigate});

  @override
  State<OpsDashboardView> createState() => _OpsDashboardViewState();
}

class _OpsDashboardViewState extends State<OpsDashboardView> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    final s = await OpsDatabase.instance.getDashboardStats();
    if (mounted) {
      setState(() {
        _stats = s;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final recent = (_stats?['recent_reports'] as List<dynamic>?) ?? [];

    return SingleChildScrollView(
      padding: EdgeInsets.all(AppTheme.space24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('仪表盘与概览', style: AppTheme.fontHeadline),
                  SizedBox(height: 4),
                  Text('查看系统关键运行指标、DevOps 自动化状态与近期运营报告',
                      style: AppTheme.fontCaption
                          .copyWith(color: context.textSecondary)),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _loadStats,
                tooltip: '刷新概览',
              ),
            ],
          ),
          const SizedBox(height: AppTheme.space24),

          // 指标卡片网格
          LayoutBuilder(builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 3 * AppTheme.space16) / 4;
            return Wrap(
              spacing: AppTheme.space16,
              runSpacing: AppTheme.space16,
              children: [
                _buildMetricCard(
                  title: '报告总数',
                  value: '${_stats?['report_count'] ?? 0}',
                  icon: Icons.description_outlined,
                  color: context.accentText,
                  width: cardWidth,
                  onTap: () => widget.onNavigate('report'),
                ),
                _buildMetricCard(
                  title: '已配置数据源',
                  value: '${_stats?['data_source_count'] ?? 0}',
                  icon: Icons.storage_rounded,
                  color: context.infoText,
                  width: cardWidth,
                  onTap: () => widget.onNavigate('datasource'),
                ),
                _buildMetricCard(
                  title: '定时调度任务',
                  value:
                      '${_stats?['enabled_task_count'] ?? 0} / ${_stats?['task_count'] ?? 0}',
                  icon: Icons.schedule_rounded,
                  color: context.warningText,
                  width: cardWidth,
                  onTap: () => widget.onNavigate('scheduler'),
                ),
                _buildMetricCard(
                  title: '任务成功 / 失败',
                  value:
                      '${_stats?['task_success_count'] ?? 0} / ${_stats?['task_fail_count'] ?? 0}',
                  icon: Icons.history_rounded,
                  color: (_stats?['task_fail_count'] ?? 0) > 0
                      ? context.errorSolid
                      : context.successSolid,
                  width: cardWidth,
                  onTap: () => widget.onNavigate('scheduler'),
                ),
              ],
            );
          }),

          const SizedBox(height: AppTheme.space32),

          // 快速操作入口
          const Text('快捷流水线与功能入口', style: AppTheme.fontTitle),
          const SizedBox(height: AppTheme.space12),
          Row(
            children: [
              _buildQuickAction(
                title: 'GitLab 批量建分支',
                desc: '多项目并发创建',
                icon: Icons.fork_right_rounded,
                onTap: () => widget.onNavigate('devops'),
              ),
              const SizedBox(width: AppTheme.space12),
              _buildQuickAction(
                title: '批量修改 Pom 版本',
                desc: '一键更新并提 Commit',
                icon: Icons.edit_note_rounded,
                onTap: () => widget.onNavigate('devops'),
              ),
              const SizedBox(width: AppTheme.space12),
              _buildQuickAction(
                title: '导入 Excel 报表',
                desc: '解析生成聚合报告',
                icon: Icons.table_chart_outlined,
                onTap: () => widget.onNavigate('excel'),
              ),
              const SizedBox(width: AppTheme.space12),
              _buildQuickAction(
                title: '配置发信邮件',
                desc: '管理 SMTP 账户',
                icon: Icons.email_outlined,
                onTap: () => widget.onNavigate('email'),
              ),
            ],
          ),

          SizedBox(height: AppTheme.space32),

          // 最近生成的报告
          Text('近期生成的报告', style: AppTheme.fontTitle),
          SizedBox(height: AppTheme.space12),
          if (recent.isEmpty)
            Container(
              padding: EdgeInsets.all(AppTheme.space32),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: AppTheme.borderRadiusMedium,
                border: Border.all(color: context.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Text('暂无历史报告，可在「报告中心」或「导入 Excel」生成',
                  style: AppTheme.fontBodySecondary),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: AppTheme.borderRadiusMedium,
                border: Border.all(color: context.borderSubtle),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                itemCount: recent.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: context.borderSubtle),
                itemBuilder: (context, index) {
                  final item = recent[index] as Map<String, dynamic>;
                  return ListTile(
                    leading: Icon(Icons.article_rounded,
                        color: context.accentText),
                    title: Text(item['title'] as String? ?? '未命名报告',
                        style: AppTheme.fontBody),
                    trailing: Text(item['date'] as String? ?? '',
                        style: AppTheme.fontCaption),
                    onTap: () => widget.onNavigate('report'),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double width,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.borderRadiusMedium,
      child: Container(
        width: width,
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
                Text(title,
                    style: AppTheme.fontCaption
                        .copyWith(color: context.textSecondary)),
                Icon(icon, color: color, size: 20),
              ],
            ),
            SizedBox(height: AppTheme.space12),
            Text(value,
                style: AppTheme.fontHeadline.copyWith(color: context.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction({
    required String title,
    required String desc,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTheme.borderRadiusMedium,
        child: Container(
          padding: EdgeInsets.all(AppTheme.space16),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: AppTheme.borderRadiusMedium,
            border: Border.all(color: context.borderSubtle),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: context.accentText, size: 22),
              SizedBox(height: AppTheme.space8),
              Text(title, style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.w600)),
              SizedBox(height: 2),
              Text(desc, style: AppTheme.fontCaption.copyWith(color: context.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
