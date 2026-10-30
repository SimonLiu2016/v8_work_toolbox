/// 真实会议面板：导入、会议选择、说话人设定、合成入口。
///
/// **为什么和排练面板一样做成"宿主提供回调"**：面板不持有服务，只负责渲染与
/// 收集输入。这样它的行为可以被 widget 测试覆盖，而不必拉起 TTS 与文件系统。
///
/// 默认收起为一行入口——上班时它不该占位置。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/real_meeting_models.dart';
import '../services/role_voice_map.dart';
import '../services/speaker_profile_resolver.dart';

/// 真实会议面板。
class RealMeetingPanel extends StatefulWidget {
  /// 「取消合并」菜单项的哨兵值（不是槽位 id）。
  static const String _unmergeValue = '__unmerge__';

  final bool expanded;
  final VoidCallback onToggleExpanded;

  /// 已导入的会议列表。
  final List<RealMeeting> meetings;

  /// 当前选中的会议标识。
  final String? selectedId;

  /// 当前选中的会议（未选择时为 null）。
  final RealMeeting? meeting;

  /// 已解析的说话人。
  final Map<String, ResolvedSpeaker> speakers;

  /// 合并映射：被合并的槽位 → 目标槽位。
  final Map<String, String> mergeInto;

  /// 把某个槽位合并到另一个槽位。
  final Future<void> Function(String fromSlot, String intoSlot) onMerge;

  /// 取消某个槽位的合并。
  final Future<void> Function(String slotId) onUnmerge;

  /// 重命名当前会议（传空串表示恢复文稿标题）。
  final Future<void> Function(String title) onRenameMeeting;

  /// 合成状态（用于显示进度与失败组）。
  final MeetingBakeState? bakeState;

  /// 正在合成的进度（{done, total}）；未合成时为 null。
  final ({int done, int total})? progress;

  /// 正在导入（只禁用导入按钮）。
  final bool importing;

  /// 正在合成或重新合成（只禁用合成相关按钮）。
  final bool baking;

  /// 音频与设定不一致的组数（0 表示不显示提示）。
  final int pendingGroupCount;

  /// 重新合成的进度。
  final ({int done, int total})? rebakeProgress;

  final Future<void> Function() onRebake;
  final VoidCallback onCancelRebake;

  final Future<void> Function() onPick;
  final void Function(String meetingId) onSelect;
  final Future<void> Function(String slotId, String displayName) onRename;
  final Future<void> Function(String slotId, String voiceId) onVoice;
  final Future<void> Function(String slotId, bool isMe) onToggleMe;
  final Future<void> Function() onBake;
  final VoidCallback onOpenIdentity;

  const RealMeetingPanel({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.meetings,
    required this.selectedId,
    required this.meeting,
    required this.mergeInto,
    required this.onMerge,
    required this.onUnmerge,
    required this.onRenameMeeting,
    required this.speakers,
    required this.bakeState,
    required this.importing,
    required this.baking,
    required this.pendingGroupCount,
    required this.rebakeProgress,
    required this.onRebake,
    required this.onCancelRebake,
    required this.onPick,
    required this.onSelect,
    required this.onRename,
    required this.onVoice,
    required this.onToggleMe,
    required this.onBake,
    required this.onOpenIdentity,
    this.progress,
  });

  @override
  State<RealMeetingPanel> createState() => _RealMeetingPanelState();
}

