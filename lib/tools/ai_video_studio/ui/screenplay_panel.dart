/// 剧本创作工作台：影视分场文学剧本编辑、节拍精修与动作超载拦截（spec: screenplay-workbench）。
///
/// 位于「创意孵化」与「分镜看板」之间，支持从大纲生成分场剧本、结构化微动作节拍编辑，
/// 并在拆分镜前提供动作与台词复杂度预警，打磨完成后一键转为 5D 分镜看板。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/ai_constraint_engine.dart';
import '../services/studio_project_manager.dart';
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
  List<StudioEpisode> _allEpisodes = const [];
  String _screenplayText = '';
  final _textEditorController = TextEditingController();
  bool _isRawTextMode = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    _loadCurrentEpisode();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    _textEditorController.dispose();
    super.dispose();
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
          _screenplayText = '';
          _textEditorController.text = '';
        });
      }
      return;
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
    final freshEp = ep != null ? (_manager.readEpisode(series.id, ep.id) ?? ep) : null;
    if (mounted) {
      setState(() {
        _allEpisodes = episodes;
        _characters = chars;
        _sceneCards = sceneCards;
        _scenes = freshEp != null ? List.from(freshEp.scenes) : [];
        _screenplayText = freshEp?.screenplayText ?? '';
        _textEditorController.text = _screenplayText;
      });
    }
  }

  Future<void> _saveChanges() async {
    final series = widget.session.series;
    final ep = widget.session.episode;
    if (series == null || ep == null) return;

    final updated = ep.copyWith(
      scenes: _scenes,
      screenplayText: _isRawTextMode ? _textEditorController.text : _screenplayText,
      updatedAt: DateTime.now(),
    );
    await _manager.saveEpisode(updated);
    widget.session.episode = updated;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('剧本已保存'),
          duration: Duration(seconds: 1),
        ),
      );
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
      final res = await AiConstraintEngine.screenplayGeneration(
        synopsis: inputPrompt,
        characterNames: charNames,
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
    final ep = widget.session.episode;
    if (series == null || ep == null) return;

    if (_scenes.isEmpty || _scenes.every((s) => s.beats.isEmpty)) {
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
    );

    final segments = StudioEpisode.buildSegmentsFromScenes(_scenes, newShots);

    final updated = ep.copyWith(
      scenes: _scenes,
      screenplayText: _isRawTextMode ? _textEditorController.text : _screenplayText,
      shots: newShots,
      segments: segments,
      updatedAt: DateTime.now(),
    );

    await _manager.saveEpisode(updated);
    widget.session.episode = updated;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已从剧本成功生成 ${newShots.length} 个5D分镜！'),
        ),
      );
      widget.onNavigateToStoryboard?.call();
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
            child: _isRawTextMode ? _buildRawTextEditor(context) : _buildScenesList(context),
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
          const Spacer(),
          IconButton(
            tooltip: _isRawTextMode ? '切换为结构化分场视图' : '切换为 Markdown 文本模式',
            icon: Icon(_isRawTextMode ? Icons.view_agenda_outlined : Icons.code_outlined),
            onPressed: () {
              setState(() {
                if (!_isRawTextMode) {
                  _textEditorController.text = _exportToMarkdown(_scenes);
                }
                _isRawTextMode = !_isRawTextMode;
              });
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _addScene,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('新增场次'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _isGenerating ? null : _generateScreenplayWithAi,
            icon: _isGenerating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome, size: 16),
            label: const Text('AI 生成剧本'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saveChanges,
            icon: const Icon(Icons.save_outlined, size: 16),
            label: const Text('保存剧本'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _scenes.isEmpty ? null : _convertToStoryboard,
            icon: const Icon(Icons.transform, size: 16),
            label: const Text('一键转换为5D分镜看板'),
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
    );
  }

  Widget _buildRawTextEditor(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
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
    );
  }

  Widget _buildScenesList(BuildContext context) {
    if (_scenes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 48, color: context.textTertiary),
            const SizedBox(height: 12),
            Text(
              '当前集尚未创建剧本场次',
              style: TextStyle(color: context.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _generateScreenplayWithAi,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('根据大纲一键 AI 生成剧本'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _addScene,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('手动创建第一场'),
                ),
              ],
            ),
          ],
        ),
      );
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
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
