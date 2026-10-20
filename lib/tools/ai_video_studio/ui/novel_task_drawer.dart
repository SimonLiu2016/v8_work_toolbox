import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/novel_import_task_service.dart';
import '../services/studio_project_manager.dart';

/// 小说导入任务中心抽屉。
///
/// 具备全生命周期的任务管理视图：
/// 1. 运行中任务秒级阶段推进与耗时呈现；
/// 2. 跨重启水合的已完成、已中断与失败任务列表；
/// 3. 分类过滤（全部 / 进行中 / 已完成 / 已中断）；
/// 4. 动作闭环：查看产物、重新导入、删除记录与批量清理。
class NovelTaskDrawer extends StatefulWidget {
  const NovelTaskDrawer({
    super.key,
    this.onRetry,
    this.onNavigateToSeries,
  });

  /// 用户点击「重新导入」时的回调（导航切到创意孵化）。
  final VoidCallback? onRetry;

  /// 用户点击「查看产物」时的回调（切到对应剧集及 IP 主库）。
  final void Function(String seriesId)? onNavigateToSeries;

  @override
  State<NovelTaskDrawer> createState() => _NovelTaskDrawerState();
}

enum _TaskFilter {
  all('全部'),
  running('进行中'),
  completed('已完成'),
  interrupted('已中断/失败');

  final String label;
  const _TaskFilter(this.label);
}

class _NovelTaskDrawerState extends State<NovelTaskDrawer> {
  final _service = NovelImportTaskService.instance;
  final _manager = StudioProjectManager.instance;
  _TaskFilter _filter = _TaskFilter.all;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  List<NovelImportTask> _filteredTasks() {
    final all = _service.tasks;
    switch (_filter) {
      case _TaskFilter.all:
        return all;
      case _TaskFilter.running:
        return all.where((t) => t.isRunning).toList();
      case _TaskFilter.completed:
        return all.where((t) => t.phase == ImportPhase.done).toList();
      case _TaskFilter.interrupted:
        return all.where((t) => t.phase == ImportPhase.interrupted || t.phase == ImportPhase.failed).toList();
    }
  }

