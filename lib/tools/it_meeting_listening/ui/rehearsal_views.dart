/// 多场排练的列表栏与详情栏（横向四步条 + 讲稿编辑器）。
///
/// 满足 `specs/listening-practice-workspace/spec.md` 的多场排练、排练步骤条與讲稿编辑要求：
/// - 排练列表按最近修改时间倒序排列，显示当前步骤或"可收听"标记、目标时长、已听进度与右键菜单；
/// - 排练详情展示横向四步条（材料 → 讲稿 → 剧本 → 语音），状态覆盖 未开始 / 进行中 / 已完成 / 失败 / 已过期；
/// - 讲稿步骤提供完整编辑器（修改标题、修改各节标题与正文、新增/删除/上下移动节、显式保存与未保存提示）。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/rehearsal_models.dart';
import '../services/listening_progress_store.dart';
import '../services/task_tracker.dart';
import 'material_import_panel.dart';

/// 排练列表操作项。
enum RehearsalContextAction {
  rename,
  revealInFinder,
  delete,
}

/// 单个步骤在横向步骤条上的状态。
enum RehearsalStepperNodeState {
  notStarted('未开始'),
  running('进行中'),
  done('已完成'),
  failed('失败'),
  stale('已过期');

  final String label;
  const RehearsalStepperNodeState(this.label);
}

/// 多场排练中间列表栏。
class RehearsalListView extends StatelessWidget {
  final List<RehearsalStatusInfo> items;
  final String? selectedId;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreateNew;
  final void Function(RehearsalStatusInfo item, RehearsalContextAction action)
      onContextAction;
  final WorkspaceTaskEntry? Function(String materialId) taskFor;
  final ItemProgress? Function(String clipId) progressFor;

