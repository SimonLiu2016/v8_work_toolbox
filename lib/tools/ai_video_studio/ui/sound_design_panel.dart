/// 声音设计面板：台词列表 + 批量合成 + BGM 推荐 + 时序条形图。
///
/// spec 13.1-13.4。所有数字都来自真实测量（TTS 时长、BGM 文件大小），
/// 估算只出现在 afinfo 读不到时的兜底路径上。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/prompt_assembler.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../../ai_video_studio/services/studio_sound_design.dart';
import 'studio_shell.dart';

class SoundDesignPanel extends StatefulWidget {
  const SoundDesignPanel({super.key, required this.session});

  final StudioSession session;

  @override
  State<SoundDesignPanel> createState() => _SoundDesignPanelState();
}

class _SoundDesignPanelState extends State<SoundDesignPanel> {
  final _manager = StudioProjectManager.instance;
  final _tts = StudioTtsService();

  StudioEpisode? _episode;
  List<SynthesizedLine> _lines = const [];
  bool _synthesizing = false;
  int _progressShot = 0;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final episode = widget.session.episode;
    if (episode == null) return;
    final fresh = _manager.readEpisode(
      widget.session.series!.id,
      episode.id,
    );
    if (!mounted) return;
    setState(() {
      _episode = fresh;
      // 从磁盘恢复已合成的时长：刷新页面不该丢掉已经花时间生成的东西。
      _lines = fresh?.shots
              .where((s) => s.audioPath != null && s.audioPath!.isNotEmpty)
              .map((s) => SynthesizedLine(
                    shotNumber: s.number,
                    fileName: s.audioPath!,
                    durationMs: s.audioDurationMs ?? 0,
                  ))
              .toList() ??
          const [];
    });
  }

  Future<void> _synthesizeAll() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;

    setState(() {
      _synthesizing = true;
      _error = null;
      _progress = 0;
    });
    try {
      final characters = await _manager.listCharacters(series.id);
      final lines = await _tts.synthesizeEpisode(
        episode: episode,
        audioDir: _manager.episodeAudioDir(series.id, episode.id).path,
        defaultVoiceId: series.defaultVoiceId,
        resolveVoiceId: (shot) {
          final speaker = PromptAssembler.extractSpeakerName(shot.dialogue);
          if (speaker.isNotEmpty) {
            // 优先根据提取的真实说话人姓名精准匹配角色库音色
            final matched = characters.where((c) {
              final name = c.name.trim();
              if (name.isEmpty) return false;
              if (name == speaker || name.contains(speaker) || speaker.contains(name)) {
                return true;
              }
              return c.aliases.any((a) => a.trim().isNotEmpty && (a == speaker || speaker.contains(a)));
            }).firstOrNull;
            if (matched != null && matched.ttsVoiceId.trim().isNotEmpty) {
              return matched.ttsVoiceId.trim();
            }
          }

          // 回退：从该分镜出场角色中查找已绑定有效音色的角色
          for (final id in shot.characterIds) {
            final c = characters.where((c) => c.id == id).firstOrNull;
            if (c != null && c.ttsVoiceId.trim().isNotEmpty) {
              return c.ttsVoiceId.trim();
            }
          }

          return '';
        },
        onProgress: (shotNumber, progress) {
          if (!mounted) return;
          setState(() {
            _progressShot = shotNumber;
            _progress = progress;
          });
        },
      );

      // 时长写回 storyboard.json：SRT 生成与时序图都读它。
      final shots = episode.shots.toList();
      for (final line in lines) {
        final idx = shots.indexWhere((s) => s.number == line.shotNumber);
        if (idx < 0) continue;
        shots[idx] = shots[idx].copyWith(
          audioPath: line.fileName.isEmpty ? null : line.fileName,
          audioDurationMs: line.durationMs,
        );
      }
      final saved = episode.copyWith(shots: shots);
      await _manager.saveEpisode(saved);

      // SRT 落盘（spec 6.2：audio/ep_<id>.srt）。
      final srt = StudioSrtWriter.build(episode: saved, lines: lines);
      await StudioSrtWriter.write(
        srtText: srt,
        episodeAudioDir: _manager.episodeAudioDir(series.id, episode.id).path,
        episodeId: episode.id,
      );

      if (!mounted) return;
      setState(() {
        _lines = lines;
        _synthesizing = false;
        _progress = 1;
      });
      widget.session.reloadEpisode();
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _synthesizing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final episode = _episode;
    if (episode == null) {
      return const Center(child: Text('未选择集'));
    }
    final audioDir = widget.session.series == null
        ? ''
        : _manager.episodeAudioDir(
            widget.session.series!.id,
            episode.id,
          ).path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Text(
                '声音设计',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_synthesizing)
                SizedBox(
                  width: 160,
                  child: Row(
                    children: [
                      Expanded(
                        child: LinearProgressIndicator(value: _progress),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '镜 $_progressShot',
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _synthesizing ? null : _synthesizeAll,
                icon: _synthesizing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.record_voice_over, size: 16),
                label: Text(_synthesizing ? '合成中…' : '批量合成全集配音'),
              ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: Text(
              _error!,
              style: TextStyle(color: context.errorText, fontSize: 12),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              for (final shot in episode.shots)
                _DialogueRow(
                  shot: shot,
                  audioDir: audioDir,
                  line: _lines
                      .where((l) => l.shotNumber == shot.number)
                      .firstOrNull,
                  onPreview: () => _preview(context, audioDir, shot),
                ),
              const SizedBox(height: 16),
              Text(
                '时序',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _TimelineBar(episode: episode, lines: _lines),
              const SizedBox(height: 16),
              Text(
                'BGM',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final shot in episode.shots
                  .where((s) => s.bgmPath == null)
                  .take(3))
                _BgmRow(
                  shot: shot,
                  seriesId: widget.session.series?.id ?? '',
                  episode: episode,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _preview(
    BuildContext context,
    String audioDir,
    StudioShot shot,
  ) async {
    final line = _lines.where((l) => l.shotNumber == shot.number).firstOrNull;
    if (line == null || line.fileName.isEmpty) return;
    final file = File(p.join(audioDir, line.fileName));
    if (!file.existsSync()) return;
    // 用系统默认播放器打开：工坊内嵌播放器属于视频看板的职责域。
    try {
      await Process.run('open', [file.path]);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法播放：${file.path}')),
      );
    }
  }
}

class _DialogueRow extends StatelessWidget {
  const _DialogueRow({
    required this.shot,
    required this.audioDir,
    required this.line,
    required this.onPreview,
  });

  final StudioShot shot;
  final String audioDir;
  final SynthesizedLine? line;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final hasAudio = line != null && line!.fileName.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '#${shot.number}',
              style: TextStyle(
                color: context.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              shot.dialogue.trim().isEmpty ? '（无台词）' : shot.dialogue.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: shot.dialogue.trim().isEmpty
                    ? context.textDisabled
                    : context.textPrimary,
                fontSize: 12,
              ),
            ),
          ),
          if (hasAudio) ...[
            Text(
              formatAudioDuration(line!.durationMs),
              style: TextStyle(color: context.textSecondary, fontSize: 11),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onPreview,
              icon: Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: context.accentText,
              ),
              tooltip: '试听',
            ),
          ],
        ],
      ),
    );
  }
}

