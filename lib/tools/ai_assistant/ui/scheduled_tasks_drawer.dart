import 'package:flutter/material.dart';
import '../../../components/app_components.dart';
import '../../../services/scheduled_news_service.dart';
import '../../../theme/app_theme.dart';

class ScheduledTasksDrawer extends StatefulWidget {
  const ScheduledTasksDrawer({super.key});

  @override
  State<ScheduledTasksDrawer> createState() => _ScheduledTasksDrawerState();
}

class _ScheduledTasksDrawerState extends State<ScheduledTasksDrawer> with SingleTickerProviderStateMixin {
  final _service = ScheduledNewsService.instance;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _service.addListener(_onServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceUpdate);
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _showAddOrEditTaskDialog({ScheduledNewsTask? task}) {
    final isEditing = task != null;
    final titleCtrl = TextEditingController(text: task?.title ?? '');
    final queryCtrl = TextEditingController(text: task?.query ?? '');
    int interval = task?.intervalMinutes ?? 60;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: Text(isEditing ? '编辑定时资讯任务' : '新建定时资讯任务', style: AppTheme.fontTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(controller: titleCtrl, label: '任务标题', hintText: '例如: 美联储降息与宏观经济'),
                const SizedBox(height: AppTheme.space12),
                AppTextField(controller: queryCtrl, label: '检索关键词 / 主题', hintText: '例如: Fed rate cut news'),
                const SizedBox(height: AppTheme.space12),
                DropdownButtonFormField<int>(
                  initialValue: interval,
                  decoration: const InputDecoration(labelText: '轮询检索周期'),
                  items: const [
                    DropdownMenuItem(value: 30, child: Text('每 30 分钟')),
                    DropdownMenuItem(value: 60, child: Text('每 1 小时')),
                    DropdownMenuItem(value: 120, child: Text('每 2 小时')),
                    DropdownMenuItem(value: 360, child: Text('每 6 小时')),
                    DropdownMenuItem(value: 1440, child: Text('每天 (24 小时)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => interval = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            AppButton.ghost(label: '取消', onPressed: () => Navigator.pop(ctx)),
            AppButton.primary(
              label: '保存',
              onPressed: () async {
                final id = task?.id ?? 'task_${DateTime.now().millisecondsSinceEpoch}';
                final newTask = ScheduledNewsTask(
                  id: id,
                  title: titleCtrl.text.trim().isEmpty ? '未命名资讯任务' : titleCtrl.text.trim(),
                  query: queryCtrl.text.trim().isEmpty ? '最新资讯' : queryCtrl.text.trim(),
                  intervalMinutes: interval,
                  enabled: task?.enabled ?? true,
                  lastRunTime: task?.lastRunTime,
                  lastBriefing: task?.lastBriefing,
                  lastFingerprint: task?.lastFingerprint,
                );
                await _service.saveTask(newTask);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      child: Column(
        children: [
          // 顶栏拖拽把手与标题
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.space24, vertical: AppTheme.space16),
            child: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: AppTheme.accentLight, size: 22),
                const SizedBox(width: AppTheme.space8),
                const Text('定时资讯检索与快报追踪', style: AppTheme.fontTitle),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(icon: Icon(Icons.timer_outlined, size: 16), text: '检索任务列表'),
              Tab(icon: Icon(Icons.newspaper_outlined, size: 16), text: '资讯快报历史'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTasksTab(),
                _buildBriefingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksTab() {
    final tasks = _service.tasks;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('运行中的任务 (${tasks.length})', style: AppTheme.fontTitle),
            AppButton.primary(
              label: '新建检索任务',
              icon: Icons.add,
              onPressed: () => _showAddOrEditTaskDialog(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space16),
        if (tasks.isEmpty)
          const Center(
            child: Text('暂无定时资讯检索任务，点击右上角添加。', style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          ...tasks.map((t) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space12),
              child: AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.radar, size: 18, color: t.enabled ? AppTheme.accentLight : AppTheme.textTertiary),
                          const SizedBox(width: AppTheme.space8),
                          Text(t.title, style: AppTheme.fontTitle),
                          const SizedBox(width: AppTheme.space8),
                          AppBadge(label: '每 ${t.intervalMinutes} 分钟'),
                          const Spacer(),
                          Switch(
                            value: t.enabled,
                            activeThumbColor: AppTheme.accentLight,
                            onChanged: (val) async {
                              t.enabled = val;
                              await _service.saveTask(t);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.space8),
                      Text('关键词: ${t.query}', style: AppTheme.fontBody.copyWith(color: AppTheme.textSecondary)),
                      if (t.lastRunTime != null) ...[
                        const SizedBox(height: AppTheme.space4),
                        Text(
                          '上次检索: ${t.lastRunTime!.hour.toString().padLeft(2, '0')}:${t.lastRunTime!.minute.toString().padLeft(2, '0')}:${t.lastRunTime!.second.toString().padLeft(2, '0')}',
                          style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                        ),
                      ],
                      if (t.lastBriefing != null) ...[
                        const SizedBox(height: AppTheme.space8),
                        Container(
                          padding: const EdgeInsets.all(AppTheme.space10),
                          decoration: BoxDecoration(
                            color: AppTheme.bgContent,
                            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                          ),
                          child: Text(
                            t.lastBriefing!,
                            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.4),
                          ),
                        ),
                      ],
                      const SizedBox(height: AppTheme.space12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AppButton.secondary(
                            label: '立即执行一次',
                            icon: Icons.play_arrow_rounded,
                            onPressed: () => _service.runTaskNow(t),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          AppButton.ghost(
                            label: '编辑',
                            icon: Icons.edit_outlined,
                            onPressed: () => _showAddOrEditTaskDialog(task: t),
                          ),
                          const SizedBox(width: AppTheme.space8),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
                            tooltip: '删除任务',
                            onPressed: () => _service.deleteTask(t.id),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildBriefingsTab() {
    final briefings = _service.briefings;

    return ListView(
      padding: const EdgeInsets.all(AppTheme.space24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('资讯快报 (${briefings.length})', style: AppTheme.fontTitle),
            AppButton.ghost(
              label: '全部标记为已读',
              icon: Icons.done_all,
              onPressed: briefings.isEmpty ? null : () => _service.markAllAsRead(),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.space16),
        if (briefings.isEmpty)
          const Center(
            child: Text('暂无资讯快报。当定时任务发现新的动态时会自动汇总在此。', style: TextStyle(color: AppTheme.textSecondary)),
          )
        else
          ...briefings.map((b) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.space12),
              child: AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(AppTheme.space16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.article_outlined, size: 18, color: b.isRead ? AppTheme.textTertiary : AppTheme.accentLight),
                          const SizedBox(width: AppTheme.space8),
                          Text(b.taskTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(width: AppTheme.space8),
                          if (!b.isRead) const AppBadge(label: 'NEW', color: AppTheme.accentLight),
                          const Spacer(),
                          Text(
                            '${b.timestamp.month}/${b.timestamp.day} ${b.timestamp.hour.toString().padLeft(2, '0')}:${b.timestamp.minute.toString().padLeft(2, '0')}',
                            style: AppTheme.fontCaption.copyWith(color: AppTheme.textTertiary),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTheme.space8),
                      SelectableText(
                        b.content,
                        style: const TextStyle(fontSize: 13, height: 1.5, color: AppTheme.textPrimary),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}
