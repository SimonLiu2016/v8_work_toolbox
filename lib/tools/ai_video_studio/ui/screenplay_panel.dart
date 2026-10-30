/// 剧本创作工作台：影视分场文学剧本编辑、节拍精修与动作超载拦截（spec: screenplay-workbench）。
///
/// 位于「创意孵化」与「分镜看板」之间，支持从大纲生成分场剧本、结构化微动作节拍编辑，
/// 并在拆分镜前提供动作与台词复杂度预警，打磨完成后一键转为 5D 分镜看板。
library;

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../novel_manager/services/novel_repository.dart';
import '../models/studio_models.dart';
import '../services/ai_constraint_engine.dart';
import '../services/breakdown_input.dart';
import '../services/screenplay_importer.dart';
import '../services/screenplay_quality_evaluator.dart';
import '../services/studio_project_manager.dart';
import 'screenplay_novel_adapt_dialog.dart';
import 'studio_shell.dart';

class ScreenplayPanel extends StatefulWidget {
  const ScreenplayPanel({
    super.key,
    required this.session,
    this.onNavigateToStoryboard,
  });

  final StudioSession session;
  final VoidCallback? onNavigateToStoryboard;

  @override
  State<ScreenplayPanel> createState() => _ScreenplayPanelState();
}

class _ScreenplayPanelState extends State<ScreenplayPanel> {
  final _manager = StudioProjectManager.instance;
  bool _isGenerating = false;
  String? _statusMessage;
  List<DramaScene> _scenes = [];
  List<CharacterCard> _characters = [];
  List<SceneCard> _sceneCards = [];
  List<PropCard> _props = [];
  List<StudioEpisode> _allEpisodes = const [];
  String _screenplayText = '';
  final _textEditorController = TextEditingController();
  bool _isRawTextMode = false;
  bool _hasCustomRawText = false;
  bool _dismissedProseBanner = false;
  String? _boundNovelTitle;
  bool _synopsisExpanded = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _textEditorController.addListener(_onTextControllerChanged);
    _loadCurrentEpisode();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _textEditorController.removeListener(_onTextControllerChanged);
    _textEditorController.dispose();
    super.dispose();
  }

  void _onTextControllerChanged() {
    if (mounted) setState(() {});
  }

  void _onSessionChanged() {
    _loadCurrentEpisode();
  }

  Future<void> _loadCurrentEpisode() async {
    final series = widget.session.series;
    if (series == null) {
      if (mounted) {
        setState(() {
          _allEpisodes = const [];
          _scenes = [];
          _characters = [];
          _sceneCards = [];
          _props = [];
          _screenplayText = '';
          _textEditorController.text = '';
          _boundNovelTitle = null;
        });
      }
      return;
    }

    // 若绑定了原著小说，异步拉取其书名以提供友好提示
    String? boundNovelTitle;
    if (series.novelId != null && series.novelId!.isNotEmpty) {
      try {
        final novel = await NovelRepository.instance.getNovel(series.novelId!);
        boundNovelTitle = novel?.title;
      } catch (_) {}
    }

    final episodes = await _manager.listEpisodes(series.id);
    StudioEpisode? ep = widget.session.episode;
    if (ep == null && episodes.isNotEmpty) {
      ep = episodes.first;
      widget.session.selectEpisode(ep);
      return;
    }
    if (ep != null) {
      final matched = episodes.where((e) => e.id == ep!.id).firstOrNull;
      if (matched != null) ep = matched;
    }

    final chars = await _manager.listCharacters(series.id);
    final sceneCards = await _manager.listScenes(series.id);
    final propCards = await _manager.listProps(series.id);
    final freshEp = ep != null ? (_manager.readEpisode(series.id, ep.id) ?? ep) : null;
    if (mounted) {
      setState(() {
        _allEpisodes = episodes;
        _characters = chars;
        _sceneCards = sceneCards;
        _props = propCards;
        _boundNovelTitle = boundNovelTitle;
        _scenes = freshEp != null ? List.from(freshEp.scenes) : [];
        _screenplayText = freshEp?.screenplayText ?? '';
        final exported = _exportToMarkdown(_scenes);
        _hasCustomRawText = _screenplayText.trim().isNotEmpty &&
            _scenes.isNotEmpty &&
            _screenplayText.trim() != exported.trim();
        _textEditorController.text =
            _screenplayText.isNotEmpty ? _screenplayText : exported;
      });
    }
  }

  /// 文本模式里做过修改、且尚未反映到结构化场次（spec: 全文文本编辑不丢失用户修改）。
  ///
  /// 系统没有 markdown → DramaScene 的反向解析，所以文本模式的编辑只能落在
  /// `screenplayText` 字符串里。这个判据的职责是：切回结构化视图前发现用户
  /// 改过东西，让他自己决定保留还是丢弃，而不是静默用旧 scenes 冲掉。
  bool _hasUnsyncedTextEdits() {
    if (!_isRawTextMode) return false;
    return _textEditorController.text != _exportToMarkdown(_scenes);
  }

  /// 将当前内存中的场次节拍与全文剧本改动同步写回 `StudioEpisode` 并落盘。
  Future<StudioEpisode?> _flushInMemoryEpisode() async {
    final series = widget.session.series;
    final ep = widget.session.episode;
    if (series == null || ep == null) return null;

    final String nextScreenplayText;
    if (_isRawTextMode) {
      nextScreenplayText = _textEditorController.text;
      _screenplayText = nextScreenplayText;
      _hasCustomRawText = _scenes.isNotEmpty &&
          nextScreenplayText.trim() != _exportToMarkdown(_scenes).trim();
    } else if (!_hasCustomRawText && _scenes.isNotEmpty) {
      nextScreenplayText = _exportToMarkdown(_scenes);
      _screenplayText = nextScreenplayText;
      _textEditorController.text = nextScreenplayText;
    } else {
      nextScreenplayText = _screenplayText;
    }

    final updated = ep.copyWith(
      scenes: List<DramaScene>.from(_scenes),
      screenplayText: nextScreenplayText,
      updatedAt: DateTime.now(),
    );
    await _manager.saveEpisode(updated);
    widget.session.episode = updated;
    return updated;
  }

  /// 视图模式切换。
  ///
  /// 从文本模式切回结构化视图时，若用户在文本里做过修改，弹确认让他选：
  /// 保留（立即把全文改动同步至 `_screenplayText` 并落盘）或丢弃（用结构化数据覆盖）。
  Future<void> _handleModeToggle() async {
    if (_isRawTextMode && _hasUnsyncedTextEdits()) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('有未同步的文本修改'),
          content: const Text(
            '你在 Markdown 文本模式下修改过剧本，但这些修改还没有同步到结构化场次。\n\n'
            '「保留修改」会保存你刚才编辑的剧本全文并切换视图；'
            '「丢弃修改」会用结构化场次重新导出文本，覆盖你刚才的编辑。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('丢弃修改'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保留修改'),
            ),
          ],
        ),
      );
      if (keep == null || !mounted) return;
      if (keep) {
        setState(() {
          _screenplayText = _textEditorController.text;
          _hasCustomRawText = true;
          _isRawTextMode = false;
        });
        await _flushInMemoryEpisode();
        return;
      }
      final exported = _exportToMarkdown(_scenes);
      setState(() {
        _screenplayText = exported;
        _textEditorController.text = exported;
        _hasCustomRawText = false;
        _isRawTextMode = false;
      });
      await _flushInMemoryEpisode();
      return;
    }

    setState(() {
      if (!_isRawTextMode) {
        _textEditorController.text = (_hasCustomRawText && _screenplayText.isNotEmpty)
            ? _screenplayText
            : _exportToMarkdown(_scenes);
      }
      _isRawTextMode = !_isRawTextMode;
    });
  }

  Future<void> _saveChanges() async {
    final updated = await _flushInMemoryEpisode();
    if (updated == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剧本已保存'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  /// 防误触拦截：若当前已有编排场次或编辑中的剧本文本，弹出确认对话框提示用户继续操作将覆盖现有剧本。
  Future<void> _confirmOverwriteIfNeeded(Future<void> Function() action) async {
    final hasExistingContent = _scenes.isNotEmpty || _screenplayText.trim().isNotEmpty;
    if (hasExistingContent) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 22),
              SizedBox(width: 8),
              Text('导入或重新生成将覆盖现有剧本'),
            ],
          ),
          content: const Text('当前集已有剧本内容或编排场次，继续操作将覆盖当前内容。是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续并覆盖'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await action();
  }

  /// 从外部文件导入文学剧本（支持 .md, .txt, .fountain）
  Future<void> _importScreenplayFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: '选择外部文学剧本文件',
        type: FileType.custom,
        allowedExtensions: ['md', 'txt', 'fountain'],
      );
      if (result == null || result.files.isEmpty) return;
      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
      if (!await file.exists()) return;

      final content = await file.readAsString();
      final parsed = ScreenplayImporter.parse(content);

      if (parsed.isStructured && parsed.scenes.isNotEmpty) {
        setState(() {
          _scenes = parsed.scenes;
          _screenplayText = _exportToMarkdown(parsed.scenes);
          _textEditorController.text = _screenplayText;
          _hasCustomRawText = false;
          _isRawTextMode = false;
        });
        await _saveChanges();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已成功导入分场剧本：${parsed.parseSummary}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          _scenes = [];
          _screenplayText = parsed.rawText;
          _textEditorController.text = parsed.rawText;
          _hasCustomRawText = true;
          _isRawTextMode = true;
        });
        await _saveChanges();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(parsed.parseSummary ?? '剧本文档已载入（纯文本模式）'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入剧本失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 导出整集文学剧本到本地文件
  Future<void> _exportScreenplayToFile(String format) async {
    final ep = widget.session.episode;
    final series = widget.session.series;
    if (ep == null) return;

    final seriesTitle = series?.name ?? '剧作';
    final isMd = format.toLowerCase() == 'md';
    final ext = isMd ? 'md' : 'txt';
    final defaultName = '${seriesTitle}_第${ep.index}集_${ep.title}_文学剧本.$ext';

    String contentToExport;
    if (isMd) {
      contentToExport = _isRawTextMode
          ? _textEditorController.text
          : (_screenplayText.isNotEmpty
              ? _screenplayText
              : _exportToMarkdown(_scenes));
    } else {
      final md = _isRawTextMode
          ? _textEditorController.text
          : (_screenplayText.isNotEmpty
              ? _screenplayText
              : _exportToMarkdown(_scenes));
      // 转为无 Markdown 语法符号的规范纯文本剧本
      contentToExport = md
          .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
          .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'$1')
          .replaceAll(RegExp(r'\*(.*?)\*'), r'$1');
    }

    String? savePath;
    try {
      savePath = await FilePicker.platform.saveFile(
        dialogTitle: '导出文学剧本到本地',
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
            content: Text('剧本已成功导出到: $savePath'),
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
            content: Text('导出剧本失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// 唤起小说正文深度影视化改编弹窗
  Future<void> _showNovelAdaptDialog() async {
    final series = widget.session.series;
    final ep = widget.session.episode;
    if (series == null || ep == null) return;

    final result = await showDialog<ScreenplayNovelAdaptResult>(
      context: context,
      builder: (ctx) => ScreenplayNovelAdaptDialog(
        series: series,
        episodeIndex: ep.index,
        targetChapterRange: ep.novelChapterRange,
        targetChapterIndices: ep.novelChapterIndices,
        onSeriesUpdated: (updatedSeries) {
          widget.session.updateSeries(updatedSeries);
        },
      ),
    );

    if (result != null && mounted) {
      if (result.selectedChapterIndices.isNotEmpty) {
        final sorted = List<int>.from(result.selectedChapterIndices)..sort();
        final rangeDesc = sorted.length == 1 ? '${sorted.first}' : '${sorted.first}-${sorted.last}';
        final updatedEp = ep.copyWith(
          novelChapterRange: rangeDesc,
          novelChapterIndices: sorted,
          updatedAt: DateTime.now(),
        );
        widget.session.updateEpisode(updatedEp);
      }
      await _adaptFromNovelText(
        result.novelText,
        chapterTitle: result.chapterTitle,
      );
    }
  }

  /// 依据原著小说章节全文进行单集深度影视化改编
  Future<void> _adaptFromNovelText(
    String novelText, {
    String? chapterTitle,
  }) async {
    final series = widget.session.series;
    final ep = widget.session.episode;
    if (series == null || ep == null) return;

    setState(() {
      _isGenerating = true;
      _statusMessage = 'AI 正在通读小说正文，提炼戏剧场次并锁定原著金句...';
    });

    try {
      final charNames = _characters.map((c) => c.name).toList();
      final memoryContext = series.memories
          .map((m) => '【${m.title}】${m.summary}')
          .join('\n');

      final res = await AiConstraintEngine.adaptNovelDramaChapter(
        novelText: novelText,
        seriesName: series.name,
        worldview: series.worldview,
        characterNames: charNames,
        propNames: _props.map((p) => p.name).toList(),
        productionType: series.productionType.id,
        episodeIndex: ep.index,
        memoryContext: memoryContext,
      );

      final scenesRaw = res.data['scenes'];
      final parsedScenes = <DramaScene>[];
      if (scenesRaw is List) {
        for (final s in scenesRaw) {
          if (s is Map) {
            parsedScenes.add(DramaScene.fromJson(
              s.map((k, v) => MapEntry(k as String, v)),
            ));
          }
        }
      }

      final contractRaw = res.data['protected_contract'];
      final protectedContract = contractRaw is Map<String, dynamic>
          ? ProtectedContract.fromJson(contractRaw)
          : (contractRaw is Map
              ? ProtectedContract.fromJson(
                  contractRaw.map((k, v) => MapEntry(k as String, v)))
              : ProtectedContract.empty);

      final dynamicTitle = (res.data['title'] as String? ?? '').trim();
      final effectiveTitle = dynamicTitle.isNotEmpty
          ? dynamicTitle
          : (chapterTitle?.trim().isNotEmpty == true
              ? chapterTitle!.trim()
              : ep.title);
      final effectiveSynopsis =
          (res.data['synopsis'] as String? ?? ep.synopsis).trim();
      final effectiveSummary =
          (res.data['summary'] as String? ?? effectiveSynopsis).trim();
      final effectiveHook = (res.data['hook'] as String? ?? '').trim();
      final dynamicScreenplay =
          (res.data['screenplay_text'] as String? ?? '').trim();
      final effectiveScreenplay = dynamicScreenplay.isNotEmpty
          ? dynamicScreenplay
          : DramaScene.exportToMarkdown(parsedScenes);

      final updatedSeries = await _manager.importChapterToEpisode(
        seriesId: series.id,
        masterExtraction: const {},
        targetEpisodeIndex: ep.index,
        episodeTitle: effectiveTitle,
        episodeSynopsis: effectiveSynopsis,
        episodeSummary: effectiveSummary,
        episodeHook: effectiveHook,
        scenes: parsedScenes,
        screenplayText: effectiveScreenplay,
        protectedContract: protectedContract,
      );

      widget.session.updateSeries(updatedSeries);

      final reloadedEp = _manager.readEpisode(series.id, ep.id);
      if (reloadedEp != null) {
        widget.session.episode = reloadedEp;
      }

      final chars = await _manager.listCharacters(series.id);
      final sceneCards = await _manager.listScenes(series.id);

      if (mounted) {
        setState(() {
          _characters = chars;
          _sceneCards = sceneCards;
          _scenes = reloadedEp?.scenes ?? parsedScenes;
          _screenplayText = reloadedEp?.screenplayText ?? effectiveScreenplay;
          _textEditorController.text = _screenplayText;
          _hasCustomRawText = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '《第 ${ep.index} 集》剧本改编完成！提炼 ${_scenes.length} 场，锁定 ${protectedContract.utterances.length} 条原著对白、${protectedContract.facts.length} 条核心事实',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('小说改编剧本失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = null;
        });
      }
    }
  }

  /// AI 一键大纲/小说章节转分场剧本
  Future<void> _generateScreenplayWithAi() async {
    final series = widget.session.series;
    final ep = widget.session.episode;
    if (series == null || ep == null) return;

    final inputPrompt = ep.synopsis.trim().isNotEmpty
        ? ep.synopsis.trim()
        : '剧集标题：${ep.title}。请创作具备戏剧冲突的分场剧本。';

    setState(() {
      _isGenerating = true;
      _statusMessage = 'AI 正在通读大纲，规划影视场次与动作对白...';
    });

    try {
      final charNames = _characters.map((c) => c.name).toList();
      // 角色设定与已有场景卡名一并注入（spec: 剧本生成注入资产上下文）。
      // 少了这两样，AI 只能凭粗大纲自造角色外貌与地点名——生成的地点对不上
      // 场景库，_ensureScenesForDramaScenes 就另建新卡，场景库迅速膨胀。
      final charProfiles = _characters.map((c) {
        final traits = <String>[
          if (c.facialFeaturesZh.trim().isNotEmpty) c.facialFeaturesZh.trim(),
          if (c.defaultAttireZh.trim().isNotEmpty) c.defaultAttireZh.trim(),
        ];
        return traits.isEmpty ? c.name : '${c.name}（${traits.join('，')}）';
      }).toList();
      final res = await AiConstraintEngine.screenplayGeneration(
        synopsis: inputPrompt,
        characterNames: charNames,
        characterProfiles: charProfiles,
        sceneNames: _sceneCards.map((s) => s.name).toList(),
        propNames: _props.map((p) => p.name).toList(),
        protectedContract: ep.protectedContract,
        seriesName: series.name,
        productionType: series.productionType.id,
      );

      final scenesRaw = res.data['scenes'];
      if (scenesRaw is List && scenesRaw.isNotEmpty) {
        final parsed = scenesRaw
            .whereType<Map>()
            .map((e) => DramaScene.fromJson(e.map((k, v) => MapEntry(k as String, v))))
            .toList();
        setState(() {
          _scenes = parsed;
          _screenplayText = _exportToMarkdown(parsed);
          _textEditorController.text = _screenplayText;
          _hasCustomRawText = false;
        });
        await _saveChanges();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('AI 未能成功生成结构化分场剧本，请重试')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成剧本失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = null;
        });
      }
    }
  }

  String _exportToMarkdown(List<DramaScene> scenes) =>
      DramaScene.exportToMarkdown(scenes);

  void _addScene() {
    final nextNum = _scenes.isEmpty ? 1 : _scenes.map((s) => s.sceneNumber).reduce((a, b) => a > b ? a : b) + 1;
    final newScene = DramaScene(
      id: 'SC${nextNum.toString().padLeft(3, '0')}',
      sceneNumber: nextNum,
      title: '场景 $nextNum',
      location: '地点',
      setting: '内景',
      timeOfDay: '日景',
      beats: [
        DramaBeat(
          id: 'B01',
          sceneId: 'SC${nextNum.toString().padLeft(3, '0')}',
          order: 1,
          name: '初始动作',
          action: '角色登场进入场景',
        ),
      ],
    );
    setState(() {
      _scenes.add(newScene);
    });
  }

  void _removeScene(int index) {
    setState(() {
      _scenes.removeAt(index);
    });
  }

  void _addBeat(DramaScene scene) {
    final sceneIndex = _scenes.indexWhere((s) => s.id == scene.id);
    if (sceneIndex < 0) return;

    final nextOrder = scene.beats.isEmpty ? 1 : scene.beats.length + 1;
    final newBeat = DramaBeat(
      id: 'B${nextOrder.toString().padLeft(2, '0')}',
      sceneId: scene.id,
      order: nextOrder,
      name: '动作节拍 $nextOrder',
      action: '',
    );
    final updatedBeats = List<DramaBeat>.from(scene.beats)..add(newBeat);
    setState(() {
      _scenes[sceneIndex] = scene.copyWith(beats: updatedBeats);
    });
  }

  void _removeBeat(DramaScene scene, int beatIndex) {
    final sceneIndex = _scenes.indexWhere((s) => s.id == scene.id);
    if (sceneIndex < 0) return;

    final updatedBeats = List<DramaBeat>.from(scene.beats)..removeAt(beatIndex);
    setState(() {
      _scenes[sceneIndex] = scene.copyWith(beats: updatedBeats);
    });
  }

  bool _isActionOverloaded(String action) {
    return AiConstraintEngine.isActionOverloaded(action);
  }

  /// 一键将剧本结构化分场与节拍转换为 5D 分镜看板（spec 11.1 / Task 5.5）。
  Future<void> _convertToStoryboard() async {
    final series = widget.session.series;
    final ep = await _flushInMemoryEpisode();
    if (series == null || ep == null) return;

    if (_scenes.isEmpty || _scenes.every((s) => s.beats.isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前剧本没有场次或节拍，请先添加节拍或使用 AI 生成剧本')),
      );
      return;
    }

    final syncedCards = await _manager.ensureScenesForEpisode(
      seriesId: series.id,
      episode: ep.copyWith(scenes: _scenes),
    );
    final refreshedEp = _manager.readEpisode(series.id, ep.id) ?? ep;
    _scenes = refreshedEp.scenes.isNotEmpty ? refreshedEp.scenes : _scenes;
    _sceneCards = syncedCards;

    final newShots = AiConstraintEngine.convertScenesToShots(
      _scenes,
      characters: _characters,
      sceneCards: _sceneCards,
      props: _props,
    );

    final segments = StudioEpisode.buildSegmentsFromScenes(_scenes, newShots);

    final updated = ep.copyWith(
      scenes: _scenes,
      screenplayText: _screenplayText,
      shots: newShots,
      segments: segments,
      updatedAt: DateTime.now(),
    );

    await _manager.saveEpisode(updated);
    widget.session.episode = updated;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已将 ${_scenes.length} 个场次共 ${newShots.length} 个节拍本地同步至分镜看板（本地映射，未调用外部 AI 模型）'),
        ),
      );
      widget.onNavigateToStoryboard?.call();
    }
  }

  /// 使用 AI 大模型五维导演拆镜服务，将当前剧本或大纲全新拆解为电影级分镜。
  Future<void> _breakdownWithAi() async {
    final series = widget.session.series;
    final ep = await _flushInMemoryEpisode();
    if (series == null || ep == null) return;
    // 输入取值与分镜看板共用同一份逻辑（spec: 拆镜入口的输入一致性）：
    // 先把内存态落进 ep，再优先用打磨过的文学剧本全文，为空才回退到粗大纲。
    final synopsis = BreakdownInput.synopsisOf(
      ep,
      rawTextOverride: _isRawTextMode ? _textEditorController.text : null,
    );
    if (synopsis.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前剧本与大纲均为空，请先输入文本或使用 AI 生成剧本')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = 'AI 正在执行五维导演拆镜（运镜、机位、视线与因果链）...';
    });

    try {
      final characters = await _manager.listCharacters(series.id);
      final scenes = await _manager.listScenes(series.id);
      final result = await AiConstraintEngine.scriptBreakdown5D(
        synopsis: synopsis,
        context: ScriptContext(
          seriesName: series.name,
          productionType: series.productionType.id,
          styleTokens: series.styleTokens,
          episodeIndex: ep.index,
          characterNames: characters.map((c) => c.name).toList(),
          sceneNames: scenes.map((s) => s.name).toList(),
          scenes: BreakdownInput.scenesOf(ep),
          protectedContract: BreakdownInput.contractOf(ep),
          preferSynopsisOverScenes: BreakdownInput.hasUnsyncedRawScreenplay(ep),
        ),
      );
      final shots = ((result.data['shots'] as List)
              .cast<Map<String, dynamic>>())
          .map(StudioShot.fromJson)
          .toList();
      final segments = ((result.data['segments'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(StudioSegment.fromJson)
              .toList();
      final saved = ep.copyWith(
        synopsis: ep.synopsis.isNotEmpty ? ep.synopsis : synopsis,
        shots: shots,
        segments: segments.isNotEmpty ? segments : null,
        updatedAt: DateTime.now(),
      );
      await _manager.saveEpisode(saved);
      widget.session.episode = saved;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 五维拆解完成！成功生成 ${shots.length} 个全新电影级分镜')),
        );
        widget.onNavigateToStoryboard?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 拆镜失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusMessage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.session.series;
    final episode = widget.session.episode;

    if (series == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_collection_outlined, size: 48, color: context.textTertiary),
            const SizedBox(height: 16),
            Text('请先选择或创建剧集', style: TextStyle(color: context.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }

    if (episode == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.movie_outlined, size: 48, color: context.textTertiary),
            const SizedBox(height: 16),
            Text('请在左上角或剧集库中选择具体集数', style: TextStyle(color: context.textSecondary, fontSize: 16)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: context.bgContent,
      body: Column(
        children: [
          _buildToolbar(context, episode),
          _buildEpisodeSynopsisHeader(context, episode),
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              color: context.bgSelected,
              child: Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(_statusMessage!, style: TextStyle(color: context.accentText, fontSize: 12)),
                ],
              ),
            ),
          Expanded(
            child: _isRawTextMode
                ? _buildRawTextEditor(context)
                : (_scenes.isEmpty
                    ? _buildEmptyScenesGuide(context, episode)
                    : _buildScenesList(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(BuildContext context, StudioEpisode episode) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.bgWindow,
        border: Border(bottom: BorderSide(color: context.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_stories_outlined, size: 20, color: context.accentText),
          if (_allEpisodes.length > 1) ...[
            DropdownButton<String>(
              value: episode.id,
              isDense: true,
              underline: const SizedBox.shrink(),
              dropdownColor: context.bgCard,
              icon: Icon(Icons.arrow_drop_down, color: context.accentText, size: 20),
              items: _allEpisodes.map((e) {
                return DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    '第 ${e.index} 集：${e.title}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimary,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (newId) {
                if (newId != null) {
                  final target = _allEpisodes.firstWhere((e) => e.id == newId);
                  widget.session.selectEpisode(target);
                }
              },
            ),
          ] else
            Text(
              '第 ${episode.index} 集：文学剧本',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: context.textPrimary,
              ),
            ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: context.borderSubtle),
            ),
            child: Text(
              '共 ${_scenes.length} 场 / ${_scenes.fold(0, (sum, s) => sum + s.beats.length)} 节拍',
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (context) {
              final currentDraft = episode.copyWith(
                scenes: _scenes,
                screenplayText: _isRawTextMode
                    ? _textEditorController.text
                    : _screenplayText,
              );
              final report = ScreenplayQualityEvaluator.evaluate(currentDraft);
              final scoreColor = report.overallScore >= 85
                  ? Colors.green
                  : (report.overallScore >= 70 ? Colors.orange : Colors.red);
              return InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _showScreenplayQualityDialog(context, report),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scoreColor.withValues(alpha: 0.45)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        report.isClean
                            ? Icons.verified_outlined
                            : Icons.visibility_outlined,
                        size: 13,
                        color: scoreColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '可拍性: ${report.overallScore}分${report.issues.isEmpty ? '' : ' (${report.issues.length}项待外化)'}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: scoreColor,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: _isRawTextMode ? '切换为结构化分场视图' : '切换为 Markdown 文本模式',
            icon: Icon(_isRawTextMode ? Icons.view_agenda_outlined : Icons.code_outlined),
            onPressed: () => _handleModeToggle(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    onPressed: _addScene,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新增场次'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isGenerating
                        ? null
                        : () => _confirmOverwriteIfNeeded(_importScreenplayFromFile),
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('导入剧本'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _isGenerating
                        ? null
                        : () => _confirmOverwriteIfNeeded(_showNovelAdaptDialog),
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_stories, size: 16),
                    label: const Text('从小说正文生成剧本'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _isGenerating
                        ? null
                        : () => _confirmOverwriteIfNeeded(_generateScreenplayWithAi),
                    icon: const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('根据大纲扩写'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _saveChanges,
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('保存剧本'),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    tooltip: '导出文学剧本到文件',
                    onSelected: _exportScreenplayToFile,
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'md',
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('导出为 Markdown 剧本 (.md)'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'txt',
                        child: Row(
                          children: [
                            Icon(Icons.text_snippet_outlined, size: 16),
                            SizedBox(width: 8),
                            Text('导出为纯文本剧本 (.txt)'),
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
                          Icon(Icons.file_download_outlined, size: 16, color: context.textPrimary),
                          const SizedBox(width: 6),
                          Text('导出剧本', style: TextStyle(fontSize: 13, color: context.textPrimary)),
                          const SizedBox(width: 4),
                          Icon(Icons.arrow_drop_down, size: 16, color: context.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _scenes.isEmpty ? null : _convertToStoryboard,
                    icon: const Icon(Icons.sync_alt, size: 16),
                    label: const Text('同步节拍至分镜（本地）'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    onPressed: _isGenerating ? null : _breakdownWithAi,
                    icon: _isGenerating
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome, size: 16),
                    label: const Text('AI 拆分分镜'),
                  ),
                  if (widget.onNavigateToStoryboard != null) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _saveChanges();
                        widget.onNavigateToStoryboard?.call();
                      },
                      icon: const Icon(Icons.dashboard_outlined, size: 16),
                      label: const Text('前往分镜看板'),
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

  Widget _buildRawTextEditor(BuildContext context) {
    final text = _textEditorController.text;
    final isProse = text.length > 500 &&
        !text.contains('### 第') &&
        !text.contains('[场次]') &&
        !text.contains('### 场次') &&
        !text.contains('【场次】');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (isProse && !_dismissedProseBanner) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_stories, size: 20, color: Colors.blue),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '检测到小说正文内容（非结构化分场），是否一键交由 AI 改编为分场文学剧本？',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () {
                      _confirmOverwriteIfNeeded(
                        () => _adaptFromNovelText(text),
                      );
                    },
                    child: const Text('一键 AI 改编为剧本'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '关闭提示',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () =>
                        setState(() => _dismissedProseBanner = true),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: TextField(
              controller: _textEditorController,
              maxLines: null,
              expands: true,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: context.textPrimary,
                height: 1.6,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: context.borderSubtle),
                ),
                hintText: '输入或编辑剧本文本...',
                fillColor: context.bgCard,
                filled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeSynopsisHeader(BuildContext context, StudioEpisode episode) {
    final series = widget.session.series;
    final memory = series?.memories.where((m) => m.episodeId == episode.id).firstOrNull;
    final hook = memory?.hook.trim() ?? '';
    final synopsis = episode.synopsis.trim().isNotEmpty
        ? episode.synopsis.trim()
        : (memory?.summary.trim() ?? '');
    final hasNovel = series?.novelId != null && series!.novelId!.isNotEmpty;
    final novelTitle = _boundNovelTitle ?? '原著小说';
    final hasOutline = synopsis.isNotEmpty || hook.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasOutline
              ? context.accentText.withValues(alpha: 0.35)
              : context.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏与折叠按钮
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              setState(() {
                _synopsisExpanded = !_synopsisExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.movie_filter_outlined,
                    size: 18,
                    color: hasOutline ? context.accentText : context.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '第 ${episode.index} 集大纲与剧情钩子',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                  ),
                  if (episode.title.isNotEmpty && episode.title != '第${episode.index}集') ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '《${episode.title}》',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  if (hasNovel) ...[
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.menu_book, size: 12, color: Colors.blue),
                          const SizedBox(width: 4),
                          Text(
                            '对应《$novelTitle》第 ${episode.index} 章',
                            style: const TextStyle(fontSize: 11, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!hasOutline)
                    Text(
                      '暂无大纲',
                      style: TextStyle(fontSize: 11, color: context.textTertiary),
                    ),
                  const SizedBox(width: 4),
                  Icon(
                    _synopsisExpanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 18,
                    color: context.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (_synopsisExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (synopsis.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.bgSelected,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '核心对抗',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.accentText,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            synopsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: context.textPrimary,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    Text(
                      '当前分集尚未从编剧研讨室同步大纲。您可以在下方选择从原著正文改编，或前往编剧研讨室一键策划全季大纲与断章钩子。',
                      style: TextStyle(fontSize: 12, color: context.textTertiary),
                    ),
                  ],
                  if (hook.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.flash_on, size: 14, color: Colors.amber),
                          const SizedBox(width: 6),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, color: Colors.amber, height: 1.4),
                                children: [
                                  const TextSpan(
                                    text: '断章悬念钩子 (Hook)：',
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  TextSpan(text: hook),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyScenesGuide(BuildContext context, StudioEpisode episode) {
    final series = widget.session.series;
    final hasNovel = series?.novelId != null && series!.novelId!.isNotEmpty;
    final novelTitle = _boundNovelTitle ?? '已关联小说';
    final synopsis = episode.synopsis.trim();
    final chDesc = episode.novelChapterRange.isNotEmpty
        ? '第 ${episode.novelChapterRange} 章'
        : (episode.novelChapterIndices.isNotEmpty
            ? '第 ${episode.novelChapterIndices.first}${episode.novelChapterIndices.length > 1 ? "~${episode.novelChapterIndices.last}" : ""} 章'
            : '第 ${episode.index} 章');

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: context.accentSubtle,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.movie_creation_outlined, size: 26, color: context.accentText),
              ),
              const SizedBox(height: 12),
              Text(
                '第 ${episode.index} 集：尚未生成剧本场次',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '从编剧研讨室定稿后，您可以选择以下两种工作流模式开始创作剧本：',
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 通道 A: 原著章节精读深度改编
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: hasNovel
                              ? Colors.blue.withValues(alpha: 0.45)
                              : context.borderSubtle,
                          width: hasNovel ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.auto_stories, size: 18, color: Colors.blue),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '通道 A：原著章节精读改编',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (hasNovel)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '推荐',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            hasNovel
                                ? '已自动关联原著《$novelTitle》$chDesc。点击后将自动载入并精读对应原著内容，AI 深度细读原文，原汁原味提炼真实角色对白与戏剧场次，锁定核心事实。'
                                : '从本地小说库或直接粘贴小说正文章节，AI 深度通读该章全文，提炼视听动作场次并锁定原著金句。',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _isGenerating
                                  ? null
                                  : () => _confirmOverwriteIfNeeded(_showNovelAdaptDialog),
                              icon: const Icon(Icons.menu_book, size: 16),
                              label: Text(
                                hasNovel
                                    ? '精读原著$chDesc改编'
                                    : '从小说正文改编剧本',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 通道 B: 基于大纲 AI 一键推演
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: synopsis.isNotEmpty
                              ? Colors.amber.withValues(alpha: 0.45)
                              : context.borderSubtle,
                          width: synopsis.isNotEmpty ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(Icons.auto_awesome, size: 18, color: Colors.amber),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '通道 B：大纲 AI 快速推演',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            synopsis.isNotEmpty
                                ? '无需逐字精读小说全文，AI 直接以编剧研讨室同步的本集冲突大纲（"${synopsis.length > 32 ? '${synopsis.substring(0, 32)}...' : synopsis}"）为蓝本，推演 3~5 场标准影视分场。'
                                : '以当前分集标题与设定为基础，AI 自动发挥创意推演具备戏剧冲突的文学剧本分场。',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isGenerating
                                  ? null
                                  : () => _confirmOverwriteIfNeeded(_generateScreenplayWithAi),
                              icon: const Icon(Icons.flash_on, size: 16),
                              label: const Text('基于大纲推演剧本'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 通道 C: 外部剧本文件导入
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Icon(
                                  Icons.file_upload_outlined,
                                  size: 18,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  '通道 C：导入外部剧本',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '已自备编剧创作的剧本文学？直接选择并导入本地 .md、.txt 或 .fountain 文件。系统自动识别分场标记拆解为结构化节拍，或作为全文草稿载入。',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondary,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _isGenerating
                                  ? null
                                  : () => _confirmOverwriteIfNeeded(_importScreenplayFromFile),
                              icon: const Icon(Icons.file_upload_outlined, size: 16),
                              label: const Text('选择外部剧本文件'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              TextButton.icon(
                onPressed: _addScene,
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('手动从空白创建第一场'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScenesList(BuildContext context) {
    if (_scenes.isEmpty) {
      final ep = widget.session.episode;
      if (ep != null) {
        return _buildEmptyScenesGuide(context, ep);
      }
      return const SizedBox.shrink();
    }

    final epId = widget.session.episode?.id ?? '';
    return ListView.builder(
      key: ValueKey('scenes_list_$epId'),
      padding: const EdgeInsets.all(16),
      itemCount: _scenes.length,
      itemBuilder: (context, index) {
        final scene = _scenes[index];
        return _buildSceneCard(context, scene, index, epId);
      },
    );
  }

  Widget _buildSceneCard(
    BuildContext context,
    DramaScene scene,
    int sceneIndex, [
    String? currentEpId,
  ]) {
    final epId = currentEpId ?? widget.session.episode?.id ?? '';
    return Card(
      key: ValueKey('scene_card_${epId}_${scene.id}'),
      margin: const EdgeInsets.only(bottom: 20),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: context.borderSubtle),
      ),
      color: context.bgCard,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 场次头部设置
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.bgSelected,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '第 ${scene.sceneNumber} 场',
                    style: TextStyle(
                      color: context.accentText,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    initialValue: scene.title,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      hintText: '场次标题（如：客栈对峙）',
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: context.textPrimary,
                    ),
                    onChanged: (val) {
                      setState(() {
                        _scenes[sceneIndex] = scene.copyWith(title: val);
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: scene.setting.isNotEmpty ? scene.setting : '内景',
                  items: const [
                    DropdownMenuItem(value: '内景', child: Text('内景')),
                    DropdownMenuItem(value: '外景', child: Text('外景')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _scenes[sceneIndex] = scene.copyWith(setting: val);
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: ['日景', '夜景', '黄昏', '黎明'].contains(scene.timeOfDay)
                      ? scene.timeOfDay
                      : '日景',
                  items: const [
                    DropdownMenuItem(value: '日景', child: Text('日景')),
                    DropdownMenuItem(value: '夜景', child: Text('夜景')),
                    DropdownMenuItem(value: '黄昏', child: Text('黄昏')),
                    DropdownMenuItem(value: '黎明', child: Text('黎明')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _scenes[sceneIndex] = scene.copyWith(timeOfDay: val);
                      });
                    }
                  },
                ),
                IconButton(
                  tooltip: '删除该场次',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => _removeScene(sceneIndex),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 地点与氛围
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: scene.location,
                    decoration: const InputDecoration(
                      labelText: '地点',
                      isDense: true,
                      hintText: '例如：巡城司后院值房',
                    ),
                    onChanged: (val) {
                      _scenes[sceneIndex] = scene.copyWith(location: val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue: _sceneCards.any((sc) => sc.id == scene.sceneCardId)
                        ? scene.sceneCardId
                        : '',
                    isDense: true,
                    decoration: const InputDecoration(
                      labelText: '关联场景库',
                      isDense: true,
                      prefixIcon: Icon(Icons.landscape_outlined, size: 16),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('智能自动匹配', style: TextStyle(fontSize: 12)),
                      ),
                      ..._sceneCards.map((sc) => DropdownMenuItem(
                            value: sc.id,
                            child: Text(
                              sc.name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          )),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _scenes[sceneIndex] = scene.copyWith(sceneCardId: val ?? '');
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: scene.atmosphere,
                    decoration: const InputDecoration(
                      labelText: '光影氛围',
                      isDense: true,
                      hintText: '例如：昏黄油灯、阴暗压抑、肃杀寒风',
                    ),
                    onChanged: (val) {
                      _scenes[sceneIndex] = scene.copyWith(atmosphere: val);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // 节拍列表
            Row(
              children: [
                Text(
                  '动作节拍与台词 (${scene.beats.length})',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimary,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _addBeat(scene),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('添加节拍', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...List.generate(scene.beats.length, (beatIndex) {
              final beat = scene.beats[beatIndex];
              final isOverloaded = _isActionOverloaded(beat.action);
              return Container(
                key: ValueKey('beat_${epId}_${scene.id}_${beat.id}_$beatIndex'),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.bgContent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOverloaded ? context.warningText.withAlpha(120) : context.borderSubtle,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${beat.order} 节拍',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: context.accentText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: beat.name,
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: '节拍名称（如：挑衅对峙）',
                              border: InputBorder.none,
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimary,
                            ),
                            onChanged: (val) {
                              final updated = List<DramaBeat>.from(scene.beats);
                              updated[beatIndex] = beat.copyWith(name: val);
                              _scenes[sceneIndex] = scene.copyWith(beats: updated);
                            },
                          ),
                        ),
                        if (isOverloaded)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.warningText.withAlpha(30),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded, size: 12, color: context.warningText),
                                const SizedBox(width: 4),
                                Text(
                                  '动作较复合，建议拆镜',
                                  style: TextStyle(fontSize: 10, color: context.warningText),
                                ),
                              ],
                            ),
                          ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          tooltip: '删除节拍',
                          onPressed: () => _removeBeat(scene, beatIndex),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      initialValue: beat.action,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '画面动作描述',
                        hintText: '角色执行的主干物理动作与姿态变化...',
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (val) {
                        final updated = List<DramaBeat>.from(scene.beats);
                        updated[beatIndex] = beat.copyWith(action: val);
                        setState(() {
                          _scenes[sceneIndex] = scene.copyWith(beats: updated);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: TextFormField(
                            initialValue: beat.dialogueSpeaker,
                            decoration: const InputDecoration(
                              labelText: '说话角色',
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                            onChanged: (val) {
                              final updated = List<DramaBeat>.from(scene.beats);
                              updated[beatIndex] = beat.copyWith(dialogueSpeaker: val);
                              _scenes[sceneIndex] = scene.copyWith(beats: updated);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: beat.dialogue,
                            decoration: const InputDecoration(
                              labelText: '角色台词 / 旁白',
                              hintText: '“余小白，我迟早得叫你姐夫。”',
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                            onChanged: (val) {
                              final updated = List<DramaBeat>.from(scene.beats);
                              updated[beatIndex] = beat.copyWith(dialogue: val);
                              _scenes[sceneIndex] = scene.copyWith(beats: updated);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            initialValue: beat.subtext,
                            decoration: const InputDecoration(
                              labelText: '潜台词 / 情绪',
                              hintText: '满脸戏谑，故意调侃激怒对方',
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 12),
                            onChanged: (val) {
                              final updated = List<DramaBeat>.from(scene.beats);
                              updated[beatIndex] = beat.copyWith(subtext: val);
                              _scenes[sceneIndex] = scene.copyWith(beats: updated);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildBeatPropsSection(scene, sceneIndex, beat, beatIndex),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _quickSaveProp(String propName) async {
    final series = widget.session.series;
    if (series == null) return;
    final trimmed = propName.trim();
    if (trimmed.isEmpty) return;
    try {
      await _manager.createProp(
        seriesId: series.id,
        name: trimmed,
        descriptionZh: '剧本节拍提炼道具',
        isKeyProp: false,
      );
      final propCards = await _manager.listProps(series.id);
      if (mounted) {
        setState(() {
          _props = propCards;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功收录道具「$trimmed」至项目道具库')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('收录道具失败: $e')),
        );
      }
    }
  }

  Future<void> _promptAddProp(
    DramaScene scene,
    int sceneIndex,
    DramaBeat beat,
    int beatIndex,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加节拍道具', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '道具名称',
            hintText: '如：淬毒短刃、掌天瓶、灵石袋',
          ),
          onSubmitted: (val) => Navigator.of(ctx).pop(val.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      final updatedProps = <String>{...beat.props, name.trim()}.toList();
      final updatedBeats = List<DramaBeat>.from(scene.beats);
      updatedBeats[beatIndex] = beat.copyWith(props: updatedProps);
      setState(() {
        _scenes[sceneIndex] = scene.copyWith(beats: updatedBeats);
      });
    }
  }

  Widget _buildBeatPropsSection(
    DramaScene scene,
    int sceneIndex,
    DramaBeat beat,
    int beatIndex,
  ) {
    final props = beat.props;
    final hasHolding = beat.holdingItem.trim().isNotEmpty;
    if (props.isEmpty && !hasHolding) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _promptAddProp(scene, sceneIndex, beat, beatIndex),
          icon: Icon(Icons.add, size: 13, color: context.textSecondary),
          label: Text(
            '关联道具',
            style: TextStyle(fontSize: 11, color: context.textSecondary),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.backpack_outlined, size: 13, color: context.textSecondary),
        for (final propName in props) ...[
          Builder(builder: (ctx) {
            final isKnown = _props.any((p) =>
                p.name == propName ||
                (propName.length >= 2 && p.name.contains(propName)) ||
                (p.name.length >= 2 && propName.contains(p.name)));
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isKnown
                    ? Colors.green.withAlpha(25)
                    : context.accentText.withAlpha(20),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isKnown
                      ? Colors.green.withAlpha(80)
                      : context.accentText.withAlpha(60),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isKnown ? Icons.check_circle_outline : Icons.inventory_2_outlined,
                    size: 11,
                    color: isKnown ? Colors.green : context.accentText,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    propName,
                    style: TextStyle(
                      fontSize: 11,
                      color: isKnown ? Colors.green.shade700 : context.textPrimary,
                    ),
                  ),
                  if (!isKnown) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _quickSaveProp(propName),
                      borderRadius: BorderRadius.circular(2),
                      child: Tooltip(
                        message: '未入库，点击一键收录为 IP 道具卡',
                        child: Padding(
                          padding: const EdgeInsets.all(1.0),
                          child: Icon(Icons.add, size: 12, color: context.accentText),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 3),
                  InkWell(
                    onTap: () {
                      final updatedProps = List<String>.from(beat.props)..remove(propName);
                      final updatedBeats = List<DramaBeat>.from(scene.beats);
                      updatedBeats[beatIndex] = beat.copyWith(props: updatedProps);
                      setState(() {
                        _scenes[sceneIndex] = scene.copyWith(beats: updatedBeats);
                      });
                    },
                    borderRadius: BorderRadius.circular(2),
                    child: Padding(
                      padding: const EdgeInsets.all(1.0),
                      child: Icon(Icons.close, size: 11, color: context.textSecondary),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
        if (hasHolding)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withAlpha(25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.withAlpha(80)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pan_tool_outlined, size: 11, color: Colors.amber),
                const SizedBox(width: 3),
                Text(
                  '手持: ${beat.holdingItem}（${beat.holdingHand == 'left' ? '左手' : beat.holdingHand == 'both' ? '双手' : '右手'}）',
                  style: const TextStyle(fontSize: 11, color: Colors.amber),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: () => _promptAddProp(scene, sceneIndex, beat, beatIndex),
          borderRadius: BorderRadius.circular(4),
          child: Tooltip(
            message: '添加道具',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.add_circle_outline, size: 14, color: context.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showScreenplayQualityDialog(
    BuildContext context,
    ScreenplayQualityReport report,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              report.isClean
                  ? Icons.verified_outlined
                  : Icons.visibility_outlined,
              color: report.overallScore >= 85 ? Colors.green : Colors.orange,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text('文学剧本可拍性评估 (${report.overallScore}/100)'),
          ],
        ),
        content: SizedBox(
          width: 640,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildScoreMiniCard(
                    ctx,
                    '动作视听外化率',
                    report.externalizationScore,
                    'Show, Don\'t Tell',
                  ),
                  const SizedBox(width: 8),
                  _buildScoreMiniCard(
                    ctx,
                    '三一律场次切分',
                    report.sceneUnityScore,
                    '时空人物聚焦',
                  ),
                  const SizedBox(width: 8),
                  _buildScoreMiniCard(
                    ctx,
                    '对白呼吸与气口',
                    report.speakabilityScore,
                    '单气口 ≤25 字',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (report.issues.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前剧本所有动作描述均为摄像机可直接拍摄的物理动作与表情，对白气口与场次三一律均达标。',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: report.issues.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, idx) {
                      final issue = report.issues[idx];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ctx.bgCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: ctx.borderSubtle),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    issue.sceneNumber > 0
                                        ? '第${issue.sceneNumber}场${issue.beatOrder != null ? "·节拍${issue.beatOrder! + 1}" : ""}'
                                        : '剧本正文',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    issue.message,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (issue.suggestion.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '建议外化：${issue.suggestion}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          if (!report.isClean)
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(ctx).pop();
                final episode = widget.session.episode;
                if (episode == null) return;
                final draft = episode.copyWith(
                  scenes: _scenes,
                  screenplayText: _isRawTextMode
                      ? _textEditorController.text
                      : _screenplayText,
                );
                final externalized =
                    await ScreenplayQualityEvaluator.externalizeEpisode(
                      draft,
                      useAi: false,
                    );
                setState(() {
                  _scenes = List<DramaScene>.from(externalized.scenes);
                  _screenplayText = _exportToMarkdown(_scenes);
                  _textEditorController.text = _screenplayText;
                });
                await _flushInMemoryEpisode();
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    const SnackBar(
                      content: Text('已完成剧本动作视听外化与长句气口切分'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('一键视听外化 (Show, Don\'t Tell)'),
            ),
        ],
      ),
    );
  }

  Widget _buildScoreMiniCard(
    BuildContext context,
    String title,
    int score,
    String subtitle,
  ) {
    final color = score >= 85
        ? Colors.green
        : (score >= 70 ? Colors.orange : Colors.red);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(fontSize: 11, color: context.textSecondary),
            ),
            const SizedBox(height: 2),
            Text(
              '$score 分',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: context.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
