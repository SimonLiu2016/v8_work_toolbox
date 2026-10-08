/// 分镜可视化看板：卡片列表 + AI 拆分 + 内联编辑 + 运镜推荐 + 生成状态。
///
/// spec 11.1-11.8 / 12.1-12.5。这一页是工坊的心脏，所有能力都汇到分镜卡片上。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path/path.dart' as p;

import '../../../components/app_components.dart';
import '../../../shell/ai_config_page.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/ai_constraint_engine.dart';
import '../../ai_video_studio/services/image_gen_adapter.dart';
import '../../ai_video_studio/services/prompt_assembler.dart';
import '../../ai_video_studio/services/studio_generation_tasks.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../../ai_video_studio/services/studio_task_queue.dart';
import '../../ai_video_studio/services/video_gen_adapter.dart';
import 'studio_shell.dart';

class StoryboardBoard extends StatefulWidget {
  const StoryboardBoard({super.key, required this.session});

  final StudioSession session;

  @override
  State<StoryboardBoard> createState() => _StoryboardBoardState();
}

class _StoryboardBoardState extends State<StoryboardBoard> {
  final _manager = StudioProjectManager.instance;
  final _queue = StudioTaskQueue.instance;
  final _synopsisController = TextEditingController();

  final Map<int, Timer> _editDebounce = {};
  final Map<int, TextEditingController> _dialogueControllers = {};
  final Map<int, TextEditingController> _actionControllers = {};

  bool _breaking = false;
  String? _error;

  /// 新建本集时数据层注入的前情上下文（spec 11.7）。
  String _memoryContext = '';

  StudioEpisode? _episode;
  List<StudioEpisode> _allEpisodes = const [];
  List<SceneCard> _scenes = const [];

