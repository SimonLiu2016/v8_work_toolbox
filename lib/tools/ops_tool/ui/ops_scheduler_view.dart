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
          backgroundColor: context.bgCard,
          title: Text(existing == null ? '添加定时调度任务' : '编辑定时任务', style: AppTheme.fontTitle),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: nameCtrl, decoration: InputDecoration(labelText: '任务名称')),
                  SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: type,
                    dropdownColor: context.bgCard,
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
                        icon: Icon(Icons.timer_outlined),
                        tooltip: '选择预设频率',
                        onSelected: (expr) => cronCtrl.text = expr,
                        itemBuilder: (_) => _cronPresets
                            .map((p) => PopupMenuItem(value: p.$2, child: Text('${p.$1} (${p.$2})')))
                            .toList(),
                      ),
                    ],
                  ),
                  if (type == 'generate_report') ...[
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: templateId,
                      dropdownColor: context.bgCard,
                      decoration: const InputDecoration(labelText: '绑定报告模板'),
                      items: _templates
                          .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
                          .toList(),
                      onChanged: (v) => setDialogState(() => templateId = v),
                    ),
                    SizedBox(height: 12),
                    SwitchListTile(
                      title: Text('生成后自动发送邮件'),
                      value: autoEmail,
                      activeColor: context.accentSolid,
                      onChanged: (v) => setDialogState(() => autoEmail = v),
                    ),
                  ],
                  if (type == 'send_email' || autoEmail) ...[
                    SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: accountId,
                      dropdownColor: context.bgCard,
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
              style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
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
                    Text('Cron 定时任务管理', style: AppTheme.fontTitle),
                    ElevatedButton.icon(
                      icon: Icon(Icons.add, size: 18),
                      label: Text('添加任务'),
                      style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
                      onPressed: _showTaskDialog,
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: _tasks.isEmpty
                        ? Center(child: Text('暂无定时任务，点击上方添加。', style: AppTheme.fontBodySecondary))
                        : ListView.separated(
                            itemCount: _tasks.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
                            itemBuilder: (context, idx) {
                              final task = _tasks[idx];
                              return ListTile(
                                leading: Icon(
                                  task.taskType == 'generate_report'
                                      ? Icons.auto_awesome_rounded
                                      : task.taskType == 'send_email'
                                          ? Icons.email_outlined
                                          : Icons.sync_rounded,
                                  color: context.accentText,
                                ),
                                title: Text(task.name, style: AppTheme.fontBody.copyWith(fontWeight: FontWeight.w600)),
                                subtitle: Text('Cron: ${task.cronExpr} | 上次执行: ${task.lastRun ?? "未执行"}',
                                    style: AppTheme.fontCaption.copyWith(color: context.textSecondary)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(Icons.play_circle_fill_rounded, color: context.successText, size: 22),
                                      tooltip: '立即手动执行一次',
                                      onPressed: () async {
                                        await SchedulerService.instance.executeTask(task);
                                        _loadAll();
                                      },
                                    ),
                                    Switch(
                                      value: task.enabled,
                                      activeColor: context.accentSolid,
                                      onChanged: (val) async {
                                        await OpsDatabase.instance.toggleScheduledTask(task.id, val);
                                        await SchedulerService.instance.reloadTasks();
                                        _loadAll();
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline, color: context.errorText, size: 18),
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
                    Text('任务执行日志', style: AppTheme.fontTitle),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, size: 18),
                      onPressed: _loadAll,
                      tooltip: '刷新日志',
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: _logs.isEmpty
                        ? Center(child: Text('暂无任务执行日志', style: AppTheme.fontBodySecondary))
                        : ListView.separated(
                            itemCount: _logs.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: context.borderSubtle),
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
                                      ? context.successSolid
                                      : log.status == 'failed'
                                          ? context.errorSolid
                                          : context.warningSolid,
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
