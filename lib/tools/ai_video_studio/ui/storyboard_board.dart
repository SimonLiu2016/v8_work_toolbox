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
import '../../../services/ai_config_store.dart';
import '../../../services/keychain_service.dart';
import '../../../services/settings_store.dart';
import '../../../shell/ai_config_page.dart';
import '../../../theme/app_theme.dart';
import '../../ai_video_studio/models/studio_models.dart';
import '../../ai_video_studio/services/ai_constraint_engine.dart';
import '../../ai_video_studio/services/director_validation_engine.dart';
import '../../ai_video_studio/services/image_gen_adapter.dart';
import '../../ai_video_studio/services/keyframe_visual_critic.dart';
import '../../ai_video_studio/services/novel_import_task_service.dart';
import '../../ai_video_studio/services/prompt_assembler.dart';
import '../../ai_video_studio/services/studio_generation_tasks.dart';
import '../../ai_video_studio/services/studio_project_manager.dart';
import '../../ai_video_studio/services/studio_task_queue.dart';
import '../../ai_video_studio/services/video_gen_adapter.dart';
import '../services/asset_library.dart';
import '../services/storyboard_exporter.dart';
import '../../ai_video_studio/services/video_task_ledger.dart';
import '../../ai_video_studio/services/video_task_recovery.dart';
import '../../agnes_playground/models/playground_models.dart';
import '../../agnes_playground/services/playground_store.dart';
import '../../agnes_playground/ui/playground_page.dart';
import '../../registry.dart';
import 'studio_shell.dart';

/// 分镜看板的视图模式（spec: 分镜看板提供「按片段」与「按镜头」两种视图）。
enum _BoardView {
  /// 按片段：片段为可折叠分组，组头展示目标时长、边界理由与片段视频。
  bySegment,

  /// 按镜头：改造前的平铺形态，一行一张分镜卡。
  byShot,
}

class StoryboardBoard extends StatefulWidget {
  const StoryboardBoard({
    super.key,
    required this.session,
    this.onNavigateStage,
  });

  final StudioSession session;
  final ValueChanged<StudioStage>? onNavigateStage;

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

  StreamSubscription? _queueSub;

  bool _breaking = false;
  String? _error;

  /// 正在进行单镜 AI 改写的分镜编号集合（解耦单镜改写与大段生成状态）。
  final Set<int> _regeneratingShotNumbers = {};

  /// 新建本集时数据层注入的前情上下文（spec 11.7）。
  String _memoryContext = '';

  StudioEpisode? _episode;
  List<StudioEpisode> _allEpisodes = const [];
  List<SceneCard> _scenes = const [];
  List<CharacterCard> _characters = const [];
  List<PropCard> _props = const [];

  /// 看板视图模式（spec: 分镜看板提供「按片段」与「按镜头」两种视图）。
  ///
  /// 默认按片段：片段是现在的视频生成单元，用户主要在该视图下工作；
  /// 「按镜头」保留改造前的平铺形态，供逐镜微调台词/动作时使用。
  _BoardView _view = _BoardView.bySegment;

  @override
  void initState() {
    super.initState();
    _episode = widget.session.episode;
    if (_episode != null) {
      _synopsisController.text = _episode!.synopsis;
    }
    widget.session.addListener(_onSessionChanged);
    _loadContextData();
    _queueSub = _queue.stream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  void _onSessionChanged() {
    if (!mounted) return;
    final sessEp = widget.session.episode;
    if (_episode?.id != sessEp?.id ||
        _episode?.updatedAt != sessEp?.updatedAt ||
        _episode?.shots.length != sessEp?.shots.length ||
        _episode?.scenes.length != sessEp?.scenes.length) {
      setState(() {
        _episode = sessEp;
        if (sessEp != null) {
          _synopsisController.text = sessEp.synopsis;
        }
      });
      _loadContextData();
    }
  }

  Future<void> _loadContextData() async {
    final series = widget.session.series;
    if (series == null) return;
    final episodes = await _manager.listEpisodes(series.id);
    final scenes = await _manager.listScenes(series.id);
    final characters = await _manager.listCharacters(series.id);
    final props = await _manager.listProps(series.id);
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
      _characters = characters;
      _props = props;
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
    widget.session.removeListener(_onSessionChanged);
    _queueSub?.cancel();
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

  /// 一键根据剧本分场与节拍生成 5D 分镜（保真剧本内容并绑定真实场景与角色别名）。
  Future<void> _generateFromScreenplay() async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    if (episode.scenes.isEmpty ||
        episode.scenes.every((s) => s.beats.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前剧本没有场次或节拍，请先在剧本工作台添加节拍')));
      return;
    }

    setState(() {
      _breaking = true;
      _error = null;
    });

    try {
      final updatedCards = await _manager.ensureScenesForEpisode(
        seriesId: series.id,
        episode: episode,
      );
      final refreshedEp =
          _manager.readEpisode(series.id, episode.id) ?? episode;
      final newShots = AiConstraintEngine.convertScenesToShots(
        refreshedEp.scenes,
        characters: _characters,
        sceneCards: updatedCards,
      );
      final segments = StudioEpisode.buildSegmentsFromScenes(
        refreshedEp.scenes,
        newShots,
      );
      final updated = refreshedEp.copyWith(
        shots: newShots,
        segments: segments,
        updatedAt: DateTime.now(),
      );
      await _manager.saveEpisode(updated);
      _scenes = updatedCards;
      _reload();
      _summarizeEpisode(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已从剧本成功生成 ${newShots.length} 个5D分镜！')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _breaking = false);
      }
    }
  }

  /// 带确认弹窗的从剧本重新拆解分镜。
  Future<void> _confirmAndReBreakdownFromScreenplay() async {
    final episode = _episode;
    if (episode == null) return;
    if (episode.scenes.isEmpty ||
        episode.scenes.every((s) => s.beats.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前剧本没有场次或节拍，请先在剧本工作台添加节拍或使用 AI 生成剧本')),
      );
      return;
    }

    if (episode.shots.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.bgCard,
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, size: 20),
              SizedBox(width: 8),
              Text('从剧本重新拆解生成分镜'),
            ],
          ),
          content: Text(
            '重新拆镜将读取剧本工作台最新的 ${episode.scenes.length} 个戏剧场次与各场节拍，'
            '全量重新生成结构化分镜，并将覆盖当前已有的 ${episode.shots.length} 个分镜。\n\n'
            '系统将自动关联 IP 场景库卡片与角色别名。是否确认覆盖？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认重新拆镜'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    await _generateFromScreenplay();
  }

  /// 带高危防误触弹窗的一键清空本集分镜。
  /// 清空成功后的提示文案（spec: 归档位置对用户可见）。
  /// 导出整集分镜表到本地文件（支持 Markdown 与 CSV）
  Future<void> _exportStoryboardToFile(String format) async {
    final episode = widget.session.episode;
    final series = widget.session.series;
    if (episode == null || episode.shots.isEmpty) return;

    final seriesName = series?.name ?? '剧作';
    final isMd = format.toLowerCase() == 'md';
    final ext = isMd ? 'md' : 'csv';
    final defaultName = '${seriesName}_第${episode.index}集_${episode.title}_分镜表.$ext';

    final charMap = {for (final c in _characters) c.id: c.name};
    final propMap = {for (final p in _props) p.id: p.name};
    final sceneMap = {for (final s in _scenes) s.id: s.name};

    String contentToExport;
    if (isMd) {
      contentToExport = StoryboardExporter.exportToMarkdown(
        seriesTitle: seriesName,
        episode: episode,
        characterNames: charMap,
        propNames: propMap,
        sceneNames: sceneMap,
      );
    } else {
      contentToExport = StoryboardExporter.exportToCsv(
        seriesTitle: seriesName,
        episode: episode,
        characterNames: charMap,
        propNames: propMap,
        sceneNames: sceneMap,
      );
    }

    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出整集分镜表到本地',
        fileName: defaultName,
        type: FileType.custom,
        allowedExtensions: [ext],
      );
    } catch (_) {
      savePath = null;
    }

    if (savePath == null) return;

