/// 公开素材场景视图（两栏形态，右侧不设独立详情栏）。
///
/// - 标题栏展示场景名、片段数、总时长、多来源时的来源下拉筛选；
/// - 存在待生成片段时显示就地横幅「n 段还没有音频 [生成]」（仅作用于当前场景）；
/// - 列表项内直接展示标题、一句话摘要、时长、人数、轮数与已听进度。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../services/listening_progress_store.dart';
import '../services/task_tracker.dart';

/// 公开素材场景视图。
class PublicSceneView extends StatelessWidget {
  final MeetingScene scene;
  final List<Clip> clips;
  final List<Clip> pendingClips;
  final Map<String, String> availableSources;
  final String? selectedSourceId;
  final ValueChanged<String?> onSourceChanged;
  final VoidCallback onBakeScene;
  final WorkspaceTaskEntry? sceneBakeTask;
  final String? playingClipId;
  final ValueChanged<Clip> onPlayClip;
  final ItemProgress? Function(String clipId) progressFor;

  const PublicSceneView({
    super.key,
    required this.scene,
    required this.clips,
    required this.pendingClips,
    required this.availableSources,
    required this.selectedSourceId,
    required this.onSourceChanged,
    required this.onBakeScene,
    this.sceneBakeTask,
    required this.playingClipId,
    required this.onPlayClip,
    required this.progressFor,
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

    final totalMs = clips.fold<int>(0, (a, c) => a + c.durationMs);
    final isBaking = sceneBakeTask?.running ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border)),
          ),
          child: Row(
            children: [
              Text(
                scene.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${clips.length} 段 · 共 ${_formatTotal(totalMs)}',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
              const Spacer(),
              if (availableSources.length > 1)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '来源：',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        key: const ValueKey('public-source-dropdown'),
                        value: selectedSourceId,
                        isDense: true,
                        style: TextStyle(fontSize: 12, color: textPrimary),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '全部来源',
                              style:
                                  TextStyle(fontSize: 12, color: textPrimary),
                            ),
                          ),
                          for (final entry in availableSources.entries)
                            DropdownMenuItem<String?>(
                              value: entry.key,
                              child: Text(
                                entry.value,
                                style:
                                    TextStyle(fontSize: 12, color: textPrimary),
                              ),
                            ),
                        ],
                        onChanged: onSourceChanged,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (pendingClips.isNotEmpty || isBaking)
          Container(
            key: const ValueKey('public-scene-pending-banner'),
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: accent.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 16, color: accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isBaking
                        ? (sceneBakeTask?.label ?? '正在生成当前场景音频…')
                        : '${pendingClips.length} 段还没有音频',
                    style: TextStyle(fontSize: 12, color: textPrimary),
                  ),
                ),
                FilledButton.tonal(
                  key: const ValueKey('public-scene-bake-btn'),
                  onPressed: isBaking ? null : onBakeScene,
                  child: Text(isBaking ? '生成中…' : '生成'),
                ),
              ],
            ),
          ),
        Expanded(
          child: clips.isEmpty
              ? Center(
                  child: Text(
                    '该场景下暂无素材',
                    style: TextStyle(fontSize: 12, color: textSecondary),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: clips.length,
                  itemBuilder: (context, i) {
                    final clip = clips[i];
                    final isPlaying = playingClipId == clip.id;
                    final prog = progressFor(clip.id);
                    return _buildClipCard(
                      context,
                      clip,
                      isPlaying,
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
    );
  }

  Widget _buildClipCard(
    BuildContext context,
    Clip clip,
    bool isPlaying,
    ItemProgress? progress,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final pct = progress == null ? 0 : (progress.ratio * 100).round();
    final progressText = progress == null
        ? null
        : (progress.isCompleted
            ? '已听完'
            : (pct > 0 ? '已听 $pct%' : null));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isPlaying ? accent : border,
          width: isPlaying ? 1.4 : 1,
        ),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: ListTile(
        dense: true,
        onTap: () => onPlayClip(clip),
        title: Text(
          clip.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isPlaying ? FontWeight.w600 : FontWeight.normal,
            color: textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (clip.summary.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 2),
                child: Text(
                  clip.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ),
            Text(
              clip.isPlaceholder
                  ? '待生成音频 · ${clip.turns.length} 轮'
                  : '${_formatDuration(clip.durationMs)} · ${clip.speakerCount} 人 · ${clip.turns.length} 轮'
                      '${progressText != null ? " · $progressText" : ""}',
              style: TextStyle(fontSize: 11, color: textSecondary),
            ),
          ],
        ),
        trailing: isPlaying
            ? Icon(Icons.graphic_eq_rounded, color: accent, size: 18)
            : (clip.isPlaceholder
                ? Icon(Icons.schedule_rounded, size: 16, color: textSecondary)
                : Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: textSecondary,
                  )),
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

  static String _formatDuration(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }
}
