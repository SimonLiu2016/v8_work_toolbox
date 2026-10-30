/// 真实会议的列表栏与详情栏（概览 | 说话人与音色）。
///
/// 满足 `specs/listening-practice-workspace/spec.md` 的真实会议详情与条目状态要求：
/// - 列表栏提供搜索、状态标记（未合成 / 合成中 n/m / ● 已合成 / ⚠ n 组待更新 / ✕ n 组失败）、已听进度与右键菜单（重命名 / 删除 / 在 Finder 中显示）；
/// - 详情栏包含「概览」与「说话人与音色」两个页签，且整场会议只有**唯一一个**合成主操作按钮（随状态切换文案，进行中可取消）。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../services/listening_progress_store.dart';
import '../services/real_meetings_controller.dart';
import '../services/role_voice_map.dart';
import '../services/task_tracker.dart';

/// 真实会议列表操作项。
enum RealMeetingContextAction {
  rename,
  revealInFinder,
  delete,
}

/// 真实会议中间列表栏。
class RealMeetingListView extends StatelessWidget {
  final List<RealMeetingItemSnapshot> items;
  final String? selectedId;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSelect;
  final VoidCallback onImportNew;
  final void Function(RealMeetingItemSnapshot item, RealMeetingContextAction action)
      onContextAction;
  final WorkspaceTaskEntry? Function(String meetingId) bakeTaskFor;
  final ItemProgress? Function(String meetingId) progressFor;

