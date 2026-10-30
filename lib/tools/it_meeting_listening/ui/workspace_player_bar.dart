/// 工作区底部持久播放栏（Group 9.1）。
///
/// 布局：
/// `[当前播放标题 + 说话人（点击跳回对应分类与条目）]  [⏮] [▶/⏸] [⏭]  ────●──── 04:12/38:20  [1.0x▾]  [🔁]  [📖 精听]`
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../services/listening_player_controller.dart';

class WorkspacePlayerBar extends StatelessWidget {
  final ListeningPlayerController player;
  final Clip? fallbackClip;
  final bool transcriptOpen;
  final VoidCallback onToggleTranscript;
  final VoidCallback onTogglePlay;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final ValueChanged<Clip> onJumpToClip;

  const WorkspacePlayerBar({
    super.key,
    required this.player,
    this.fallbackClip,
    required this.transcriptOpen,
    required this.onToggleTranscript,
    required this.onTogglePlay,
    required this.onPrevious,
    required this.onNext,
    required this.onJumpToClip,
  });

  SpeakerTurn? _currentTurn(Clip? clip, int posMs) {
    if (clip == null || clip.turns.isEmpty) return null;
    for (final t in clip.turns) {
      if (posMs >= t.startMs && posMs < t.endMs) return t;
    }
    return clip.turns.last;
  }

  static String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms < 0 ? 0 : ms);
    if (d.inMinutes > 0) {
      return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '0:${d.inSeconds.toString().padLeft(2, '0')}';
  }

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

    final clip = player.clip ?? fallbackClip;
    final position = player.position.inMilliseconds;
    final duration = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds
        : (clip?.durationMs ?? 0);
    final ratio = duration > 0 ? (position / duration).clamp(0.0, 1.0) : 0.0;
    final turn = _currentTurn(clip, position);
    final isMeeting = clip != null &&
        (clip.source.sourceId == 'real-meeting' ||
            clip.source.sourceId == 'rehearsal');

    return Container(
      key: const ValueKey('workspace-player-bar'),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
        color: bgCard,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          // 左侧：标题与当前说话人（点击跳回对应分类与条目）
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140, maxWidth: 240),
            child: InkWell(
              key: const ValueKey('player-bar-title-jump'),
              borderRadius: BorderRadius.circular(4),
              onTap: clip == null ? null : () => onJumpToClip(clip),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      clip?.title ?? '未选择素材',
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
                      clip == null
                          ? '点击列表中的条目开始播放'
                          : (turn != null
                              ? '${turn.speaker} · ${clip.scene.label}'
                              : clip.scene.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: clip == null ? null : onPrevious,
            icon: const Icon(Icons.skip_previous_rounded, size: 18),
            tooltip: isMeeting ? '上一轮发言' : '上一段',
          ),
          IconButton(
            key: const ValueKey('player-bar-play-pause'),
            onPressed: clip == null ? null : onTogglePlay,
            icon: Icon(
              player.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 22,
              color: clip == null ? textSecondary : accent,
            ),
            tooltip: '播放/暂停',
          ),
          IconButton(
            onPressed: clip == null ? null : onNext,
            icon: const Icon(Icons.skip_next_rounded, size: 18),
            tooltip: isMeeting ? '下一轮发言' : '下一段',
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: ratio,
                activeColor: accent,
                inactiveColor: context.bgInput,
                onChanged: (clip == null || duration <= 0)
                    ? null
                    : (v) {
                        final targetMs = (v * duration).round();
                        player.seek(targetMs);
                      },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_formatDuration(position)} / ${_formatDuration(duration)}',
            style: TextStyle(fontSize: 11, color: textSecondary),
          ),
          const SizedBox(width: 8),
          _buildSpeedMenu(context, accent),
          const SizedBox(width: 4),
          if (!isMeeting)
            Tooltip(
              message: '连续播放（场景内循环）',
              child: IconButton(
                onPressed: () => player.setContinuous(!player.isContinuous),
                icon: Icon(
                  Icons.repeat_rounded,
                  size: 18,
                  color: player.isContinuous ? accent : textSecondary,
                ),
              ),
            ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            key: const ValueKey('player-bar-transcript-btn'),
            onPressed: clip == null ? null : onToggleTranscript,
            icon: Icon(
              Icons.menu_book_rounded,
              size: 15,
              color: transcriptOpen ? accent : textSecondary,
            ),
            label: Text(
              '精听',
              style: TextStyle(
                fontSize: 12,
                color: transcriptOpen ? accent : textPrimary,
              ),
            ),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              backgroundColor:
                  transcriptOpen ? accent.withValues(alpha: 0.12) : null,
              side: BorderSide(
                color: transcriptOpen ? accent : border,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedMenu(BuildContext context, Color accent) {
    return PopupMenuButton<double>(
      tooltip: '播放速度',
      color: context.bgCardHover,
      onSelected: (v) => player.setSpeed(v),
      itemBuilder: (context) => [
        for (final step in kListeningSpeedSteps)
          PopupMenuItem<double>(
            value: step,
            child: Text(
              '${step}x',
              style: TextStyle(
                fontSize: 12,
                color: step == player.speed ? accent : null,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: accent.withValues(alpha: 0.12),
        ),
        child: Text(
          '${player.speed}x',
          style: TextStyle(fontSize: 11, color: accent),
        ),
      ),
    );
  }
}