  const RehearsalListView({
    super.key,
    required this.items,
    required this.selectedId,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onCreateNew,
    required this.onContextAction,
    required this.taskFor,
    required this.progressFor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bgCard = isDark ? context.bgCard : AppTheme.lightBgCard;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    return Container(
      width: 260,
      color: bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: SizedBox(
              height: 32,
              child: TextField(
                key: const ValueKey('rehearsal-search'),
                onChanged: onSearchChanged,
                style: TextStyle(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索排练会议…',
                  hintStyle: TextStyle(fontSize: 12, color: textSecondary),
                  prefixIcon:
                      Icon(Icons.search_rounded, size: 15, color: textSecondary),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: border),
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: border),
          Expanded(
            child: items.isEmpty
                ? _buildEmptyList(context, textPrimary, textSecondary)
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final selected = item.material.id == selectedId;
                      final task = taskFor(item.material.id);
                      final prog = progressFor(item.clipId);
                      return _buildListItem(
                        context,
                        item,
                        selected,
                        task,
                        prog,
                        border,
                        textPrimary,
                        textSecondary,
                        accent,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyList(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.campaign_outlined, size: 30, color: textSecondary),
            const SizedBox(height: 8),
            Text(
              searchQuery.trim().isNotEmpty ? '没有匹配的排练' : '还没有会议排练',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '导入周会或专项汇报材料，生成英文讲稿与 5 角色模拟问答，会前预听整场表现',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
            const SizedBox(height: 12),
            if (searchQuery.trim().isEmpty)
              OutlinedButton.icon(
                key: const ValueKey('empty-rehearsal-create-btn'),
                onPressed: onCreateNew,
                icon: const Icon(Icons.upload_file_outlined, size: 15),
                label: const Text('新建排练'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    RehearsalStatusInfo item,
    bool selected,
    WorkspaceTaskEntry? task,
    ItemProgress? progress,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final badge = (task != null && task.running)
        ? (task.total > 0 ? '进行中 ${task.done}/${task.total}' : '进行中…')
        : item.stage.badgeLabel;
    final pct = progress == null ? 0 : (progress.ratio * 100).round();
    final progressLabel = progress == null
        ? null
        : (progress.isCompleted
            ? '已听完'
            : (pct > 0 ? '已听 $pct%' : null));

    Future<void> showContextMenu(Offset globalPos) async {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox?;
      if (overlay == null) return;
      final selectedAction = await showMenu<RehearsalContextAction>(
        context: context,
        position: RelativeRect.fromRect(
          globalPos & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            value: RehearsalContextAction.rename,
            child: Text('重命名', style: TextStyle(fontSize: 12)),
          ),
          PopupMenuItem(
            value: RehearsalContextAction.revealInFinder,
            child: Text('在 Finder 中显示', style: TextStyle(fontSize: 12)),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: RehearsalContextAction.delete,
            child: Text('删除', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
      if (selectedAction != null) {
        onContextAction(item, selectedAction);
      }
    }

    return GestureDetector(
      onSecondaryTapUp: (details) => showContextMenu(details.globalPosition),
      child: InkWell(
        key: ValueKey('rehearsal-item-${item.material.id}'),
        onTap: () => onSelect(item.material.id),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          decoration: BoxDecoration(
            color: selected ? context.bgSelected : Colors.transparent,
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.material.effectiveTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? accent : textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$badge · ${item.material.targetMinutes} 分钟'
                      '${progressLabel != null ? " · $progressLabel" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<RehearsalContextAction>(
                tooltip: '更多操作',
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(Icons.more_vert_rounded,
                    size: 16, color: textSecondary),
                onSelected: (action) => onContextAction(item, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: RehearsalContextAction.rename,
                    child: Text('重命名', style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuItem(
                    value: RehearsalContextAction.revealInFinder,
                    child: Text('在 Finder 中显示', style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: RehearsalContextAction.delete,
                    child: Text('删除', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排练详情视图（横向四步条 + 当前步骤内容 + 讲稿编辑器）。
class RehearsalDetail extends StatelessWidget {
  final RehearsalStatusInfo? item;
  final RehearsalStep activeStep;
  final ValueChanged<RehearsalStep> onSelectStep;
  final bool Function(RehearsalStep step) canRunStep;
  final String? Function(RehearsalStep step) stepMessageFor;
  final WorkspaceTaskEntry? activeTask;
  final bool isPlaying;

  final VoidCallback onRename;
  final ValueChanged<int> onTargetMinutesChanged;
  final VoidCallback onReimportMaterial;
  final VoidCallback onGenerateDraft;
  final VoidCallback onGenerateScript;
  final VoidCallback onBakeAudio;
  final VoidCallback onPlay;
  final VoidCallback onOpenTranscriptDrawer;

  // ---- 讲稿编辑状态与回调 ----
  final bool hasUnsavedDraft;
  final String workingDraftTitle;
  final List<DraftSection> workingDraftSections;
  final ValueChanged<String> onDraftTitleChanged;
  final void Function(int index, {String? title, String? body})
      onDraftSectionChanged;
  final VoidCallback onAddDraftSection;
  final ValueChanged<int> onRemoveDraftSection;
  final void Function(int fromIndex, int toIndex) onMoveDraftSection;
  final VoidCallback onSaveDraft;
  final VoidCallback onDiscardDraft;

  const RehearsalDetail({
    super.key,
    required this.item,
    required this.activeStep,
    required this.onSelectStep,
    required this.canRunStep,
    required this.stepMessageFor,
    this.activeTask,
    required this.isPlaying,
    required this.onRename,
    required this.onTargetMinutesChanged,
    required this.onReimportMaterial,
    required this.onGenerateDraft,
    required this.onGenerateScript,
    required this.onBakeAudio,
    required this.onPlay,
    required this.onOpenTranscriptDrawer,
    required this.hasUnsavedDraft,
    required this.workingDraftTitle,
    required this.workingDraftSections,
    required this.onDraftTitleChanged,
    required this.onDraftSectionChanged,
    required this.onAddDraftSection,
    required this.onRemoveDraftSection,
    required this.onMoveDraftSection,
    required this.onSaveDraft,
    required this.onDiscardDraft,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final info = item;
    if (info == null) {
      return Center(
        child: Text(
          '请在左侧选择或新建一场排练',
          style: TextStyle(fontSize: 12, color: textSecondary),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTopHeader(
          context,
          info,
          border,
          textPrimary,
          textSecondary,
          accent,
        ),
        _buildHorizontalStepper(
          context,
          info,
          border,
          textPrimary,
          textSecondary,
          accent,
        ),
        Expanded(
          child: switch (activeStep) {
            RehearsalStep.material => _buildMaterialStep(
                context,
                info,
                border,
                textPrimary,
                textSecondary,
                accent,
              ),
            RehearsalStep.draft => _buildDraftStep(
                context,
                info,
                border,
                textPrimary,
                textSecondary,
                accent,
              ),
            RehearsalStep.script => _buildScriptStep(
                context,
                info,
                border,
                textPrimary,
                textSecondary,
                accent,
              ),
            RehearsalStep.audio => _buildAudioStep(
                context,
                info,
                border,
                textPrimary,
                textSecondary,
                accent,
              ),
          },
        ),
      ],
    );
  }

  Widget _buildTopHeader(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  info.material.effectiveTitle,
                  key: const ValueKey('rehearsal-detail-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                key: const ValueKey('rehearsal-rename-btn'),
                tooltip: '重命名排练',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: onRename,
                icon: Icon(
                  Icons.drive_file_rename_outline,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '目标时长',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              for (final minutes in const [30, 60])
                ChoiceChip(
                  key: ValueKey('rehearsal-target-$minutes'),
                  label: Text(
                    '$minutes 分钟',
                    style: TextStyle(
                      fontSize: 11,
                      color: info.material.targetMinutes == minutes
                          ? accent
                          : textPrimary,
                    ),
                  ),
                  selected: info.material.targetMinutes == minutes,
                  onSelected: (_) => onTargetMinutesChanged(minutes),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
              if (info.hasPlayableAudio)
                FilledButton.tonalIcon(
                  key: const ValueKey('rehearsal-play-btn'),
                  onPressed: onPlay,
                  icon: Icon(
                    isPlaying
                        ? Icons.graphic_eq_rounded
                        : Icons.play_arrow_rounded,
                    size: 16,
                  ),
                  label: Text(isPlaying ? '正在播放' : '播放排练'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  RehearsalStepperNodeState _nodeStateFor(
    RehearsalStatusInfo info,
    RehearsalStep step,
  ) {
    final running = activeTask?.running ?? false;
    final err = stepMessageFor(step);
    if (running && activeStep == step) {
      return RehearsalStepperNodeState.running;
    }
    switch (step) {
      case RehearsalStep.material:
        return RehearsalStepperNodeState.done;
      case RehearsalStep.draft:
        if (err != null && info.draft == null) {
          return RehearsalStepperNodeState.failed;
        }
        return info.draft != null
            ? RehearsalStepperNodeState.done
            : RehearsalStepperNodeState.notStarted;
      case RehearsalStep.script:
        if (info.isScriptStale) return RehearsalStepperNodeState.stale;
        if (err != null && info.script == null) {
          return RehearsalStepperNodeState.failed;
        }
        return info.script != null
            ? RehearsalStepperNodeState.done
            : RehearsalStepperNodeState.notStarted;
      case RehearsalStep.audio:
        if (err != null && !info.hasPlayableAudio) {
          return RehearsalStepperNodeState.failed;
        }
        return info.hasPlayableAudio
            ? RehearsalStepperNodeState.done
            : RehearsalStepperNodeState.notStarted;
    }
  }

  Widget _buildHorizontalStepper(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < RehearsalStep.values.length; i++) ...[
              if (i > 0)
                Container(
                  width: 20,
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: border,
                ),
              _buildStepTab(
                context,
                index: i + 1,
                step: RehearsalStep.values[i],
                state: _nodeStateFor(info, RehearsalStep.values[i]),
                selected: activeStep == RehearsalStep.values[i],
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                border: border,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStepTab(
    BuildContext context, {
    required int index,
    required RehearsalStep step,
    required RehearsalStepperNodeState state,
    required bool selected,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
  }) {
    final statusIcon = switch (state) {
      RehearsalStepperNodeState.done => Icons.check_circle_rounded,
      RehearsalStepperNodeState.running => Icons.sync_rounded,
      RehearsalStepperNodeState.failed => Icons.error_outline_rounded,
      RehearsalStepperNodeState.stale => Icons.warning_amber_rounded,
      RehearsalStepperNodeState.notStarted => Icons.radio_button_unchecked,
    };
    final statusColor = switch (state) {
      RehearsalStepperNodeState.done => accent,
      RehearsalStepperNodeState.running => accent,
      RehearsalStepperNodeState.failed => Colors.redAccent,
      RehearsalStepperNodeState.stale => Colors.orangeAccent,
      RehearsalStepperNodeState.notStarted => textSecondary,
    };

    return InkWell(
      key: ValueKey('rehearsal-step-tab-${step.name}'),
      onTap: () => onSelectStep(step),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? accent : border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(statusIcon, size: 15, color: statusColor),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$index. ${step.label}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? accent : textPrimary,
                  ),
                ),
                Text(
                  state.label,
                  style: TextStyle(fontSize: 10, color: statusColor),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialStep(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '来源文件：${info.material.fileName} · ${info.material.charCount} 字符',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('rehearsal-reimport-material-btn'),
                onPressed: canRunStep(RehearsalStep.material)
                    ? onReimportMaterial
                    : null,
                icon: const Icon(Icons.upload_file_outlined, size: 15),
                label: const Text('重新导入材料'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => onSelectStep(RehearsalStep.draft),
                icon: const Icon(Icons.arrow_forward_rounded, size: 15),
                label: const Text('下一步：讲稿'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: AppTheme.borderRadiusSmall,
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  info.material.text,
                  style: TextStyle(fontSize: 12, height: 1.5, color: textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftStep(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final draft = info.draft;
    final running = activeTask?.running ?? false;
    final err = stepMessageFor(RehearsalStep.draft);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (hasUnsavedDraft) ...[
                Container(
                  key: const ValueKey('draft-dirty-badge'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orangeAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '● 有未保存的修改',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.orangeAccent,
                    ),
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('save-draft-btn'),
                  onPressed: onSaveDraft,
                  icon: const Icon(Icons.save_outlined, size: 15),
                  label: const Text('保存讲稿'),
                ),
                TextButton(
                  key: const ValueKey('discard-draft-btn'),
                  onPressed: onDiscardDraft,
                  child: const Text('放弃修改'),
                ),
              ] else if (draft != null)
                Text(
                  '共 ${workingDraftSections.length} 节${draft.isEdited ? " · 已手工编辑" : ""}',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                )
              else
                Text(
                  '尚未生成讲稿',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              if (draft != null)
                OutlinedButton.icon(
                  key: const ValueKey('draft-add-section-btn'),
                  onPressed: onAddDraftSection,
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text('新增一节'),
                ),
              if (running)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      activeTask?.label ?? '正在生成讲稿…',
                      style: TextStyle(fontSize: 12, color: accent),
                    ),
                  ],
                )
              else
                FilledButton.tonalIcon(
                  key: const ValueKey('generate-draft-btn'),
                  onPressed: canRunStep(RehearsalStep.draft)
                      ? onGenerateDraft
                      : null,
                  icon: const Icon(Icons.auto_awesome_outlined, size: 15),
                  label: Text(draft == null ? '生成讲稿' : '重新生成讲稿'),
                ),
            ],
          ),
          if (err != null) ...[
            const SizedBox(height: 8),
            Text(err, style: TextStyle(fontSize: 11, color: accent)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: draft == null
                ? Center(
                    child: Text(
                      '点击右上角「生成讲稿」，由会议材料生成 Simon 第一人称英文汇报讲稿；生成后可在此直接编辑各节内容',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  )
                : ListView(
                    children: [
                      TextFormField(
                        key: const ValueKey('draft-title-field'),
                        initialValue: workingDraftTitle,
                        onChanged: onDraftTitleChanged,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: '讲稿标题',
                          isDense: true,
                          border: OutlineInputBorder(
                            borderSide: BorderSide(color: border),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (var i = 0; i < workingDraftSections.length; i++)
                        _DraftSectionCard(
                          key: ValueKey(
                              'draft-sec-${info.material.id}-${draft.id}-$i'),
                          index: i,
                          total: workingDraftSections.length,
                          section: workingDraftSections[i],
                          border: border,
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                          onTitleChanged: (v) =>
                              onDraftSectionChanged(i, title: v),
                          onBodyChanged: (v) =>
                              onDraftSectionChanged(i, body: v),
                          onMoveUp: i > 0
                              ? () => onMoveDraftSection(i, i - 1)
                              : null,
                          onMoveDown: i < workingDraftSections.length - 1
                              ? () => onMoveDraftSection(i, i + 1)
                              : null,
                          onDelete: () => onRemoveDraftSection(i),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildScriptStep(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final script = info.script;
    final running = activeTask?.running ?? false;
    final msg = stepMessageFor(RehearsalStep.script);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (info.isScriptStale)
            Container(
              key: const ValueKey('script-stale-banner'),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orangeAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '当前剧本基于旧版讲稿（讲稿已修改保存）。现有剧本与音频仍可查看和播放，可按需重新生成剧本。',
                      style: TextStyle(fontSize: 12, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  script == null
                      ? (info.draft == null
                          ? '请先在「2. 讲稿」步骤生成讲稿'
                          : '基于讲稿生成 5 角色（Simon / xiaofeng / songyang / deepan / Josh）模拟会议剧本')
                      : '共 ${script.turns.length} 轮 · 预估 ${script.estimatedMs ~/ 60000} 分钟 · 目标 ${script.targetMinutes} 分钟',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
              ),
              if (running)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      activeTask?.label ?? '正在生成剧本…',
                      style: TextStyle(fontSize: 12, color: accent),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  key: const ValueKey('generate-script-btn'),
                  onPressed: canRunStep(RehearsalStep.script)
                      ? onGenerateScript
                      : null,
                  icon: const Icon(Icons.groups_outlined, size: 16),
                  label: Text(script == null ? '生成剧本' : '重新生成剧本'),
                ),
            ],
          ),
          if (msg != null) ...[
            const SizedBox(height: 8),
            Text(msg, style: TextStyle(fontSize: 11, color: accent)),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: script == null
                ? Center(
                    child: Text(
                      '尚无剧本内容',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  )
                : ListView.builder(
                    itemCount: script.turns.length,
                    itemBuilder: (context, i) {
                      final turn = script.turns[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: border),
                          borderRadius: AppTheme.borderRadiusSmall,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 110,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    turn.role.speaker,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: accent,
                                    ),
                                  ),
                                  Text(
                                    '${turn.phase.label} · #${i + 1}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Text(
                                turn.text,
                                style:
                                    TextStyle(fontSize: 12, color: textPrimary),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAudioStep(
    BuildContext context,
    RehearsalStatusInfo info,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final running = activeTask?.running ?? false;
    final msg = stepMessageFor(RehearsalStep.audio);
    final clip = info.clip;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.hasPlayableAudio
                      ? '整场排练语音已就绪（时长 ${_formatDuration(clip!.durationMs)} · ${clip.turns.length} 轮）'
                      : (info.script == null
                          ? '请先完成「3. 剧本」步骤'
                          : '剧本已就绪，点击下方按钮逐回合合成整场排练语音'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                if (msg != null) ...[
                  const SizedBox(height: 8),
                  Text(msg, style: TextStyle(fontSize: 11, color: accent)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    if (running) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          activeTask?.label ?? '正在合成语音…',
                          style: TextStyle(fontSize: 12, color: accent),
                        ),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        key: const ValueKey('bake-rehearsal-audio-btn'),
                        onPressed: canRunStep(RehearsalStep.audio)
                            ? onBakeAudio
                            : null,
                        icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                        label: Text(
                          info.hasPlayableAudio ? '重新合成语音' : '合成语音',
                        ),
                      ),
                      if (info.hasPlayableAudio) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          key: const ValueKey('rehearsal-audio-step-play-btn'),
                          onPressed: () {
                            onPlay();
                            onOpenTranscriptDrawer();
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 16),
                          label: const Text('开始播放并打开精听抽屉'),
                        ),
                      ],
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}

class _DraftSectionCard extends StatefulWidget {
  final int index;
  final int total;
  final DraftSection section;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onBodyChanged;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onDelete;

  const _DraftSectionCard({
    super.key,
    required this.index,
    required this.total,
    required this.section,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.onTitleChanged,
    required this.onBodyChanged,
    this.onMoveUp,
    this.onMoveDown,
    required this.onDelete,
  });

  @override
  State<_DraftSectionCard> createState() => _DraftSectionCardState();
}

class _DraftSectionCardState extends State<_DraftSectionCard> {
  late TextEditingController _titleCtrl;
  late TextEditingController _bodyCtrl;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.section.title);
    _bodyCtrl = TextEditingController(text: widget.section.body);
  }

  @override
  void didUpdateWidget(covariant _DraftSectionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.title != widget.section.title &&
        _titleCtrl.text != widget.section.title) {
      _titleCtrl.text = widget.section.title;
    }
    if (oldWidget.section.body != widget.section.body &&
        _bodyCtrl.text != widget.section.body) {
      _bodyCtrl.text = widget.section.body;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: widget.border),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '第 ${widget.index + 1} 节',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: widget.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    key: ValueKey('draft-section-title-${widget.index}'),
                    controller: _titleCtrl,
                    onChanged: widget.onTitleChanged,
                    style: TextStyle(fontSize: 12, color: widget.textPrimary),
                    decoration: InputDecoration(
                      hintText: '小节议题名',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: widget.border),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: ValueKey('draft-section-up-${widget.index}'),
                tooltip: '上移该节',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: widget.onMoveUp,
                icon: Icon(Icons.arrow_upward_rounded,
                    color: widget.textSecondary),
              ),
              IconButton(
                key: ValueKey('draft-section-down-${widget.index}'),
                tooltip: '下移该节',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: widget.onMoveDown,
                icon: Icon(Icons.arrow_downward_rounded,
                    color: widget.textSecondary),
              ),
              IconButton(
                key: ValueKey('draft-section-delete-${widget.index}'),
                tooltip: '删除该节',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                onPressed: widget.onDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: widget.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            key: ValueKey('draft-section-body-${widget.index}'),
            controller: _bodyCtrl,
            onChanged: widget.onBodyChanged,
            minLines: 2,
            maxLines: 6,
            style: TextStyle(fontSize: 12, height: 1.45, color: widget.textPrimary),
            decoration: InputDecoration(
              hintText: '英文汇报讲稿正文…',
              isDense: true,
              contentPadding: const EdgeInsets.all(10),
              border: OutlineInputBorder(
                borderSide: BorderSide(color: widget.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