/// 简化时序条形图：台词轨 + BGM 轨的相对位置（spec 13.4）。
class _TimelineBar extends StatelessWidget {
  const _TimelineBar({required this.episode, required this.lines});

  final StudioEpisode episode;
  final List<SynthesizedLine> lines;

  @override
  Widget build(BuildContext context) {
    // 总时长 = 各分镜占用时长之和（有音频按音频，否则按建议时长）。
    final byShot = {for (final l in lines) l.shotNumber: l};
    var totalMs = 0;
    final widths = <double>[];
    for (final shot in episode.shots) {
      final audio = byShot[shot.number]?.durationMs ?? 0;
      final span = audio > 0 ? audio : (shot.durationSec * 1000).round();
      widths.add(span.toDouble());
      totalMs += span;
    }
    if (totalMs <= 0) {
      return Text(
        '还没有音频，先合成台词。',
        style: TextStyle(color: context.textTertiary, fontSize: 12),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TrackRow(
          color: context.accentText,
          widths: widths,
          totalMs: totalMs,
          label: '台词',
        ),
        const SizedBox(height: 6),
        _TrackRow(
          color: context.infoText,
          widths: widths,
          totalMs: totalMs,
          label: 'BGM',
        ),
        const SizedBox(height: 6),
        Text(
          '总时长 ${formatAudioDuration(totalMs)}',
          style: TextStyle(color: context.textTertiary, fontSize: 11),
        ),
      ],
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.color,
    required this.widths,
    required this.totalMs,
    required this.label,
  });

  final Color color;
  final List<double> widths;
  final int totalMs;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 32,
          child: Text(
            label,
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                for (final w in widths)
                  Expanded(
                    flex: w.round().clamp(1, 1 << 20),
                    child: Container(
                      margin: const EdgeInsets.only(right: 1),
                      decoration: BoxDecoration(
                        color: color.withAlpha(120),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BgmRow extends StatefulWidget {
  const _BgmRow({
    required this.shot,
    required this.seriesId,
    required this.episode,
  });

  final StudioShot shot;
  final String seriesId;
  final StudioEpisode episode;

  @override
  State<_BgmRow> createState() => _BgmRowState();
}

class _BgmRowState extends State<_BgmRow> {
  List<BgmCandidate> _candidates = const [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await const BgmMatcher().recommend(
        seriesId: widget.seriesId,
        moodId: widget.shot.mood,
      );
      if (!mounted) return;
      setState(() {
        _candidates = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '#${widget.shot.number} · '
                '${ShotMood.fromId(widget.shot.mood).label}',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
              const Spacer(),
              if (_loading)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_candidates.isEmpty && !_loading)
            Text(
              '没有找到匹配的 BGM。可在全局库或本剧库放入音频文件。',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
          for (final c in _candidates)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                c.asset.name,
                style: TextStyle(color: context.textPrimary, fontSize: 12),
              ),
              subtitle: Text(
                '${c.sourceLabel}'
                '${c.score > 0 ? ' · 匹配 ${c.score}' : ''}',
                style: TextStyle(color: context.textTertiary, fontSize: 10),
              ),
              trailing: TextButton(
                onPressed: () => _select(c.asset.path),
                child: const Text('选用'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _select(String path) async {
    // 存绝对路径：BGM 来自全局库或 IP 库，目录不在本集之内，相对路径没法解析。
    final shots = widget.episode.shots.toList();
    final idx = shots.indexWhere((s) => s.number == widget.shot.number);
    if (idx < 0) return;
    shots[idx] = shots[idx].copyWith(bgmPath: path);
    await StudioProjectManager.instance.saveEpisode(
      widget.episode.copyWith(shots: shots),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已为分镜 ${widget.shot.number} 选用 BGM')),
    );
  }
}