    try {
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsString(contentToExport);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('分镜表已成功导出到: $savePath'),
            action: SnackBarAction(
              label: '在访达中显示',
              onPressed: () {
                Process.run('open', ['-R', savePath!]);
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出分镜表失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _clearSnackbarText(int archivedCount, String? archiveError) {
    if (archiveError != null) {
      return '已清空当前集的所有分镜，但媒体归档失败：$archiveError';
    }
    if (archivedCount <= 0) {
      return '已清空当前集的所有分镜（无可归档的媒体文件）';
    }
    return '已清空当前集的所有分镜，$archivedCount 个媒体文件已归档到本集 archive/ 目录';
  }

  Future<void> _confirmAndClearAllShots() async {
    final ep = _episode;
    if (ep == null || ep.shots.isEmpty) return;
    final count = ep.shots.length;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: context.errorText,
            ),
            const SizedBox(width: 8),
            const Text('清空本集分镜'),
          ],
        ),
        content: Text(
          '警告：此操作将彻底清空当前集的全部 $count 个分镜卡片以及大段划分，重置为空白看板状态。\n\n'
          '已拆解的台词、动作描写与提示词将被删除。已生成的视频、关键帧、片段与台词音频'
          '将被移入 archive/archived_<时间戳>/ 目录（不再留在制作目录，避免与重新拆出的分镜混淆），'
          '导出的成片保持原处不动。是否确认继续清空？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.errorSolid),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final cleared = ep.clearShots();
    await _manager.saveEpisode(cleared);

    // 归档物理媒体（spec: 清空本集分镜时归档物理媒体）。
    //
    // archiveEpisodeMedia 早就写好了，但一直没有调用方——于是清空后旧视频原封
    // 不动留在 clips/，与新拆出的分镜共用 shot_<n>.mp4 命名空间。归档失败不
    // 阻断清空主流程（分镜数据已经没了，回不去），但必须告知用户。
    var archivedCount = 0;
    String? archiveError;
    try {
      archivedCount = await _manager.archiveEpisodeMedia(ep.seriesId, ep.id);
    } catch (e) {
      archiveError = e.toString();
    }

    _reload();
    _summarizeEpisode(cleared);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_clearSnackbarText(archivedCount, archiveError)),
        ),
      );
    }
  }

  /// 删除指定镜号的分镜。
  Future<void> _confirmAndDeleteShot(int shotNumber) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Row(
          children: [
            Icon(Icons.delete_outline, size: 20, color: context.errorText),
            const SizedBox(width: 8),
            Text('删除分镜 #$shotNumber'),
          ],
        ),
        content: Text(
          '确认删除分镜 #$shotNumber 吗？删除后后续所有分镜镜号将自动向前递减平移，并重新统计所属场次的总时长。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.errorSolid),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final ep = _episode;
    if (ep == null) return;
    final updated = ep.deleteShot(shotNumber);
    await _manager.saveEpisode(updated);
    _reload();
    _summarizeEpisode(updated);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已删除分镜 #$shotNumber')));
    }
  }

  /// 在指定分镜后插入新镜头。
  Future<void> _insertShotAfter(int shotNumber) async {
    final ep = _episode;
    if (ep == null) return;
    final updated = ep.insertShotAfter(shotNumber);
    await _manager.saveEpisode(updated);
    _reload();
    _summarizeEpisode(updated);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已在分镜 #$shotNumber 后插入新分镜')));
    }
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
      // 跨集上下文：新建本集时拿到的前情摘要 + 上集钩子（spec 11.7），并注入受保护契约与场次规划
      final result = await AiConstraintEngine.scriptBreakdown5D(
        synopsis: synopsis,
        context: ScriptContext(
          seriesName: series.name,
          productionType: series.productionType.id,
          styleTokens: series.styleTokens,
          memoryContext: _memoryContext,
          episodeIndex: episode.index,
          characterNames: characters.map((c) => c.name).toList(),
          sceneNames: scenes.map((s) => s.name).toList(),
          scenes: episode.scenes,
          protectedContract: episode.protectedContract,
        ),
      );
      final shots =
          ((result.data['shots'] as List).cast<Map<String, dynamic>>())
              .map(StudioShot.fromJson)
              .toList();
      final segments = ((result.data['segments'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudioSegment.fromJson)
          .toList();
      final saved = episode.copyWith(
        synopsis: synopsis,
        shots: shots,
        segments: segments.isNotEmpty ? segments : null,
      );
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
    return StudioShot.fromJson(json);
  }

  /// 计算分镜绑定的具体角色形态（层级回退：分镜级覆盖 -> 集级覆盖 -> 角色默认形态）。
  CharacterVariation? _resolveVariation({
    required StudioEpisode episode,
    required StudioShot shot,
    required CharacterCard? character,
  }) {
    if (character == null) return null;
    final shotVarId = shot.characterVariations[character.id];
    if (shotVarId != null && shotVarId.isNotEmpty) {
      final found = character.variations
          .where((v) => v.id == shotVarId)
          .firstOrNull;
      if (found != null) return found;
    }
    if (episode.variationOverrides.containsKey(character.id)) {
      final epVarId = episode.variationOverrides[character.id];
      final found = character.variations
          .where((v) => v.id == epVarId)
          .firstOrNull;
      if (found != null) return found;
    }
    return character.activeVariation;
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

  ValidationReport? get _validationReport {
    final ep = _episode;
    if (ep == null || ep.shots.isEmpty) return null;
    return DirectorValidationEngine.validate(
      episode: ep,
      shots: ep.shots,
      characters: _characters,
      scenes: _scenes,
    );
  }

  StudioQualityScorecard? get _scorecard {
    final ep = _episode;
    if (ep == null || ep.shots.isEmpty) return null;
    final seriesId = widget.session.series?.id ?? '';
    final framesDir = _manager.episodeFramesDir(seriesId, ep.id).path;
    return DirectorValidationEngine.computeScorecard(
      episode: ep,
      validationReport: _validationReport,
      characters: _characters,
      scenes: _scenes,
      framesDir: framesDir,
    );
  }

  bool _auditingKeyframes = false;

  Future<void> _auditAllKeyframes() async {
    final ep = _episode;
    final series = widget.session.series;
    if (ep == null || series == null) return;
    setState(() => _auditingKeyframes = true);
    final framesDir = _manager.episodeFramesDir(series.id, ep.id).path;
    try {
      final updatedShots = List<StudioShot>.from(ep.shots);
      var auditedCount = 0;
      for (var i = 0; i < updatedShots.length; i++) {
        final shot = updatedShots[i];
        final f = File('$framesDir/shot_${shot.number}.png');
        if (f.existsSync()) {
          final matchedScene =
              _scenes.where((s) => s.id == shot.sceneId).firstOrNull;
          final report = await KeyframeVisualCritic.evaluateShotKeyframe(
            shot: shot,
            episode: ep,
            characters: _characters,
            scene: matchedScene,
            framesDir: framesDir,
            useAi: false,
          );
          updatedShots[i] = shot.copyWith(vlmCriticReport: report);
          auditedCount++;
        }
      }
      final updatedEp = ep.copyWith(shots: updatedShots);
      await _manager.saveEpisode(updatedEp);
      setState(() => _episode = updatedEp);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已完成全片 $auditedCount 个关键帧的 4 维视觉审图验收！')),
        );
      }
    } finally {
      if (mounted) setState(() => _auditingKeyframes = false);
    }
  }

  void _showAuditReportDialog(BuildContext context, ValidationReport report) {
    final ep = _episode;
    final series = widget.session.series;
    if (ep == null || series == null) return;
    final framesDir = _manager.episodeFramesDir(series.id, ep.id).path;
    final clipsDir = _manager.episodeClipsDir(series.id, ep.id).path;
    final dialoguesDir = _manager.episodeAudioDir(series.id, ep.id).path;
    final messenger = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => _AuditReportDialog(
        report: report,
        scorecard: _scorecard,
        episode: ep,
        characters: _characters,
        scenes: _scenes,
        framesDir: framesDir,
        clipsDir: clipsDir,
        dialoguesDir: dialoguesDir,
        onAuditAllKeyframes: _auditingKeyframes ? null : _auditAllKeyframes,
        onFixCompleted: (updatedEpisode) async {
          setState(() {
            _episode = updatedEpisode;
          });
          await _manager.saveEpisode(updatedEpisode);
          if (mounted) {
            messenger.showSnackBar(
              const SnackBar(content: Text('自愈与结构裂变完成，已同步保存最新分镜编排！')),
            );
          }
        },
      ),
    );
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
    final matchedScene = scenes.where((s) => s.id == shot.sceneId).firstOrNull;
    final shotCharacters = characters
        .where((c) => shot.characterIds.contains(c.id))
        .toList();
    shotCharacters.sort((a, b) {
      final aIdx = shot.characterIds.indexOf(a.id);
      final bIdx = shot.characterIds.indexOf(b.id);
      return aIdx.compareTo(bIdx);
    });

    final charVariations = <String, CharacterVariation?>{};
    for (final char in shotCharacters) {
      charVariations[char.id] = _resolveVariation(
        episode: episode,
        shot: shot,
        character: char,
      );
    }
    final primaryChar = shotCharacters.firstOrNull;
    final primaryVariation = primaryChar != null
        ? charVariations[primaryChar.id]
        : null;

    final assembled = PromptAssembler.buildShotPrompt(
      PromptParts(
        productionType: series.productionType,
        styleTokens: series.styleTokens,
        eraGenre: VisualEraGenre.fromId(series.eraGenre),
        negativeStyleTokens: series.negativeStyleTokens,
        shotSize: ShotSizeTokens.of(shot.shotSize),
        mood: MoodTokens.of(shot.mood),
        shotFunction: ShotFunctionTokens.of(shot.function),
        character: primaryChar,
        variation: primaryVariation,
        characters: shotCharacters,
        characterVariations: charVariations,
        scene: matchedScene,
        cameraMove: shot.cameraMove,
        actionZh: shot.actionZh,
        dialogue: shot.dialogue,
        voiceType: shot.voiceType,
        continuity: shot.continuity,
      ),
    );

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
    setState(() {
      _regeneratingShotNumbers.add(shot.number);
      _error = null;
    });
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
      final updated =
          _shotFromJson(
            (result.data['shot'] as Map).map(
              (k, v) => MapEntry(k as String, v),
            ),
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
    } finally {
      if (mounted) {
        setState(() {
          _regeneratingShotNumbers.remove(shot.number);
        });
      }
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
    'character_variations': shot.characterVariations,
  };

  Future<void> _enqueueFrame(StudioShot shot) async {
    final episode = _episode;
    final series = widget.session.series;
    if (episode == null || series == null) return;
    final allCharacters = await _manager.listCharacters(series.id);
    final shotCharacters = allCharacters
        .where((c) => shot.characterIds.contains(c.id))
        .toList();
    shotCharacters.sort((a, b) {
      final aIdx = shot.characterIds.indexOf(a.id);
      final bIdx = shot.characterIds.indexOf(b.id);
      return aIdx.compareTo(bIdx);
    });

    final charVariations = <String, CharacterVariation?>{};
    for (final char in shotCharacters) {
      charVariations[char.id] = _resolveVariation(
        episode: episode,
        shot: shot,
        character: char,
      );
    }
    final primaryChar = shotCharacters.firstOrNull;
    final primaryVariation = primaryChar != null
        ? charVariations[primaryChar.id]
        : null;

    final matchedScene =
        _scenes.where((s) => s.id == shot.sceneId).firstOrNull ??
        _manager.readScene(series.id, shot.sceneId);

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
        character: primaryChar,
        variation: primaryVariation,
        characters: shotCharacters,
        characterVariations: charVariations,
        scene: matchedScene,
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

  /// 提交片段级视频生成任务。
  ///
  /// 与 [_enqueueClip] 的差别只在任务类型与执行体：这里入队
  /// [StudioTaskKind.segment] + [SegmentVideoGenTask]，一次调用覆盖整个片段。
  /// 前置检查（适配器可用性）与分镜级完全一致——用户看到的提示也一样。
  /// 提交场次/大段级视频生成任务：依序将场内的各个分镜（StudioShot）加入队列，
  /// 原子化生成 2~12s 独立视频，并依托首尾帧接力维持强延续性。
  Future<void> _enqueueSegment(
    StudioSegment segment,
    StudioEpisode episode,
  ) async {
    final series = widget.session.series;
    if (series == null) return;

    final targetShots = episode.shots
        .where((s) => segment.effectiveShotNumbers.contains(s.number))
        .toList();

    if (targetShots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前场次没有可生成的分镜')));
      return;
    }

    final adapter = await VideoGenAdapterFactory.create(
      productionType: series.productionType.id,
    );
    if (!await adapter.isAvailable()) {
      if (mounted) {
        _showVideoEngineUnavailableDialog(context);
      }
      return;
    }

    int enqueued = 0;
    for (final shot in targetShots) {
      if (_queue.tasksForShot(shot.number).any((t) => !t.isTerminal)) {
        continue;
      }
      final effectiveMode = shot.resolveEffectiveVideoMode(
        hasKeyframe: shot.framePath != null && shot.framePath!.isNotEmpty,
        hasCharacterOrSceneRef:
            shot.characterIds.isNotEmpty || shot.sceneId.isNotEmpty,
      );
      // 仅在首尾帧/关键帧模式下且未生成关键帧时，才自动先入队关键帧任务
      // 保持 reference/text 模式的确定性，避免非预期生成关键帧并篡改视频模式
      if (effectiveMode == AgnesVideoMode.keyframe &&
          (shot.framePath == null || shot.framePath!.isEmpty)) {
        await _enqueueFrame(shot);
      }
      await _enqueueClip(shot);
      enqueued++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将场次 ${segment.id} 内的 $enqueued 个分镜视频任务加入队列（顺序接力生成）'),
          action: SnackBarAction(label: '查看队列', onPressed: _showQueueDrawer),
        ),
      );
    }
  }

  Future<void> _updateSegmentDuration(
    StudioEpisode episode,
    StudioSegment segment,
    int newDurationSec,
  ) async {
    final updatedSegments = episode.segments.map((s) {
      if (s.id == segment.id) {
        return s.copyWith(targetDurationSec: newDurationSec);
      }
      return s;
    }).toList();
    final updated = episode.copyWith(
      segments: updatedSegments,
      updatedAt: DateTime.now(),
    );
    await _manager.saveEpisode(updated);
    _reload();
  }

  Future<void> _enqueueAllSegments(StudioEpisode episode) async {
    final series = widget.session.series;
    if (series == null) return;
    if (episode.shots.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前剧集暂无分镜')));
      return;
    }

    final total = episode.shots.length;
    final generated = episode.shots
        .where((s) => s.clipPath != null && s.clipPath!.isNotEmpty)
        .length;
    final pending = total - generated;

    bool skipExisting = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: context.bgCard,
              title: const Row(
                children: [
                  Icon(Icons.video_collection_outlined, size: 20),
                  SizedBox(width: 8),
                  Text('一键生成所有分镜视频'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前剧集共有 ${episode.scenes.isNotEmpty ? episode.scenes.length : episode.segments.length} 个场次，包含 $total 个原子分镜（已生成 $generated 个，未生成 $pending 个）。',
                  ),
                  const SizedBox(height: 16),
                  RadioListTile<bool>(
                    title: const Text('仅生成尚未出片的分镜 (推荐)'),
                    subtitle: Text('跳过已有视频的 $generated 个分镜，仅对剩余 $pending 个入队'),
                    value: true,
                    groupValue: skipExisting,
                    onChanged: (val) =>
                        setDialogState(() => skipExisting = val ?? true),
                  ),
                  RadioListTile<bool>(
                    title: const Text('重新生成全部分镜'),
                    subtitle: const Text('覆盖已有成片，将所有分镜按顺序重新加入生成队列'),
                    value: false,
                    groupValue: skipExisting,
                    onChanged: (val) =>
                        setDialogState(() => skipExisting = val ?? false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('开始批量生成'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final targetShots = episode.shots.where((s) {
      if (skipExisting && s.clipPath != null && s.clipPath!.isNotEmpty)
        return false;
      return true;
    }).toList();

    if (targetShots.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('所有分镜均已完成视频生成，无须重复入队')));
      }
      return;
    }

    final adapter = await VideoGenAdapterFactory.create(
      productionType: series.productionType.id,
    );
    if (!await adapter.isAvailable()) {
      if (mounted) {
        _showVideoEngineUnavailableDialog(context);
      }
      return;
    }

    int enqueuedCount = 0;
    for (final shot in targetShots) {
      if (_queue.tasksForShot(shot.number).any((t) => !t.isTerminal)) {
        continue;
      }
      final effectiveMode = shot.resolveEffectiveVideoMode(
        hasKeyframe: shot.framePath != null && shot.framePath!.isNotEmpty,
        hasCharacterOrSceneRef:
            shot.characterIds.isNotEmpty || shot.sceneId.isNotEmpty,
      );
      if (effectiveMode == AgnesVideoMode.keyframe &&
          (shot.framePath == null || shot.framePath!.isEmpty)) {
        await _enqueueFrame(shot);
      }
      await _enqueueClip(shot);
      enqueuedCount++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功将 $enqueuedCount 个分镜视频任务加入队列（顺序接力生成）'),
          action: SnackBarAction(label: '查看队列', onPressed: _showQueueDrawer),
        ),
      );
    }
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
          AppButton.ghost(label: '稍后再说', onPressed: () => Navigator.pop(ctx)),
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
          Icon(
            Icons.video_library_outlined,
            size: 16,
            color: context.textTertiary,
          ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryColor : context.bgInput,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? primaryColor
                              : context.borderSubtle,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            ep.title,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : context.textPrimary,
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
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
                                color: isSelected
                                    ? Colors.white
                                    : context.textTertiary,
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
              SegmentedButton<_BoardView>(
                segments: const [
                  ButtonSegment(
                    value: _BoardView.bySegment,
                    icon: Icon(Icons.view_column_outlined, size: 15),
                    tooltip: '按片段',
                  ),
                  ButtonSegment(
                    value: _BoardView.byShot,
                    icon: Icon(Icons.dashboard_outlined, size: 15),
                    tooltip: '按镜头',
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) => setState(() => _view = s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showQueueDrawer,
                icon: const Icon(Icons.list_alt, size: 16),
                label: const Text('任务队列'),
              ),
              if (episode != null && episode.scenes.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _breaking
                      ? null
                      : _confirmAndReBreakdownFromScreenplay,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('从剧本重拆'),
                ),
              ],
              if (episode != null && episode.shots.isNotEmpty) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: context.errorText,
                  ),
                  onPressed: _breaking ? null : _confirmAndClearAllShots,
                  icon: Icon(
                    Icons.delete_sweep_outlined,
                    size: 16,
                    color: context.errorText,
                  ),
                  label: const Text('清空分镜'),
                ),
              ],
              if (episode != null && episode.shots.isNotEmpty) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: '导出整集分镜表到文件',
                  onSelected: _exportStoryboardToFile,
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'md',
                      child: Row(
                        children: [
                          Icon(Icons.description_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('导出为 Markdown 分镜表 (.md)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart_outlined, size: 16),
                          SizedBox(width: 8),
                          Text('导出为 CSV 表格分镜表 (.csv)'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      border: Border.all(color: context.borderSubtle),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.table_view_outlined, size: 16, color: context.textPrimary),
                        const SizedBox(width: 6),
                        Text('导出分镜表', style: TextStyle(fontSize: 13, color: context.textPrimary)),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_drop_down, size: 16, color: context.textSecondary),
                      ],
                    ),
                  ),
                ),
              ],
              if (episode != null && episode.shots.isNotEmpty) ...[
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  onPressed: () => _enqueueAllSegments(episode),
                  icon: const Icon(Icons.video_collection_outlined, size: 16),
                  label: const Text('一键生成所有分镜'),
                ),
              ],
              if (_validationReport != null) ...[
                const SizedBox(width: 8),
                Builder(
                  builder: (context) {
                    final audit = _validationReport!;
                    final scorecard = _scorecard;
                    final score = scorecard?.overallScore;
                    final isHealthy = audit.isValid && (score == null || score >= 80);
                    final color = !audit.isValid
                        ? context.errorText
                        : (isHealthy ? const Color(0xFF22C55E) : context.warningText);

                    return InkWell(
                      onTap: () => _showAuditReportDialog(context, audit),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: color.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: color.withAlpha(90)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              !audit.isValid
                                  ? Icons.error_outline
                                  : (isHealthy
                                        ? Icons.verified_outlined
                                        : Icons.warning_amber_rounded),
                              size: 14,
                              color: color,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              scorecard != null
                                  ? '质检: ${scorecard.overallScore}分 (${audit.warningCount + audit.blockingCount}项)'
                                  : (audit.isValid
                                        ? (audit.warningCount > 0
                                              ? '质检: ${audit.warningCount}建议'
                                              : '质检全通')
                                        : '质检: ${audit.blockingCount}阻断'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
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
              : _view == _BoardView.bySegment
              ? _buildSegmentList(context, episode)
              : _buildShotList(context, episode),
        ),
      ],
    );
  }

  /// 按镜头视图：改造前的平铺形态，一行一张分镜卡。
  Widget _buildShotList(BuildContext context, StudioEpisode episode) {
    final seriesId = widget.session.series?.id ?? '';
    final framesDir = _manager.episodeFramesDir(seriesId, episode.id).path;
    final clipsDir = _manager.episodeClipsDir(seriesId, episode.id).path;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      itemCount: episode.shots.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _SynopsisCard(episode: episode);
        final shot = episode.shots[i - 1];
        return _buildShotCard(shot, episode, framesDir, clipsDir);
      },
    );
  }

  /// 按片段视图（spec: 分镜看板提供「按片段」与「按镜头」两种视图）。
  ///
  /// 片段是现在的视频生成单元，所以组头直接承载片段级操作；组内复用现有的
  /// [_ShotCard]，分镜级的编辑与生成入口完全不变——两种视图共享同一批卡片，
  /// 只是组织方式不同。
  Widget _buildSegmentList(BuildContext context, StudioEpisode episode) {
    final seriesId = widget.session.series?.id ?? '';
    final framesDir = _manager.episodeFramesDir(seriesId, episode.id).path;
    final clipsDir = _manager.episodeClipsDir(seriesId, episode.id).path;

    // 没有片段的旧集（尚未迁移或刚建）退回平铺，避免出现空白看板。
    if (episode.segments.isEmpty) {
      return _buildShotList(context, episode);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      itemCount: episode.segments.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return _SynopsisCard(episode: episode);
        final segment = episode.segments[i - 1];
        return _SegmentGroupCard(
          segment: segment,
          episode: episode,
          queue: _queue,
          framesDir: framesDir,
          clipsDir: clipsDir,
          seriesName: widget.session.series?.name ?? '',
          onGenerateSegment: () => _enqueueSegment(segment, episode),
          onUpdateDuration: (sec) =>
              _updateSegmentDuration(episode, segment, sec),
          shotBuilder: (shot) =>
              _buildShotCard(shot, episode, framesDir, clipsDir),
        );
      },
    );
  }

  /// 构造一张分镜卡。两种视图共用，保证「按镜头」与「按片段」里的同一分镜
  /// 长得一模一样、行为也一模一样。
  Widget _buildShotCard(
    StudioShot shot,
    StudioEpisode episode,
    String framesDir,
    String clipsDir,
  ) {
    return _ShotCard(
      shot: shot,
      episode: episode,
      scenes: _scenes,
      characters: _characters,
      props: _props,
      queue: _queue,
      framesDir: framesDir,
      clipsDir: clipsDir,
      seriesName: widget.session.series?.name ?? '',
      episodeTitle: episode.title,
      validationIssues:
          _validationReport?.issuesForShot(shot.number) ?? const [],
      dialogueController: _dialogueControllers.putIfAbsent(
        shot.number,
        () => TextEditingController(text: shot.dialogue),
      ),
      actionController: _actionControllers.putIfAbsent(
        shot.number,
        () => TextEditingController(text: shot.actionZh),
      ),
      onEdited: (updated) => _onShotEdited(shot.number, updated),
      onGenerateFrame: () => _enqueueFrame(shot),
      onGenerateClip: () => _enqueueClip(shot),
      onOpenCameraPanel: () => _openCameraPanel(shot),
      onRegenerateShot: () => _regenerateShot(shot),
      onDeleteShot: () => _confirmAndDeleteShot(shot.number),
      onInsertShotAfter: () => _insertShotAfter(shot.number),
      isRegenerating: _regeneratingShotNumbers.contains(shot.number),
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
          FilledButton(onPressed: _ensureEpisode, child: const Text('新建第一集')),
        ],
      ),
    );
  }

  Widget _buildNoShots(BuildContext context) {
    final ep = _episode;
    final hasScreenplay =
        ep != null &&
        ep.scenes.isNotEmpty &&
        ep.scenes.any((s) => s.beats.isNotEmpty);
    final totalBeats =
        ep?.scenes.fold<int>(0, (sum, s) => sum + s.beats.length) ?? 0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasScreenplay) ...[
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: context.accentSubtle.withAlpha(50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: context.accentText.withAlpha(60)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.movie_creation_outlined,
                        size: 48,
                        color: context.accentText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '剧本已就绪（共 ${ep.scenes.length} 场 / $totalBeats 个节拍）',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '当前集已完成剧本文学与分场提取，尚未生成 5D 视听分镜。\n您可以前往剧本工作台精细打磨，或直接根据剧本节拍一键生成分镜。',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _breaking
                                ? null
                                : _generateFromScreenplay,
                            icon: const Icon(Icons.auto_awesome, size: 16),
                            label: const Text('根据剧本生成 5D 分镜'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => widget.onNavigateStage?.call(
                              StudioStage.screenplay,
                            ),
                            icon: const Icon(Icons.edit_note, size: 16),
                            label: const Text('前往剧本工作台打磨'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '或从粗剧情大纲全新 AI 拆分',
                        style: TextStyle(
                          color: context.textDisabled,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _synopsisController,
                maxLines: 4,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: '本集粗剧情大纲',
                  labelStyle: TextStyle(color: context.textSecondary),
                  hintText: '用几句中文描述这一集发生了什么， AI 会拆成分镜',
                  hintStyle: TextStyle(
                    color: context.textDisabled,
                    fontSize: 12,
                  ),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _breaking ? null : _breakdown,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 拆分分镜'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQueueDrawer() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.bgCard,
      isScrollControlled: true,
      builder: (_) => _QueueDrawer(
        queue: _queue,
        seriesId: widget.session.series?.id,
        episodeId: _episode?.id,
        onReloadBoard: _reload,
      ),
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
    final contract = episode.protectedContract;
    final scenes = episode.scenes;

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
          Row(
            children: [
              Text(
                '本集大纲与导演契约',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (scenes.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.accentSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${scenes.length} 个戏剧场次',
                    style: TextStyle(
                      color: context.accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (contract.utterances.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.accentSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${contract.utterances.length} 条锁定金句',
                    style: TextStyle(
                      color: context.accentText,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            episode.synopsis.isEmpty ? '（未填写）' : episode.synopsis,
            style: TextStyle(color: context.textPrimary, fontSize: 12),
          ),
          if (scenes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: scenes.asMap().entries.map((entry) {
                final idx = entry.key + 1;
                final s = entry.value;
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgInput,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Text(
                    '第$idx幕: ${s.title}',
                    style: TextStyle(
                      color: context.textSecondary,
                      fontSize: 11,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

/// 展示片段生成失败详情。
///
/// 与 `add-studio-task-error-log-viewer-and-fix-video-frame` 里那个通用弹窗
/// 的职责相同（完整错误 + 一键复制），但那个组件在本文件里尚不存在，这里先
/// 用一个内联实现顶上——片段视图不该因为缺一个弹窗就看不到错误全文。
Future<void> _showSegmentError(
  BuildContext context,
  String title,
  String message,
) async {
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: context.bgCard,
      title: Text(title, style: TextStyle(color: context.textPrimary)),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: SelectableText(
            message,
            style: TextStyle(
              color: context.textSecondary,
              fontSize: 12,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
            Navigator.pop(context);
          },
          child: const Text('复制'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 片段分组卡（spec: 分镜看板提供「按片段」视图）。
///
/// 组头承载片段级信息与操作：目标时长、边界判定理由、片段视频预览、生成按钮。
/// 组内分镜卡由调用方通过 [shotBuilder] 注入——这样片段视图与平铺视图共享
/// 同一个 `_ShotCard`，不会出现"两种视图里同一分镜长得不一样"的问题。
/// 把片段视频收进资产库。
///
/// 复制而非移动（spec: 资产入库是复制而非移动）——片段产物还要供合成消费，
/// 移动它会让这一集的交付直接坏掉。
Future<void> _collectSegmentToAssets(
  BuildContext context,
  StudioSegment segment,
  File clip, {
  File? coverFile,
}) async {
  if (!await clip.exists()) return;
  try {
    await AssetLibrary.instance.addAsset(
      clip,
      kind: AssetKind.clip,
      name: '大段 ${segment.id}',
      coverFile: coverFile,
      prompt: segment.promptNote.trim().isNotEmpty
          ? segment.promptNote.trim()
          : '片段 ${segment.id}',
      originPath: clip.path,
      // 时长取「实际提交时长」而非目标时长：能力矩阵可能把请求吸附到较小值
      // （spec: 规整与降级可见），用目标时长会让时间轴算多。
      durationSec: (segment.submittedDurationSec ?? segment.targetDurationSec)
          .toDouble(),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('片段已收进资产库'), duration: Duration(seconds: 2)),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('收进资产库失败: $e')));
  }
}

class _SegmentGroupCard extends StatelessWidget {
  const _SegmentGroupCard({
    required this.segment,
    required this.episode,
    required this.queue,
    required this.framesDir,
    required this.clipsDir,
    required this.seriesName,
    required this.onGenerateSegment,
    this.onUpdateDuration,
    required this.shotBuilder,
  });

  final StudioSegment segment;
  final StudioEpisode episode;
  final StudioTaskQueue queue;
  final String framesDir;
  final String clipsDir;
  final String seriesName;
  final VoidCallback onGenerateSegment;
  final void Function(int newSec)? onUpdateDuration;

  /// 构造组内一张分镜卡。由看板注入，保证两种视图的卡片实现一致。
  final Widget Function(StudioShot shot) shotBuilder;

  File? get _segmentClip {
    final name = segment.clipPath;
    if (name == null || name.isEmpty) return null;
    final file = File('$clipsDir/../segments/$name');
    return file.existsSync() ? file : null;
  }

  File? get _coverFrameFile {
    for (final sNum in segment.shotNumbers) {
      final s = episode.shots.where((shot) => shot.number == sNum).firstOrNull;
      if (s != null && s.framePath != null && s.framePath!.isNotEmpty) {
        final f = File(p.join(framesDir, s.framePath!));
        if (f.existsSync()) return f;
      }
    }
    return null;
  }

  void _openPreview(BuildContext context) {
    final clip = _segmentClip;
    if (clip == null) return;
    final frameFile = _coverFrameFile;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _MediaPreviewDialog(
        segment: segment,
        customClipFile: clip,
        customFrameFile: frameFile,
        framesDir: framesDir,
        clipsDir: clipsDir,
        seriesName: seriesName,
        episodeTitle: episode.title,
      ),
    );
  }

  void _showDurationPicker(BuildContext context) {
    int selected = segment.targetDurationSec;
    final customCtrl = TextEditingController(text: selected.toString());
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final presets = [5, 8, 10, 12, 15];
            return AlertDialog(
              backgroundColor: context.bgCard,
              title: Row(
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 20,
                    color: context.accentText,
                  ),
                  const SizedBox(width: 8),
                  Text('修改大段目标时长 (${segment.id})'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择大段生成的推荐总时长，或手动输入自定义秒数 (3~30s)：'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final sec in presets)
                        ChoiceChip(
                          label: Text('${sec}s'),
                          selected: selected == sec,
                          onSelected: (bool sel) {
                            if (sel) {
                              setPickerState(() {
                                selected = sec;
                                customCtrl.text = sec.toString();
                              });
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: customCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '自定义时长 (秒)',
                      suffixText: '秒',
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val.trim());
                      if (parsed != null && parsed >= 3 && parsed <= 30) {
                        setPickerState(() => selected = parsed);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () {
                    final parsed =
                        int.tryParse(customCtrl.text.trim()) ?? selected;
                    final finalSec = parsed.clamp(3, 30);
                    Navigator.pop(ctx);
                    onUpdateDuration?.call(finalSec);
                  },
                  child: const Text('确认保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final shots = episode.shots
        .where((s) => segment.shotNumbers.contains(s.number))
        .toList();
    final safeId = segment.id.isNotEmpty
        ? segment.id
        : (segment.shotNumbers.isNotEmpty
              ? 'seg-${segment.shotNumbers.first}'
              : 'seg-1');
    final tasks = queue.tasksForSegment(safeId);
    final running = tasks.any((t) => !t.isTerminal);
    final failed = tasks.where((t) => t.status == StudioTaskStatus.failed);
    final clip = _segmentClip;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- 组头 ---
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.view_column_outlined,
                  size: 16,
                  color: context.accentText,
                ),
                const SizedBox(width: 8),
                Text(
                  safeId,
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: onUpdateDuration != null
                      ? () => _showDurationPicker(context)
                      : null,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: segment.durationWasAdjusted
                          ? context.warningText.withAlpha(20)
                          : context.borderSubtle.withAlpha(40),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: segment.durationWasAdjusted
                            ? context.warningText.withAlpha(120)
                            : context.borderSubtle,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 13,
                          color: segment.durationWasAdjusted
                              ? context.warningText
                              : context.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          segment.durationWasAdjusted
                              ? '${segment.targetDurationSec}s → ${segment.submittedDurationSec}s'
                              : '${segment.targetDurationSec}s',
                          style: TextStyle(
                            color: segment.durationWasAdjusted
                                ? context.warningText
                                : context.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down,
                          size: 14,
                          color: context.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    segment.boundaryReason.isEmpty
                        ? '${shots.length} 个分镜'
                        : segment.boundaryReason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textTertiary, fontSize: 11),
                  ),
                ),
                if (running)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Tooltip(
                    message:
                        '依序为该场次包含的 ${shots.length} 个分镜生成独立视频（合计 ${segment.targetDurationSec} 秒），自动依托首尾帧接力保持连贯',
                    child: FilledButton.icon(
                      onPressed: tasks.any((t) => !t.isTerminal)
                          ? null
                          : onGenerateSegment,
                      icon: const Icon(Icons.movie_creation_outlined, size: 14),
                      label: Text('生成整场视频 (${segment.targetDurationSec}s)'),
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 降级提示：用户传了 N 张参考图但模型只用了 1 张。必须可见，
          // 否则会以为一致性约束生效了（design 决策 4）。
          if (segment.isDegraded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '参考图被降级：本次实际使用 1 张，共传入 '
                '${segment.degradedRefCount + 1} 张。当前视频模型不支持多参考图。',
                style: TextStyle(color: context.warningText, fontSize: 11),
              ),
            ),
          if (failed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: InkWell(
                onTap: () => _showSegmentError(
                  context,
                  '片段 ${segment.id} 生成失败',
                  failed.first.error ?? '未知错误',
                ),
                child: Text(
                  '生成失败，点击查看日志',
                  style: TextStyle(color: context.errorText, fontSize: 11),
                ),
              ),
            ),
          if (clip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 13,
                    color: context.successText,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '片段视频已生成',
                    style: TextStyle(color: context.successText, fontSize: 11),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    onPressed: () => _openPreview(context),
                    icon: const Icon(Icons.play_circle_outline, size: 14),
                    label: const Text('播放预览', style: TextStyle(fontSize: 11)),
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 收进资产库放这里而不是溢出菜单：片段卡没有菜单，而这个
                  // 动作对片段级产物比对分镜级更有意义——片段是"一段成片"，
                  // 正是用户会想跨剧复用的那种东西。
                  TextButton.icon(
                    onPressed: () => _collectSegmentToAssets(
                      context,
                      segment,
                      clip,
                      coverFile: _coverFrameFile,
                    ),
                    icon: const Icon(Icons.video_library_outlined, size: 14),
                    label: const Text('收进资产库', style: TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          // --- 组内分镜 ---
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [for (final shot in shots) shotBuilder(shot)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShotCard extends StatelessWidget {
  const _ShotCard({
    required this.shot,
    required this.episode,
    required this.scenes,
    required this.characters,
    this.props = const [],
    required this.queue,
    required this.dialogueController,
    required this.actionController,
    required this.onEdited,
    required this.onGenerateFrame,
    required this.onGenerateClip,
    required this.onOpenCameraPanel,
    required this.onRegenerateShot,
    this.onDeleteShot,
    this.onInsertShotAfter,
    required this.framesDir,
    required this.clipsDir,
    required this.seriesName,
    required this.episodeTitle,
    this.validationIssues = const [],
    this.isRegenerating = false,
  });

  final StudioShot shot;
  final StudioEpisode episode;
  final List<SceneCard> scenes;
  final List<CharacterCard> characters;
  final List<PropCard> props;
  final StudioTaskQueue queue;
  final TextEditingController dialogueController;
  final TextEditingController actionController;
  final List<ValidationIssue> validationIssues;
  final bool isRegenerating;

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

  /// 删除当前镜头。
  final VoidCallback? onDeleteShot;

  /// 在当前镜头后插入新镜头。
  final VoidCallback? onInsertShotAfter;

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

  /// 把本分镜的产物收进资产库。
  ///
  /// **复制，不移动**（spec: 资产入库是复制而非移动）——原分镜产物留着，
  /// 否则"收进资产库"会变成"从剧集里拿走"，用户不敢点。
  ///
  /// 提示词取 [StudioShot.assembledPrompt]：那是实际驱动生成的那段文字，
  /// 比运镜短语信息量大得多，回望时也更有用。供应商与型号尽力而为——
  /// 查不到就不填，不该因为缺元数据就拒绝入库。
  Future<void> _collectToAssetLibrary(
    BuildContext context,
    AssetKind kind,
  ) async {
    final target = kind == AssetKind.clip ? _clipFile : _frameFile;
    if (target == null || !target.existsSync()) return;
    try {
      await AssetLibrary.instance.addAsset(
        target,
        kind: kind,
        name: kind == AssetKind.clip
            ? '分镜 #${shot.number} 视频'
            : '分镜 #${shot.number} 关键帧',
        coverFile: kind == AssetKind.clip ? _frameFile : null,
        category: kind == AssetKind.clip
            ? AssetCategory.clip
            : AssetCategory.frame,
        prompt: shot.assembledPrompt.trim().isNotEmpty
            ? shot.assembledPrompt.trim()
            : shot.cameraMove,
        originPath: target.path,
        // 分镜级视频的时长就是该镜的建议时长——它提交时用的也是这个值。
        durationSec: kind == AssetKind.clip ? shot.durationSec : null,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(kind == AssetKind.clip ? '视频已收进资产库' : '关键帧已收进资产库'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('收进资产库失败: $e')));
    }
  }

  Future<void> _revealInFinder() async {
    final target = (_clipFile != null && _clipFile!.existsSync())
        ? _clipFile
        : ((_frameFile != null && _frameFile!.existsSync())
              ? _frameFile
              : null);
    if (target != null && target.existsSync()) {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', target.path]);
      }
    }
  }

  Future<void> _exportFile(BuildContext context) async {
    final target = (_clipFile != null && _clipFile!.existsSync())
        ? _clipFile
        : ((_frameFile != null && _frameFile!.existsSync())
              ? _frameFile
              : null);
    if (target == null || !target.existsSync()) return;

    final ext = p.extension(target.path);
    final isVideo = _clipFile != null && _clipFile!.existsSync();
    final defaultName =
        '${seriesName}_${episodeTitle}_shot_${shot.number}${isVideo ? ext : (ext.isEmpty ? ".png" : ext)}';

    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出素材到本地',
        fileName: defaultName,
      );
    } catch (_) {
      savePath = null;
    }

    if (savePath == null) {
      final home = Platform.environment['HOME'] ?? '';
      savePath = p.join(home, 'Downloads', defaultName);
    }

    try {
      final destFile = File(savePath);
      await destFile.parent.create(recursive: true);
      await target.copy(savePath);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('素材已导出到: $savePath'),
            action: SnackBarAction(
              label: '打开访达',
              onPressed: () {
                if (Platform.isMacOS) {
                  Process.run('open', ['-R', savePath!]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出素材失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = queue.tasksForShot(shot.number);
    final running = tasks
        .where((t) => t.status == StudioTaskStatus.running)
        .toList();
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
            running: running.isNotEmpty || isRegenerating,
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
                      if (shot.directorDecisions.cutReason.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _Tag(
                          text: '切: ${shot.directorDecisions.cutReason}',
                          color: context.accentSubtle,
                          textColor: context.accentText,
                        ),
                      ],
                      if (shot.directorDecisions.visualTask.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        _Tag(text: shot.directorDecisions.visualTask),
                      ],
                      if (validationIssues.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        _buildValidationBadge(context),
                      ],
                      if (shot.vlmCriticReport != null) ...[
                        const SizedBox(width: 6),
                        _buildVlmCriticBadge(context),
                      ],
                      const SizedBox(width: 6),
                      _buildVideoModeBadge(context),
                      const Spacer(),
                      _StatusBadge(tasks: tasks),
                      if (onDeleteShot != null ||
                          onInsertShotAfter != null) ...[
                        const SizedBox(width: 4),
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            size: 16,
                            color: context.textSecondary,
                          ),
                          tooltip: '镜头操作',
                          color: context.bgCard,
                          onSelected: (val) {
                            if (val == 'insert') onInsertShotAfter?.call();
                            if (val == 'delete') onDeleteShot?.call();
                          },
                          itemBuilder: (context) => [
                            if (onInsertShotAfter != null)
                              const PopupMenuItem(
                                value: 'insert',
                                child: Row(
                                  children: [
                                    Icon(Icons.add_circle_outline, size: 16),
                                    SizedBox(width: 8),
                                    Text(
                                      '在此后插入分镜',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            if (onDeleteShot != null)
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline,
                                      size: 16,
                                      color: context.errorText,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      '删除此分镜',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: context.errorText,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.landscape_outlined,
                            size: 14,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '场景:',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: scenes.any((s) => s.id == shot.sceneId)
                                ? shot.sceneId
                                : '',
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: context.bgCard,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  '无关联场景',
                                  style: TextStyle(
                                    color: context.textTertiary,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              ...scenes.map(
                                (s) => DropdownMenuItem(
                                  value: s.id,
                                  child: Text(
                                    s.name,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              onEdited(shot.copyWith(sceneId: val ?? ''));
                            },
                          ),
                          const SizedBox(width: 10),
                          // 情绪（spec: 分镜情绪的用户可改性）。
                          //
                          // mood 原本只能看不能改——7 处引用全是 _Tag 只读展示，
                          // AI 填错就直接毁掉成片而用户毫无办法。它同时驱动生图
                          // 光线词（MoodTokens）与 BGM 匹配，所以改这里会一并
                          // 改变关键帧光线与配乐推荐，这是刻意的一致性。
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mood_outlined,
                                size: 14,
                                color: context.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '情绪:',
                                style: TextStyle(
                                  color: context.textTertiary,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 4),
                              DropdownButton<String>(
                                value: shot.mood,
                                isDense: true,
                                underline: const SizedBox.shrink(),
                                dropdownColor: context.bgCard,
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 11,
                                ),
                                items: ShotMood.values
                                    .map(
                                      (m) => DropdownMenuItem(
                                        value: m.id,
                                        child: Text(
                                          m.label,
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null && val != shot.mood) {
                                    onEdited(shot.copyWith(mood: val));
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      // 出场资产面板（spec: shot-asset-binding）。
                      //
                      // 原「角色」单选下拉写死 characterIds: [val]，选第二个角色
                      // 会覆盖第一个——双人镜在 UI 上根本无法表达。这里改为可增删
                      // 的多角色列表，每行带分工与素材指定，「形态」从属于角色。
                      ShotAssetPanel(
                        shot: shot,
                        characters: characters,
                        props: props,
                        seriesId: episode.seriesId,
                        scene: scenes.any((s) => s.id == shot.sceneId)
                            ? scenes.firstWhere((s) => s.id == shot.sceneId)
                            : null,
                        onEdited: onEdited,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '时长:',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<double>(
                            value: shot.durationSec,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: context.bgCard,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                            ),
                            items: [
                              for (final d in {
                                3.0,
                                4.0,
                                5.0,
                                6.0,
                                8.0,
                                10.0,
                                12.0,
                                shot.durationSec,
                              }.toList()..sort())
                                DropdownMenuItem(
                                  value: d,
                                  child: Text(
                                    '${d.toStringAsFixed(d.truncateToDouble() == d ? 0 : 1)}s',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                            ],
                            onChanged: (val) {
                              if (val != null && val != shot.durationSec) {
                                onEdited(shot.copyWith(durationSec: val));
                              }
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_outlined,
                            size: 14,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '模式:',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: shot.videoMode,
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: context.bgCard,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'auto',
                                child: Text(
                                  '自动(推荐)',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'keyframe',
                                child: Text(
                                  '首尾帧(keyframe)',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'reference',
                                child: Text(
                                  '参考图(reference)',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: 'text',
                                child: Text(
                                  '纯文本(text)',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              onEdited(shot.copyWith(videoMode: val));
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.aspect_ratio_outlined,
                            size: 14,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '画幅:',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: shot.aspectRatio ?? '',
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: context.bgCard,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  '继承默认',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '9:16',
                                child: Text(
                                  '9:16 竖屏',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '16:9',
                                child: Text(
                                  '16:9 横屏',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '21:9',
                                child: Text(
                                  '21:9 宽画幅',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '4:3',
                                child: Text(
                                  '4:3 复古',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1:1',
                                child: Text(
                                  '1:1 方形',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              onEdited(
                                shot.copyWith(
                                  aspectRatio: (val == null || val.isEmpty)
                                      ? null
                                      : val,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hd_outlined,
                            size: 14,
                            color: context.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '清晰度:',
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 4),
                          DropdownButton<String>(
                            value: shot.resolution ?? '',
                            isDense: true,
                            underline: const SizedBox.shrink(),
                            dropdownColor: context.bgCard,
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 11,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '',
                                child: Text(
                                  '继承默认',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '720P',
                                child: Text(
                                  '720P',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1080P',
                                child: Text(
                                  '1080P',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '1K',
                                child: Text(
                                  '1K',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '2K',
                                child: Text(
                                  '2K 超清',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                              DropdownMenuItem(
                                value: '4K',
                                child: Text(
                                  '4K 影院',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              onEdited(
                                shot.copyWith(
                                  resolution: (val == null || val.isEmpty)
                                      ? null
                                      : val,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: dialogueController,
                    maxLines: 2,
                    onChanged: (v) => onEdited(shot.copyWith(dialogue: v)),
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: '台词',
                      labelStyle: TextStyle(
                        color: context.textTertiary,
                        fontSize: 11,
                      ),
                      suffixText:
                          '${shot.dialogue.trim().length}'
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
                      Tooltip(
                        message: '为当前单个分镜生成独立视频（${shot.durationSec.toInt()}s）',
                        child: TextButton.icon(
                          onPressed: onGenerateClip,
                          icon: const Icon(Icons.movie_outlined, size: 15),
                          label: const Text('单镜视频'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: '针对当前分镜让 AI 优化动作与台词描述',
                        child: TextButton.icon(
                          onPressed: isRegenerating ? null : onRegenerateShot,
                          icon: isRegenerating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_fix_high, size: 15),
                          label: Text(isRegenerating ? '改写中…' : 'AI改写'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      TextButton.icon(
                        onPressed: onOpenCameraPanel,
                        icon: const Icon(Icons.videocam_outlined, size: 15),
                        label: Text(
                          shot.cameraMove.isEmpty ? '运镜' : shot.cameraMove,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: '查看并优化分镜视频 Prompt（AI 消解冲突、规则过滤、分流定制）',
                        child: TextButton.icon(
                          onPressed: () => _openVideoPromptDialog(context),
                          icon: Icon(
                            shot.videoPrompt.isNotEmpty
                                ? Icons.auto_awesome
                                : Icons.edit_note,
                            size: 15,
                            color: shot.videoPrompt.isNotEmpty
                                ? context.accentText
                                : null,
                          ),
                          label: Text(
                            shot.videoPrompt.isNotEmpty ? '视频提示词*' : 'AI提示词',
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: shot.vlmCriticReport != null
                            ? (shot.vlmCriticReport!.passed
                                ? (shot.vlmCriticReport!.isAiEvaluated
                                    ? 'VLM 多模态大模型审图通过 (${shot.vlmCriticReport!.score}分)'
                                    : '确定性规则预审通过 (${shot.vlmCriticReport!.score}分)，建议点击进行 AI 真实读图复验')
                                : '质检未通过：${shot.vlmCriticReport!.issues.join("；")}')
                            : '使用 VLM 审核关键帧角色人数、高低透视、坐骑与构图',
                        child: TextButton.icon(
                          onPressed: () => _handleVlmCritic(context),
                          icon: Icon(
                            shot.vlmCriticReport != null
                                ? (shot.vlmCriticReport!.passed
                                    ? (shot.vlmCriticReport!.isAiEvaluated
                                        ? Icons.verified
                                        : Icons.fact_check_outlined)
                                    : Icons.warning_amber)
                                : Icons.visibility_outlined,
                            size: 15,
                            color: shot.vlmCriticReport != null
                                ? (shot.vlmCriticReport!.passed
                                    ? (shot.vlmCriticReport!.isAiEvaluated
                                        ? Colors.green
                                        : Colors.blueGrey)
                                    : Colors.orange)
                                : null,
                          ),
                          label: Text(
                            shot.vlmCriticReport != null
                                ? (shot.vlmCriticReport!.passed
                                    ? (shot.vlmCriticReport!.isAiEvaluated
                                        ? 'VLM合格'
                                        : '规则通过')
                                    : 'VLM待改')
                                : 'VLM审图',
                          ),
                        ),
                      ),
                      if (shot.vlmCriticReport != null && !shot.vlmCriticReport!.passed) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: '一键采纳 VLM 审图修复建议并重新抽卡关键帧',
                          child: TextButton.icon(
                            onPressed: () => _handleApplyVlmFix(context),
                            icon: const Icon(
                              Icons.auto_fix_high,
                              size: 15,
                              color: Colors.orange,
                            ),
                            label: const Text(
                              '采纳建议重抽',
                              style: TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
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
                            if (act == 'collect-frame') {
                              _collectToAssetLibrary(context, AssetKind.image);
                            }
                            if (act == 'collect-clip') {
                              _collectToAssetLibrary(context, AssetKind.clip);
                            }
                          },
                          itemBuilder: (context) => [
                            if (_frameFile != null && _frameFile!.existsSync())
                              const PopupMenuItem(
                                value: 'collect-frame',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.photo_library_outlined,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '关键帧收进资产库',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            if (_clipFile != null && _clipFile!.existsSync())
                              const PopupMenuItem(
                                value: 'collect-clip',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.video_library_outlined,
                                      size: 16,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '视频收进资产库',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            const PopupMenuItem(
                              value: 'finder',
                              child: Row(
                                children: [
                                  Icon(Icons.folder_open_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    '在访达中显示',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'export',
                              child: Row(
                                children: [
                                  Icon(Icons.download_outlined, size: 16),
                                  SizedBox(width: 8),
                                  Text(
                                    '导出保存到本地',
                                    style: TextStyle(fontSize: 12),
                                  ),
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
                  _DirectorDecisionsPanel(shot: shot, onEdited: onEdited),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationBadge(BuildContext context) {
    final hasBlocking = validationIssues.any(
      (i) => i.severity == ValidationSeverity.blocking,
    );
    final color = hasBlocking ? context.errorText : context.warningText;
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('镜 #${shot.number} 导演质检说明'),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: validationIssues
                      .map(
                        (issue) => Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                (issue.severity == ValidationSeverity.blocking
                                        ? ctx.errorText
                                        : ctx.warningText)
                                    .withAlpha(20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '【${issue.ruleId} ${issue.ruleName} · ${issue.severity.label}】',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color:
                                      issue.severity ==
                                          ValidationSeverity.blocking
                                      ? ctx.errorText
                                      : ctx.warningText,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                issue.message,
                                style: const TextStyle(fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '建议: ${issue.suggestion}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: ctx.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('了解'),
              ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasBlocking ? Icons.error_outline : Icons.warning_amber_rounded,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              hasBlocking
                  ? '${validationIssues.length}阻断'
                  : '${validationIssues.length}提示',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVlmCriticBadge(BuildContext context) {
    final vlm = shot.vlmCriticReport;
    if (vlm == null) return const SizedBox.shrink();
    final color = vlm.passed ? Colors.green : Colors.orange;

    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  vlm.passed ? Icons.verified : Icons.warning_amber,
                  color: color,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text('镜 #${shot.number} 关键帧 VLM 审图报告'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _buildVlmDimTag(ctx, '角色防克隆', vlm.characterCountOk),
                        const SizedBox(width: 6),
                        _buildVlmDimTag(ctx, '高低位透视', vlm.spatialElevationOk),
                        const SizedBox(width: 6),
                        _buildVlmDimTag(ctx, '坐骑道具', vlm.mountPropOk),
                        const SizedBox(width: 6),
                        _buildVlmDimTag(ctx, '景别对白', vlm.shotScaleOk),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (vlm.issues.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.withAlpha(20),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '关键帧构图完全符合剧本视听要求，未检测到克隆分身、浮空或坐骑丢失。',
                          style: TextStyle(fontSize: 12, color: Colors.green),
                        ),
                      )
                    else
                      ...vlm.issues.map(
                        (iss) => Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withAlpha(15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.orange.withAlpha(50),
                            ),
                          ),
                          child: Text(
                            '• $iss',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    if (vlm.promptFixSuggestion.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        '建议修复生图词：',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: ctx.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: ctx.bgInput,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ctx.borderSubtle),
                        ),
                        child: Text(
                          vlm.promptFixSuggestion,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: ctx.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭'),
              ),
              if (!vlm.passed)
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handleApplyVlmFix(context);
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 15),
                  label: const Text('采纳修复词并重抽'),
                ),
            ],
          ),
        );
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(90)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              vlm.passed ? Icons.verified : Icons.warning_amber,
              size: 11,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              vlm.passed ? 'VLM合格' : 'VLM待改',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVlmDimTag(BuildContext context, String label, bool ok) {
    final color = ok ? Colors.green : Colors.orange;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withAlpha(60)),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9, color: context.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              ok ? '合格' : '待改',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleVlmCritic(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text('正在审核镜 #${shot.number} 关键帧与生图提示词…'),
        duration: const Duration(seconds: 1),
      ),
    );

    final matchedScene = scenes.where((s) => s.id == shot.sceneId).firstOrNull;
    final report = await KeyframeVisualCritic.evaluateShotKeyframe(
      shot: shot,
      episode: episode,
      characters: characters,
      scene: matchedScene,
      framesDir: framesDir,
      useAi: true,
    );

    final updated = shot.copyWith(vlmCriticReport: report);
    onEdited(updated);

    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            report.passed
                ? '镜 #${shot.number} 关键帧 VLM 审图通过！'
                : '镜 #${shot.number} 关键帧存在 ${report.issues.length} 项隐患，可点击采纳建议重抽',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _handleApplyVlmFix(BuildContext context) {
    final matchedScene = scenes.where((s) => s.id == shot.sceneId).firstOrNull;
    final fixedShot = KeyframeVisualCritic.applySuggestedFixToShot(
      shot,
      characters: characters,
      scene: matchedScene,
    );
    onEdited(fixedShot);
    onGenerateFrame();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已采纳修复提示词并重新提交镜 #${shot.number} 关键帧生成！'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildVideoModeBadge(BuildContext context) {
    final hasFrame =
        (_frameFile != null && _frameFile!.existsSync()) ||
        (shot.firstFramePath != null && shot.firstFramePath!.isNotEmpty);
    final hasRef =
        shot.characterIds.isNotEmpty || shot.sceneId.trim().isNotEmpty;
    final effectiveMode = shot.resolveEffectiveVideoMode(
      hasKeyframe: hasFrame,
      hasCharacterOrSceneRef: hasRef,
    );
    final isCustom = shot.videoMode != 'auto';
    final label = '${effectiveMode.id}${isCustom ? "(手动)" : "(自动)"}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: context.accentSubtle.withAlpha(50),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.accentSubtle),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: context.accentText,
        ),
      ),
    );
  }

  void _openVideoPromptDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _VideoPromptDialog(
        shot: shot,
        episode: episode,
        characters: characters,
        props: props,
        scenes: scenes,
        framesDir: framesDir,
        onSave: onEdited,
      ),
    );
  }
}

/// 出场资产面板（spec: shot-asset-binding）。
///
/// 折叠式：分镜卡已有场景/模式/画幅/时长/景别等一排控件，面板默认收起，
/// 展开时才占空间。
///
/// 每行一个角色或道具，含分工与素材多图指定；素材弹窗列出该资产下
/// **磁盘上真实存在**的候选图，支持多选。用户未显式指定时
/// 显示「自动：<默认文件名>」，让「程序挑了哪张」始终可见、可覆盖。
class ShotAssetPanel extends StatelessWidget {
  const ShotAssetPanel({
    super.key,
    required this.shot,
    required this.characters,
    this.props = const [],
    required this.scene,
    required this.seriesId,
    required this.onEdited,
  });

  final StudioShot shot;
  final List<CharacterCard> characters;
  final List<PropCard> props;

  /// 当前分镜关联的场景卡；null 表示未关联。
  final SceneCard? scene;

  final String seriesId;
  final ValueChanged<StudioShot> onEdited;

  @override
  Widget build(BuildContext context) {
    final selectedCharIds = shot.characterIds;
    final selectedPropIds = shot.propIds;
    final availableChars =
        characters.where((c) => !selectedCharIds.contains(c.id)).toList();
    final availableProps =
        props.where((p) => !selectedPropIds.contains(p.id)).toList();
    final bindings = shot.assetBindings;

    // 汇总将要提交的参考图总数量（支持多图展开）
    var materialCount = 0;
    for (final cid in selectedCharIds) {
      final b = bindings[cid];
      if (b != null && b.materialPaths.isNotEmpty) {
        materialCount += b.materialPaths.length;
      } else {
        materialCount += 1;
      }
    }
    for (final pid in selectedPropIds) {
      final b = bindings[pid];
      if (b != null && b.materialPaths.isNotEmpty) {
        materialCount += b.materialPaths.length;
      } else {
        materialCount += 1;
      }
    }
    if (scene != null) {
      final b = bindings[scene!.id];
      if (b != null && b.materialPaths.isNotEmpty) {
        materialCount += b.materialPaths.length;
      } else {
        materialCount += 1;
      }
    }
    final maxRefs = SettingsStore.instance.videoMaxReferenceImages;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 0),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        initiallyExpanded: false,
        title: Row(
          children: [
            Icon(
              Icons.perm_media_outlined,
              size: 14,
              color: context.textTertiary,
            ),
            const SizedBox(width: 4),
            Text(
              '出场资产',
              style: TextStyle(color: context.textTertiary, fontSize: 11),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${selectedCharIds.length} 角色 · ${selectedPropIds.length} 道具 · ${scene != null ? 1 : 0} 场景 ($materialCount 参考图)',
                style: TextStyle(color: context.textPrimary, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        children: [
          if (maxRefs != null && materialCount > maxRefs)
            _OverLimitBanner(count: materialCount, max: maxRefs),
          for (final id in selectedCharIds) ...[
            AssetRow(
              key: ValueKey('char_$id'),
              assetId: id,
              assetName:
                  characters.where((c) => c.id == id).firstOrNull?.name ?? id,
              isScene: false,
              isProp: false,
              binding: bindings[id] ?? const ShotAssetBinding(),
              seriesId: seriesId,
              onChanged: (b) => _updateBinding(id, b),
              onRemove: () => _removeCharacter(id),
              trailing: _RoleDropdown(
                role: bindings[id]?.role ?? ShotAssetRole.subject,
                onChanged: (r) => _updateBinding(
                  id,
                  (bindings[id] ?? const ShotAssetBinding()).copyWith(role: r),
                ),
              ),
            ),
          ],
          for (final id in selectedPropIds) ...[
            AssetRow(
              key: ValueKey('prop_$id'),
              assetId: id,
              assetName:
                  props.where((p) => p.id == id).firstOrNull?.name ?? id,
              isScene: false,
              isProp: true,
              binding: bindings[id] ?? const ShotAssetBinding(),
              seriesId: seriesId,
              onChanged: (b) => _updateBinding(id, b),
              onRemove: () => _removeProp(id),
              trailing: null,
            ),
          ],
          if (scene != null)
            AssetRow(
              key: ValueKey('scene_${scene!.id}'),
              assetId: scene!.id,
              assetName: scene!.name,
              isScene: true,
              isProp: false,
              binding: bindings[scene!.id] ?? const ShotAssetBinding(),
              seriesId: seriesId,
              onChanged: (b) => _updateBinding(scene!.id, b),
              onChangedScene: null,
              onRemove: null,
              trailing: null,
            ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                if (availableChars.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: '选择添加角色',
                    onSelected: _addCharacter,
                    itemBuilder: (ctx) => [
                      for (final c in availableChars)
                        PopupMenuItem<String>(
                          value: c.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.person_outline, size: 14),
                              const SizedBox(width: 6),
                              Text(c.name,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.bgInput,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_add_alt,
                              size: 13, color: context.textSecondary),
                          const SizedBox(width: 4),
                          Text('添加角色',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary)),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down,
                              size: 14, color: context.textTertiary),
                        ],
                      ),
                    ),
                  ),
                if (availableChars.isNotEmpty && availableProps.isNotEmpty)
                  const SizedBox(width: 8),
                if (availableProps.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: '选择添加道具',
                    onSelected: _addProp,
                    itemBuilder: (ctx) => [
                      for (final p in availableProps)
                        PopupMenuItem<String>(
                          value: p.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.category_outlined, size: 14),
                              const SizedBox(width: 6),
                              Text(p.name,
                                  style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: context.bgInput,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline,
                              size: 13, color: context.textSecondary),
                          const SizedBox(width: 4),
                          Text('添加道具',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: context.textSecondary)),
                          const SizedBox(width: 2),
                          Icon(Icons.arrow_drop_down,
                              size: 14, color: context.textTertiary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addCharacter(String characterId) {
    if (shot.characterIds.contains(characterId)) return;
    final nextIds = [...shot.characterIds, characterId];
    onEdited(shot.copyWith(characterIds: nextIds));
  }

  void _removeCharacter(String characterId) {
    final nextIds =
        shot.characterIds.where((id) => id != characterId).toList();
    final nextBindings =
        Map<String, ShotAssetBinding>.from(shot.assetBindings)
          ..remove(characterId);
    final nextVariations =
        Map<String, String>.from(shot.characterVariations)
          ..remove(characterId);
    onEdited(
      shot.copyWith(
        characterIds: nextIds,
        assetBindings: nextBindings,
        characterVariations: nextVariations,
      ),
    );
  }

  void _addProp(String propId) {
    if (shot.propIds.contains(propId)) return;
    final nextIds = [...shot.propIds, propId];
    onEdited(shot.copyWith(propIds: nextIds));
  }

  void _removeProp(String propId) {
    final nextIds = shot.propIds.where((id) => id != propId).toList();
    final nextBindings =
        Map<String, ShotAssetBinding>.from(shot.assetBindings)..remove(propId);
    onEdited(
      shot.copyWith(
        propIds: nextIds,
        assetBindings: nextBindings,
      ),
    );
  }

  void _updateBinding(String assetId, ShotAssetBinding binding) {
    final next = Map<String, ShotAssetBinding>.from(shot.assetBindings);
    next[assetId] = binding;
    onEdited(shot.copyWith(assetBindings: next));
  }
}

/// 多图素材选择弹窗（spec: 支持单个角色或道具绑定多张参考素材）。
class MaterialMultiSelectDialog extends StatefulWidget {
  const MaterialMultiSelectDialog({
    super.key,
    required this.assetName,
    required this.isProp,
    required this.isScene,
    required this.candidates,
    required this.initialSelected,
    required this.assetDirPath,
  });

  final String assetName;
  final bool isProp;
  final bool isScene;
  final List<AssetMaterialCandidate> candidates;
  final List<String> initialSelected;
  final String assetDirPath;

  @override
  State<MaterialMultiSelectDialog> createState() =>
      _MaterialMultiSelectDialogState();
}

class _MaterialMultiSelectDialogState extends State<MaterialMultiSelectDialog> {
  late final List<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = List<String>.from(widget.initialSelected);
  }

  void _toggle(String fileName) {
    setState(() {
      if (_selected.contains(fileName)) {
        _selected.remove(fileName);
      } else {
        _selected.add(fileName);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final assetTypeLabel = widget.isScene
        ? '场景'
        : (widget.isProp ? '道具' : '角色');
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: context.borderSubtle),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    widget.isProp
                        ? Icons.category_outlined
                        : (widget.isScene
                            ? Icons.landscape_outlined
                            : Icons.person_outline),
                    size: 18,
                    color: primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '选择参考图 · ${widget.assetName}（$assetTypeLabel）',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '支持勾选多张参考图，按勾选次序编排为连续的 <Picture N> 序列指代',
                style: TextStyle(fontSize: 11, color: context.textTertiary),
              ),
              const Divider(height: 16),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.candidates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final candidate = widget.candidates[index];
                    final isChecked = _selected.contains(candidate.fileName);
                    final filePath =
                        p.join(widget.assetDirPath, candidate.fileName);
                    final fileExists = File(filePath).existsSync();

                    return InkWell(
                      onTap: () => _toggle(candidate.fileName),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: isChecked
                              ? primaryColor.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isChecked
                                ? primaryColor.withValues(alpha: 0.3)
                                : context.borderSubtle.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: isChecked,
                              onChanged: (_) => _toggle(candidate.fileName),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 6),
                            if (fileExists)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.file(
                                  File(filePath),
                                  width: 36,
                                  height: 36,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(
                                      Icons.broken_image,
                                      size: 20),
                                ),
                              )
                            else
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: context.bgInput,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(Icons.image_outlined,
                                    size: 18),
                              ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        candidate.label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: context.textPrimary,
                                        ),
                                      ),
                                      if (candidate.isDefault) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: primaryColor
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            '默认',
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: primaryColor,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    candidate.fileName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: context.textTertiary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      // 恢复自动默认（清空显式绑定）
                      Navigator.of(context).pop(<String>[]);
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: context.textTertiary,
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('恢复自动默认'),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () {
                      Navigator.of(context).pop(_selected);
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: Text(
                      _selected.isEmpty
                          ? '确定（自动默认）'
                          : '确定（已选 ${_selected.length} 张）',
                    ),
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

/// 单个资产的素材指定行。
class AssetRow extends StatelessWidget {
  const AssetRow({
    super.key,
    required this.assetId,
    required this.assetName,
    required this.isScene,
    this.isProp = false,
    required this.binding,
    required this.seriesId,
    required this.onChanged,
    this.trailing,
    this.onRemove,
    this.onChangedScene,
  });

  final String assetId;
  final String assetName;
  final bool isScene;
  final bool isProp;
  final ShotAssetBinding binding;
  final String seriesId;

  /// 素材选择变更。
  final ValueChanged<ShotAssetBinding> onChanged;

  /// 角色行显示分工下拉；场景行传 null。
  final Widget? trailing;

  /// 移除按钮；场景行传 null。
  final VoidCallback? onRemove;

  /// 场景变更（保留字段，暂由主行「场景」下拉承担）。
  final ValueChanged<String>? onChangedScene;

  String _getAssetDirPath() {
    if (isScene) {
      return StudioProjectManager.instance.sceneDir(seriesId, assetId).path;
    }
    if (isProp) {
      return StudioProjectManager.instance.propDir(seriesId, assetId).path;
    }
    return StudioProjectManager.instance.characterDir(seriesId, assetId).path;
  }

  Future<void> _openMaterialSelector(
    BuildContext context,
    List<AssetMaterialCandidate> candidates,
  ) async {
    final selected = binding.materialPaths;
    final result = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => MaterialMultiSelectDialog(
        assetName: assetName,
        isProp: isProp,
        isScene: isScene,
        candidates: candidates,
        initialSelected: selected,
        assetDirPath: _getAssetDirPath(),
      ),
    );
    if (result != null) {
      onChanged(
        binding.copyWith(
          materialPaths: result,
          materialPath: result.isNotEmpty ? result.first : '',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final candidates = _loadCandidates();
    final binding = this.binding;

    String displayText;
    if (candidates.isEmpty) {
      displayText = '无素材图';
    } else if (!binding.hasExplicitMaterial) {
      displayText = '自动：${candidates.first.fileName}';
    } else if (binding.materialPaths.length == 1) {
      displayText = binding.materialPaths.first;
    } else {
      displayText = '已选 ${binding.materialPaths.length} 张图片';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Row(
              children: [
                Icon(
                  isProp
                      ? Icons.category_outlined
                      : (isScene
                          ? Icons.landscape_outlined
                          : Icons.person_outline),
                  size: 12,
                  color: context.textTertiary,
                ),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(
                    assetName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.textPrimary, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
          Expanded(
            child: InkWell(
              onTap: candidates.isEmpty
                  ? null
                  : () => _openMaterialSelector(context, candidates),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: binding.hasExplicitMaterial
                        ? primaryColor.withValues(alpha: 0.4)
                        : context.borderSubtle,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  color: context.bgInput,
                ),
                child: Row(
                  children: [
                    Icon(
                      binding.materialPaths.length > 1
                          ? Icons.photo_library_outlined
                          : Icons.image_outlined,
                      size: 13,
                      color: binding.hasExplicitMaterial
                          ? primaryColor
                          : context.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: binding.hasExplicitMaterial
                              ? context.textPrimary
                              : context.textTertiary,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down,
                        size: 14, color: context.textTertiary),
                  ],
                ),
              ),
            ),
          ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 13, color: context.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  List<AssetMaterialCandidate> _loadCandidates() {
    if (isScene) {
      final scene = _sceneCard;
      if (scene == null) return const [];
      return AssetMaterialEnumerator.forScene(
        scene,
        sceneDirPath: StudioProjectManager.instance
            .sceneDir(seriesId, assetId)
            .path,
      );
    }
    if (isProp) {
      final prop = _propCard;
      if (prop == null) return const [];
      return AssetMaterialEnumerator.forProp(
        prop,
        propDirPath: StudioProjectManager.instance
            .propDir(seriesId, assetId)
            .path,
      );
    }
    final character = _characterCard;
    if (character == null) return const [];
    return AssetMaterialEnumerator.forCharacter(
      character,
      activeVariation: character.activeVariation,
      charDirPath: StudioProjectManager.instance
          .characterDir(seriesId, assetId)
          .path,
    );
  }

  SceneCard? get _sceneCard {
    try {
      return StudioProjectManager.instance.readScene(seriesId, assetId);
    } catch (_) {
      return null;
    }
  }

  CharacterCard? get _characterCard {
    try {
      return StudioProjectManager.instance.readCharacter(seriesId, assetId);
    } catch (_) {
      return null;
    }
  }

  PropCard? get _propCard {
    try {
      return StudioProjectManager.instance.readProp(seriesId, assetId);
    } catch (_) {
      return null;
    }
  }
}

/// 角色分工下拉。
class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.role, required this.onChanged});

  final ShotAssetRole role;
  final ValueChanged<ShotAssetRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<ShotAssetRole>(
      value: role,
      isDense: true,
      underline: const SizedBox.shrink(),
      dropdownColor: context.bgCard,
      style: TextStyle(color: context.textSecondary, fontSize: 11),
      items: ShotAssetRole.values
          .map(
            (r) => DropdownMenuItem(
              value: r,
              child: Text(r.label, style: const TextStyle(fontSize: 11)),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

/// 参考素材超限警告条（spec: 超限阻止而非静默截断）。
class _OverLimitBanner extends StatelessWidget {
  const _OverLimitBanner({required this.count, required this.max});

  final int count;
  final int max;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: context.errorSolid.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: context.errorText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '已选 $count 张参考图，当前视频模型上限 $max 张。请减少角色、道具或参考图后再生成。',
              style: TextStyle(color: context.errorText, fontSize: 10),
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
                      Icon(
                        Icons.image_outlined,
                        color: context.textTertiary,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '未生成',
                        style: TextStyle(
                          color: context.textDisabled,
                          fontSize: 10,
                        ),
                      ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1.5,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
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

enum _PreviewTab { video, frame }

class _MediaPreviewDialog extends StatefulWidget {
  const _MediaPreviewDialog({
    this.shot,
    this.segment,
    this.framesDir = '',
    this.clipsDir = '',
    required this.seriesName,
    required this.episodeTitle,
    this.customClipFile,
    this.customFrameFile,
  });

  final StudioShot? shot;
  final StudioSegment? segment;
  final String framesDir;
  final String clipsDir;
  final String seriesName;
  final String episodeTitle;
  final File? customClipFile;
  final File? customFrameFile;

  @override
  State<_MediaPreviewDialog> createState() => _MediaPreviewDialogState();
}

class _MediaPreviewDialogState extends State<_MediaPreviewDialog> {
  Player? _player;
  VideoController? _videoController;
  bool _hasClip = false;
  File? _clipFile;
  File? _frameFile;
  _PreviewTab _activeTab = _PreviewTab.video;
  final TransformationController _transformationController =
      TransformationController();

  StreamSubscription? _errorSub;
  StreamSubscription? _videoParamsSub;
  bool _hasError = false;
  String? _errorMessage;
  double _aspectRatio = 9 / 16;

  double get _durationSec {
    if (widget.shot != null) return widget.shot!.durationSec;
    if (widget.segment != null) {
      return (widget.segment!.submittedDurationSec ??
              widget.segment!.targetDurationSec)
          .toDouble();
    }
    return 0.0;
  }

  String get _dialogTitle {
    if (widget.shot != null) {
      return '分镜 #${widget.shot!.number} 媒体预览';
    }
    if (widget.segment != null) {
      return '大段 ${widget.segment!.id} 视频预览';
    }
    return '媒体预览';
  }

  @override
  void initState() {
    super.initState();
    File? resolvedClip = widget.customClipFile;
    if (resolvedClip == null && widget.shot != null) {
      final clipName = widget.shot!.clipPath;
      if (clipName != null && clipName.isNotEmpty) {
        final f = File(p.join(widget.clipsDir, clipName));
        if (f.existsSync()) resolvedClip = f;
      }
    } else if (resolvedClip == null && widget.segment != null) {
      final clipName = widget.segment!.clipPath;
      if (clipName != null && clipName.isNotEmpty) {
        final f = File(p.join(widget.clipsDir, '..', 'segments', clipName));
        if (f.existsSync()) resolvedClip = f;
      }
    }

    if (resolvedClip != null && resolvedClip.existsSync()) {
      _hasClip = true;
      _clipFile = resolvedClip;
      _activeTab = _PreviewTab.video;
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
      _player!.open(Media(resolvedClip.path));
      _player!.setPlaylistMode(PlaylistMode.loop);
    }

    File? resolvedFrame = widget.customFrameFile;
    if (resolvedFrame == null && widget.shot != null) {
      final frameName = widget.shot!.framePath;
      if (frameName != null && frameName.isNotEmpty) {
        final f = File(p.join(widget.framesDir, frameName));
        if (f.existsSync()) resolvedFrame = f;
      }
    }
    if (resolvedFrame != null && resolvedFrame.existsSync()) {
      _frameFile = resolvedFrame;
      if (!_hasClip) {
        _activeTab = _PreviewTab.frame;
      }
    }
  }

  @override
  void dispose() {
    _errorSub?.cancel();
    _videoParamsSub?.cancel();
    _player?.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _revealInFinder() async {
    final target =
        (_activeTab == _PreviewTab.frame ? _frameFile : null) ??
        _clipFile ??
        _frameFile;
    if (target != null && target.existsSync()) {
      if (Platform.isMacOS) {
        await Process.run('open', ['-R', target.path]);
      }
    }
  }

  Future<void> _exportFile() async {
    final target =
        (_activeTab == _PreviewTab.frame ? _frameFile : null) ??
        _clipFile ??
        _frameFile;
    if (target == null || !target.existsSync()) return;
    final ext = p.extension(target.path);
    final isVideo = target.path.endsWith('.mp4');
    final String fileName;
    if (widget.segment != null) {
      fileName =
          '${widget.seriesName}_${widget.episodeTitle}_segment_${widget.segment!.id}${isVideo ? ".mp4" : (ext.isEmpty ? ".png" : ext)}';
    } else if (widget.shot != null) {
      fileName =
          '${widget.seriesName}_${widget.episodeTitle}_shot_${widget.shot!.number}${isVideo ? ".mp4" : (ext.isEmpty ? ".png" : ext)}';
    } else {
      fileName =
          '${widget.seriesName}_${widget.episodeTitle}_media${isVideo ? ".mp4" : (ext.isEmpty ? ".png" : ext)}';
    }

    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出分镜素材到本地',
        fileName: fileName,
      );
    } catch (_) {
      savePath = null;
    }

    if (savePath == null) {
      final home = Platform.environment['HOME'] ?? '';
      savePath = p.join(home, 'Downloads', fileName);
    }

    try {
      final destFile = File(savePath);
      await destFile.parent.create(recursive: true);
      await target.copy(savePath);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功导出到: $savePath'),
            action: SnackBarAction(
              label: '打开访达',
              onPressed: () {
                if (Platform.isMacOS) {
                  Process.run('open', ['-R', savePath!]);
                }
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('导出失败: $e')));
      }
    }
  }

  Future<void> _openSystemPlayer() async {
    if (_clipFile != null && _clipFile!.existsSync()) {
      await Process.run('open', [_clipFile!.path]);
    }
  }

  Widget _buildMediaContent() {
    if (_activeTab == _PreviewTab.video &&
        _hasClip &&
        _videoController != null) {
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
      return Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            transformationController: _transformationController,
            minScale: 0.2,
            maxScale: 8.0,
            child: Center(child: Image.file(_frameFile!, fit: BoxFit.contain)),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.zoom_in, color: Colors.white70, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    '滚轮/捏合缩放',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () {
                      _transformationController.value = Matrix4.identity();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '复位',
                        style: TextStyle(color: Colors.white, fontSize: 11),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: context.borderSubtle),
                  ),
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
                      _dialogTitle,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_hasClip &&
                        _frameFile != null &&
                        _frameFile!.existsSync()) ...[
                      const SizedBox(width: 12),
                      SegmentedButton<_PreviewTab>(
                        segments: [
                          ButtonSegment(
                            value: _PreviewTab.video,
                            label: Text(
                              widget.segment != null
                                  ? '大段视频 (${_durationSec.toStringAsFixed(1)}s)'
                                  : '单镜视频 (${_durationSec.toStringAsFixed(1)}s)',
                            ),
                            icon: const Icon(Icons.movie_outlined, size: 14),
                          ),
                          const ButtonSegment(
                            value: _PreviewTab.frame,
                            label: Text('关键帧大图 (可缩放)'),
                            icon: Icon(Icons.image_outlined, size: 14),
                          ),
                        ],
                        selected: {_activeTab},
                        onSelectionChanged: (set) {
                          setState(() => _activeTab = set.first);
                        },
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _hasClip
                              ? context.accentSubtle
                              : context.borderSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _hasClip
                              ? (widget.segment != null
                                    ? '大段成片 (${_durationSec.toStringAsFixed(1)}s)'
                                    : '视频片段 (${_durationSec.toStringAsFixed(1)}s)')
                              : '关键帧大图',
                          style: TextStyle(
                            fontSize: 11,
                            color: _hasClip
                                ? context.accentText
                                : context.textSecondary,
                          ),
                        ),
                      ),
                    ],
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
              if (widget.shot != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    border: Border(
                      top: BorderSide(color: context.borderSubtle),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _Tag(text: '景别: ${widget.shot!.shotSize.label}'),
                          const SizedBox(width: 6),
                          _Tag(
                            text:
                                '情绪: ${ShotMood.fromId(widget.shot!.mood).label}',
                          ),
                          const SizedBox(width: 6),
                          _Tag(text: '功能: ${widget.shot!.function.label}'),
                          if (widget.shot!.cameraMove.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _Tag(text: '运镜: ${widget.shot!.cameraMove}'),
                          ],
                        ],
                      ),
                      if (widget.shot!.actionZh.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '画面动作: ${widget.shot!.actionZh}',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (widget.shot!.dialogue.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '台词: ${widget.shot!.dialogue}',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (widget.segment != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    border: Border(
                      top: BorderSide(color: context.borderSubtle),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          _Tag(text: '大段 ID: ${widget.segment!.id}'),
                          const SizedBox(width: 6),
                          _Tag(text: '时长: ${_durationSec.toStringAsFixed(0)}s'),
                          const SizedBox(width: 6),
                          _Tag(
                            text:
                                '包含 ${widget.segment!.shotNumbers.length} 个分镜 (${widget.segment!.shotNumbers.join(", ")})',
                          ),
                          if (widget.segment!.durationWasAdjusted) ...[
                            const SizedBox(width: 6),
                            _Tag(
                              text:
                                  '模型吸附: ${widget.segment!.targetDurationSec}s → ${widget.segment!.submittedDurationSec}s',
                            ),
                          ],
                        ],
                      ),
                      if (widget.segment!.boundaryReason.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '分段依据: ${widget.segment!.boundaryReason}',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (widget.segment!.promptNote.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '补充润色: ${widget.segment!.promptNote}',
                          style: TextStyle(
                            color: context.textSecondary,
                            fontSize: 11,
                          ),
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
  const _Tag({required this.text, this.color, this.textColor});

  final String text;
  final Color? color;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color ?? context.bgInput,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? context.textSecondary,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _DirectorDecisionsPanel extends StatefulWidget {
  const _DirectorDecisionsPanel({required this.shot, required this.onEdited});

  final StudioShot shot;

  /// 五维字段编辑后的回调（spec: 五维导演决策的用户可改性）。
  final ValueChanged<StudioShot> onEdited;

  @override
  State<_DirectorDecisionsPanel> createState() =>
      _DirectorDecisionsPanelState();
}

class _DirectorDecisionsPanelState extends State<_DirectorDecisionsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.shot.directorDecisions;
    final combat = widget.shot.combatSteps;
    final exit = widget.shot.continuity.dynamicExitState;
    final hasContent = d.isNotEmpty || combat.isNotEmpty || exit.isNotEmpty;
    if (!hasContent) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 16,
                  color: context.accentText,
                ),
                const SizedBox(width: 4),
                Text(
                  '五维导演决策 & 攻防因果${combat.isNotEmpty ? ' (${combat.length}步交互)' : ''}',
                  style: TextStyle(
                    color: context.accentText,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (d.cutReason.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: context.accentSubtle,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '切: ${d.cutReason}',
                      style: TextStyle(fontSize: 10, color: context.accentText),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.bgInput.withAlpha(120),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.physicalMomentum.isNotEmpty)
                  _buildDecisionRow(context, '物理动势', d.physicalMomentum),
                if (d.lightingStaging.isNotEmpty)
                  _buildDecisionRow(context, '空间光影', d.lightingStaging),
                if (d.cameraStaging.isNotEmpty)
                  _buildDecisionRow(context, '光学机位', d.cameraStaging),
                // 时间演变是唯一开放编辑的五维字段（spec: 五维导演决策的用户
                // 可改性）——它直接驱动视频提示词的因果时间轴，而 AI 自由文本
                // 十句里九句不含可解析秒数，用户必须能改写它。其余五维或已被
                // 运镜面板覆盖（光影/机位），或是 AI 内部推导（美学质感）。
                _buildDecisionEditor(
                  context,
                  '时间演变',
                  d.temporalEvolution,
                  hint: '例：前2.0秒拱手，后3.0秒转身',
                  onChanged: (v) =>
                      _saveDecisions(d.copyWith(temporalEvolution: v)),
                ),
                if (d.aestheticTexture.isNotEmpty)
                  _buildDecisionRow(context, '美学质感', d.aestheticTexture),
                if (exit.isNotEmpty)
                  _buildDecisionRow(
                    context,
                    '出幅动态',
                    '${exit.unfinishedPhase} · 动势: ${exit.velocityVector}',
                  ),
                if (combat.isNotEmpty) ...[
                  const Divider(height: 12),
                  Text(
                    '动作攻防六步因果链',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...combat.map((step) {
                    final targets = step.targetNames.isNotEmpty
                        ? step.targetNames.join('、')
                        : '目标';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '#${step.stepIndex} 【${step.actorName} ⚔️ $targets】${step.intent} → ${step.attack} | 反应: ${step.defense} (受力: ${step.impact}, 位移: ${step.displacement})',
                        style: TextStyle(
                          fontSize: 10,
                          color: context.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 可编辑的五维字段行（spec: 五维导演决策的用户可改性）。
  ///
  /// 失焦即保存——分镜卡没有「确定」按钮，逐字符回调会让每次击键都写一次
  /// storyboard.json，那在快速输入时是明显的 IO 抖动。
  Widget _buildDecisionEditor(
    BuildContext context,
    String label,
    String value, {
    required ValueChanged<String> onChanged,
    String hint = '',
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: TextStyle(
                color: context.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: _DecisionField(
              initialValue: value,
              hint: hint,
              onCommit: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  void _saveDecisions(DirectorDecisions next) {
    widget.onEdited(widget.shot.copyWith(directorDecisions: next));
  }

  Widget _buildDecisionRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 55,
            child: Text(
              label,
              style: TextStyle(
                color: context.textTertiary,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 10,
                height: 1.25,
              ),
            ),
          ),
        ],
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

class QueueDrawer extends StatefulWidget {
  const QueueDrawer({
    super.key,
    required this.queue,
    this.seriesId,
    this.episodeId,
    this.onReloadBoard,
  });

  final StudioTaskQueue queue;
  final String? seriesId;
  final String? episodeId;
  final VoidCallback? onReloadBoard;

  @override
  State<QueueDrawer> createState() => _QueueDrawerState();
}

typedef _QueueDrawer = QueueDrawer;

enum _QueueFilter {
  all('全部'),
  active('进行中'),
  completed('已完成'),
  failed('失败');

  final String label;
  const _QueueFilter(this.label);
}

class _QueueDrawerState extends State<_QueueDrawer> {
  List<VideoTaskLedgerEntry> _cloudTasks = const [];
  _QueueFilter _filter = _QueueFilter.all;

  @override
  void initState() {
    super.initState();
    _loadCloudTasks();
  }

  Future<void> _loadCloudTasks() async {
    final all = await VideoTaskLedger.instance.allEntries();
    if (!mounted) return;
    setState(() {
      _cloudTasks = all
          .where(
            (e) =>
                e.adapterId != NovelImportTaskService.adapterId &&
                (e.status.isActive ||
                    e.status == VideoTaskLedgerStatus.completed) &&
                (widget.seriesId == null ||
                    widget.seriesId!.isEmpty ||
                    e.seriesId == widget.seriesId) &&
                (widget.episodeId == null ||
                    widget.episodeId!.isEmpty ||
                    e.episodeId == widget.episodeId),
          )
          .toList();
    });
  }

  Widget _buildFilterChip(_QueueFilter filter, String text) {
    final isSelected = _filter == filter;
    return ChoiceChip(
      label: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onSelected: (_) => setState(() => _filter = filter),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTaskTile(BuildContext context, StudioTask task) {
    return ListTile(
      dense: true,
      leading: Icon(
        switch (task.kind) {
          StudioTaskKind.image => Icons.image_outlined,
          StudioTaskKind.video => Icons.movie_outlined,
          StudioTaskKind.segment => Icons.view_column_outlined,
        },
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final tasks = widget.queue.tasks;
    final activeCount = tasks
        .where(
          (t) =>
              t.status == StudioTaskStatus.queued ||
              t.status == StudioTaskStatus.running,
        )
        .length;
    final completedCount =
        tasks.where((t) => t.status == StudioTaskStatus.completed).length;
    final failedCount =
        tasks.where((t) => t.status == StudioTaskStatus.failed).length;

    final filteredTasks = tasks.where((t) {
      return switch (_filter) {
        _QueueFilter.all => true,
        _QueueFilter.active =>
          t.status == StudioTaskStatus.queued ||
              t.status == StudioTaskStatus.running,
        _QueueFilter.completed => t.status == StudioTaskStatus.completed,
        _QueueFilter.failed => t.status == StudioTaskStatus.failed,
      };
    }).toList();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
                  const SizedBox(width: 14),
                  Text(
                    '并发数:',
                    style: TextStyle(color: context.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(width: 6),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 1, label: Text('1')),
                      ButtonSegment(value: 2, label: Text('2')),
                      ButtonSegment(value: 3, label: Text('3')),
                      ButtonSegment(value: 4, label: Text('4')),
                      ButtonSegment(value: 5, label: Text('5')),
                    ],
                    selected: {widget.queue.maxConcurrency},
                    onSelectionChanged: (set) {
                      widget.queue.setMaxConcurrency(set.first);
                      setState(() {});
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip(_QueueFilter.all, '全部 (${tasks.length})'),
                    const SizedBox(width: 8),
                    _buildFilterChip(_QueueFilter.active, '进行中 ($activeCount)'),
                    const SizedBox(width: 8),
                    _buildFilterChip(
                      _QueueFilter.completed,
                      '已完成 ($completedCount)',
                    ),
                    const SizedBox(width: 8),
                    _buildFilterChip(_QueueFilter.failed, '失败 ($failedCount)'),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  child: ListView(
                    children: [
                      if (filteredTasks.isEmpty &&
                          (_filter != _QueueFilter.all || _cloudTasks.isEmpty))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Center(
                            child: Text(
                              _filter == _QueueFilter.all
                                  ? '队列是空的。'
                                  : '没有 ${_filter.label} 的任务。',
                              style: TextStyle(
                                color: context.textTertiary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      for (final entry in _groupByKind(filteredTasks)) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 2),
                          child: Text(
                            entry.key.label,
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        for (final task in entry.value)
                          _buildTaskTile(context, task),
                      ],
                      if (_cloudTasks.isNotEmpty &&
                          (_filter == _QueueFilter.all ||
                              _filter == _QueueFilter.active ||
                              _filter == _QueueFilter.completed)) ...[
                        _CloudTaskSection(
                          tasks: _cloudTasks,
                          onChanged: _loadCloudTasks,
                          onReloadBoard: widget.onReloadBoard,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 把任务按 kind 分组，保持 `StudioTaskKind` 的声明顺序。
  ///
  /// 声明顺序即展示顺序（片段 → 视频 → 关键帧）：片段任务最长，放最上面让
  /// 用户第一眼看到"还有个大家伙在跑"。
  List<MapEntry<StudioTaskKind, List<StudioTask>>> _groupByKind(
    List<StudioTask> tasks,
  ) {
    final result = <MapEntry<StudioTaskKind, List<StudioTask>>>[];
    for (final kind in StudioTaskKind.values) {
      final group = tasks.where((t) => t.kind == kind).toList();
      if (group.isEmpty) continue;
      result.add(MapEntry(kind, group));
    }
    return result;
  }
}

/// 云端视频任务区。
///
/// 与上面的内存队列分开展示，因为它们是两种不同的东西：
/// - 内存队列 = 本进程正在跑的调度单元，取消它就真的不跑了；
/// - 这里 = **云端还在计费**的任务，取消只代表本地不再等。
///
/// 混在一起展示会让用户以为点「放弃」就停止扣费——那是比不展示更糟的误导，
/// 所以这个区的标题与每条卡片都把「本地操作不影响云端」写明。
class _CloudTaskSection extends StatelessWidget {
  const _CloudTaskSection({
    required this.tasks,
    required this.onChanged,
    this.onReloadBoard,
  });

  final List<VideoTaskLedgerEntry> tasks;
  final Future<void> Function() onChanged;
  final VoidCallback? onReloadBoard;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 2),
          child: Text(
            '云端视频任务',
            style: TextStyle(
              color: context.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 计费明示。放在区级而不是每条卡片里：这句话对区内所有条目都成立，
        // 重复 N 遍只会变噪音被忽略。
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: context.accentSubtle,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 13, color: context.accentText),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  '这些任务在云端继续生成并计费。放弃只表示本机不再等待，'
                  '不会停止云端——视频仍可用右侧 id 去 Agnes 控制台取回。',
                  style: TextStyle(fontSize: 10, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        for (final entry in tasks)
          _CloudTaskTile(
            entry: entry,
            onChanged: onChanged,
            onReloadBoard: onReloadBoard,
          ),
      ],
    );
  }
}

class _CloudTaskTile extends StatelessWidget {
  const _CloudTaskTile({
    required this.entry,
    required this.onChanged,
    this.onReloadBoard,
  });

  final VideoTaskLedgerEntry entry;
  final Future<void> Function() onChanged;
  final VoidCallback? onReloadBoard;

  String get _createdTimeStr {
    final t = entry.createdAt.toLocal();
    final y = t.year.toString().padLeft(4, '0');
    final m = t.month.toString().padLeft(2, '0');
    final d = t.day.toString().padLeft(2, '0');
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String get _elapsed {
    final d = DateTime.now().toUtc().difference(entry.createdAt);
    if (d.inMinutes < 1) return '${d.inSeconds} 秒';
    if (d.inHours < 1) return '${d.inMinutes} 分钟';
    return '${d.inHours} 小时 ${d.inMinutes % 60} 分';
  }

  @override
  Widget build(BuildContext context) {
    final isCloudProcessing =
        entry.status == VideoTaskLedgerStatus.cloudProcessing;
    final stage = switch (entry.lastRemoteStatus) {
      'queued' => '排队中',
      'in_progress' || 'processing' => '生成中',
      'completed' => '已完成',
      'failed' => '云端失败',
      _ => isCloudProcessing ? '云端仍在处理' : '本地等待中',
    };

    return Card(
      color: context.bgCard,
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 16,
                  color: isCloudProcessing
                      ? context.accentText
                      : context.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.label.isEmpty ? entry.model : entry.label,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '创建时间：$_createdTimeStr',
                        style: TextStyle(
                          color: context.textTertiary,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                // video_id 可复制：这是用户去控制台自查的唯一钥匙。
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '复制 video_id',
                  icon: const Icon(Icons.copy, size: 14),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.remoteTaskId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('已复制 video_id：${entry.remoteTaskId}'),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(
                '$stage · 已等待 $_elapsed'
                '${entry.lastProgress != null ? ' · 云端进度 ${entry.lastProgress}%' : ''}',
                style: TextStyle(color: context.textTertiary, fontSize: 11),
              ),
            ),
            // 来源元数据：用户要能判断"这条值不值得取回"，光有状态不够
            // ——型号与提示词才是判断依据。
            if (entry.model.isNotEmpty || (entry.prompt?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  [
                    if (entry.model.isNotEmpty) entry.model,
                    if (entry.prompt?.isNotEmpty ?? false) entry.prompt!,
                  ].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.textTertiary, fontSize: 10),
                ),
              ),
            if (entry.error != null && entry.error!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 22, top: 2),
                child: Text(
                  entry.error!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.errorText, fontSize: 10),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: [
                  // 刷新状态：只查一次，不重新挂轮询、不动等待预算。
                  // 对停在「云端仍在处理」的任务，这是最常用的查看方式。
                  TextButton(
                    onPressed: () => _refreshStatus(context),
                    child: const Text('刷新状态', style: TextStyle(fontSize: 11)),
                  ),
                  if (isCompleted) ...[
                    // 重新取回：云端 URL 实测长期有效，本地丢了能捞回来。
                    TextButton(
                      onPressed: () => _refetch(context),
                      child: const Text('重新取回', style: TextStyle(fontSize: 11)),
                    ),
                    TextButton(
                      onPressed: () => _collectToAssets(context),
                      child: const Text(
                        '收进资产库',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ] else
                    TextButton(
                      onPressed: () async {
                        // 继续等待：重新挂起轮询。预算可无限次追加——云端
                        // 任务没有取消端点，等下去是唯一取回的办法。
                        final ok = await VideoTaskRecovery.instance
                            .resumeManually(entry.localId);
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('该任务已在等待中')),
                          );
                        }
                        await onChanged();
                      },
                      child: const Text('继续等待', style: TextStyle(fontSize: 11)),
                    ),
                  TextButton(
                    onPressed: () => _showRawRequestDialog(context),
                    child: const Text('查看请求体', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: () => _debugInPlayground(context),
                    child: const Text('在试炼场调试', style: TextStyle(fontSize: 11)),
                  ),
                  TextButton(
                    onPressed: () async {
                      // 放弃前说清后果：本地不再等，云端继续计费。用户必须
                      // 在点下去之前知道这一点，而不是之后发现账单。
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: context.bgCard,
                          title: const Text('放弃本地等待？'),
                          content: const Text(
                            '放弃只让本机不再等待这个任务。云端仍会继续生成并计费，'
                            '视频也不会自动消失——你仍可用 video_id 去 Agnes '
                            '控制台取回。确定放弃吗？',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('取消'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('仍要放弃'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      await VideoTaskRecovery.instance.abandon(entry.localId);
                      await onChanged();
                    },
                    child: const Text('放弃', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get isCompleted => entry.status == VideoTaskLedgerStatus.completed;

  /// 重建一个 Agnes 适配器来查询。
  ///
  /// 台账条目记的是创建时的型号与供应商标识，恢复/刷新都该用那组值——
  /// 用户可能已经改了全局默认模型，但云端那个任务还是老型号。
  Future<AgnesVideoAdapter?> _adapterFor() async {
    final provider = AiConfigStore.instance.providers
        .where((p) => p.id == entry.providerId)
        .firstOrNull;
    // 供应商配置可能已被删除。退回 Agnes 公开地址——地址不需要配置也能查，
    // 但 Key 不行：没有供应商配置就拿不到 key id。
    final baseUrl = provider?.baseUrl ?? 'https://api.agnes-ai.cn/v1';
    final key = provider == null
        ? null
        : await KeychainService.instance.readSecret(provider.keychainKeyId);
    if (key == null || key.isEmpty) return null;
    return AgnesVideoAdapter(
      baseUrl: baseUrl,
      model: entry.model,
      apiKey: key,
      providerId: entry.providerId,
    );
  }

  Future<void> _refreshStatus(BuildContext context) async {
    final adapter = await _adapterFor();
    if (adapter == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该任务的 API Key 已不可用，无法查询')));
      }
      return;
    }
    try {
      final status = await adapter.refreshStatusOnce(entry);
      await onChanged();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(status == null ? '查询失败，请稍后再试' : '当前状态: $status'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _refetch(BuildContext context) async {
    final adapter = await _adapterFor();
    if (adapter == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('该任务的 API Key 已不可用，无法取回')));
      }
      return;
    }
    try {
      final file = await adapter.refetchCompleted(entry);
      await VideoTaskRecovery.instance.writeBack(entry, file);
      await onChanged();
      onReloadBoard?.call();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已取回并同步至剧集：${p.basename(file.path)}')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('取回失败: $e')));
    }
  }

  void _showRawRequestDialog(BuildContext context) {
    final draft = PlaygroundDraft.fromLedgerEntry(entry);
    final jsonText = draft.formattedRawPayloadJson;
    final reqText = draft.renderRedactedRequest();
    var showJson = true;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final activeText = showJson ? jsonText : reqText;
            return AlertDialog(
              backgroundColor: dialogCtx.bgCard,
              title: Row(
                children: [
                  Text(
                    '任务 [${entry.label}] 请求体',
                    style: TextStyle(
                      color: dialogCtx.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text(
                          'HTTP JSON',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('参数概览', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                    selected: {showJson},
                    onSelectionChanged: (set) {
                      setDialogState(() => showJson = set.first);
                    },
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 620,
                height: 420,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: dialogCtx.bgContent,
                    borderRadius: AppTheme.borderRadiusSmall,
                    border: Border.all(color: dialogCtx.borderSubtle),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      activeText,
                      style: TextStyle(
                        color: dialogCtx.textPrimary,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              actions: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy, size: 14),
                  label: const Text('复制请求 JSON'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: jsonText));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制完整脱敏请求 JSON 到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.text_snippet_outlined, size: 14),
                  label: const Text('复制提示词'),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: entry.prompt ?? ''));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制提示词全文到剪贴板'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 14),
                  label: const Text('转入试炼场调试'),
                  onPressed: () {
                    Navigator.pop(dialogCtx);
                    _debugInPlayground(context);
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _debugInPlayground(BuildContext context) async {
    final draft = PlaygroundDraft.fromLedgerEntry(entry);
    await PlaygroundStore.instance.saveDraft(draft);

    var windowOpened = false;
    try {
      final tool = ToolRegistry.findById(kToolIdAgnesPlayground);
      if (tool case final AgnesPlaygroundToolDefinition pg) {
        await pg.openNewWindow();
        windowOpened = true;
      }
    } catch (e) {
      debugPrint('[CloudTaskTile] 打开试炼场窗口失败: $e');
    }

    if (!windowOpened && context.mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: PlaygroundPage()),
        ),
      );
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已将该任务的完整调用参数与参考图载入 Agnes 试炼场'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _collectToAssets(BuildContext context) async {
    final file = File(entry.targetPath);
    if (!file.existsSync()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('本地产物不存在，请先「重新取回」')));
      return;
    }

    String semanticName = '生成产物 ${entry.localId}';
    File? coverCandidate;

    if (entry.seriesId.isNotEmpty) {
      final manager = StudioProjectManager.instance;
      final series = manager.readSeries(entry.seriesId);
      final episode = entry.episodeId.isNotEmpty
          ? manager.readEpisode(entry.seriesId, entry.episodeId)
          : null;
      final seriesTitle = series?.name ?? '剧集';
      final epTitle = episode != null ? '第${episode.index}集' : '';

      if (entry.segmentId.isNotEmpty) {
        final seg = episode?.segments
            .where((s) => s.id == entry.segmentId)
            .firstOrNull;
        final segIndex = seg != null
            ? (episode!.segments.indexOf(seg) + 1)
            : entry.segmentId;
        semanticName = '[$seriesTitle $epTitle] 大段 $segIndex 视频';
      } else if (entry.shotNumber != null) {
        semanticName = '[$seriesTitle $epTitle] 分镜 #${entry.shotNumber} 视频';
      }
    }

    final refPaths = entry.requestSnapshot?['referencePaths'];
    if (refPaths is List) {
      for (final p in refPaths) {
        if (p is String && p.isNotEmpty) {
          final f = File(p);
          if (f.existsSync()) {
            coverCandidate = f;
            break;
          }
        }
      }
    }

    try {
      await AssetLibrary.instance.addAsset(
        file,
        kind: AssetKind.clip,
        name: semanticName,
        coverFile: coverCandidate,
        category: AssetCategory.clip,
        prompt: entry.prompt,
        model: entry.model,
        sourceCallId: entry.localId,
        originPath: entry.targetPath,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已收进资产库「视频片段」分类')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('收进资产库失败: $e')));
    }
  }
}

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
    final sorted = plans.toList()..sort((a, b) => b.score.compareTo(a.score));
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
                  color: plan == best ? context.accentSubtle : context.bgInput,
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
                    plan == best ? Icons.auto_awesome : Icons.videocam_outlined,
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
                    style: TextStyle(color: context.textTertiary, fontSize: 11),
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

class _AuditReportDialog extends StatefulWidget {
  const _AuditReportDialog({
    required this.report,
    this.scorecard,
    required this.episode,
    required this.characters,
    required this.scenes,
    this.framesDir,
    this.clipsDir,
    this.dialoguesDir,
    this.onAuditAllKeyframes,
    required this.onFixCompleted,
  });

  final ValidationReport report;
  final StudioQualityScorecard? scorecard;
  final StudioEpisode episode;
  final List<CharacterCard> characters;
  final List<SceneCard> scenes;
  final String? framesDir;
  final String? clipsDir;
  final String? dialoguesDir;
  final VoidCallback? onAuditAllKeyframes;
  final ValueChanged<StudioEpisode> onFixCompleted;

  @override
  State<_AuditReportDialog> createState() => _AuditReportDialogState();
}

class _AuditReportDialogState extends State<_AuditReportDialog> {
  bool _isAutoFixing = false;

  Future<void> _handleAutoFix() async {
    setState(() {
      _isAutoFixing = true;
    });

    try {
      final result = await AiConstraintEngine.autoFixAuditIssues(
        shots: widget.episode.shots,
        report: widget.report,
        characters: widget.characters,
        scenes: widget.scenes,
      );

      final fixedShotsList = result.data['fixed_shots'] as List? ?? const [];
      final fixedMap = <int, Map<String, dynamic>>{};
      for (final item in fixedShotsList) {
        if (item is Map) {
          final num = item['number'] is int
              ? item['number'] as int
              : int.tryParse(item['number'].toString());
          if (num != null) {
            fixedMap[num] = item.map((k, v) => MapEntry(k.toString(), v));
          }
        }
      }

      final updatedShots = widget.episode.shots.map((orig) {
        final fix = fixedMap[orig.number];
        if (fix == null) return orig;
        return orig.copyWith(
          actionZh: fix['action_zh'] as String? ?? orig.actionZh,
          dialogue: fix['dialogue'] as String? ?? orig.dialogue,
          cameraMove: fix['camera_move'] as String? ?? orig.cameraMove,
          mood: fix['mood'] as String? ?? orig.mood,
          shotSize: fix['shot_size'] != null
              ? StudioShotSize.fromId(fix['shot_size'].toString())
              : orig.shotSize,
          durationSec: fix['duration_sec'] is num
              ? (fix['duration_sec'] as num).toDouble()
              : orig.durationSec,
        );
      }).toList();

      final updatedEpisode = widget.episode.copyWith(shots: updatedShots);

      if (!mounted) return;
      widget.onFixCompleted(updatedEpisode);
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI 一键自愈失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isAutoFixing = false;
        });
      }
    }
  }

  void _handleStaggerShot(int shotNumber) {
    final updated = DirectorValidationEngine.staggerConsecutiveShotScale(
      widget.episode,
      shotNumber,
    );
    widget.onFixCompleted(updated);
    Navigator.of(context).pop();
  }

  void _handleSplitOverloaded(int shotNumber) {
    final updated = DirectorValidationEngine.splitOverloadedShot(
      widget.episode,
      shotNumber,
      framesDir: widget.framesDir,
      clipsDir: widget.clipsDir,
      dialoguesDir: widget.dialoguesDir,
    );
    widget.onFixCompleted(updated);
    Navigator.of(context).pop();
  }

  void _handleSplitVerticalReversePair(int shotNumber) {
    final updated = DirectorValidationEngine.splitVerticalShotIntoReversePair(
      widget.episode,
      shotNumber,
      characters: widget.characters,
      framesDir: widget.framesDir,
      clipsDir: widget.clipsDir,
      dialoguesDir: widget.dialoguesDir,
    );
    widget.onFixCompleted(updated);
    Navigator.of(context).pop();
  }

  Widget _buildScorePill(BuildContext context, String stage, int score, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withAlpha(80)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage,
              style: TextStyle(fontSize: 10, color: context.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              '$score 分',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final sc = widget.scorecard;
    final errorColor = context.errorText;
    final warningColor = context.warningText;

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            report.isValid
                ? Icons.verified_outlined
                : Icons.report_problem_outlined,
            color: report.isValid ? const Color(0xFF22C55E) : errorColor,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              sc != null
                  ? '全链路影视质检报告 (${sc.overallScore}分 · C01~C17)'
                  : (report.isValid ? '导演质检报告（通过）' : '导演质检报告（待优化）'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (sc != null) ...[
                Row(
                  children: [
                    _buildScorePill(
                      context,
                      '1.剧本可拍性',
                      sc.screenplayScore,
                      sc.screenplayScore >= 80 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    _buildScorePill(
                      context,
                      '2.分镜语法',
                      sc.storyboardGrammarScore,
                      sc.storyboardGrammarScore >= 80 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    _buildScorePill(
                      context,
                      '3.关键帧生图',
                      sc.keyframeAndPromptScore,
                      sc.keyframeAndPromptScore >= 80 ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    _buildScorePill(
                      context,
                      '4.视频安全',
                      sc.videoMotionSafetyScore,
                      sc.videoMotionSafetyScore >= 80 ? Colors.green : Colors.orange,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (report.blockingCount > 0
                                  ? errorColor
                                  : const Color(0xFF22C55E))
                              .withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '阻断项: ${report.blockingCount}',
                      style: TextStyle(
                        color: report.blockingCount > 0
                            ? errorColor
                            : const Color(0xFF22C55E),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (report.warningCount > 0
                                  ? warningColor
                                  : context.textTertiary)
                              .withAlpha(25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '建议项: ${report.warningCount}',
                      style: TextStyle(
                        color: report.warningCount > 0
                            ? warningColor
                            : context.textTertiary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '合规通关: ${report.passCount} / 14 规则',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: report.passCount >= 10
                          ? const Color(0xFF22C55E)
                          : errorColor,
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              if (report.issues.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      '恭喜！全案所有分镜完全符合 C01~C17 视听与物理可执行性规范。',
                      style: TextStyle(fontSize: 13, color: Color(0xFF22C55E)),
                    ),
                  ),
                )
              else
                ...report.issues.map((issue) {
                  final isBlocking =
                      issue.severity == ValidationSeverity.blocking;
                  final color = isBlocking ? errorColor : warningColor;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withAlpha(16),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withAlpha(70)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: color.withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${issue.ruleId} · ${issue.ruleName}',
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (issue.shotNumber != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                '镜 #${issue.shotNumber}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              issue.severity.label,
                              style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          issue.message,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '建议: ${issue.suggestion}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textSecondary,
                          ),
                        ),
                        if (issue.shotNumber != null) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (issue.ruleId == 'C14')
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _handleStaggerShot(issue.shotNumber!),
                                  icon: const Icon(Icons.tune, size: 14),
                                  label: Text('一键错落景别 (#${issue.shotNumber})'),
                                ),
                              if (issue.ruleId == 'C15')
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _handleSplitOverloaded(issue.shotNumber!),
                                  icon: const Icon(Icons.call_split, size: 14),
                                  label: Text('一键拆分双镜 (#${issue.shotNumber})'),
                                ),
                              if (issue.ruleId == 'C16')
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.indigo,
                                  ),
                                  onPressed: () =>
                                      _handleSplitVerticalReversePair(
                                        issue.shotNumber!,
                                      ),
                                  icon: const Icon(
                                    Icons.swap_horiz,
                                    size: 14,
                                  ),
                                  label: Text(
                                    '一键裂变为正反打双镜 (#${issue.shotNumber})',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
      ),
      actions: [
        if (report.issues.isNotEmpty)
          ElevatedButton.icon(
            onPressed: _isAutoFixing ? null : _handleAutoFix,
            icon: _isAutoFixing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high, size: 16),
            label: Text(_isAutoFixing ? 'AI 一键自愈中…' : 'AI 一键自愈'),
          ),
        if (widget.onAuditAllKeyframes != null)
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onAuditAllKeyframes?.call();
            },
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            label: const Text('全片关键帧质检'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _VideoPromptDialog extends StatefulWidget {
  const _VideoPromptDialog({
    required this.shot,
    required this.episode,
    required this.characters,
    this.props = const [],
    required this.scenes,
    required this.framesDir,
    required this.onSave,
  });

  final StudioShot shot;
  final StudioEpisode episode;
  final List<CharacterCard> characters;
  final List<PropCard> props;
  final List<SceneCard> scenes;
  final String framesDir;
  final ValueChanged<StudioShot> onSave;

  @override
  State<_VideoPromptDialog> createState() => _VideoPromptDialogState();
}

class _VideoPromptDialogState extends State<_VideoPromptDialog> {
  late final TextEditingController _controller;
  bool _isRewriting = false;

  @override
  void initState() {
    super.initState();
    final initialText = widget.shot.videoPrompt.isNotEmpty
        ? widget.shot.videoPrompt
        : PromptAssembler.buildSanitizedVideoPrompt(
            shot: widget.shot,
            episode: widget.episode,
            characters: widget.characters,
            props: widget.props,
            scene: widget.scenes
                .where((s) => s.id == widget.shot.sceneId)
                .firstOrNull,
          );
    _controller = TextEditingController(text: initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleAiRewrite() async {
    setState(() {
      _isRewriting = true;
    });

    try {
      final result = await AiConstraintEngine.rewriteVideoPrompt(
        shot: widget.shot,
        episode: widget.episode,
        characters: widget.characters,
        props: widget.props,
        scene: widget.scenes
            .where((s) => s.id == widget.shot.sceneId)
            .firstOrNull,
      );

      final rewritten =
          (result.data['rewritten_prompt'] as String?)?.trim() ?? '';
      if (rewritten.isEmpty) {
        throw Exception('AI 返回重写结果为空');
      }

      if (!mounted) return;
      setState(() {
        _controller.text = rewritten;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('AI 提示词消解重写完成！')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('AI 提示词重写失败: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _isRewriting = false;
        });
      }
    }
  }

  void _handleRuleClean() {
    final cleaned = PromptAssembler.cleanAndResolveConflicts(_controller.text);
    setState(() {
      _controller.text = cleaned;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已应用视听与机位规则清洗！')));
  }

  void _handleResetDefault() {
    final defaultPrompt = PromptAssembler.buildSanitizedVideoPrompt(
      shot: widget.shot.copyWith(videoPrompt: ''),
      episode: widget.episode,
      characters: widget.characters,
      scene: widget.scenes
          .where((s) => s.id == widget.shot.sceneId)
          .firstOrNull,
    );
    setState(() {
      _controller.text = defaultPrompt;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已重置为默认装配提示词')));
  }

  void _handleSave() {
    widget.onSave(widget.shot.copyWith(videoPrompt: _controller.text.trim()));
    Navigator.of(context).pop();
  }

  void _handleClearOverride() {
    widget.onSave(widget.shot.copyWith(videoPrompt: ''));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final hasFrame =
        (widget.shot.firstFramePath != null &&
            widget.shot.firstFramePath!.isNotEmpty) ||
        (widget.shot.framePath != null && widget.shot.framePath!.isNotEmpty);
    final hasRef =
        widget.shot.characterIds.isNotEmpty ||
        widget.shot.sceneId.trim().isNotEmpty;
    final effectiveMode = widget.shot.resolveEffectiveVideoMode(
      hasKeyframe: hasFrame,
      hasCharacterOrSceneRef: hasRef,
    );

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.movie_filter_outlined, size: 20),
          const SizedBox(width: 8),
          Text('分镜 #${widget.shot.number} 视频生成 Prompt'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: context.accentSubtle.withAlpha(50),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.accentSubtle),
            ),
            child: Text(
              '当前生效: ${effectiveMode.id}',
              style: TextStyle(
                fontSize: 11,
                color: context.accentText,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 650,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '此处为最终发送给 Agnes 视频模型的 Prompt 内容。你可以直接手动微调，也可使用 AI 重写消除冲突，或使用规则清洗。',
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              style: TextStyle(
                fontSize: 12,
                color: context.textPrimary,
                fontFamily: 'monospace',
              ),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: '输入或生成视频提示词…',
                helperText: effectiveMode == AgnesVideoMode.text
                    ? '纯文本(text)模式：模型完全依据本段提示词生成画面，不传递图像。'
                    : (effectiveMode == AgnesVideoMode.reference
                          ? '参考图(reference)模式：已自动分离角色与场景图，提示词仅描述动态。'
                          : '首尾帧(keyframe)模式：首尾画面已由关键帧锁定，提示词聚焦动作与光影。'),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _isRewriting ? null : _handleAiRewrite,
                  icon: _isRewriting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: Text(_isRewriting ? 'AI 重写中…' : 'AI 智能消解冲突'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _handleRuleClean,
                  icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                  label: const Text('规则清洗'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _handleResetDefault,
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('重置为默认装配'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.shot.videoPrompt.isNotEmpty)
          TextButton(
            onPressed: _handleClearOverride,
            child: Text('恢复动态组装', style: TextStyle(color: context.warningText)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(onPressed: _handleSave, child: const Text('保存修改')),
      ],
    );
  }
}

/// 五维字段的编辑框（spec: 五维导演决策的用户可改性）。
///
/// 自己持有 controller 而不是每次 build 新建——后者会在父组件重绘时重置光标，
/// 输入体验直接崩掉。提交时机取「失焦 + 回车」两个：分镜卡没有确定按钮，
/// 逐字符回调会让每次击键都写一次 storyboard.json。
class _DecisionField extends StatefulWidget {
  const _DecisionField({
    required this.initialValue,
    required this.onCommit,
    this.hint = '',
  });

  final String initialValue;
  final ValueChanged<String> onCommit;
  final String hint;

  @override
  State<_DecisionField> createState() => _DecisionFieldState();
}

class _DecisionFieldState extends State<_DecisionField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    final text = _controller.text.trim();
    if (text != widget.initialValue.trim()) {
      widget.onCommit(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (hasFocus) {
        if (!hasFocus) _commit();
      },
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: 3,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 10,
          height: 1.25,
        ),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: TextStyle(color: context.textTertiary, fontSize: 10),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: InputBorder.none,
        ),
        onSubmitted: (_) => _commit(),
      ),
    );
  }
}
