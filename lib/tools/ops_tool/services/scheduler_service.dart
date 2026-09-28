import 'dart:async';
import 'package:cron/cron.dart' as cron_pkg;
import 'package:flutter/foundation.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import 'argocd_service.dart';
import 'email_service.dart';
import 'ops_notifier.dart';
import 'report_generator.dart';
import 'template_engine.dart';

class SchedulerService {
  SchedulerService._();
  static final SchedulerService instance = SchedulerService._();

  final cron_pkg.Cron _cron = cron_pkg.Cron();
  final List<cron_pkg.ScheduledTask> _scheduledHooks = [];
  bool _isRunning = false;
  Timer? _argocdTimer;
  bool _argocdRunning = false;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;
    await reloadTasks();
    OpsNotifier.instance.start();
    _scheduleArgocdCheck();
  }

  Future<void> stop() async {
    _isRunning = false;
    _argocdTimer?.cancel();
    _argocdTimer = null;
    for (final hook in _scheduledHooks) {
      await hook.cancel();
    }
    _scheduledHooks.clear();
  }

  // ==========================================================================
  // ArgoCD 后台巡检循环
  // ==========================================================================

  /// 排入下一次巡检：延迟 `delay` 后执行单次全量巡检，并按「启用环境的最小检查间隔」
  /// 自我校正地排入后续巡检。环境增删改后无需重启循环；首轮默认延迟 5 秒，
  /// 避免与窗口启动期的服务初始化相互竞争。
  void _scheduleArgocdCheck({Duration delay = const Duration(seconds: 5)}) {
    _argocdTimer?.cancel();
    _argocdTimer = Timer(delay, () async {
      await _runArgocdCheckOnce();
      if (!_isRunning) return;
      final secs = await OpsDatabase.instance.getMinArgoCdInterval();
      _argocdTimer = Timer(Duration(seconds: secs), _scheduleArgocdCheck);
    });
  }

  /// 单次巡检：遍历全部启用环境并逐个检查。单环境异常仅记日志并跳过，不中断整体巡检。
  Future<void> _runArgocdCheckOnce() async {
    if (_argocdRunning) return;
    _argocdRunning = true;
    try {
      final envs = await OpsDatabase.instance.loadEnabledArgoCdEnvs();
      if (envs.isEmpty) return;

      for (final env in envs) {
        try {
          await ArgoCdService.instance.checkEnvironment(env);
        } catch (e) {
          debugPrint('[ArgoCD] 环境 "${env.name}" 检查失败: $e');
        }
      }
    } finally {
      _argocdRunning = false;
    }
  }

  Future<void> reloadTasks() async {
    for (final hook in _scheduledHooks) {
      await hook.cancel();
    }
    _scheduledHooks.clear();

    final tasks = await OpsDatabase.instance.loadScheduledTasks();
    for (final task in tasks) {
      if (!task.enabled) continue;

      try {
        final schedule = cron_pkg.Schedule.parse(task.cronExpr);
        final hook = _cron.schedule(schedule, () async {
          await executeTask(task);
        });
        _scheduledHooks.add(hook);
      } catch (_) {}
    }
  }

  Future<void> executeTask(ScheduledTask task) async {
    final log = TaskLog(
      taskType: task.taskType,
      status: 'running',
      message: '任务 "${task.name}" 开始执行',
      startedAt: DateTime.now().toIso8601String(),
    );
    await OpsDatabase.instance.addTaskLog(log);

    final updatedTask = ScheduledTask(
      id: task.id,
      name: task.name,
      taskType: task.taskType,
      config: task.config,
      cronExpr: task.cronExpr,
      enabled: task.enabled,
      lastRun: DateTime.now().toIso8601String(),
      nextRun: task.nextRun,
      createdAt: task.createdAt,
    );
    await OpsDatabase.instance.saveScheduledTask(updatedTask);

    try {
      final configMap = task.getConfigMap();

      switch (task.taskType) {
        case 'generate_report':
          await _executeGenerateReport(task, configMap);
          break;
        case 'send_email':
          await _executeSendEmail(task, configMap);
          break;
        case 'scrape':
        default:
          // Data scrape heartbeat
          break;
      }

      final successLog = TaskLog(
        id: log.id,
        taskType: task.taskType,
        status: 'success',
        message: '任务 "${task.name}" 执行成功',
        startedAt: log.startedAt,
        finishedAt: DateTime.now().toIso8601String(),
      );
      await OpsDatabase.instance.addTaskLog(successLog);
    } catch (e) {
      final failedLog = TaskLog(
        id: log.id,
        taskType: task.taskType,
        status: 'failed',
        message: '任务 "${task.name}" 执行异常: $e',
        startedAt: log.startedAt,
        finishedAt: DateTime.now().toIso8601String(),
      );
      await OpsDatabase.instance.addTaskLog(failedLog);
    }
  }

  Future<void> _executeGenerateReport(
      ScheduledTask task, Map<String, dynamic> config) async {
    final templateId = config['report_template_id'] as String?;
    if (templateId == null || templateId.isEmpty) return;

    final templates = await OpsDatabase.instance.loadReportTemplates();
    final template = templates.firstWhere((t) => t.id == templateId);

    // Resolve template
    final content = TemplateEngine.resolveTemplate(
      template: template.content,
      rules: template.rules,
    );

    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final report = Report(
      title: '${template.name} - $dateStr',
      date: dateStr,
      sections: [
        ReportSection(
          sectionType: 'custom',
          title: template.name,
          content: content,
          order: 1,
        ),
      ],
    );

    final html = ReportGenerator.generateHtml(report);
    final savedReport = Report(
      id: report.id,
      title: report.title,
      date: report.date,
      htmlContent: html,
      sections: report.sections,
    );
    await OpsDatabase.instance.saveReport(savedReport);

    final autoSendEmail = config['auto_send_email'] as bool? ?? false;
    if (autoSendEmail) {
      final accountId = config['email_account_id'] as String?;
      if (accountId != null && accountId.isNotEmpty) {
        final accounts = await OpsDatabase.instance.loadEmailAccounts();
        final account = accounts.firstWhere((a) => a.id == accountId);
        final recipients =
            await OpsDatabase.instance.loadEmailRecipients(accountId);
        if (recipients.isNotEmpty) {
          await EmailService.instance.sendReportEmail(
            account: account,
            recipients: recipients,
            subject: savedReport.title,
            htmlContent: html,
          );
        }
      }
    }
  }

  Future<void> _executeSendEmail(
      ScheduledTask task, Map<String, dynamic> config) async {
    final accountId = config['email_account_id'] as String?;
    if (accountId == null || accountId.isEmpty) {
      throw Exception('未指定邮件账户');
    }

    final accounts = await OpsDatabase.instance.loadEmailAccounts();
    final account = accounts.firstWhere((a) => a.id == accountId);
    final recipients = await OpsDatabase.instance.loadEmailRecipients(accountId);
    if (recipients.isEmpty) {
      throw Exception('当前账户下无可用收件人');
    }

    final reports = await OpsDatabase.instance.listReports(limit: 1);
    if (reports.isEmpty) {
      throw Exception('暂无生成的报告可供发送');
    }

    final latestReport = reports.first;
    await EmailService.instance.sendReportEmail(
      account: account,
      recipients: recipients,
      subject: latestReport.title,
      htmlContent: latestReport.htmlContent,
    );
  }
}