  @override
  void initState() {
    super.initState();
    _episode = widget.session.episode;
    if (_episode != null) {
      _synopsisController.text = _episode!.synopsis;
    }
    _loadContextData();
    _queue.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadContextData() async {
    final series = widget.session.series;
    if (series == null) return;
    final episodes = await _manager.listEpisodes(series.id);
    final scenes = await _manager.listScenes(series.id);
    if (!mounted) return;

    StudioEpisode? target = _episode;
    if (target == null && episodes.isNotEmpty) {
      target = episodes.first;
      widget.session.selectEpisode(target);
    } else if (target != null) {
      final matched = episodes.where((e) => e.id == target!.id).firstOrNull;
      if (matched != null) target = matched;
    }

    setState(() {
      _allEpisodes = episodes;
      _scenes = scenes;
      _episode = target;
      if (target != null && _synopsisController.text != target.synopsis) {
        _synopsisController.text = target.synopsis;
      }
    });
  }

  Future<void> _switchEpisode(StudioEpisode ep) async {
    for (final t in _editDebounce.values) {
      t.cancel();
    }
    _editDebounce.clear();
    for (final c in _dialogueControllers.values) {
      c.dispose();
    }
    _dialogueControllers.clear();
    for (final c in _actionControllers.values) {
      c.dispose();
    }
    _actionControllers.clear();

    widget.session.selectEpisode(ep);
    setState(() {
      _episode = ep;
      _synopsisController.text = ep.synopsis;
    });
    await _loadContextData();
  }

  Future<void> _createNewEpisode() async {
    final series = widget.session.series;
    if (series == null) return;
    final created = await _manager.createEpisode(seriesId: series.id);
    _memoryContext = created.memoryContext;
    await _switchEpisode(created.episode);
  }

  @override
  void dispose() {
    for (final t in _editDebounce.values) {
      t.cancel();
    }
    for (final c in _dialogueControllers.values) {
      c.dispose();
    }
    for (final c in _actionControllers.values) {
      c.dispose();
    }
    _synopsisController.dispose();
    super.dispose();
  }

  Future<void> _ensureEpisode() async {
    if (_episode != null) return;
    await _createNewEpisode();
  }

  Future<void> _breakdown() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final synopsis = _synopsisController.text.trim();
    if (synopsis.isEmpty) return;

    setState(() {
      _breaking = true;
      _error = null;
    });
    try {
      final characters = await _manager.listCharacters(series.id);
      final scenes = await _manager.listScenes(series.id);
      // 跨集上下文：新建本集时拿到的前情摘要 + 上集钩子（spec 11.7）。
      final result = await AiConstraintEngine.scriptBreakdown(
        synopsis: synopsis,
        context: ScriptContext(
          seriesName: series.name,
          productionType: series.productionType.id,
          styleTokens: series.styleTokens,
          memoryContext: _memoryContext,
          episodeIndex: episode.index,
          characterNames: characters.map((c) => c.name).toList(),
          sceneNames: scenes.map((s) => s.name).toList(),
        ),
      );
      final shots = ((result.data['shots'] as List)
              .cast<Map<String, dynamic>>())
          .map(_shotFromJson)
          .toList();
      final saved = episode.copyWith(synopsis: synopsis, shots: shots);
      await _manager.saveEpisode(saved);
      _reload();

      // 11.8：本集落盘后立刻抽摘要写进剧情记忆库。放在这里而不是等用户点
      // 「完成」，是因为人很可能拆完分镜就直接切窗口——摘要丢了，下一集
      // 的上下文注入就断一截。
      _summarizeEpisode(saved);
    } on ConstraintParseError catch (e) {
      if (!mounted) return;
      setState(() => _error = 'AI 输出无法解析，原文已保留：\n${e.rawText}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _breaking = false);
    }
  }

  /// 生成一句话摘要 + 末尾钩子，写进记忆库（spec 11.8）。
  ///
  /// 后台跑，不阻塞用户：摘要失败只影响后续集数的上下文质量，不该让眼前
  /// 已经拆好的分镜陪着一起报错。
  Future<void> _summarizeEpisode(StudioEpisode episode) async {
    final series = widget.session.series;
    if (series == null) return;
    try {
      final result = await AiConstraintEngine.episodeSummary(
        synopsis: episode.synopsis,
        shotsSummary: episode.shots
            .map((s) => '${s.number}. ${s.actionZh}')
            .join('\n'),
      );
      await _manager.upsertEpisodeMemory(
        seriesId: series.id,
        episodeId: episode.id,
        title: episode.title,
        summary: result.data['summary'] as String? ?? '',
        hook: result.data['hook'] as String? ?? '',
        shotCount: episode.shots.length,
      );
      widget.session.select(_manager.readSeries(series.id));
    } catch (e) {
      debugPrint('剧情摘要生成失败（不影响已保存的分镜）: $e');
    }
  }

  StudioShot _shotFromJson(Map<String, dynamic> json) {
    return StudioShot(
      number: (json['number'] as num).toInt(),
      durationSec: (json['duration_sec'] as num).toDouble(),
      shotSize: StudioShotSize.fromId(json['shot_size'] as String?),
      mood: json['mood'] as String? ?? 'warm',
      function: ShotFunction.fromId(json['function'] as String?),
      actionZh: json['action_zh'] as String? ?? '',
      dialogue: json['dialogue'] as String? ?? '',
      characterIds:
          (json['character_ids'] as List?)?.cast<String>() ?? const [],
      sceneId: json['scene_id'] as String? ?? '',
      cameraMove: json['camera_move'] as String? ?? '',
    );
  }

  void _reload() {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final fresh = _manager.readEpisode(series.id, episode.id);
    if (fresh == null) return;
    setState(() => _episode = fresh);
    widget.session.selectEpisode(fresh);
  }

  /// 内联编辑后 2 秒内重算 Prompt（spec 11.4）。
  void _onShotEdited(int shotNumber, StudioShot updated) {
    final episode = _episode;
    if (episode == null) return;
    final index = episode.shots.indexWhere((s) => s.number == shotNumber);
    if (index < 0) return;
    final shots = episode.shots.toList();
    shots[index] = updated;
    _episode = episode.copyWith(shots: shots);

    _editDebounce[shotNumber]?.cancel();
    _editDebounce[shotNumber] = Timer(
      const Duration(seconds: 2),
      () => _reassemblePrompt(shotNumber),
    );
  }

  Future<void> _reassemblePrompt(int shotNumber) async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final index = episode.shots.indexWhere((s) => s.number == shotNumber);
    if (index < 0) return;
    final shot = episode.shots[index];

    final characters = await _manager.listCharacters(series.id);
    final scenes = await _manager.listScenes(series.id);
    final character = shot.characterIds.isEmpty
        ? null
        : characters.where((c) => c.id == shot.characterIds.first).firstOrNull;
    final scene = scenes.where((s) => s.id == shot.sceneId).firstOrNull;

    final assembled = PromptAssembler.buildShotPrompt(PromptParts(
      styleTokens: series.styleTokens,
      shotSize: ShotSizeTokens.of(shot.shotSize),
      mood: MoodTokens.of(shot.mood),
      shotFunction: ShotFunctionTokens.of(shot.function),
      character: character,
      variation: character?.activeVariation,
      scene: scene,
      cameraMove: shot.cameraMove,
    ));

    final shots = episode.shots.toList();
    shots[index] = shot.copyWith(assembledPrompt: assembled.positive);
    _episode = episode.copyWith(shots: shots);
    await _manager.saveEpisode(_episode!);
    if (mounted) setState(() {});
  }