  const RealMeetingListView({
    super.key,
    required this.items,
    required this.selectedId,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onSelect,
    required this.onImportNew,
    required this.onContextAction,
    required this.bakeTaskFor,
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
                key: const ValueKey('real-meeting-search'),
                onChanged: onSearchChanged,
                style: TextStyle(fontSize: 12, color: textPrimary),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: '搜索真实会议…',
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
                ? _buildEmptyList(context, textPrimary, textSecondary, accent)
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      final selected = item.meeting.id == selectedId;
                      final task = bakeTaskFor(item.meeting.id);
                      final prog = progressFor(item.meeting.id);
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
    Color accent,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.record_voice_over_outlined,
              size: 30,
              color: textSecondary,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery.trim().isNotEmpty ? '没有匹配的会议' : '还没有真实会议',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '导入会议记录系统的 Markdown 逐字稿，分配说话人音色后复听整场会议并插入回答练习',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
            const SizedBox(height: 12),
            if (searchQuery.trim().isEmpty)
              OutlinedButton.icon(
                key: const ValueKey('empty-real-meeting-import-btn'),
                onPressed: onImportNew,
                icon: const Icon(Icons.upload_file_outlined, size: 15),
                label: const Text('导入逐字稿'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    RealMeetingItemSnapshot item,
    bool selected,
    WorkspaceTaskEntry? activeTask,
    ItemProgress? progress,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final badge = item.statusBadge(activeTask: activeTask);
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
      final selectedAction = await showMenu<RealMeetingContextAction>(
        context: context,
        position: RelativeRect.fromRect(
          globalPos & const Size(1, 1),
          Offset.zero & overlay.size,
        ),
        items: const [
          PopupMenuItem(
            value: RealMeetingContextAction.rename,
            child: Text('重命名', style: TextStyle(fontSize: 12)),
          ),
          PopupMenuItem(
            value: RealMeetingContextAction.revealInFinder,
            child: Text('在 Finder 中显示', style: TextStyle(fontSize: 12)),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: RealMeetingContextAction.delete,
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
        key: ValueKey('real-meeting-item-${item.meeting.id}'),
        onTap: () => onSelect(item.meeting.id),
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
                      item.displayTitle,
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
                      '$badge · ${item.meeting.turns.length} 轮'
                      '${progressLabel != null ? " · $progressLabel" : ""}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<RealMeetingContextAction>(
                tooltip: '更多操作',
                padding: EdgeInsets.zero,
                iconSize: 16,
                icon: Icon(Icons.more_vert_rounded,
                    size: 16, color: textSecondary),
                onSelected: (action) => onContextAction(item, action),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: RealMeetingContextAction.rename,
                    child: Text('重命名', style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuItem(
                    value: RealMeetingContextAction.revealInFinder,
                    child: Text('在 Finder 中显示', style: TextStyle(fontSize: 12)),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: RealMeetingContextAction.delete,
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

/// 真实会议右侧详情栏（包含「概览」与「说话人与音色」两个页签）。
class RealMeetingDetail extends StatefulWidget {
  static const String _unmergeValue = '__unmerge__';

  final RealMeetingItemSnapshot? snapshot;
  final Clip? publishedClip;
  final bool isPlaying;
  final WorkspaceTaskEntry? activeTask;

  final VoidCallback onRunPrimaryAction;
  final VoidCallback onCancelBake;
  final VoidCallback onPlay;
  final VoidCallback onOpenTranscriptDrawer;
  final VoidCallback onRenameMeeting;
  final VoidCallback onOpenIdentity;

  final Future<void> Function(String slotId, String displayName) onRenameSpeaker;
  final Future<void> Function(String slotId, String voiceId) onVoiceChanged;
  final Future<void> Function(String slotId, bool isMe) onToggleMe;
  final Future<void> Function(String fromSlot, String intoSlot) onMergeSpeaker;
  final Future<void> Function(String slotId) onUnmergeSpeaker;

  const RealMeetingDetail({
    super.key,
    required this.snapshot,
    this.publishedClip,
    required this.isPlaying,
    this.activeTask,
    required this.onRunPrimaryAction,
    required this.onCancelBake,
    required this.onPlay,
    required this.onOpenTranscriptDrawer,
    required this.onRenameMeeting,
    required this.onOpenIdentity,
    required this.onRenameSpeaker,
    required this.onVoiceChanged,
    required this.onToggleMe,
    required this.onMergeSpeaker,
    required this.onUnmergeSpeaker,
  });

  @override
  State<RealMeetingDetail> createState() => _RealMeetingDetailState();
}

class _RealMeetingDetailState extends State<RealMeetingDetail> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final snap = widget.snapshot;
    if (snap == null) {
      return Center(
        child: Text(
          '请在左侧选择或导入一场真实会议',
          style: TextStyle(fontSize: 12, color: textSecondary),
        ),
      );
    }

    final isRunning = widget.activeTask?.running ?? false;
    final badge = snap.statusBadge(activeTask: widget.activeTask);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部会议标题 + 状态标记 + 唯一主操作
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            snap.displayTitle,
                            key: const ValueKey('real-meeting-detail-title'),
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
                          key: const ValueKey('real-meeting-rename-btn'),
                          tooltip: '重命名会议（不修改原稿）',
                          visualDensity: VisualDensity.compact,
                          iconSize: 16,
                          onPressed: widget.onRenameMeeting,
                          icon: Icon(
                            Icons.drive_file_rename_outline,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(fontSize: 11, color: accent),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (snap.hasPlayableClip) ...[
                    OutlinedButton.icon(
                      key: const ValueKey('real-meeting-play-btn'),
                      onPressed: widget.onPlay,
                      icon: Icon(
                        widget.isPlaying
                            ? Icons.graphic_eq_rounded
                            : Icons.play_arrow_rounded,
                        size: 16,
                      ),
                      label: Text(widget.isPlaying ? '正在播放' : '播放'),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (isRunning)
                    OutlinedButton.icon(
                      key: const ValueKey('real-meeting-cancel-bake-btn'),
                      onPressed: widget.onCancelBake,
                      icon: const Icon(Icons.close_rounded, size: 15),
                      label: Text(widget.activeTask?.label ?? '取消合成'),
                    )
                  else
                    FilledButton.icon(
                      key: const ValueKey('real-meeting-primary-action'),
                      onPressed: widget.onRunPrimaryAction,
                      icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                      label: Text(snap.primaryActionLabel),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTabChip(
                    key: const ValueKey('real-meeting-tab-overview'),
                    label: '概览',
                    selected: _tabIndex == 0,
                    onTap: () => setState(() => _tabIndex = 0),
                    accent: accent,
                    textPrimary: textPrimary,
                  ),
                  const SizedBox(width: 8),
                  _buildTabChip(
                    key: const ValueKey('real-meeting-tab-speakers'),
                    label: '说话人与音色 (${snap.meeting.slots.length})',
                    selected: _tabIndex == 1,
                    onTap: () => setState(() => _tabIndex = 1),
                    accent: accent,
                    textPrimary: textPrimary,
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: _tabIndex == 0
              ? _buildOverviewTab(
                  context,
                  snap,
                  border,
                  textPrimary,
                  textSecondary,
                  accent,
                )
              : _buildSpeakersTab(
                  context,
                  snap,
                  border,
                  textPrimary,
                  textSecondary,
                  accent,
                ),
        ),
      ],
    );
  }

  Widget _buildTabChip({
    required Key key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
    required Color textPrimary,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? accent : textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewTab(
    BuildContext context,
    RealMeetingItemSnapshot snap,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final clip = widget.publishedClip;
    final durText = clip != null && clip.durationMs > 0
        ? _formatDuration(clip.durationMs)
        : '待合成';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: AppTheme.borderRadiusSmall,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '会议摘要',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _kv('文稿原名', snap.meeting.title, textPrimary, textSecondary),
                    _kv('发言轮数', '${snap.meeting.turns.length} 轮', textPrimary,
                        textSecondary),
                    _kv('说话人槽位', '${snap.meeting.slots.length} 人', textPrimary,
                        textSecondary),
                    _kv('音频时长', durText, textPrimary, textSecondary),
                  ],
                ),
                if (snap.hasPlayableClip) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          widget.onPlay();
                          widget.onOpenTranscriptDrawer();
                        },
                        icon: const Icon(Icons.menu_book_rounded, size: 15),
                        label: const Text('边听边看精听文稿 / 插入我的回答'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '对话预览（前 ${snap.meeting.turns.take(12).length} 轮）',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final turn in snap.meeting.turns.take(12))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${snap.speakers[turn.slotId]?.displayName ?? turn.slotId}:',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      turn.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: textPrimary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(
    String k,
    String v,
    Color textPrimary,
    Color textSecondary,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 10, color: textSecondary)),
        const SizedBox(height: 2),
        Text(
          v,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildSpeakersTab(
    BuildContext context,
    RealMeetingItemSnapshot snap,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '说话人（改名与音色都可随时修改，原稿不动；修改后点右上角主操作按钮即可重新合成）',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
              OutlinedButton.icon(
                key: const ValueKey('real-meeting-identity-btn'),
                onPressed: widget.onOpenIdentity,
                icon: const Icon(Icons.person_outline, size: 15),
                label: const Text('我的身份'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            children: [
              for (final slot in snap.meeting.slots)
                _buildSpeakerRow(
                  context,
                  snap,
                  slot.id,
                  textPrimary,
                  textSecondary,
                  border,
                  accent,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSpeakerRow(
    BuildContext context,
    RealMeetingItemSnapshot snap,
    String slotId,
    Color textPrimary,
    Color textSecondary,
    Color border,
    Color accent,
  ) {
    final resolved = snap.speakers[slotId];
    final name = resolved?.displayName ?? slotId;
    final isMe = resolved?.isMe ?? false;
    final voiceId = resolved?.voiceId ?? '';
    final inPool = VoicePool.byId(voiceId) != null;
    final mergedInto = snap.mergeInto[slotId];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(
              slotId,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ),
          SizedBox(
            width: 150,
            height: 30,
            child: TextFormField(
              key: ValueKey('speaker-name-$slotId-$name'),
              initialValue: name,
              style: TextStyle(fontSize: 12, color: textPrimary),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide(color: border),
                ),
              ),
              onFieldSubmitted: (v) {
                final trimmed = v.trim();
                if (trimmed.isEmpty || trimmed == name) return;
                widget.onRenameSpeaker(slotId, trimmed);
              },
            ),
          ),
          const SizedBox(width: 10),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: voiceId.isEmpty ? null : voiceId,
              isDense: true,
              style: TextStyle(fontSize: 11, color: textPrimary),
              items: [
                if (!inPool && voiceId.isNotEmpty)
                  DropdownMenuItem(
                    value: voiceId,
                    child: Text(
                      '$voiceId（自动）',
                      style: TextStyle(fontSize: 11, color: textPrimary),
                    ),
                  ),
                for (final v in VoicePool.all)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text(
                      '${v.label} · ${v.gender == VoiceGender.male ? "男" : "女"}',
                      style: TextStyle(fontSize: 11, color: textPrimary),
                    ),
                  ),
              ],
              onChanged: isMe
                  ? null
                  : (v) {
                      if (v != null) widget.onVoiceChanged(slotId, v);
                    },
            ),
          ),
          const Spacer(),
          if (mergedInto != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                '→ $mergedInto',
                style: TextStyle(fontSize: 10, color: accent),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: '合并到别人 / 取消合并',
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: Icon(Icons.merge_type, size: 16, color: textSecondary),
            onSelected: (v) {
              if (v == RealMeetingDetail._unmergeValue) {
                widget.onUnmergeSpeaker(slotId);
              } else {
                widget.onMergeSpeaker(slotId, v);
              }
            },
            itemBuilder: (ctx) => [
              if (mergedInto != null)
                const PopupMenuItem(
                  value: RealMeetingDetail._unmergeValue,
                  child: Text('取消合并', style: TextStyle(fontSize: 12)),
                ),
              for (final other in snap.meeting.slots)
                if (other.id != slotId && other.id != mergedInto)
                  PopupMenuItem(
                    value: other.id,
                    child: Text(
                      '合并到 ${other.id}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('是我', style: TextStyle(fontSize: 10, color: textSecondary)),
              Switch(
                value: isMe,
                onChanged: (v) => widget.onToggleMe(slotId, v),
              ),
            ],
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

/// 在 Finder 中定位原始文件。
Future<void> revealFileInFinder(String path) async {
  if (path.isEmpty) return;
  try {
    if (Platform.isMacOS) {
      await Process.run('open', ['-R', path]);
    }
  } catch (_) {}
}
