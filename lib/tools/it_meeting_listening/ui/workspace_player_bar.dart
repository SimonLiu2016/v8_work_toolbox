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
  final ValueChanged<ListeningLoopMode>? onLoopModeChanged;

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
    this.onLoopModeChanged,
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
          // 极速慢速切换 (0.8x ↔ 1.0x)
          Tooltip(
            message: '极速变速（当前 ${player.speed}x ↔ 目标 ${player.speed == 1.0 ? "${player.lastCustomSpeed}x" : "1.0x"}）',
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => player.toggleQuickSpeed(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: player.speed != 1.0 ? accent.withValues(alpha: 0.15) : null,
                  border: Border.all(
                    color: player.speed != 1.0 ? accent : border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.speed_rounded,
                      size: 13,
                      color: player.speed != 1.0 ? accent : textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      player.speed != 1.0 ? '慢速' : '原速',
                      style: TextStyle(
                        fontSize: 11,
                        color: player.speed != 1.0 ? accent : textSecondary,
                        fontWeight: player.speed != 1.0 ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          _buildSpeedMenu(context, accent),
          const SizedBox(width: 4),
          // 单句循环指示器
          if (player.isLoopingTurn)
            Tooltip(
              message: '当前正在单句循环（第 ${(player.loopingTurnIndex ?? 0) + 1} 句），点击退出',
              child: InkWell(
                key: const ValueKey('player-bar-loop-indicator'),
                borderRadius: BorderRadius.circular(12),
                onTap: () => player.setLoopingTurn(null),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.amber.withValues(alpha: 0.18),
                    border: Border.all(color: Colors.amber.shade700),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat_one_rounded, size: 13, color: Colors.amber.shade800),
                      const SizedBox(width: 3),
                      Text(
                        '句循环',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(Icons.close_rounded, size: 12, color: Colors.amber.shade800),
                    ],
                  ),
                ),
              ),
            ),
          // 句级跟读模式胶囊（畅听 ↔ 逐句跟读）
          _buildShadowingCapsule(context, accent, textSecondary, border),
          const SizedBox(width: 4),
          // 篇级流转三态循环按钮（单篇播放 ➔ 列表连播 ➔ 单篇循环）
          _buildLoopModeButton(context, accent, textSecondary),
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

  Widget _buildShadowingCapsule(
    BuildContext context,
    Color accent,
    Color textSecondary,
    Color border,
  ) {
    if (player.isLoopingTurn) return const SizedBox.shrink();

    if (player.isAutoPause) {
      // 逐句跟读开启中
      return Tooltip(
        message: '当前开启了逐句跟读停顿（每句播完自动暂停复述留白）。点击切换为整篇畅听',
        child: InkWell(
          key: const ValueKey('player-bar-autopause-indicator'),
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            player.setAutoPause(false);
            if (!player.isPlaying) {
              player.resume();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepOrange.withValues(alpha: 0.18),
              border: Border.all(color: Colors.deepOrange.shade400),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pause_circle_rounded, size: 13, color: Colors.deepOrange.shade700),
                const SizedBox(width: 3),
                Text(
                  '逐句跟读',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.deepOrange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(Icons.close_rounded, size: 12, color: Colors.deepOrange.shade700),
              ],
            ),
          ),
        ),
      );
    }

    // 整篇畅听模式
    return Tooltip(
      message: '当前为整篇畅听模式。点击开启逐句停顿（每句播完自动暂停留白复述）',
      child: InkWell(
        key: const ValueKey('player-bar-autopause-toggle'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => player.setAutoPause(true),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.hearing_rounded, size: 13, color: textSecondary),
              const SizedBox(width: 3),
              Text(
                '畅听',
                style: TextStyle(
                  fontSize: 11,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoopModeButton(
    BuildContext context,
    Color accent,
    Color textSecondary,
  ) {
    IconData icon;
    String tooltip;
    Color color;

    switch (player.loopMode) {
      case ListeningLoopMode.orderOnce:
        icon = Icons.arrow_right_alt_rounded;
        tooltip = '播放模式：单篇播放（播完即止，不自动切下一首）· 点击切换';
        color = textSecondary;
        break;
      case ListeningLoopMode.listLoop:
        icon = Icons.repeat_rounded;
        tooltip = '播放模式：列表连播（播完自动切下一篇素材）· 点击切换';
        color = accent;
        break;
      case ListeningLoopMode.singleLoop:
        icon = Icons.repeat_one_rounded;
        tooltip = '播放模式：单篇循环（反复重听当前篇）· 点击切换';
        color = accent;
        break;
    }

    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: const ValueKey('player-bar-loop-mode-btn'),
        visualDensity: VisualDensity.compact,
        onPressed: () {
          final newMode = player.cycleLoopMode();
          onLoopModeChanged?.call(newMode);
        },
        icon: Icon(icon, size: 20, color: color),
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