  /// 运镜方案推荐面板（spec 11.5）。
  ///
  /// 方案是**规则表**而不是 AI 生成的：情绪 → 适配的运镜集合这段知识是稳定的
  /// 影视语法，写进提示词只会让 AI 每次给出不同措辞，而用户要的是「选一个」。
  /// 评分按「与情绪的匹配度 + 变化幅度」算，让推荐项可解释。
  Future<void> _openCameraPanel(StudioShot shot) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => _CameraMoveSheet(shot: shot),
    );
    if (picked == null) return;
    final updated = shot.copyWith(cameraMove: picked);
    _onShotEdited(shot.number, updated);
    await _reassemblePrompt(shot.number);
  }

  /// 单镜 AI 重新生成（spec 11.6）：只改这一个分镜，其余不动。
  Future<void> _regenerateShot(StudioShot shot) async {
    final series = widget.session.series;
    if (series == null) return;
    setState(() => _error = null);
    try {
      final result = await AiConstraintEngine.shotRegenerate(
        currentShotJson: jsonEncode(_shotToJson(shot)),
        instruction: '按现有设定改进这个分镜，保持镜号 ${shot.number} 不变',
        context: ScriptContext(
          seriesName: series.name,
          productionType: series.productionType.id,
          styleTokens: series.styleTokens,
        ),
      );
      final updated = _shotFromJson(
        (result.data['shot'] as Map).map((k, v) => MapEntry(k as String, v)),
      ).copyWith(
        // 保留生成产物与已选运镜：重新生成只重写「内容」，不该让用户
        // 已经生好的关键帧与视频从磁盘上失联。
        framePath: shot.framePath,
        clipPath: shot.clipPath,
        audioPath: shot.audioPath,
        audioDurationMs: shot.audioDurationMs,
        bgmPath: shot.bgmPath,
        status: shot.status,
        assembledPrompt: shot.assembledPrompt,
      );
      final episode = _episode;
      if (episode == null) return;
      final shots = episode.shots.toList();
      final idx = shots.indexWhere((s) => s.number == shot.number);
      if (idx < 0) return;
      shots[idx] = updated;
      await _manager.saveEpisode(episode.copyWith(shots: shots));
      _reload();
      await _reassemblePrompt(shot.number);
    } on ConstraintParseError catch (e) {
      if (!mounted) return;
      setState(() => _error = 'AI 输出无法解析，原文已保留：\n${e.rawText}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  /// 反向序列化：把分镜写成 AI 能读的 JSON。
  Map<String, dynamic> _shotToJson(StudioShot shot) => {
    'number': shot.number,
    'duration_sec': shot.durationSec,
    'shot_size': shot.shotSize.id,
    'mood': shot.mood,
    'function': shot.function.id,
    'action_zh': shot.actionZh,
    'dialogue': shot.dialogue,
    'character_ids': shot.characterIds,
    'scene_id': shot.sceneId,
    'camera_move': shot.cameraMove,
  };

  Future<void> _enqueueFrame(StudioShot shot) async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final characters = await _manager.listCharacters(series.id);
    final character = shot.characterIds.isEmpty
        ? null
        : characters.where((c) => c.id == shot.characterIds.first).firstOrNull;

    final adapter = await ImageGenAdapterFactory.create();
    _queue.enqueue(
      kind: StudioTaskKind.image,
      shotNumber: shot.number,
      label: '分镜 ${shot.number} 关键帧',
      runner: ImageGenTask(
        taskId: 'img-${shot.number}',
        seriesId: series.id,
        episodeId: episode.id,
        shotNumber: shot.number,
        adapter: adapter,
        character: character,
        variation: character?.activeVariation,
        styleTokens: series.styleTokens,
        onPersisted: (_) => _reload(),
      ),
    );
  }

  Future<void> _enqueueAllFrames() async {
    final episode = _episode;
    if (episode == null) return;
    for (final shot in episode.shots) {
      if (shot.framePath != null && shot.framePath!.isNotEmpty) continue;
      await _enqueueFrame(shot);
    }
  }

  Future<void> _enqueueClip(StudioShot shot) async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final adapter = await VideoGenAdapterFactory.create(
      productionType: series.productionType.id,
    );
    if (!await adapter.isAvailable()) {
      if (mounted) {
        _showVideoEngineUnavailableDialog(context);
      }
      return;
    }
    _queue.enqueue(
      kind: StudioTaskKind.video,
      shotNumber: shot.number,
      label: '分镜 ${shot.number} 视频',
      runner: VideoGenTask(
        taskId: 'vid-${shot.number}',
        seriesId: series.id,
        episodeId: episode.id,
        shotNumber: shot.number,
        adapter: adapter,
        onPersisted: (_) => _reload(),
      ),
    );
  }

  void _showVideoEngineUnavailableDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Row(
          children: [
            Icon(
              Icons.videocam_off_outlined,
              color: context.warningSolid,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text('未检测到可用的视频生成引擎', style: AppTheme.fontTitle),
          ],
        ),
        content: const SizedBox(
          width: 440,
          child: Text(
            '当前系统既未在「AI 基础设施」中配置可用的视频模型（如 SenseAudio），'
            '本地亦未检测到 FFmpeg 动效环境。\n\n'
            '您可以前往系统配置添加视频模型（支持 SenseAudio 官方视频大模型等），'
            '或者在电脑中安装 FFmpeg 以启用本地免费动效。',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
        ),
        actions: [
          AppButton.ghost(
            label: '稍后再说',
            onPressed: () => Navigator.pop(ctx),
          ),
          AppButton.primary(
            label: '前往 AI 基础设施配置',
            icon: Icons.settings_suggest_outlined,
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (navCtx) => Scaffold(
                    appBar: AppBar(
                      title: const Text('AI 基础设施配置'),
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back),
                        onPressed: () => Navigator.of(navCtx).pop(),
                      ),
                    ),
                    body: const AiConfigPage(),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeSelectorBar(BuildContext context) {
    if (_allEpisodes.isEmpty && _episode == null) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: context.bgCard,
        border: Border(
          top: BorderSide(color: context.borderSubtle),
          bottom: BorderSide(color: context.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.video_library_outlined, size: 16, color: context.textTertiary),
          const SizedBox(width: 8),
          Text(
            '分集导航:',
            style: TextStyle(
              color: context.textTertiary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _allEpisodes.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final ep = _allEpisodes[i];
                final isSelected = _episode?.id == ep.id;
                return Center(
                  child: InkWell(
                    onTap: () => _switchEpisode(ep),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryColor : context.bgInput,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected ? primaryColor : context.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ep.title,
                            style: TextStyle(
                              color: isSelected ? Colors.white : context.textPrimary,
                              fontSize: 12,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.25)
                                  : context.borderSubtle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${ep.shots.length}镜',
                              style: TextStyle(
                                fontSize: 10,
                                color: isSelected ? Colors.white : context.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _createNewEpisode,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.bgInput,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 14, color: primaryColor),
                  const SizedBox(width: 4),
                  Text(
                    '新建第${_allEpisodes.length + 1}集',
                    style: TextStyle(
                      color: primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final episode = _episode;
    final seriesId = widget.session.series?.id ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Text(
                episode?.title ?? '分镜看板',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              if (_queue.activeCount > 0)
                _ActiveBadge(count: _queue.activeCount),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _queue.activeCount == 0 ? null : _showQueueDrawer,
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text('任务队列'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: episode == null || _breaking ? null : _breakdown,
                icon: _breaking
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 16),
                label: Text(_breaking ? '拆分中…' : 'AI 拆分分镜'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: episode == null ? null : _enqueueAllFrames,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('批量生成关键帧'),
              ),
            ],
          ),
        ),
        _buildEpisodeSelectorBar(context),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8, bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.errorText.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _error!,
                maxLines: 10,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.errorText, fontSize: 11),
              ),
            ),
          ),
        Expanded(
          child: episode == null
              ? _buildNoEpisode(context)
              : episode.shots.isEmpty
                  ? _buildNoShots(context)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
                      itemCount: episode.shots.length + 1,
                      itemBuilder: (context, i) {
                        if (i == 0) return _SynopsisCard(episode: episode);
                        final shot = episode.shots[i - 1];
                        return _ShotCard(
                          shot: shot,
                          scenes: _scenes,
                          queue: _queue,
                          framesDir: _manager
                              .episodeFramesDir(seriesId, episode.id)
                              .path,
                          clipsDir: _manager
                              .episodeClipsDir(seriesId, episode.id)
                              .path,
                          seriesName: widget.session.series?.name ?? '',
                          episodeTitle: episode.title,
                          dialogueController: _dialogueControllers
                              .putIfAbsent(
                            shot.number,
                            () => TextEditingController(text: shot.dialogue),
                          ),
                          actionController: _actionControllers.putIfAbsent(
                            shot.number,
                            () => TextEditingController(text: shot.actionZh),
                          ),
                          onEdited: (updated) =>
                              _onShotEdited(shot.number, updated),
                          onGenerateFrame: () => _enqueueFrame(shot),
                          onGenerateClip: () => _enqueueClip(shot),
                          onOpenCameraPanel: () => _openCameraPanel(shot),
                          onRegenerateShot: () => _regenerateShot(shot),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildNoEpisode(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_outlined, size: 44, color: context.textTertiary),
          const SizedBox(height: 10),
          Text(
            '还没有集。',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _ensureEpisode,
            child: const Text('新建第一集'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoShots(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _synopsisController,
              maxLines: 6,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: '本集粗剧情大纲',
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: '用几句中文描述这一集发生了什么， AI 会拆成分镜',
                hintStyle: TextStyle(color: context.textDisabled, fontSize: 12),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _breaking ? null : _breakdown,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('AI 拆分分镜'),
            ),
          ],
        ),
      ),
    );
  }

  void _showQueueDrawer() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgCard,
      isScrollControlled: true,
      builder: (_) => _QueueDrawer(queue: _queue),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count 个任务',
        style: TextStyle(color: context.accentText, fontSize: 11),
      ),
    );
  }
}

class _SynopsisCard extends StatelessWidget {
  const _SynopsisCard({required this.episode});

  final StudioEpisode episode;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本集大纲',
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            episode.synopsis.isEmpty ? '（未填写）' : episode.synopsis,
            style: TextStyle(color: context.textPrimary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ShotCard extends StatelessWidget {
  const _ShotCard({
    required this.shot,
    required this.scenes,
    required this.queue,
    required this.dialogueController,
    required this.actionController,
    required this.onEdited,
    required this.onGenerateFrame,
    required this.onGenerateClip,
    required this.onOpenCameraPanel,
    required this.onRegenerateShot,
    required this.framesDir,
    required this.clipsDir,
    required this.seriesName,
    required this.episodeTitle,
  });

  final StudioShot shot;
  final List<SceneCard> scenes;
  final StudioTaskQueue queue;
  final TextEditingController dialogueController;
  final TextEditingController actionController;

  /// `frames/` 的绝对目录（`storyboard.json` 里只存文件名）。
  final String framesDir;

  /// `clips/` 的绝对目录。
  final String clipsDir;
  final String seriesName;
  final String episodeTitle;

  final ValueChanged<StudioShot> onEdited;
  final VoidCallback onGenerateFrame;
  final VoidCallback onGenerateClip;

  /// 打开运镜方案推荐面板（spec 11.5）。
  final VoidCallback onOpenCameraPanel;

  /// 单镜 AI 重新生成（spec 11.6）。
  final VoidCallback onRegenerateShot;

  File? get _clipFile {
    final name = shot.clipPath;
    if (name == null || name.isEmpty) return null;
    return File('$clipsDir/$name');
  }

  File? get _frameFile {
    final name = shot.framePath;
    if (name == null || name.isEmpty) return null;
    return File('$framesDir/$name');
  }

  bool get _hasMedia {
    final c = _clipFile;
    if (c != null && c.existsSync()) return true;
    final f = _frameFile;
    if (f != null && f.existsSync()) return true;
    return false;
  }

  void _openPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MediaPreviewDialog(
        shot: shot,
        framesDir: framesDir,
        clipsDir: clipsDir,
        seriesName: seriesName,
        episodeTitle: episodeTitle,
      ),
    );
  }

  Future<void> _revealInFinder() async {
    final target = (_clipFile != null && _clipFile!.existsSync())
        ? _clipFile
        : ((_frameFile != null && _frameFile!.existsSync()) ? _frameFile : null);
    if (target != null && target.existsSync()) {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', target.path]);
      }
    }
  }

  Future<void> _exportFile(BuildContext context) async {
    final target = (_clipFile != null && _clipFile!.existsSync())
        ? _clipFile
        : ((_frameFile != null && _frameFile!.existsSync()) ? _frameFile : null);
    if (target == null || !target.existsSync()) return;

    final ext = p.extension(target.path);
    final isVideo = _clipFile != null && _clipFile!.existsSync();
    final defaultName =
        '${seriesName}_${episodeTitle}_shot_${shot.number}${isVideo ? ext : (ext.isEmpty ? ".png" : ext)}';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出素材到本地',
      fileName: defaultName,
    );
    if (savePath != null) {
      await target.copy(savePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('素材已导出到: $savePath')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = queue.tasksForShot(shot.number);
    final running =
        tasks.where((t) => t.status == StudioTaskStatus.running).toList();
    final failed = tasks.where((t) => t.status == StudioTaskStatus.failed);
    final tooLong = shot.isDialogueTooLong;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: tooLong ? context.warningText : context.borderSubtle,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Thumbnail(
            shot: shot,
            running: running.isNotEmpty,
            framesDir: framesDir,
            clipsDir: clipsDir,
            onTap: () => _openPreview(context),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${shot.number}',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Tag(text: shot.shotSize.label),
                      const SizedBox(width: 4),
                      _Tag(text: ShotMood.fromId(shot.mood).label),
                      const SizedBox(width: 4),
                      _Tag(text: shot.function.label),
                      const Spacer(),
                      _StatusBadge(tasks: tasks),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.landscape_outlined, size: 14, color: context.textTertiary),
                      const SizedBox(width: 4),
                      Text('场景:', style: TextStyle(color: context.textTertiary, fontSize: 11)),
                      const SizedBox(width: 6),
                      DropdownButton<String>(
                        value: scenes.any((s) => s.id == shot.sceneId) ? shot.sceneId : '',
                        isDense: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: context.bgCard,
                        style: TextStyle(color: context.textPrimary, fontSize: 11),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text('无关联场景', style: TextStyle(color: context.textTertiary, fontSize: 11)),
                          ),
                          ...scenes.map((s) => DropdownMenuItem(
                                value: s.id,
                                child: Text(s.name, style: TextStyle(fontSize: 11)),
                              )),
                        ],
                        onChanged: (val) {
                          onEdited(shot.copyWith(sceneId: val ?? ''));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dialogueController,
                    maxLines: 2,
                    onChanged: (v) =>
                        onEdited(shot.copyWith(dialogue: v)),
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '台词',
                      labelStyle: TextStyle(
                        color: context.textTertiary,
                        fontSize: 11,
                      ),
                      suffixText: '${shot.dialogue.trim().length}'
                          '/${shot.dialogueCharLimit}',
                    ),
                  ),
                  if (tooLong)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '台词过长：${shot.dialogue.trim().length} 字 > '
                        '${shot.durationSec.toInt()} 秒可容纳的 '
                        '${shot.dialogueCharLimit} 字',
                        style: TextStyle(
                          color: context.warningText,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: actionController,
                    maxLines: 2,
                    onChanged: (v) => onEdited(shot.copyWith(actionZh: v)),
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '画面动作',
                      labelStyle: TextStyle(
                        color: context.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: onGenerateFrame,
                        icon: const Icon(Icons.image_outlined, size: 15),
                        label: const Text('关键帧'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onGenerateClip,
                        icon: const Icon(Icons.movie_outlined, size: 15),
                        label: const Text('视频'),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onOpenCameraPanel,
                        icon: const Icon(Icons.videocam_outlined, size: 15),
                        label: Text(
                          shot.cameraMove.isEmpty ? '运镜' : shot.cameraMove,
                        ),
                      ),
                      if (_hasMedia) ...[
                        const SizedBox(width: 4),
                        TextButton.icon(
                          onPressed: () => _openPreview(context),
                          icon: const Icon(Icons.fullscreen, size: 15),
                          label: const Text('预览'),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, size: 16),
                          tooltip: '素材操作',
                          color: context.bgCard,
                          onSelected: (act) {
                            if (act == 'finder') _revealInFinder();
                            if (act == 'export') _exportFile(context);
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'finder',
                              child: Row(
                                children: [
                                  Icon(Icons.folder_open_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('在访达中显示', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text('导出保存到本地', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (failed.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          failed.first.error ?? '失败',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.errorText,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (shot.assembledPrompt.isNotEmpty) ...[
                    const Divider(height: 16),
                    Text(
                      shot.assembledPrompt,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textTertiary,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.shot,
    required this.running,
    required this.framesDir,
    required this.clipsDir,
    required this.onTap,
  });

  final StudioShot shot;
  final bool running;
  final String framesDir;
  final String clipsDir;
  final VoidCallback onTap;

  File? get _frameFile {
    final name = shot.framePath;
    if (name == null || name.isEmpty) return null;
    return File('$framesDir/$name');
  }

  File? get _clipFile {
    final name = shot.clipPath;
    if (name == null || name.isEmpty) return null;
    return File('$clipsDir/$name');
  }

  @override
  Widget build(BuildContext context) {
    final hasClip = _clipFile != null && _clipFile!.existsSync();
    final hasFrame = _frameFile != null && _frameFile!.existsSync();
    final hasAnyMedia = hasClip || hasFrame;

    return MouseRegion(
      cursor: hasAnyMedia ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: hasAnyMedia ? onTap : null,
        child: Container(
          width: 80,
          height: 136,
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.bgInput,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (running)
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (hasFrame)
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    _frameFile!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => Icon(
                      Icons.broken_image_outlined,
                      color: context.textTertiary,
                      size: 20,
                    ),
                  ),
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_outlined, color: context.textTertiary, size: 22),
                      const SizedBox(height: 4),
                      Text('未生成', style: TextStyle(color: context.textDisabled, fontSize: 10)),
                    ],
                  ),
                ),
              // 如果是视频，覆盖居中播放图标
              if (!running && hasClip)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                )
              else if (!running && hasFrame)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.zoom_in,
                      color: Colors.white,
                      size: 13,
                    ),
                  ),
                ),
              // 徽章与时长指示
              if (!running && hasClip) ...[
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '视频',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '${shot.durationSec.toStringAsFixed(1)}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ] else if (!running && hasFrame) ...[
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text(
                      '关键帧',
                      style: TextStyle(color: Colors.white, fontSize: 9),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({
    required this.shot,
    required this.framesDir,
    required this.clipsDir,
    required this.seriesName,
    required this.episodeTitle,
  });

  final StudioShot shot;
  final String framesDir;
  final String clipsDir;
  final String seriesName;
  final String episodeTitle;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  Player? _player;
  VideoController? _videoController;
  bool _hasClip = false;
  File? _clipFile;
  File? _frameFile;

  StreamSubscription? _errorSub;
  StreamSubscription? _videoParamsSub;
  bool _hasError = false;
  String? _errorMessage;
  double _aspectRatio = 9 / 16;

  @override
  void initState() {
    super.initState();
    final clipName = widget.shot.clipPath;
    if (clipName != null && clipName.isNotEmpty) {
      final f = File(p.join(widget.clipsDir, clipName));
      if (f.existsSync()) {
        _hasClip = true;
        _clipFile = f;
        _player = Player();
        _videoController = VideoController(_player!);
        _errorSub = _player!.stream.error.listen((err) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = err.toString();
            });
          }
        });
        _videoParamsSub = _player!.stream.videoParams.listen((params) {
          if (mounted && params.aspect != null && params.aspect! > 0) {
            setState(() {
              _aspectRatio = params.aspect!;
            });
          }
        });
        _player!.open(Media(f.path));
        _player!.setPlaylistMode(PlaylistMode.loop);
      }
    }
    final frameName = widget.shot.framePath;
    if (frameName != null && frameName.isNotEmpty) {
      final f = File(p.join(widget.framesDir, frameName));
      if (f.existsSync()) {
        _frameFile = f;
      }
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _videoParamsSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _revealInFinder() async {
    final target = _clipFile ?? _frameFile;
    if (target != null && target.existsSync()) {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', target.path]);
      }
    }
  }

  Future<void> _exportFile() async {
    final target = _clipFile ?? _frameFile;
    if (target == null || !target.existsSync()) return;
    final ext = p.extension(target.path);
    final isVideo = _clipFile != null;
    final fileName =
        '${widget.seriesName}_${widget.episodeTitle}_shot_${widget.shot.number}${isVideo ? ext : (ext.isEmpty ? ".png" : ext)}';

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出分镜素材',
      fileName: fileName,
    );
    if (savePath != null) {
      await target.copy(savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到: $savePath')),
        );
      }
    }
  }

  Future<void> _openSystemPlayer() async {
    if (_clipFile != null && _clipFile!.existsSync()) {
      await Process.run('open', [_clipFile!.path]);
    }
  }

  Widget _buildMediaContent() {
    if (_hasClip && _videoController != null) {
      if (_hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.orangeAccent,
                  size: 44,
                ),
                const SizedBox(height: 12),
                Text(
                  '内嵌播放器解码失败: ${_errorMessage ?? "格式不兼容"}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                AppButton.primary(
                  label: '使用系统播放器打开',
                  icon: Icons.launch,
                  onPressed: _openSystemPlayer,
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: AspectRatio(
          aspectRatio: _aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 关键帧垫底，防止视频纹理加载期间灰屏
              if (_frameFile != null && _frameFile!.existsSync())
                Image.file(_frameFile!, fit: BoxFit.contain)
              else
                Container(color: Colors.black),
              Video(controller: _videoController!),
            ],
          ),
        ),
      );
    }

    if (_frameFile != null && _frameFile!.existsSync()) {
      return InteractiveViewer(
        maxScale: 4.0,
        child: Center(child: Image.file(_frameFile!, fit: BoxFit.contain)),
      );
    }

    return const Center(
      child: Text(
        '未检测到已生成的媒体文件',
        style: TextStyle(color: Colors.white70, fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.pop(context);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Dialog(
        backgroundColor: context.bgCard,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(
          width: 860,
          height: 640,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border:
                      Border(bottom: BorderSide(color: context.borderSubtle)),
                ),
                child: Row(
                  children: [
                    AppButton.secondary(
                      label: '返回 (ESC)',
                      icon: Icons.arrow_back,
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '分镜 #${widget.shot.number} 媒体预览',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _hasClip
                            ? context.accentSubtle
                            : context.borderSubtle,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _hasClip
                            ? '视频片段 (${widget.shot.durationSec.toStringAsFixed(1)}s)'
                            : '关键帧大图',
                        style: TextStyle(
                          fontSize: 11,
                          color: _hasClip
                              ? context.accentText
                              : context.textSecondary,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (_hasClip)
                      IconButton(
                        tooltip: '系统播放器打开',
                        icon: const Icon(Icons.launch, size: 18),
                        onPressed: _openSystemPlayer,
                      ),
                    IconButton(
                      tooltip: '在访达中显示',
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      onPressed: _revealInFinder,
                    ),
                    IconButton(
                      tooltip: '导出保存到本地',
                      icon: const Icon(Icons.download_outlined, size: 18),
                      onPressed: _exportFile,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '关闭 (ESC)',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Container(
                  color: Colors.black,
                  child: _buildMediaContent(),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  border: Border(top: BorderSide(color: context.borderSubtle)),
                ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      _Tag(text: '景别: ${widget.shot.shotSize.label}'),
                      const SizedBox(width: 6),
                      _Tag(text: '情绪: ${ShotMood.fromId(widget.shot.mood).label}'),
                      const SizedBox(width: 6),
                      _Tag(text: '功能: ${widget.shot.function.label}'),
                      if (widget.shot.cameraMove.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _Tag(text: '运镜: ${widget.shot.cameraMove}'),
                      ],
                    ],
                  ),
                  if (widget.shot.actionZh.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '画面动作: ${widget.shot.actionZh}',
                      style: TextStyle(color: context.textPrimary, fontSize: 12),
                    ),
                  ],
                  if (widget.shot.dialogue.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '台词: ${widget.shot.dialogue}',
                      style: TextStyle(color: context.textSecondary, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(color: context.textSecondary, fontSize: 10),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.tasks});

  final List<StudioTask> tasks;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Text(
        '未生成',
        style: TextStyle(color: context.textDisabled, fontSize: 10),
      );
    }
    final last = tasks.last;
    final color = switch (last.status) {
      StudioTaskStatus.completed => context.successText,
      StudioTaskStatus.failed => context.errorText,
      StudioTaskStatus.running => context.infoText,
      StudioTaskStatus.cancelled => context.textTertiary,
      StudioTaskStatus.queued => context.textSecondary,
    };
    return Text(
      last.status.label,
      style: TextStyle(color: color, fontSize: 10),
    );
  }
}

class _QueueDrawer extends StatefulWidget {
  const _QueueDrawer({required this.queue});

  final StudioTaskQueue queue;

  @override
  State<_QueueDrawer> createState() => _QueueDrawerState();
}

class _QueueDrawerState extends State<_QueueDrawer> {
  @override
  Widget build(BuildContext context) {
    final tasks = widget.queue.tasks;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '任务队列',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    widget.queue.clearFinished();
                    setState(() {});
                  },
                  child: const Text('清掉已完成'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (tasks.isEmpty)
              Text(
                '队列是空的。',
                style: TextStyle(color: context.textTertiary, fontSize: 12),
              ),
            for (final task in tasks)
              ListTile(
                dense: true,
                leading: Icon(
                  task.kind == StudioTaskKind.image
                      ? Icons.image_outlined
                      : Icons.movie_outlined,
                  color: context.textSecondary,
                  size: 18,
                ),
                title: Text(
                  task.label,
                  style: TextStyle(color: context.textPrimary, fontSize: 12),
                ),
                subtitle: Text(
                  task.error ?? task.status.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: task.status == StudioTaskStatus.failed
                        ? context.errorText
                        : context.textTertiary,
                    fontSize: 11,
                  ),
                ),
                trailing: task.isTerminal
                    ? null
                    : IconButton(
                        onPressed: () {
                          widget.queue.cancel(task.id);
                        },
                        icon: const Icon(Icons.close, size: 16),
                        tooltip: '取消',
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 运镜方案候选表。
///
/// 每档方案带「适用情绪」与「预估视觉评分」。AI 推荐高亮 = 分数最高的那个，
/// 用户仍可自由改选。
class _CameraMoveSheet extends StatelessWidget {
  const _CameraMoveSheet({required this.shot});

  final StudioShot shot;

  /// 情绪 → 运镜候选。每种情绪给 3-4 个可选项，覆盖「推拉 / 平移 / 固定 /
  /// 环绕」四类基础运动，保证任何情绪下都凑得出三个方案。
  static const Map<String, List<({String move, int score, String note})>>
  _kPlans = {
    'depressing': [
      (move: 'slow pull-back, handheld', score: 92, note: '后退拉开甩下主角，适合颓势'),
      (move: 'static medium shot', score: 78, note: '固定机位让压抑感沉积'),
      (move: 'slow pan left', score: 70, note: '缓横移带出空荡环境'),
    ],
    'excited': [
      (move: 'fast push-in', score: 94, note: '快速推近制造冲击'),
      (move: 'low angle, tilt up', score: 85, note: '低角仰拍抬高气势'),
      (move: 'orbit around subject', score: 80, note: '环绕强调动态'),
    ],
    'warm': [
      (move: 'gentle push-in', score: 90, note: '轻推近拉近距离感'),
      (move: 'static two-shot', score: 82, note: '固定双人构图显亲密'),
      (move: 'slow pan right', score: 68, note: '缓横移带过环境'),
    ],
    'battle': [
      (move: 'fast push-in, dutch angle', score: 96, note: '斜角快推最烈'),
      (move: 'side tracking shot', score: 88, note: '侧面跟随打斗'),
      (move: 'whip pan', score: 84, note: '甩镜切换焦点'),
    ],
    'suspense': [
      (move: 'slow push-in, low key', score: 91, note: '慢推近逼出不安'),
      (move: 'static wide, subject small', score: 80, note: '小人物大环境显孤'),
      (move: 'over-the-shoulder', score: 74, note: '过肩暗示有人在看'),
    ],
    'relaxed': [
      (move: 'gentle pan right', score: 88, note: '缓横移显闲适'),
      (move: 'static wide', score: 80, note: '固定大场景留白'),
      (move: 'slow pull-back', score: 72, note: '缓拉远收住轻盈'),
    ],
    'sad': [
      (move: 'slow pull-back, soft focus', score: 93, note: '拉远+柔焦最哀'),
      (move: 'static close-up', score: 82, note: '固定特写盯表情'),
      (move: 'slow tilt down', score: 70, note: '下摇配合低落'),
    ],
  };

  List<({String move, int score, String note})> get plans {
    final list = _kPlans[shot.mood] ?? _kPlans['warm']!;
    // 至少 3 个候选（spec），不足时用通用项补齐。
    if (list.length >= 3) return list;
    return [
      ...list,
      ...const [
        (move: 'gentle push-in', score: 60, note: '通用缓推'),
        (move: 'static shot', score: 50, note: '固定机位'),
      ],
    ].take(3).toList();
  }

  ({String move, int score, String note})? get recommended {
    final sorted = plans.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sorted.isEmpty ? null : sorted.first;
  }

  @override
  Widget build(BuildContext context) {
    final best = recommended;
    return Dialog(
      backgroundColor: context.bgCard,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运镜方案 · 镜 ${shot.number} · '
              '${ShotMood.fromId(shot.mood).label}',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'AI 推荐评分最高的方案，选完会自动更新该镜的生图 Prompt。',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
            const SizedBox(height: 14),
            for (final plan in plans)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: plan == best
                      ? context.accentSubtle
                      : context.bgInput,
                  borderRadius: AppTheme.borderRadiusSmall,
                  border: Border.all(
                    color: plan == best
                        ? context.accentText
                        : context.borderSubtle,
                  ),
                ),
                child: ListTile(
                  dense: true,
                  leading: Icon(
                    plan == best
                        ? Icons.auto_awesome
                        : Icons.videocam_outlined,
                    size: 18,
                    color: plan == best
                        ? context.accentText
                        : context.textSecondary,
                  ),
                  title: Text(
                    plan.move,
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  subtitle: Text(
                    plan.note,
                    style: TextStyle(
                      color: context.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${plan.score}',
                        style: TextStyle(
                          color: plan == best
                              ? context.accentText
                              : context.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context, plan.move),
                        child: const Text('选用'),
                      ),
                    ],
                  ),
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