class _RealMeetingPanelState extends State<RealMeetingPanel> {
  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary = isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final meeting = widget.meeting;
    final state = widget.bakeState;

    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onToggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.record_voice_over_outlined, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Text('真实会议',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: textPrimary)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meeting == null
                          ? '导入会议记录系统的逐字稿'
                          : '${meeting.title} · ${meeting.turns.length} 轮'
                              '${state == null ? '' : ' · ${state.failedGroupCount == 0 ? '已合成' : '${state.failedGroupCount} 组失败'}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                  ),
                  Icon(widget.expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18, color: textSecondary),
                ],
              ),
            ),
          ),
          if (widget.expanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.importing ? null : () => widget.onPick(),
                    icon: const Icon(Icons.upload_file_outlined, size: 16),
                    label: const Text('导入逐字稿'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.meeting == null || widget.baking
                        ? null
                        : () => widget.onBake(),
                    icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                    label: Text(state == null ? '合成语音' : '重新合成'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.meeting == null
                        ? null
                        : () => widget.onRenameMeeting(widget.meeting!.title),
                    icon: const Icon(Icons.drive_file_rename_outline, size: 16),
                    label: const Text('重命名'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenIdentity,
                    icon: const Icon(Icons.person_outline, size: 16),
                    label: const Text('我的身份'),
                  ),
                  const Spacer(),
                  if (widget.progress != null)
                    Text(
                      '合成中 ${widget.progress!.done}/${widget.progress!.total}',
                      style: TextStyle(fontSize: 11, color: accent),
                    ),
                ],
              ),
            ),
            if (widget.meetings.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final m in widget.meetings)
                      _chip(
                        label: m.title,
                        selected: m.id == widget.selectedId,
                        onTap: () => widget.onSelect(m.id),
                        accent: accent,
                        textPrimary: textPrimary,
                        border: border,
                      ),
                  ],
                ),
              ),
            if (meeting != null && widget.pendingGroupCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.rebakeProgress != null
                              ? '正在重新合成 ${widget.rebakeProgress!.done}/${widget.rebakeProgress!.total} 组'
                              : '${widget.pendingGroupCount} 组音频待更新（当前仍是旧音色）',
                          style: TextStyle(fontSize: 11, color: textPrimary),
                        ),
                      ),
                      if (widget.rebakeProgress != null)
                        TextButton(
                          onPressed: widget.onCancelRebake,
                          child: const Text('取消'),
                        )
                      else
                        FilledButton.tonal(
                          onPressed: widget.baking ? null : () => widget.onRebake(),
                          child: const Text('重新合成'),
                        ),
                    ],
                  ),
                ),
              ),
            if (meeting != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
                child: Text('说话人（改名与音色都可随时改，原稿不动）',
                    style: TextStyle(fontSize: 10, color: textSecondary)),
              ),
              for (final slot in meeting.slots)
                _speakerRow(context, slot.id, textPrimary, textSecondary,
                    border, accent),
              const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
    required Color textPrimary,
    required Color border,
  }) =>
      InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(color: selected ? accent : border),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 10, color: selected ? accent : textPrimary)),
        ),
      );

  Widget _speakerRow(BuildContext context, String slotId, Color textPrimary,
      Color textSecondary, Color border, Color accent) {
    final resolved = widget.speakers[slotId];
    final name = resolved?.displayName ?? slotId;
    final isMe = resolved?.isMe ?? false;
    // 散列兜底音色不一定在音色池里（池子只有 9 个），而 DropdownButton 的
    // value 必须在 items 里。不在池中就补一个只读项，让用户看得见实际用的是
    // 哪个音色，而不是显示成"未选择"。
    final voiceId = resolved?.voiceId ?? '';
    final inPool = VoicePool.byId(voiceId) != null;
    final mergedInto = widget.mergeInto[slotId];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(slotId,
                style: TextStyle(fontSize: 11, color: textSecondary)),
          ),
          SizedBox(
            width: 150,
            height: 30,
            child: TextFormField(
              // 每次槽位或当前值变化时重建输入框；用 key 保证切换会议后
              // 输入框不会残留上一场会的名字。
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
                widget.onRename(slotId, trimmed);
              },
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: voiceId.isEmpty ? null : voiceId,
              isDense: true,
              style: TextStyle(fontSize: 11, color: textPrimary),
              items: [
                if (!inPool && voiceId.isNotEmpty)
                  DropdownMenuItem(
                    value: voiceId,
                    child: Text('$voiceId（自动）',
                        style: TextStyle(fontSize: 11, color: textPrimary)),
                  ),
                for (final v in VoicePool.all)
                  DropdownMenuItem(
                    value: v.id,
                    child: Text('${v.label} · ${v.gender == VoiceGender.male ? "男" : "女"}',
                        style: TextStyle(fontSize: 11, color: textPrimary)),
                  ),
              ],
              onChanged: isMe
                  ? null // 标记为「我」的槽位音色跟随「我的身份」，不单独选
                  : (v) {
                      if (v != null) widget.onVoice(slotId, v);
                    },
            ),
          ),
          const Spacer(),
          if (mergedInto != null)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text('→ $mergedInto',
                  style: TextStyle(fontSize: 10, color: accent)),
            ),
          // 合并入口。同一人常有多种写法（`李嘉成` / `嘉成`），合并后两者
          // 用同一个名字与音色；系统不自动合并，只在用户点的时候合。
          PopupMenuButton<String>(
            tooltip: '合并到别人 / 取消合并',
            padding: EdgeInsets.zero,
            iconSize: 16,
            icon: Icon(Icons.merge_type, size: 16, color: textSecondary),
            onSelected: (v) {
              if (v == RealMeetingPanel._unmergeValue) {
                widget.onUnmerge(slotId);
              } else {
                widget.onMerge(slotId, v);
              }
            },
            itemBuilder: (ctx) => [
              if (mergedInto != null)
                const PopupMenuItem(
                  value: RealMeetingPanel._unmergeValue,
                  child: Text('取消合并', style: TextStyle(fontSize: 12)),
                ),
              for (final other in widget.meeting?.slots ?? const <SpeakerSlot>[])
                if (other.id != slotId && other.id != mergedInto)
                  PopupMenuItem(
                    value: other.id,
                    child: Text('合并到 ${other.id}',
                        style: const TextStyle(fontSize: 12)),
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
}
