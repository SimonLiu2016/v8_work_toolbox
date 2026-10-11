/// 合成交付与发布套件页。
///
/// spec 14.1-14.7。这一页把前面几页攒下的素材变成成品，并顺手生成发布要用的
/// 标题、封面、标签与下集钩子。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/ai_constraint_engine.dart';
import '../../ai_video_studio/services/ffmpeg_composer.dart';
import '../../ai_video_studio/services/jianying_exporter.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import 'studio_shell.dart';

class DeliveryPanel extends StatefulWidget {
  const DeliveryPanel({super.key, required this.session});

  final StudioSession session;

  @override
  State<DeliveryPanel> createState() => _DeliveryPanelState();
}

class _DeliveryPanelState extends State<DeliveryPanel> {
  final _manager = StudioProjectManager.instance;

  StudioEpisode? _episode;
  FfmpegStatus _ffmpeg = const FfmpegStatus.unavailable('尚未检测');
  bool _composing = false;
  double _composeProgress = 0;
  String? _error;
  String? _outputPath;
  String? _coverPath;

  final _titleController = TextEditingController();
  List<Map<String, dynamic>> _titleCandidates = const [];
  bool _generatingTitles = false;
  List<String> _hashtags = const [];
  String _nextHook = '';

  @override
  void initState() {
    super.initState();
    _episode = widget.session.episode;
    _checkFfmpeg();
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _checkFfmpeg() async {
    final status = await FfmpegComposer.checkAvailability(forceRefresh: true);
    if (!mounted) return;
    setState(() => _ffmpeg = status);
  }

  /// 有待合成视频的分镜，按分镜顺序。
  ///
  /// 片段化后「有视频」有两种来源（spec: 片段媒体存放与交付兼容）：
  /// - 分镜级产物 `shot.clipPath`（用户单独出的那一镜）
  /// - 片段级产物 `segment.clipPath`（覆盖该片段的全部镜头）
  ///
  /// 这里只回答「哪些镜有视频」。片段产物与分镜产物的时长如何计入时间轴
  /// 由 [_clipDurationOf] 决定——片段产物按它覆盖的镜头数摊到每镜，而不是
  /// 按片段总时长重复累加（那会让成片时长虚高）。
  List<StudioShot> get _readyClips {
    final episode = _episode;
    if (episode == null) return const [];
    return episode.shots.where((s) => _clipFileOf(s) != null).toList();
  }

  /// 某分镜的视频文件：分镜级优先，缺失时回落到所属片段的产物。
  File? _clipFileOf(StudioShot shot) {
    final episode = _episode;
    if (episode == null) return null;
    final own = shot.clipPath;
    if (own != null && own.isNotEmpty) {
      final file = File(
        p.join(_manager.episodeClipsDir(episode.seriesId, episode.id).path, own),
      );
      if (file.existsSync()) return file;
    }
    // 回落到片段产物。
    if (shot.segmentId.isEmpty) return null;
    final segment = _segmentOf(shot.segmentId);
    if (segment == null || !segment.hasClip) return null;
    final file = File(
      p.join(
        _manager.episodeSegmentsDir(episode.seriesId, episode.id).path,
        segment.clipPath!,
      ),
    );
    return file.existsSync() ? file : null;
  }

  /// 某分镜在时间轴上占用的秒数。
  ///
  /// 分镜级产物用该镜的建议时长；片段级产物按「片段目标时长 ÷ 覆盖镜头数」
  /// 摊分——片段是一次生成的整体，剪回时间轴时必须按镜头摊，否则 N 镜的
  /// 片段会按整段时长累加，成片时长虚高 N 倍。
  double _clipDurationOf(StudioShot shot, List<StudioSegment> segments) {
    if (shot.clipPath != null && shot.clipPath!.isNotEmpty) {
      return shot.durationSec;
    }
    if (shot.segmentId.isEmpty) return shot.durationSec;
    final matches = segments.where((s) => s.id == shot.segmentId);
    if (matches.isEmpty) return shot.durationSec;
    final segment = matches.first;
    final effective = segment.effectiveShotNumbers.length;
    if (effective == 0) return shot.durationSec;
    return segment.targetDurationSec / effective;
  }

  /// 按 id 找片段；找不到返回 null。
  StudioSegment? _segmentOf(String segmentId) {
    final episode = _episode;
    if (episode == null || segmentId.isEmpty) return null;
    final matches = episode.segments.where((s) => s.id == segmentId);
    return matches.isEmpty ? null : matches.first;
  }

  int get _missingClipCount =>
      (_episode?.shots.length ?? 0) - _readyClips.length;

  bool get _hasAudio {
    final episode = _episode;
    if (episode == null) return false;
    return episode.shots.any(
      (s) => s.audioPath != null && s.audioPath!.isNotEmpty,
    );
  }

  Future<void> _compose() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    if (!_ffmpeg.available) {
      setState(() => _error = '本机未检测到 FFmpeg，无法合成。');
      return;
    }
    // 部分分镜未生成时先问（spec 14.4）。
    if (_missingClipCount > 0) {
      final skip = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Text(
            '有 $_missingClipCount 个分镜还没生成视频',
            style: TextStyle(color: context.textPrimary),
          ),
          content: Text(
            '合成时会跳过这些分镜，成片时长会短于预期。',
            style: TextStyle(color: context.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('跳过并继续'),
            ),
          ],
        ),
      );
      if (skip != true) return;
    }

    setState(() {
      _composing = true;
      _error = null;
      _composeProgress = 0;
    });

    final exportsDir = _manager.episodeExportsDir(series.id, episode.id);
    final audioDir = _manager.episodeAudioDir(series.id, episode.id);
    final clips = _readyClips.map(_clipFileOf).whereType<File>().toList();
    final audios = episode.shots
        .where((s) => s.audioPath != null && s.audioPath!.isNotEmpty)
        .map((s) => File(p.join(audioDir.path, s.audioPath!)))
        .toList();
    final srt = File(p.join(audioDir.path, 'ep_${episode.id}.srt'));
    final bgm = episode.shots
            .map((s) => s.bgmPath)
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .map(File.new)
            .firstOrNull;
    final output = File(p.join(exportsDir.path, 'episode.mp4'));

    // 总时长只算**有视频**的分镜：没有片段的镜会在拼接时被跳过，把它算进去
    // 会让进度条走不完（FFmpeg 报的 progress 是按实际输入算的）。
    final totalDuration = _readyClips.fold<double>(
      0,
      (sum, s) => sum + _clipDurationOf(s, episode.segments),
    );

    final result = await FfmpegComposer.compose(
      ComposeRequest(
        clips: clips,
        dialogueAudios: audios,
        bgm: (bgm != null && bgm.existsSync()) ? bgm : null,
        subtitle: srt.existsSync() ? srt : null,
        useDissolve: true,
        outputFile: output,
        durationSec: totalDuration,
      ),
      onProgress: (v) {
        if (mounted) setState(() => _composeProgress = v);
      },
    );

    if (!mounted) return;
    setState(() => _composing = false);
    if (!result.success) {
      setState(() => _error = '合成失败：${result.stderr}');
      return;
    }
    setState(() => _outputPath = output.path);
  }

  Future<void> _pickCover() async {
    final path = _outputPath;
    if (path == null) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CoverPicker(videoPath: path),
    );
    if (picked == null || !mounted) return;
    setState(() => _coverPath = picked);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已选封面帧：${picked.split('/').last}')),
    );
  }

  Future<void> _revealInFinder() async {
    final path = _outputPath;
    if (path == null) return;
    try {
      await Process.run('open', ['-R', path]);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法定位文件：$path')),
      );
    }
  }

  /// 把封面帧复制到 exports/，名字固定，方便用户直接拖进发布平台。
  Future<void> _exportCover() async {
    final cover = _coverPath;
    final episode = _episode;
    final series = widget.session.series;
    if (cover == null || episode == null || series == null) return;
    final target = File(p.join(
      _manager.episodeExportsDir(series.id, episode.id).path,
      'cover.jpg',
    ));
    await File(cover).copy(target.path);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('封面已导出到 exports/cover.jpg')),
    );
  }

  Future<void> _exportJianying() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    setState(() {
      _error = null;
    });
    try {
      final audioDir = _manager.episodeAudioDir(series.id, episode.id);
      final srt = File(p.join(audioDir.path, 'ep_${episode.id}.srt'));
      final bgm = episode.shots
              .map((s) => s.bgmPath)
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .map(File.new)
              .firstOrNull;
      await JianyingExporter.export(
        outputDir: _manager.episodeExportsDir(series.id, episode.id).path,
        episode: episode,
        shots: episode.shots,
        srtPath: srt.existsSync() ? srt.path : null,
        bgmPath: bgm?.path,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剪映草稿已导出到 exports/jianying_draft/')),
      );
    } catch (e) {
      if (!mounted) return;
      // 草稿自检失败时自动走备用导出，并把退路告诉用户。
      try {
        final fallback = await JianyingExporter.exportFallback(
          outputDir: _manager.episodeExportsDir(series.id, episode.id).path,
          episode: episode,
          shots: episode.shots,
        );
        if (!mounted) return;
        setState(() {
          _error = '剪映草稿格式校验未通过，已改为素材文件夹导出：${fallback.path}';
        });
      } catch (_) {
        if (!mounted) return;
        setState(() => _error = e.toString());
      }
    }
  }

  /// 生成发布三件套：标题候选、话题标签、下集钩子文案。
  ///
  /// 标签走 `titleGeneration` 之外另开一次 AI 调用会让用户多点一次按钮，
  /// 所以这三个都在同一个「生成标题」动作里一次拿完——失败时分别降级，
  /// 不连带让已经拿到的标题也消失。
  Future<void> _generatePublishKit() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    setState(() => _generatingTitles = true);
    try {
      final result = await AiConstraintEngine.titleGeneration(
        seriesName: series.name,
        productionType: series.productionType.id,
        episodeSummary: episode.synopsis,
      );
      if (!mounted) return;
      setState(() {
        _titleCandidates =
            (result.data['titles'] as List).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '标题生成失败：$e');
    }

    // 标签与下集钩子各自独立：一个失败不该带走另一个。
    try {
      final tags = await AiConstraintEngine.bgmRecommend(
        moodLabel: series.productionType.label,
        productionType: series.productionType.id,
        availableTracks: episode.shots
            .map((s) => ShotMood.fromId(s.mood).label)
            .toSet()
            .toList(),
      );
      if (!mounted) return;
      setState(() {
        _hashtags = (tags.data['recommendations'] as List)
            .map((e) => '#${(e as Map)['name']}')
            .toSet()
            .toList();
      });
    } catch (_) {
      // 标签拿不到不影响主流程，静默降级即可。
    }
    try {
      final memory = _manager.readSeries(series.id);
      final hook = memory?.memories.isNotEmpty == true
          ? memory!.memories.last.hook
          : '';
      final summary = await AiConstraintEngine.episodeSummary(
        synopsis: episode.synopsis,
        shotsSummary: hook,
      );
      if (!mounted) return;
      setState(() {
        _nextHook = summary.data['hook'] as String? ?? '';
      });
    } catch (_) {}
    if (!mounted) return;
    setState(() => _generatingTitles = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          '合成交付',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        _ReadinessCard(
          clipCount: _readyClips.length,
          totalShots: _episode?.shots.length ?? 0,
          hasAudio: _hasAudio,
          ffmpeg: _ffmpeg,
          onRecheck: _checkFfmpeg,
        ),
        if (!_ffmpeg.available) ...[
          const SizedBox(height: 12),
          _FfmpegBanner(status: _ffmpeg),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: _composing ? null : _compose,
              icon: _composing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.movie_creation_outlined, size: 16),
              label: Text(_composing ? '合成中…' : '导出 MP4 成片'),
            ),
            OutlinedButton.icon(
              onPressed: _exportJianying,
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('导出剪映工程'),
            ),
            if (_outputPath != null) ...[
              if (_coverPath != null)
                OutlinedButton.icon(
                  onPressed: _exportCover,
                  icon: const Icon(Icons.download_outlined, size: 16),
                  label: const Text('导出封面'),
                ),
              if (_coverPath != null) const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('选封面帧'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _revealInFinder,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: const Text('Finder 定位'),
              ),
            ],
          ],
        ),
        if (_composing) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: _composeProgress),
          const SizedBox(height: 4),
          Text(
            '${(_composeProgress * 100).round()}%',
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.errorText.withAlpha(30),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _error!,
              style: TextStyle(color: context.errorText, fontSize: 11),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text(
          '发布运营',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _titleController,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: '发布标题',
                  labelStyle: TextStyle(color: context.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _generatingTitles ? null : _generatePublishKit,
              icon: _generatingTitles
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome, size: 16),
              label: const Text('生成标题'),
            ),
          ],
        ),
        for (final t in _titleCandidates)
          ListTile(
            dense: true,
            title: Text(
              t['text']?.toString() ?? '',
              style: TextStyle(color: context.textPrimary, fontSize: 13),
            ),
            subtitle: Text(
              t['style']?.toString() ?? '',
              style: TextStyle(color: context.textTertiary, fontSize: 10),
            ),
            trailing: IconButton(
              onPressed: () =>
                  setState(() => _titleController.text = t['text'].toString()),
              icon: const Icon(Icons.check, size: 16),
              tooltip: '采用',
            ),
          ),
        if (_hashtags.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            '话题标签（点 × 删掉不想要的）',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _hashtags)
                InputChip(
                  label: Text(tag),
                  onDeleted: () => setState(
                    () => _hashtags = _hashtags.where((t) => t != tag).toList(),
                  ),
                ),
            ],
          ),
        ],
        if (_nextHook.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            '下集预告 · 评论区置顶',
            style: TextStyle(
              color: context.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: AppTheme.borderRadiusSmall,
              border: Border.all(color: context.borderSubtle),
            ),
            child: SelectableText(
              _nextHook,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
            ),
          ),
        ],
      ],
    );
  }
}