  String _seriesNameOf(String seriesId) {
    final s = _manager.readSeries(seriesId);
    return s?.name ?? '未知剧集';
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _filteredTasks();
    final runningCount = _service.runningCount;
    final completedCount = _service.tasks.where((t) => t.phase == ImportPhase.done).length;
    final interruptedCount = _service.tasks.where((t) => t.phase == ImportPhase.interrupted || t.phase == ImportPhase.failed).length;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶栏：标题、清理按钮、关闭按钮
            Row(
              children: [
                Icon(Icons.assignment_outlined, size: 20, color: context.accentText),
                const SizedBox(width: 8),
                Text(
                  '小说导入任务中心',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_service.tasks.any((t) => !t.isRunning))
                  TextButton.icon(
                    onPressed: () async {
                      await _service.clearFinishedTasks();
                    },
                    icon: const Icon(Icons.clear_all, size: 15),
                    label: const Text('清理已结束', style: TextStyle(fontSize: 11)),
                  ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: '关闭',
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 分类过滤器 Pills
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterChip(_TaskFilter.all, '${_TaskFilter.all.label} (${_service.tasks.length})'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_TaskFilter.running, '${_TaskFilter.running.label} ($runningCount)'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_TaskFilter.completed, '${_TaskFilter.completed.label} ($completedCount)'),
                  const SizedBox(width: 8),
                  _buildFilterChip(_TaskFilter.interrupted, '${_TaskFilter.interrupted.label} ($interruptedCount)'),
                ],
              ),
            ),
            const SizedBox(height: 14),
            // 任务列表主体
            Flexible(
              child: tasks.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_outlined, size: 40, color: context.textDisabled),
                            const SizedBox(height: 10),
                            Text(
                              '暂无匹配的导入任务',
                              style: TextStyle(color: context.textTertiary, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: tasks.length,
                      itemBuilder: (ctx, i) {
                        final task = tasks[i];
                        return _TaskCard(
                          task: task,
                          seriesName: _seriesNameOf(task.seriesId),
                          onRetry: () {
                            Navigator.pop(context);
                            widget.onRetry?.call();
                          },
                          onViewResult: () {
                            Navigator.pop(context);
                            widget.onNavigateToSeries?.call(task.seriesId);
                          },
                          onDelete: () => _service.removeTask(task.localId),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(_TaskFilter filter, String label) {
    final selected = _filter == filter;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      labelStyle: TextStyle(
        fontSize: 11,
        color: selected ? context.accentText : context.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
      backgroundColor: context.bgInput,
      selectedColor: context.accentSubtle,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.seriesName,
    required this.onRetry,
    required this.onViewResult,
    required this.onDelete,
  });

  final NovelImportTask task;
  final String seriesName;
  final VoidCallback onRetry;
  final VoidCallback onViewResult;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDone = task.phase == ImportPhase.done;
    final isRunning = task.isRunning;
    final isInterrupted = task.phase == ImportPhase.interrupted;

    Color statusColor;
    IconData statusIcon;
    String statusTitle;

    if (isRunning) {
      statusColor = context.accentText;
      statusIcon = Icons.autorenew;
      statusTitle = [
        if (task.phase.passLabel.isNotEmpty) '${task.phase.passLabel} ',
        task.phase.label,
      ].join();
    } else if (isDone) {
      statusColor = context.successText;
      statusIcon = Icons.check_circle_outline;
      statusTitle = '已完成入库';
    } else if (isInterrupted) {
      statusColor = context.warningText;
      statusIcon = Icons.pause_circle_outline;
      statusTitle = '已中断';
    } else {
      statusColor = context.errorText;
      statusIcon = Icons.error_outline;
      statusTitle = '失败';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isRunning
              ? context.accentText.withAlpha(90)
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isRunning)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: statusColor,
                  ),
                )
              else
                Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '《${task.novelTitle}》',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  statusTitle,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '关联剧集：$seriesName · 模式：${task.scopeLabel}',
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 2),
          Text(
            [
              '提交时间：${_formatTime(task.startedAt)}',
              '已耗时：${task.elapsed.inSeconds}s',
              if (task.attempt > 1) '第 ${task.attempt} 次尝试',
            ].join(' · '),
            style: TextStyle(color: context.textTertiary, fontSize: 10),
          ),
          if (task.error != null && task.error!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: (isInterrupted ? context.warningText : context.errorText).withAlpha(15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                task.error!,
                style: TextStyle(
                  color: isInterrupted ? context.warningText : context.errorText,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          // 底部操作区
          Builder(
            builder: (context) {
              final targetEp = _resolveTargetEpisode();
              final hasContract = targetEp != null &&
                  (targetEp.scenes.isNotEmpty || targetEp.protectedContract.isNotEmpty);

              return Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isRunning)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 15),
                      tooltip: '删除记录',
                      visualDensity: VisualDensity.compact,
                    ),
                  if (isDone && hasContract) ...[
                    const SizedBox(width: 6),
                    OutlinedButton.icon(
                      onPressed: () => _showDramaContractDialog(context, targetEp),
                      icon: const Icon(Icons.theater_comedy_outlined, size: 13),
                      label: Text(
                        '场次与契约 (${targetEp.scenes.length}场/${targetEp.protectedContract.utterances.length}句)',
                        style: const TextStyle(fontSize: 10),
                      ),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ],
                  if (isDone) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: onViewResult,
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('查看产物', style: TextStyle(fontSize: 11)),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ],
                  if (isInterrupted || task.phase == ImportPhase.failed) ...[
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重新导入', style: TextStyle(fontSize: 11)),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  StudioEpisode? _resolveTargetEpisode() {
    final manager = StudioProjectManager.instance;
    final dir = manager.episodesDir(task.seriesId);
    if (!dir.existsSync()) return null;
    for (final entry in dir.listSync().whereType<Directory>()) {
      final ep = manager.readEpisode(task.seriesId, p.basename(entry.path));
      if (ep != null) {
        if (task.targetEpisodeIndex == null || ep.index == task.targetEpisodeIndex) {
          if (ep.scenes.isNotEmpty || ep.protectedContract.isNotEmpty) {
            return ep;
          }
        }
      }
    }
    return null;
  }

  void _showDramaContractDialog(BuildContext context, StudioEpisode ep) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.movie_filter_outlined, size: 20),
            const SizedBox(width: 8),
            Text('影视化改编资产 · ${ep.title}'),
          ],
        ),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (ep.scenes.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.view_carousel_outlined, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '场次规划 (${ep.scenes.length} 场)',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ...ep.scenes.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(80),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${s.id} · ${s.title.isNotEmpty ? s.title : s.location} (${s.timeOfDay})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                                ),
                                const Spacer(),
                                if (s.primaryLightWorldDirection.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Theme.of(ctx).colorScheme.primary.withAlpha(30),
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: Text(
                                      s.primaryLightWorldDirection,
                                      style: TextStyle(
                                        color: Theme.of(ctx).colorScheme.primary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (s.dramaticObjective.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '戏剧目标: ${s.dramaticObjective}',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                            if (s.beats.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: s.beats.map((b) => Chip(
                                  label: Text(
                                    '${b.id}: ${b.name.isNotEmpty ? b.name : b.action}${b.dramaticFunction.isNotEmpty ? ' (${b.dramaticFunction})' : ''}',
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                )).toList(),
                              ),
                            ],
                          ],
                        ),
                      )),
                  const Divider(height: 20),
                ],
                if (ep.protectedContract.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        '原著受保护契约清单',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (ep.protectedContract.utterances.isNotEmpty) ...[
                    const Text('【核心保真台词】', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ...ep.protectedContract.utterances.map((u) => Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 4),
                          child: Text(
                            '• 【${u.speaker}】: "${u.text}"',
                            style: const TextStyle(fontSize: 11),
                          ),
                        )),
                    const SizedBox(height: 6),
                  ],
                  if (ep.protectedContract.facts.isNotEmpty) ...[
                    const Text('【剧情基准事实】', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    ...ep.protectedContract.facts.map((f) => Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 4),
                          child: Text(
                            '• [${f.type.label}] ${f.content}${f.sourceLocation.isNotEmpty ? ' (${f.sourceLocation})' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        )),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }
}

/// 顶栏常驻「导入任务」入口按钮。
///
/// 无论是否有进行中任务均常驻显示，并根据当前状态反馈视觉信息：
/// - 空闲时：显示常规图标与文字，点击即可随时打开任务抽屉；
/// - 运行中：显示旋转进度圈与运行中数量角标；
/// - 有中断/失败：展示琥珀色告警小点。
class NovelTaskCenterButton extends StatelessWidget {
  const NovelTaskCenterButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final service = NovelImportTaskService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final runningCount = service.runningCount;
        final hasInterrupted = service.tasks.any(
          (t) => t.phase == ImportPhase.interrupted || t.phase == ImportPhase.failed,
        );

        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: runningCount > 0 ? context.accentSubtle : context.bgInput,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: runningCount > 0
                    ? context.accentText.withAlpha(90)
                    : (hasInterrupted ? context.warningText.withAlpha(90) : Colors.transparent),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (runningCount > 0)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: context.accentText,
                    ),
                  )
                else
                  Icon(
                    Icons.assignment_outlined,
                    size: 15,
                    color: hasInterrupted ? context.warningText : context.textSecondary,
                  ),
                const SizedBox(width: 5),
                Text(
                  runningCount > 0 ? '$runningCount 个导入中' : '导入任务',
                  style: TextStyle(
                    color: runningCount > 0
                        ? context.accentText
                        : (hasInterrupted ? context.warningText : context.textSecondary),
                    fontSize: 11,
                    fontWeight: runningCount > 0 ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
                if (hasInterrupted && runningCount == 0) ...[
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: context.warningText,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 兼容旧代码的角标组件封装（重定向到 [NovelTaskCenterButton]）。
class ImportTaskBadge extends StatelessWidget {
  const ImportTaskBadge({super.key, required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return NovelTaskCenterButton(onTap: onTap);
  }
}
