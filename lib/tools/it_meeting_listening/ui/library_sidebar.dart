/// 左侧资料库导航栏：继续收听卡片、「我的会议」分区、「公开素材」场景分区与同步状态。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../services/task_tracker.dart';
import '../services/workspace_selection.dart';

/// 左侧资料库导航栏。
class LibrarySidebar extends StatelessWidget {
  final WorkspaceNavTarget selectedSection;
  final ValueChanged<WorkspaceNavTarget> onSelectSection;

  final int realMeetingCount;
  final int rehearsalCount;

  /// 非空公开素材场景及其片段列表（已按当前来源过滤）。
  final List<(MeetingScene scene, List<Clip> clips)> publicScenes;

  /// 待生成的公开素材总片段数。
  final int totalPendingPublicCount;
  final VoidCallback onBakeAllPublic;
  final VoidCallback onSyncPublic;
  final WorkspaceTaskEntry? syncTask;
  final WorkspaceTaskEntry? bakeAllTask;

  /// 继续收听卡片信息（无上次播放记录时为 null）。
  final ({Clip clip, int offsetMs, bool isPlaying})? continueListening;
  final VoidCallback? onTapContinueListening;

  const LibrarySidebar({
    super.key,
    required this.selectedSection,
    required this.onSelectSection,
    required this.realMeetingCount,
    required this.rehearsalCount,
    required this.publicScenes,
    required this.totalPendingPublicCount,
    required this.onBakeAllPublic,
    required this.onSyncPublic,
    this.syncTask,
    this.bakeAllTask,
    this.continueListening,
    this.onTapContinueListening,
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
      width: 200,
      color: bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (continueListening != null) ...[
                    _buildContinueCard(
                      context,
                      continueListening!,
                      accent,
                      textPrimary,
                      textSecondary,
                      border,
                    ),
                    Divider(height: 1, color: border),
                  ],
                  _buildSectionHeader('我的会议', textSecondary),
                  _buildNavItem(
                    context,
                    key: const ValueKey('nav-real-meetings'),
                    icon: Icons.record_voice_over_outlined,
                    label: '真实会议',
                    count: realMeetingCount,
                    selected: selectedSection.isRealMeetings,
                    onTap: () => onSelectSection(
                      const WorkspaceNavTarget.realMeetings(),
                    ),
                    accent: accent,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  _buildNavItem(
                    context,
                    key: const ValueKey('nav-rehearsals'),
                    icon: Icons.campaign_outlined,
                    label: '排练',
                    count: rehearsalCount,
                    selected: selectedSection.isRehearsals,
                    onTap: () => onSelectSection(
                      const WorkspaceNavTarget.rehearsals(),
                    ),
                    accent: accent,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(height: 1, color: border),
                  ),
                  _buildSectionHeader('公开素材', textSecondary),
                  if (publicScenes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        '暂无公开素材',
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    )
                  else
                    for (final entry in publicScenes)
                      _buildSceneItem(
                        context,
                        entry.$1,
                        entry.$2,
                        selectedSection ==
                            WorkspaceNavTarget.publicScene(entry.$1),
                        accent,
                        textPrimary,
                        textSecondary,
                      ),
                ],
              ),
            ),
          ),
          _buildPublicFooter(
            context,
            border,
            accent,
            textPrimary,
            textSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildContinueCard(
    BuildContext context,
    ({Clip clip, int offsetMs, bool isPlaying}) info,
    Color accent,
    Color textPrimary,
    Color textSecondary,
    Color border,
  ) {
    return InkWell(
      key: const ValueKey('sidebar-continue-card'),
      onTap: onTapContinueListening,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  info.isPlaying
                      ? Icons.graphic_eq_rounded
                      : Icons.play_circle_fill_rounded,
                  size: 15,
                  color: accent,
                ),
                const SizedBox(width: 6),
                Text(
                  info.isPlaying ? '正在收听' : '继续收听',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              info.clip.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${_fmtClock(info.offsetMs)} / ${_fmtClock(info.clip.durationMs)}',
              style: TextStyle(fontSize: 10, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textSecondary,
        ),
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: selected ? context.bgSelected : Colors.transparent,
        child: Row(
          children: [
            Icon(icon, size: 15, color: selected ? accent : textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? accent : textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            Text(
              '$count',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSceneItem(
    BuildContext context,
    MeetingScene scene,
    List<Clip> clips,
    bool selected,
    Color accent,
    Color textPrimary,
    Color textSecondary,
  ) {
    final totalMs = clips.fold<int>(0, (a, c) => a + c.durationMs);
    return InkWell(
      onTap: () => onSelectSection(WorkspaceNavTarget.publicScene(scene)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: selected ? context.bgSelected : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    scene.label,
                    key: ValueKey('scene-label-${scene.id}'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: selected ? accent : textPrimary,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${clips.length}',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              totalMs <= 0 ? scene.labelEn : _formatTotal(totalMs),
              style: TextStyle(fontSize: 10, color: textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPublicFooter(
    BuildContext context,
    Color border,
    Color accent,
    Color textPrimary,
    Color textSecondary,
  ) {
    final isSyncing = syncTask?.running ?? false;
    final isBaking = bakeAllTask?.running ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSyncing)
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    syncTask?.label ?? '正在同步…',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: accent),
                  ),
                ),
              ],
            )
          else
            InkWell(
              onTap: onSyncPublic,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.sync_rounded, size: 14, color: textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        syncTask?.message ?? '同步公开素材',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (totalPendingPublicCount > 0 || isBaking) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isBaking
                        ? (bakeAllTask?.label ?? '正在生成…')
                        : '$totalPendingPublicCount 段待生成音频',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: textSecondary),
                  ),
                ),
                if (!isBaking)
                  TextButton(
                    key: const ValueKey('sidebar-bake-all-public-btn'),
                    onPressed: onBakeAllPublic,
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    child: const Text('全部生成', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTotal(int ms) {
    final total = Duration(milliseconds: ms);
    if (total.inMinutes > 0) {
      return '${total.inMinutes} 分钟 ${total.inSeconds % 60} 秒';
    }
    return '${total.inSeconds} 秒';
  }

  static String _fmtClock(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}