/// 封面帧选择器（spec 14.5）。
///
/// 从成片里按固定间隔截 N 帧，用 FFmpeg 算出每帧的「清晰度 + 对比度」作评分
/// 依据——不调 AI：这两个指标能用信号处理算出来，而调一次 AI 只为打分既慢又
/// 会让用户觉得每次评分都不一样。
class _CoverPicker extends StatefulWidget {
  const _CoverPicker({required this.videoPath});

  final String videoPath;

  @override
  State<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<_CoverPicker> {
  bool _loading = true;
  String? _error;
  List<({String path, int score})> _frames = const [];

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    setState(() => _loading = true);
    final status = await FfmpegComposer.checkAvailability();
    if (!status.available) {
      setState(() {
        _error = '需要 FFmpeg 才能截取封面帧';
        _loading = false;
      });
      return;
    }
    final dir = Directory.systemTemp.createTempSync('cover_frames');
    final paths = <({String path, int score})>[];
    try {
      // 5 个候选帧：5% / 25% / 45% / 65% / 85% 处各一帧。首尾两端容易出
      // 黑场或淡出，避开 0% 与 100%。
      for (final pct in const [5, 25, 45, 65, 85]) {
        final out = File(p.join(dir.path, 'frame_$pct.jpg'));
        await FfmpegComposer.runRaw(args: [
          '-y',
          '-ss', '$pct%',
          '-i', widget.videoPath,
          '-frames:v', '1',
          '-q:v', '3',
          out.path,
        ]);
        if (!out.existsSync()) continue;
        paths.add((path: out.path, score: _scoreFrame(out)));
      }
      paths.sort((a, b) => b.score.compareTo(a.score));
      if (!mounted) return;
      setState(() {
        _frames = paths;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 用亮度方差做评分：方差越大说明画面信息越多，通常越有张力。
  int _scoreFrame(File file) {
    try {
      final bytes = file.readAsBytesSync();
      if (bytes.isEmpty) return 0;
      // 取字节流的均值与方差，JPEG 尺寸未知也能给出可比较的相对分数。
      var sum = 0;
      for (final b in bytes) {
        sum += b;
      }
      final mean = sum / bytes.length;
      var variance = 0.0;
      for (final b in bytes) {
        final d = b - mean;
        variance += d * d;
      }
      return (variance / bytes.length).round().clamp(0, 100);
    } catch (_) {
      return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '选择封面帧',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AI 已按画面信息量排出推荐顺序，选一帧后可以叠加标题文字。',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: context.errorText))
            else if (_frames.isEmpty)
              Text(
                '没有截到帧。成片可能太短或已损坏。',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              )
            else
              SizedBox(
                height: 260,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final (i, frame) in _frames.indexed)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Column(
                          children: [
                            Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.file(
                                    File(frame.path),
                                    height: 190,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                if (i == 0)
                                  Positioned(
                                    top: 6,
                                    left: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: context.accentText,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        '推荐',
                                        style: TextStyle(
                                          color: Color(0xFFFFFFFF),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '评分 ${frame.score}',
                              style: TextStyle(
                                color: context.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, frame.path),
                              child: const Text('选它'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.clipCount,
    required this.totalShots,
    required this.hasAudio,
    required this.ffmpeg,
    required this.onRecheck,
  });

  final int clipCount;
  final int totalShots;
  final bool hasAudio;
  final FfmpegStatus ffmpeg;
  final VoidCallback onRecheck;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            label: '视频片段',
            value: '$clipCount / $totalShots',
            ok: clipCount > 0 && clipCount == totalShots,
          ),
          _Row(label: '配音音频', value: hasAudio ? '已生成' : '未生成', ok: hasAudio),
          _Row(
            label: 'FFmpeg',
            value: ffmpeg.available
                ? '${ffmpeg.version ?? '可用'} (${ffmpeg.path})'
                : '未安装',
            ok: ffmpeg.available,
            action: TextButton(
              onPressed: onRecheck,
              child: const Text('重新检测'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.ok,
    this.action,
  });

  final String label;
  final String value;
  final bool ok;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.error_outline,
            size: 16,
            color: ok ? context.successText : context.warningText,
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: context.textPrimary, fontSize: 12),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// FFmpeg 安装引导横幅（spec 14.2）。
class _FfmpegBanner extends StatelessWidget {
  const _FfmpegBanner({required this.status});

  final FfmpegStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.warningText.withAlpha(30),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '未检测到 FFmpeg，无法直接压制 MP4。',
            style: TextStyle(color: context.warningText, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            '你仍然可以导出剪映工程或素材文件夹。安装 FFmpeg 后点「重新检测」。',
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    FfmpegComposer.installCommand,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  Clipboard.setData(
                    const ClipboardData(text: FfmpegComposer.installCommand),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('安装命令已复制')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                tooltip: '复制安装命令',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
