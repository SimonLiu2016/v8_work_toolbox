import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/scheduler_service.dart';

class OpsSchedulerView extends StatefulWidget {
  const OpsSchedulerView({super.key});

  @override
  State<OpsSchedulerView> createState() => _OpsSchedulerViewState();
}

class _OpsSchedulerViewState extends State<OpsSchedulerView> {
  List<ScheduledTask> _tasks = [];
  List<TaskLog> _logs = [];
  List<ReportTemplate> _templates = [];
  List<EmailAccount> _emailAccounts = [];
  bool _loading = true;

  final List<(String label, String expr)> _cronPresets = const [
    ('每分钟', '* * * * *'),
    ('每5分钟', '*/5 * * * *'),
    ('每30分钟', '*/30 * * * *'),
    ('每小时', '0 * * * *'),
    ('每天早上 8:00', '0 8 * * *'),
    ('每天中午 12:00', '0 12 * * *'),
    ('每天下午 18:00', '0 18 * * *'),
    ('工作日 9:00', '0 9 * * 1-5'),
  ];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final tasks = await OpsDatabase.instance.loadScheduledTasks();
    final logs = await OpsDatabase.instance.loadTaskLogs();
    final templates = await OpsDatabase.instance.loadReportTemplates();
    final accounts = await OpsDatabase.instance.loadEmailAccounts();

    if (mounted) {
      setState(() {
        _tasks = tasks;
        _logs = logs;
        _templates = templates;
        _emailAccounts = accounts;
        _loading = false;
      });
    }
  }

  void _showTaskDialog([ScheduledTask? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    String type = existing?.taskType ?? 'generate_report';
    final cronCtrl = TextEditingController(text: existing?.cronExpr ?? '0 9 * * 1-5');
    final cfg = existing?.getConfigMap() ?? {};
    String? templateId = cfg['report_template_id'] as String? ??
        (_templates.isNotEmpty ? _templates.first.id : null);
    String? accountId = cfg['email_account_id'] as String? ??
        (_emailAccounts.isNotEmpty ? _emailAccounts.first.id : null);
    bool autoEmail = cfg['auto_send_email'] as bool? ?? false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(existing == null ? '添加定时调度任务' : '编辑定时任务', style: AppTheme.fontTitle),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '任务名称')),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: AppTheme.bgCard,
                    decoration: const InputDecoration(labelText: '任务类型'),
                    items: const [
                      DropdownMenuItem(value: 'generate_report', child: Text('定时生成运营报告')),
                      DropdownMenuItem(value: 'send_email', child: Text('定时发送最新报告邮件')),
                      DropdownMenuItem(value: 'scrape', child: Text('定时数据源采集心跳')),
                    ],
                    onChanged: (v) {
                      if (v != null) setDialogState(() => type = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: cronCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Cron 调度表达式',
                            hintText: '分 时 日 月 周',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.timer_outlined),
                        tooltip: '选择预设频率',
                        onSelected: (expr) => cronCtrl.text = expr,
                        itemBuilder: (_) => _cronPresets
                            .map((p) => PopupMenuItem(value: p.$2, child: Text('${p.$1} (${p.$2})')))
                            .toList(),
                      ),
                    ],
                  ),
                  if (type == 'generate_report') ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: templateId,
                      dropdownColor: AppTheme.bgCard,
                      decoration: const InputDecoration(labelText: '绑定报告模板'),
                      items: _templates
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => templateId = v),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('生成后自动发送邮件'),
                      value: autoEmail,
                      activeColor: AppTheme.accent,
                      onChanged: (v) => setDialogState(() => autoEmail = v),
                    ),
                  ],
                  if (type == 'send_email' || autoEmail) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: accountId,
                      dropdownColor: AppTheme.bgCard,
                      decoration: const InputDecoration(labelText: '发信邮件账户'),
                      items: _emailAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => accountId = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                final task = ScheduledTask(
                  id: existing?.id,
                  name: nameCtrl.text.trim(),
                  taskType: type,
                  cronExpr: cronCtrl.text.trim(),
                  config: jsonEncode({
                    'report_template_id': templateId,
                    'email_account_id': accountId,
                    'auto_send_email': autoEmail,
                  }),
                  enabled: existing?.enabled ?? true,
                );
                await OpsDatabase.instance.saveScheduledTask(task);
                await SchedulerService.instance.reloadTasks();
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：定时任务列表
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cron 定时任务管理', style: AppTheme.fontTitle),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加任务'),
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                      onPressed: _showTaskDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _tasks.isEmpty
                        ? const Center(child: Text('暂无定时任务，点击上方添加。', style: AppTheme.fontBodySecondary))
                        : ListView.separated(
                            itemCount: _tasks.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
                            itemBuilder: (context, idx) {
                              final task = _tasks[idx];
                              return ListTile(
                                leading: Icon(
                                  task.taskType == 'generate_report'
                                      ? Icons.auto_awesome_rounded
                                      : task.taskType == 'send_email'
                                          ? Icons.email_outlined
                                          : Icons.sync_rounded,
                                  color: AppTheme.accent,
                                ),
                                title: Text(task.name, style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text('Cron: ${task.cronExpr} | 上次执行: ${task.lastRun ?? "未执行"}',
                                    style: AppTheme.fontCaption.copyWith(color: AppTheme.textSecondary)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.play_circle_fill_rounded, color: AppTheme.success, size: 22),
                                      tooltip: '立即手动执行一次',
                                      onPressed: () async {
                                        await SchedulerService.instance.executeTask(task);
                                        _loadAll();
                                      },
                                    ),
                                    Switch(
                                      value: task.enabled,
                                      activeColor: AppTheme.accent,
                                      onChanged: (val) async {
                                        await OpsDatabase.instance.toggleScheduledTask(task.id, val);
                                        await SchedulerService.instance.reloadTasks();
                                        _loadAll();
                                      },
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: AppTheme.error, size: 18),
                                      onPressed: () async {
                                        await OpsDatabase.instance.deleteScheduledTask(task.id);
                                        await SchedulerService.instance.reloadTasks();
                                        _loadAll();
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：任务执行日志
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('任务执行日志', style: AppTheme.fontTitle),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      onPressed: _loadAll,
                      tooltip: '刷新日志',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: AppTheme.borderSubtle),
                    ),
                    child: _logs.isEmpty
                        ? const Center(child: Text('暂无任务执行日志', style: AppTheme.fontBodySecondary))
                        : ListView.separated(
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: AppTheme.borderSubtle),
                            itemBuilder: (context, idx) {
                              final log = _logs[idx];
                              return ListTile(
                                leading: Icon(
                                  log.status == 'success'
                                      ? Icons.check_circle_rounded
                                      : log.status == 'failed'
                                          ? Icons.error_rounded
                                          : Icons.timelapse_rounded,
                                  color: log.status == 'success'
                                      ? AppTheme.success
                                      : log.status == 'failed'
                                          ? AppTheme.error
                                          : AppTheme.warning,
                                  size: 20,
                                ),
                                title: Text(log.message ?? log.taskType, style: AppTheme.fontBody),
                                subtitle: Text(log.startedAt, style: AppTheme.fontCaption),
                              );
                            },
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
}
