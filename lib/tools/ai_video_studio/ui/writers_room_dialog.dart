import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/ai_constraint_engine.dart';
import '../services/studio_project_manager.dart';
import 'novel_selector_dialog.dart';

/// 编剧研讨室：长篇小说宏观主线提取、必留/可删/可改情节界定与人机协商式分集大纲共创弹窗。
class WritersRoomDialog extends StatefulWidget {
  const WritersRoomDialog({
    super.key,
    required this.series,
    required this.onSeriesUpdated,
  });

  final StudioSeries series;
  final ValueChanged<StudioSeries> onSeriesUpdated;

  static Future<void> show(
    BuildContext context, {
    required StudioSeries series,
    required ValueChanged<StudioSeries> onSeriesUpdated,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => WritersRoomDialog(
        series: series,
        onSeriesUpdated: onSeriesUpdated,
      ),
    );
  }

  @override
  State<WritersRoomDialog> createState() => _WritersRoomDialogState();
}

class _WritersRoomDialogState extends State<WritersRoomDialog> {
  final _manager = StudioProjectManager.instance;
  final _dialogueCtrl = TextEditingController();
  final _scrollController = ScrollController();

  // 状态机
  bool _isAnalyzing = false;
  bool _isPlanningBeats = false;
  bool _isChatting = false;
  String? _statusMessage;
  String? _beatsPlanError;

  // 输入小说文本状态
  String? _novelId;
  String _novelText = '';
  String _novelTitle = '';
  int _targetEpisodeCount = 12;
  int _targetDurationSec = 90; // 默认 90 秒标准短剧

  // 宏观分析与全书多季宇宙产物
  int? _recommendedEpisodeCount;
  String _episodeCountReason = '';
  int _seasonNumber = 1;
  String _seasonName = '第1季';
  String _adaptedChaptersRange = '';
  String _seasonClimax = '';
  String _masterPlot = '';
  List<Map<String, dynamic>> _seasonsRoadmap = [];
  int _selectedSeasonIndex = 0;
  final Map<int, List<Map<String, dynamic>>> _seasonEpisodesCache = {};
  final Map<int, List<Map<String, dynamic>>> _seasonMacroArcsCache = {};
  List<Map<String, dynamic>> _mustKeep = [];
  List<Map<String, dynamic>> _canCut = [];
  List<Map<String, dynamic>> _canModify = [];
  List<Map<String, dynamic>> _characters = [];
  List<Map<String, dynamic>> _characterRelations = [];
  bool _isSyncingCharacters = false;
  List<Map<String, dynamic>> _keyProps = [];
  bool _isSyncingProps = false;

  // 全季分集规划产物
  String _seasonTitle = '';
  List<Map<String, dynamic>> _macroArcs = [];
  List<Map<String, dynamic>> _episodes = [];

  // 研讨对话记录
  final List<Map<String, String>> _chatHistory = [];

  @override
  void initState() {
    super.initState();
    _novelTitle = widget.series.name;
    _seasonTitle = widget.series.name;
    _novelId = widget.series.novelId;
    _restoreSavedProfile();
  }

  void _restoreSavedProfile() {
    final data = _manager.readWritersRoomData(widget.series.id);
    if (data == null) return;

    final nId = data['novel_id'] as String? ?? widget.series.novelId;
    final nTitle = data['novel_title'] as String? ?? '';
    final nText = data['novel_text'] as String? ?? '';
    final mPlot = data['master_plot'] as String? ?? '';
    final sRoadmap = (data['seasons_roadmap'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final sIndex = (data['selected_season_index'] as num?)?.toInt() ?? 0;
    final sNum = (data['season_number'] as num?)?.toInt() ?? 1;
    final sName = (data['season_name'] as String? ?? '第1季').trim();
    final sTitle = (data['season_title'] as String? ?? '').trim();
    final cRange = (data['adapted_chapters_range'] as String? ?? '').trim();
    final sClimax = (data['season_climax'] as String? ?? '').trim();
    final tCount = (data['target_episode_count'] as num?)?.toInt() ?? 12;
    final tDur = (data['target_duration_sec'] as num?)?.toInt() ?? 90;
    final rCount = (data['recommended_episode_count'] as num?)?.toInt();
    final rReason = (data['episode_count_reason'] as String? ?? '').trim();

    final mKeep = (data['must_keep'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cCut = (data['can_cut'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final cMod = (data['can_modify'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final chars = (data['characters'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final rels = (data['character_relations'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final kProps = (data['key_props'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final mArcs = (data['macro_arcs'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final eps = (data['episodes'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final epCacheRaw = data['season_episodes_cache'] as Map?;
    if (epCacheRaw != null) {
      for (final entry in epCacheRaw.entries) {
        final k = int.tryParse(entry.key.toString());
        if (k != null && entry.value is List) {
          _seasonEpisodesCache[k] = (entry.value as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    }
    final arcCacheRaw = data['season_macro_arcs_cache'] as Map?;
    if (arcCacheRaw != null) {
      for (final entry in arcCacheRaw.entries) {
        final k = int.tryParse(entry.key.toString());
        if (k != null && entry.value is List) {
          _seasonMacroArcsCache[k] = (entry.value as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }
    }

    final chatRaw = data['chat_history'] as List?;
    if (chatRaw != null) {
      for (final c in chatRaw) {
        if (c is Map) {
          _chatHistory.add({
            'role': c['role'] as String? ?? 'user',
            'content': c['content'] as String? ?? '',
          });
        }
      }
    }

    setState(() {
      _novelId = nId;
      if (nTitle.isNotEmpty) _novelTitle = nTitle;
      _novelText = nText;
      _masterPlot = mPlot;
      _seasonsRoadmap = sRoadmap;
      _selectedSeasonIndex = sIndex;
      _seasonNumber = sNum;
      _seasonName = sName;
      if (sTitle.isNotEmpty) _seasonTitle = sTitle;
      _adaptedChaptersRange = cRange;
      _seasonClimax = sClimax;
      _targetEpisodeCount = tCount;
      _targetDurationSec = tDur;
      _recommendedEpisodeCount = rCount;
      _episodeCountReason = rReason;
      _mustKeep = mKeep;
      _canCut = cCut;
      _canModify = cMod;
      _characters = chars;
      _characterRelations = rels;
      _keyProps = kProps;
      _macroArcs = mArcs;
      _episodes = eps;
    });
  }

  Map<String, dynamic> _buildProfileData() {
    return <String, dynamic>{
      'novel_id': _novelId ?? widget.series.novelId,
      'novel_title': _novelTitle,
      'novel_text': _novelText,
      'target_episode_count': _targetEpisodeCount,
      'target_duration_sec': _targetDurationSec,
      'recommended_episode_count': _recommendedEpisodeCount,
      'episode_count_reason': _episodeCountReason,
      'season_number': _seasonNumber,
      'season_name': _seasonName,
      'season_title': _seasonTitle,
      'adapted_chapters_range': _adaptedChaptersRange,
      'season_climax': _seasonClimax,
      'master_plot': _masterPlot,
      'seasons_roadmap': _seasonsRoadmap,
      'selected_season_index': _selectedSeasonIndex,
      'season_episodes_cache': _seasonEpisodesCache.map((k, v) => MapEntry(k.toString(), v)),
      'season_macro_arcs_cache': _seasonMacroArcsCache.map((k, v) => MapEntry(k.toString(), v)),
      'must_keep': _mustKeep,
      'can_cut': _canCut,
      'can_modify': _canModify,
      'characters': _characters,
      'character_relations': _characterRelations,
      'key_props': _keyProps,
      'macro_arcs': _macroArcs,
      'episodes': _episodes,
      'chat_history': _chatHistory,
    };
  }

  Future<void> _saveWritersRoomProfile([String? targetSeriesId]) async {
    final seriesId = targetSeriesId ?? widget.series.id;
    await _manager.saveWritersRoomData(seriesId, _buildProfileData());
  }

  @override
  void dispose() {
    _dialogueCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFromNovelLibrary() async {
    final result = await showDialog<NovelSelectionResult>(
      context: context,
      builder: (_) => const NovelSelectorDialog(
        initialIsFullSeason: true,
      ),
    );
    if (result == null) return;

    setState(() {
      _novelId = result.novel.id;
      _novelTitle = result.novel.title;
      _seasonTitle = '${result.novel.title} 短剧版';
      _isAnalyzing = true;
      _statusMessage = '正在从本地小说库载入《${result.novel.title}》章节正文...';
    });

    final text = await result.loadCombinedText();
    if (!mounted) return;

    if (text.trim().isEmpty) {
      setState(() {
        _isAnalyzing = false;
        _statusMessage = null;
        _novelTitle = '';
        _novelText = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('《${result.novel.title}》暂无章节正文，请先在小说管理器中下载或导入正文'),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    setState(() {
      _novelText = text;
    });

    await _runMacroAnalysis();
  }

  Future<void> _runMacroAnalysis() async {
    if (_novelText.trim().isEmpty) return;

    setState(() {
      _isAnalyzing = true;
      _statusMessage = '编剧总监正在通读全景文本，解构主线脉络与必留/可删情节...';
    });

    try {
      final res = await AiConstraintEngine.extractWritersRoomMaster(
        novelText: _novelText,
        seriesName: _novelTitle,
      );

      final data = res.data;
      final recCount = (data['recommended_episode_count'] as num?)?.toInt();
      final recReason = (data['episode_count_reason'] as String?) ?? '';
      final sNum = (data['season_number'] as num?)?.toInt() ?? 1;
      final sTitle = (data['season_title'] as String? ?? '第1季').trim();
      final cRange = (data['adapted_chapters_range'] as String? ?? '').trim();
      final sClimax = (data['season_climax'] as String? ?? '').trim();
      final chars = (data['characters'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rels = (data['character_relations'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final kProps = (data['key_props'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final rawRoadmap = (data['seasons_roadmap'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _masterPlot = data['master_plot'] as String? ?? '';
        _mustKeep = (data['must_keep'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _canCut = (data['can_cut'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _canModify = (data['can_modify'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _characters = chars;
        _characterRelations = rels;
        _keyProps = kProps;
        _recommendedEpisodeCount = recCount;
        _episodeCountReason = recReason;
        _seasonNumber = sNum;
        _seasonName = sTitle;
        _adaptedChaptersRange = cRange;
        _seasonClimax = sClimax;
        _seasonsRoadmap = rawRoadmap;
        _selectedSeasonIndex = 0;
        _seasonEpisodesCache.clear();
        _seasonMacroArcsCache.clear();
        if (recCount != null && recCount > 0) {
          _targetEpisodeCount = recCount;
        }
        _isAnalyzing = false;
        _statusMessage = null;
      });

      // 自动触发第一轮全季大纲规划
      await _planSeasonBeats();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('主线与改编分析失败: $e')),
        );
      }
    }
  }

  Future<void> _switchSeason(int index) async {
    if (index < 0 || index >= _seasonsRoadmap.length) return;
    if (_isAnalyzing || _isPlanningBeats) return;

    // 缓存当前季已规划的大纲与大幕
    if (_episodes.isNotEmpty) {
      _seasonEpisodesCache[_selectedSeasonIndex] = List.from(_episodes);
      _seasonMacroArcsCache[_selectedSeasonIndex] = List.from(_macroArcs);
    }

    final targetSeason = _seasonsRoadmap[index];
    final sNum = (targetSeason['season_number'] as num?)?.toInt() ?? (index + 1);
    final sTitle = (targetSeason['season_title'] as String? ?? '第$sNum季').trim();
    final cRange = (targetSeason['adapted_chapters_range'] as String? ?? '').trim();
    final sClimax = (targetSeason['season_climax'] as String? ?? '').trim();
    final epCount = (targetSeason['recommended_episode_count'] as num?)?.toInt() ?? 80;

    final cachedEpisodes = _seasonEpisodesCache[index];
    final cachedArcs = _seasonMacroArcsCache[index];

    setState(() {
      _selectedSeasonIndex = index;
      _seasonNumber = sNum;
      _seasonName = sTitle;
      _seasonTitle = '${_novelTitle.isNotEmpty ? _novelTitle : widget.series.name} $sTitle';
      _adaptedChaptersRange = cRange;
      _seasonClimax = sClimax;
      _targetEpisodeCount = epCount;
      _recommendedEpisodeCount = epCount;

      if (cachedEpisodes != null && cachedEpisodes.isNotEmpty) {
        _episodes = List.from(cachedEpisodes);
        _macroArcs = List.from(cachedArcs ?? []);
      } else {
        _episodes = [];
        _macroArcs = [];
      }
      _beatsPlanError = null;
    });

    // 若未命中缓存，自动为新选中的季规划分集大纲
    if (cachedEpisodes == null || cachedEpisodes.isEmpty) {
      await _planSeasonBeats();
    }
  }

  Future<void> _planSeasonBeats() async {
    if (_masterPlot.trim().isEmpty) return;

    setState(() {
      _isPlanningBeats = true;
      _beatsPlanError = null;
      _statusMessage = '正在按照短剧节奏规划第 $_seasonNumber 季（共 $_targetEpisodeCount 集 · 单集 $_targetDurationSec 秒）高能分集大纲...';
    });

    final currentSeasonTheme = (_selectedSeasonIndex < _seasonsRoadmap.length)
        ? (_seasonsRoadmap[_selectedSeasonIndex]['season_theme'] as String? ?? '')
        : '';
    final fullSeriesName = '${_novelTitle.isNotEmpty ? _novelTitle : widget.series.name} $_seasonName';

    try {
      final res = await AiConstraintEngine.planWritersRoomSeasonBeats(
        masterPlot: _masterPlot,
        seriesName: fullSeriesName,
        episodeCount: _targetEpisodeCount,
        targetDurationSec: _targetDurationSec,
        seasonNumber: _seasonNumber,
        seasonTitle: _seasonName,
        adaptedChaptersRange: _adaptedChaptersRange,
        seasonTheme: currentSeasonTheme,
        seasonClimax: _seasonClimax,
        mustKeep: _mustKeep,
        canCut: _canCut,
        canModify: _canModify,
        onProgress: (msg, _) {
          if (mounted) {
            setState(() {
              _statusMessage = msg;
            });
          }
        },
      );

      final data = res.data;
      final parsedTitle = (data['season_title'] as String? ?? fullSeriesName).trim();
      final parsedArcs = (data['macro_arcs'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final parsedEpisodes = (data['episodes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      setState(() {
        _seasonTitle = parsedTitle;
        _macroArcs = parsedArcs;
        _episodes = parsedEpisodes;
        if (parsedEpisodes.isNotEmpty) {
          _targetEpisodeCount = parsedEpisodes.length;
          if (_selectedSeasonIndex < _seasonsRoadmap.length) {
            _seasonsRoadmap[_selectedSeasonIndex]['episodes_count'] = parsedEpisodes.length;
          }
        }
        _seasonEpisodesCache[_selectedSeasonIndex] = List.from(parsedEpisodes);
        _seasonMacroArcsCache[_selectedSeasonIndex] = List.from(parsedArcs);
        _isPlanningBeats = false;
        _beatsPlanError = null;
        _statusMessage = null;
      });
      await _saveWritersRoomProfile();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPlanningBeats = false;
          _beatsPlanError = e.toString();
          _statusMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('第 $_seasonNumber 季分集规划失败: $e')),
        );
      }
    }
  }

  Future<void> _showCustomEpisodeDialog() async {
    final ctrl = TextEditingController(text: '$_targetEpisodeCount');
    final val = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('自定义目标集数', style: TextStyle(color: context.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('长篇小说或百集短剧可输入任意目标集数（建议 10 ~ 150 集）：',
                style: TextStyle(color: context.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: '集数',
                suffixText: '集',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final parsed = int.tryParse(ctrl.text.trim());
              if (parsed != null && parsed > 0 && parsed <= 500) {
                Navigator.of(ctx).pop(parsed);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入 1 到 500 之间的有效集数')),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (val != null && val != _targetEpisodeCount) {
      setState(() => _targetEpisodeCount = val);
      await _planSeasonBeats();
    }
  }

  Future<int> _syncCharactersToIpLibrary({bool showToast = true}) async {
    if (_characters.isEmpty) return 0;
    setState(() => _isSyncingCharacters = true);
    int count = 0;
    try {
      final seriesId = widget.series.id;
      final existingChars = await _manager.listCharacters(seriesId);
      final existingByName = <String, CharacterCard>{
        for (final c in existingChars) c.name.trim().toLowerCase(): c,
      };

      for (final raw in _characters) {
        final name = (raw['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final role = (raw['role'] as String? ?? '').trim();
        final personality = (raw['personality'] as String? ?? '').trim();
        final appearance = (raw['appearance_features'] as String? ?? '').trim();
        final motivation = (raw['motivation'] as String? ?? '').trim();

        final descZh = StringBuffer();
        if (role.isNotEmpty) descZh.writeln('【定位】$role');
        if (personality.isNotEmpty) descZh.writeln('【性格】$personality');
        if (appearance.isNotEmpty) descZh.writeln('【外貌体态】$appearance');
        if (motivation.isNotEmpty) descZh.writeln('【核心动机】$motivation');

        final key = name.toLowerCase();
        final existing = existingByName[key];
        if (existing != null) {
          // 增量合并，保留已有参考图和人脸锚点
          final updated = existing.copyWith(
            descriptionZh: existing.descriptionZh.isEmpty ? descZh.toString().trim() : existing.descriptionZh,
            facialFeaturesZh: existing.facialFeaturesZh.isEmpty ? appearance : existing.facialFeaturesZh,
            basePromptPositive: existing.basePromptPositive.isEmpty ? appearance : existing.basePromptPositive,
            updatedAt: DateTime.now(),
          );
          await _manager.saveCharacter(seriesId, updated);
        } else {
          // 全新创建
          final now = DateTime.now();
          final newCard = CharacterCard(
            id: 'char_${now.millisecondsSinceEpoch}_${count + 1}',
            name: name,
            descriptionZh: descZh.toString().trim(),
            facialFeaturesZh: appearance,
            basePromptPositive: appearance,
            variations: [
              CharacterVariation(
                id: 'var_${now.millisecondsSinceEpoch}_${count + 1}',
                name: '默认',
                active: true,
              ),
            ],
            updatedAt: now,
          );
          await _manager.saveCharacter(seriesId, newCard);
        }
        count++;
      }

      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功将 $count 位角色画像沉淀同步至 IP 资产库！')),
        );
      }
    } catch (e) {
      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步角色至 IP 库失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingCharacters = false);
      }
    }
    return count;
  }

  Future<int> _syncPropsToIpLibrary({bool showToast = true}) async {
    if (_keyProps.isEmpty) return 0;
    setState(() => _isSyncingProps = true);
    int count = 0;
    try {
      final seriesId = widget.series.id;
      final existingProps = await _manager.listProps(seriesId);
      final existingByName = <String, PropCard>{
        for (final p in existingProps) p.name.trim().toLowerCase(): p,
      };

      for (final raw in _keyProps) {
        final name = (raw['name'] as String? ?? '').trim();
        if (name.isEmpty) continue;
        final category = (raw['category'] as String? ?? '').trim();
        final significance = (raw['significance'] as String? ?? '').trim();
        final appearance = (raw['appearance'] as String? ?? '').trim();

        final descZh = StringBuffer();
        if (category.isNotEmpty) descZh.writeln('【类型】$category');
        if (significance.isNotEmpty) descZh.writeln('【戏剧作用】$significance');
        if (appearance.isNotEmpty) descZh.writeln('【外观特征】$appearance');

        final key = name.toLowerCase();
        final existing = existingByName[key];
        final now = DateTime.now();
        if (existing != null) {
          final updated = existing.copyWith(
            descriptionZh: existing.descriptionZh.isEmpty ? descZh.toString().trim() : existing.descriptionZh,
            promptEn: existing.promptEn.isEmpty ? appearance : existing.promptEn,
            isKeyProp: true,
            updatedAt: now,
          );
          await _manager.saveProp(seriesId, updated);
          existingByName[key] = updated;
        } else {
          final newCard = PropCard(
            id: 'prop_${now.millisecondsSinceEpoch}_${count + 1}',
            name: name,
            descriptionZh: descZh.toString().trim(),
            promptEn: appearance,
            isKeyProp: true,
            updatedAt: now,
          );
          await _manager.saveProp(seriesId, newCard);
          existingByName[key] = newCard;
        }
        count++;
      }

      final latest = _manager.readSeries(seriesId);
      if (latest != null) {
        widget.onSeriesUpdated(latest);
      }

      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功将 $count 件关键道具沉淀同步至 IP 资产库！')),
        );
      }
    } catch (e) {
      if (mounted && showToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步关键道具至 IP 库失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingProps = false);
      }
    }
    return count;
  }

  Future<void> _sendDialogueInstruction() async {
    final text = _dialogueCtrl.text.trim();
    if (text.isEmpty || _isChatting) return;

    _dialogueCtrl.clear();
    setState(() {
      _chatHistory.add({'role': 'user', 'content': text});
      _isChatting = true;
    });

    try {
      final currentBeatsContext = jsonEncode(_episodes);
      final res = await AiConstraintEngine.dialogueWritersRoom(
        instruction: text,
        currentBeatsContext: currentBeatsContext,
        seriesName: _seasonTitle,
      );

      final reply = res.data['reply'] as String? ?? '大纲已根据您的意图更新。';
      final updatedRaw = res.data['updated_episodes'] as List?;
      if (updatedRaw != null && updatedRaw.isNotEmpty) {
        _episodes = updatedRaw
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _seasonEpisodesCache[_selectedSeasonIndex] = List.from(_episodes);
      }

      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': reply});
        _isChatting = false;
      });
    } catch (e) {
      setState(() {
        _chatHistory.add({'role': 'assistant', 'content': '调整失败: $e'});
        _isChatting = false;
      });
    }
  }

  Future<void> _applyBeatsToProject() async {
    if (_episodes.isEmpty) return;

    final seriesId = widget.series.id;
    final baseSeriesName = _novelTitle.isNotEmpty
        ? _novelTitle
        : widget.series.name.split(' · ')[0].trim();
    final effectiveNovelId = _novelId ?? widget.series.novelId;

    // 1. 同步第 1 季（或当前研讨室规划季）到当前工程
    final s1Num = (_seasonsRoadmap.isNotEmpty
            ? (_seasonsRoadmap[0]['season'] as num?)?.toInt()
            : null) ?? 1;
    final s1Name = (_seasonsRoadmap.isNotEmpty
            ? (_seasonsRoadmap[0]['title'] as String?)?.trim()
            : null) ?? _seasonName;
    final s1Title = '第 $s1Num 季${s1Name.isNotEmpty ? ' · $s1Name' : ''}';
    final seasonTitleForProject = '$baseSeriesName · $s1Title';

    // 写入第 1 季分集大纲与断章钩子
    final s1Episodes = _seasonEpisodesCache[0] ?? _episodes;
    await _writeEpisodesToSeries(seriesId, s1Episodes);

    final currentSeries = _manager.readSeries(seriesId) ?? widget.series;
    final updatedSeries = currentSeries.copyWith(
      name: seasonTitleForProject,
      worldview: _masterPlot.isNotEmpty ? _masterPlot : currentSeries.worldview,
      novelId: effectiveNovelId,
      updatedAt: DateTime.now(),
    );
    await _manager.saveSeries(updatedSeries);
    await _saveWritersRoomProfile();
    widget.onSeriesUpdated(updatedSeries);

    // 2. 自动物化衍生后续各季（第 2 季、第 3 季...）
    int materializedSeasonCount = 0;
    if (_seasonsRoadmap.length > 1) {
      final sharedIpId = widget.series.resolvedIpId;
      final allSeries = await _manager.listSeries();

      for (int sIdx = 1; sIdx < _seasonsRoadmap.length; sIdx++) {
        final sItem = _seasonsRoadmap[sIdx];
        final sNum = (sItem['season'] as num?)?.toInt() ?? (sIdx + 1);
        final sTitle = (sItem['title'] as String? ?? '').trim();
        final sLogline = (sItem['logline'] as String? ?? '').trim();
        final seasonTag = '第 $sNum 季';
        final targetSeriesName = '$baseSeriesName · $seasonTag${sTitle.isNotEmpty ? ' · $sTitle' : ''}';

        // 幂等查重：查找同一 IP 下已存在的该季工程
        var targetSeries = allSeries.where((s) =>
            s.resolvedIpId == sharedIpId &&
            (s.name == targetSeriesName || s.name.contains(seasonTag))).firstOrNull;

        targetSeries ??= await _manager.createSeries(
          name: targetSeriesName,
          productionType: widget.series.productionType,
          ipId: sharedIpId,
        );

        final seasonWorldview = sLogline.isNotEmpty
            ? '【全书脉络】$_masterPlot\n\n【$seasonTag 核心主线】$sLogline'
            : _masterPlot;

        targetSeries = targetSeries.copyWith(
          name: targetSeriesName,
          worldview: seasonWorldview.isNotEmpty ? seasonWorldview : widget.series.worldview,
          novelId: effectiveNovelId,
          updatedAt: DateTime.now(),
        );
        await _manager.saveSeries(targetSeries);

        // 克隆策划蓝图入库
        await _saveWritersRoomProfile(targetSeries.id);

        // 写入该季分集
        final cachedEps = _seasonEpisodesCache[sIdx];
        if (cachedEps != null && cachedEps.isNotEmpty) {
          await _writeEpisodesToSeries(targetSeries.id, cachedEps);
        } else {
          final expectedCount = (sItem['episodes_count'] as num?)?.toInt() ?? 0;
          if (expectedCount > 0) {
            final existingEps = await _manager.listEpisodes(targetSeries.id);
            if (existingEps.isEmpty) {
              for (int i = 1; i <= expectedCount; i++) {
                final createdResult = await _manager.createEpisode(
                  seriesId: targetSeries.id,
                  title: '第 $i 集',
                  synopsis: sLogline.isNotEmpty ? '推进 $seasonTag 主线：$sLogline' : '',
                );
                await _manager.upsertEpisodeMemory(
                  seriesId: targetSeries.id,
                  episodeId: createdResult.episode.id,
                  title: '第 $i 集',
                  summary: createdResult.episode.synopsis,
                  hook: '',
                );
              }
            }
          }
        }
        materializedSeasonCount++;
      }
    }

    // 3. 角色画像与关键道具自动同步至 IP 资产库
    int syncedCharCount = 0;
    if (_characters.isNotEmpty) {
      syncedCharCount = await _syncCharactersToIpLibrary(showToast: false);
    }
    int syncedPropCount = 0;
    if (_keyProps.isNotEmpty) {
      syncedPropCount = await _syncPropsToIpLibrary(showToast: false);
    }

    if (mounted) {
      Navigator.of(context).pop();
      final totalSeasons = 1 + materializedSeasonCount;
      final assetParts = <String>[
        if (syncedCharCount > 0) '$syncedCharCount 位核心角色',
        if (syncedPropCount > 0) '$syncedPropCount 件关键道具',
      ];
      final assetSuffix = assetParts.isNotEmpty ? '，并同步 ${assetParts.join('与')}' : '';
      final msg = totalSeasons > 1
          ? '已成功将全剧 $totalSeasons 个季度物化同步至剧集库（当前《$s1Title》含 ${s1Episodes.length} 集大纲，共衍生 $materializedSeasonCount 个季度工程$assetSuffix）！'
          : '已成功将《$s1Title》（共 ${s1Episodes.length} 集大纲与断章钩子$assetSuffix）同步至当前剧集！';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Future<void> _writeEpisodesToSeries(String targetSeriesId, List<Map<String, dynamic>> episodesList) async {
    final existingEpisodes = await _manager.listEpisodes(targetSeriesId);
    for (int i = 0; i < episodesList.length; i++) {
      final epData = episodesList[i];
      final epNum = (epData['episode_number'] as num?)?.toInt() ?? (i + 1);
      final epTitle = epData['title'] as String? ?? '第 $epNum 集';
      final epConflict = epData['conflict'] as String? ?? '';
      final epHook = epData['hook'] as String? ?? '';
      final chapterRange = (epData['chapter_range'] as String? ?? '').trim();
      final chapterIndices = (epData['chapter_indices'] as List?)
              ?.whereType<num>()
              .map((n) => n.toInt())
              .toList() ??
          (chapterRange.isNotEmpty
              ? AiConstraintEngine.parseChapterRange(chapterRange, fallbackEpisodeIndex: epNum).indices
              : <int>[epNum]);

      final existing = existingEpisodes.cast<StudioEpisode?>().firstWhere(
            (e) => e?.index == epNum,
            orElse: () => null,
          );

      final String epId;
      if (existing != null) {
        epId = existing.id;
        final updated = existing.copyWith(
          title: epTitle,
          synopsis: epConflict,
          novelChapterRange: chapterRange,
          novelChapterIndices: chapterIndices,
          updatedAt: DateTime.now(),
        );
        await _manager.saveEpisode(updated);
      } else {
        final now = DateTime.now();
        epId = 'ep_${now.millisecondsSinceEpoch}_$epNum';
        final newEp = StudioEpisode(
          id: epId,
          seriesId: targetSeriesId,
          index: epNum,
          title: epTitle,
          synopsis: epConflict,
          shots: const [],
          novelChapterRange: chapterRange,
          novelChapterIndices: chapterIndices,
          createdAt: now,
          updatedAt: now,
        );
        await _manager.saveEpisode(newEp);
      }

      await _manager.upsertEpisodeMemory(
        seriesId: targetSeriesId,
        episodeId: epId,
        title: epTitle,
        summary: epConflict,
        hook: epHook,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1180,
          maxHeight: MediaQuery.of(context).size.height * 0.94,
        ),
        child: SizedBox(
          width: 1180,
          height: 750,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // 顶部 Header
                Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.psychology_outlined, size: 24, color: Colors.amber),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '编剧研讨室 · 全剧主线策划与人机共创',
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_novelText.isEmpty)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: context.accentSolid,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.library_books, size: 16),
                        label: const Text('选择小说'),
                        onPressed: _pickFromNovelLibrary,
                      )
                    else ...[
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('更换小说'),
                        onPressed: _pickFromNovelLibrary,
                      ),
                      if (_characters.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.teal,
                            side: const BorderSide(color: Colors.teal),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: _isSyncingCharacters
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.teal),
                                )
                              : const Icon(Icons.person_add_alt_1, size: 16),
                          label: Text('同步角色 (${_characters.length})'),
                          onPressed: _isSyncingCharacters ? null : () => _syncCharactersToIpLibrary(),
                        ),
                      ],
                      if (_keyProps.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.amber.shade800,
                            side: BorderSide(color: Colors.amber.shade800),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                          icon: _isSyncingProps
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber.shade800),
                                )
                              : const Icon(Icons.token, size: 16),
                          label: Text('同步道具 (${_keyProps.length})'),
                          onPressed: _isSyncingProps ? null : () => _syncPropsToIpLibrary(),
                        ),
                      ],
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: Text(_seasonsRoadmap.length > 1
                            ? '定稿并同步至剧集库 (${_seasonsRoadmap.length}季)'
                            : '定稿并同步至剧集大纲'),
                        onPressed: _episodes.isNotEmpty ? _applyBeatsToProject : null,
                      ),
                    ],
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: '关闭研讨室',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // 主工作区
            Expanded(
              child: (_isAnalyzing && _novelText.isEmpty)
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage ?? '正在载入小说章节正文...',
                            style: TextStyle(color: context.textPrimary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : _novelText.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_stories_outlined, size: 64, color: context.textTertiary),
                              const SizedBox(height: 16),
                              Text(
                                '请先选择整部小说或长篇段落，开启工业级影视化改编策划',
                                style: TextStyle(color: context.textSecondary, fontSize: 15),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'AI 将通读原著智能测算推荐集数、提炼主线脉络、解构核心角色画像与网状关系，并按爆款短剧节奏规划高能大纲',
                                style: TextStyle(color: context.textTertiary, fontSize: 12),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: context.accentSolid,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                ),
                                icon: const Icon(Icons.library_books),
                                label: const Text('立即从小说库选择', style: TextStyle(fontSize: 14)),
                                onPressed: _pickFromNovelLibrary,
                              ),
                            ],
                          ),
                        )
                      : Row(
                      children: [
                        // 左侧：改编边界清单与全季分集
                        Expanded(
                          flex: 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.bgContent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.borderSubtle),
                            ),
                            child: Column(
                              children: [
                                // 篇章控制栏
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  color: context.bgCard,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_seasonsRoadmap.length > 1) ...[
                                        _buildSeasonSwitcher(),
                                        const SizedBox(height: 6),
                                      ],
                                      // 第 1 行：当前季与原著定位行
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: context.accentSubtle,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: context.accentSolid.withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              '第 $_seasonNumber 季 · $_seasonName',
                                              style: TextStyle(
                                                color: context.accentText,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                          if (_adaptedChaptersRange.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.withValues(alpha: 0.1),
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const Icon(Icons.menu_book, size: 12, color: Colors.blue),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '原著: $_adaptedChaptersRange',
                                                    style: const TextStyle(
                                                      color: Colors.blue,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                          const Spacer(),
                                          if (_recommendedEpisodeCount != null)
                                            ActionChip(
                                              avatar: const Icon(Icons.auto_awesome, size: 13, color: Colors.amber),
                                              backgroundColor: _targetEpisodeCount == _recommendedEpisodeCount
                                                  ? Colors.amber.withValues(alpha: 0.2)
                                                  : context.bgCard,
                                              side: BorderSide(
                                                color: _targetEpisodeCount == _recommendedEpisodeCount
                                                    ? Colors.amber
                                                    : context.borderSubtle,
                                              ),
                                              label: Text(
                                                'AI 推荐: $_recommendedEpisodeCount 集',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: _targetEpisodeCount == _recommendedEpisodeCount
                                                      ? Colors.amber
                                                      : context.textSecondary,
                                                ),
                                              ),
                                              tooltip: _episodeCountReason.isNotEmpty
                                                  ? _episodeCountReason
                                                  : '点击直接采纳 AI 智能测算的推荐集数',
                                              onPressed: () {
                                                if (_targetEpisodeCount != _recommendedEpisodeCount) {
                                                  setState(() => _targetEpisodeCount = _recommendedEpisodeCount!);
                                                  _planSeasonBeats();
                                                }
                                              },
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // 第 2 行：制片规格参数与规划操作行
                                      Row(
                                        children: [
                                          Text(
                                            '单集时长:',
                                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                                          ),
                                          const SizedBox(width: 6),
                                          DropdownButton<int>(
                                            value: _targetDurationSec,
                                            isDense: true,
                                            underline: const SizedBox(),
                                            items: const [
                                              DropdownMenuItem(value: 60, child: Text('60s (快节奏)')),
                                              DropdownMenuItem(value: 90, child: Text('90s (标准短剧)')),
                                              DropdownMenuItem(value: 120, child: Text('120s (剧情篇)')),
                                              DropdownMenuItem(value: 180, child: Text('180s (精编篇)')),
                                            ],
                                            onChanged: (val) {
                                              if (val != null && val != _targetDurationSec) {
                                                setState(() => _targetDurationSec = val);
                                                _planSeasonBeats();
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 14),
                                          Text(
                                            '目标集数:',
                                            style: TextStyle(color: context.textSecondary, fontSize: 12),
                                          ),
                                          const SizedBox(width: 6),
                                          DropdownButton<int>(
                                            value: [12, 24, 60, 80, 100].contains(_targetEpisodeCount)
                                                ? _targetEpisodeCount
                                                : null,
                                            hint: Text('$_targetEpisodeCount 集', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                                            isDense: true,
                                            underline: const SizedBox(),
                                            items: [12, 24, 60, 80, 100].map((c) {
                                              return DropdownMenuItem(value: c, child: Text('$c 集'));
                                            }).toList(),
                                            onChanged: (val) {
                                              if (val != null && val != _targetEpisodeCount) {
                                                setState(() => _targetEpisodeCount = val);
                                                _planSeasonBeats();
                                              }
                                            },
                                          ),
                                          const SizedBox(width: 4),
                                          InkWell(
                                            borderRadius: BorderRadius.circular(4),
                                            onTap: _showCustomEpisodeDialog,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.edit_note, size: 15, color: context.accentText),
                                                  const SizedBox(width: 1),
                                                  Text('自定义', style: TextStyle(color: context.accentText, fontSize: 11)),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const Spacer(),
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              visualDensity: VisualDensity.compact,
                                              backgroundColor: context.accentSolid,
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            ),
                                            icon: _isPlanningBeats
                                                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                : const Icon(Icons.refresh, size: 14),
                                            label: const Text('重新规划本季大纲', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            onPressed: _isPlanningBeats ? null : _planSeasonBeats,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      // 第 3 行：全剧总片长实时看板
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: context.bgCardHover,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: context.borderSubtle.withValues(alpha: 0.6)),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.timer_outlined, size: 14, color: Colors.amber),
                                            const SizedBox(width: 6),
                                            Text(
                                              '共 $_targetEpisodeCount 集 · 单集 $_targetDurationSec 秒 (建议台词约 ${(_targetDurationSec * 3.5).round()}~${(_targetDurationSec * 4.5).round()} 字) · 全季总片长约 ${(_targetEpisodeCount * _targetDurationSec / 60).toStringAsFixed(0)} 分钟 (${(_targetEpisodeCount * _targetDurationSec / 3600).toStringAsFixed(1)} 小时)',
                                              style: TextStyle(
                                                color: context.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            if (_macroArcs.isNotEmpty) ...[
                                              const Spacer(),
                                              Text(
                                                '已划定 ${_macroArcs.length} 大篇章大幕',
                                                style: const TextStyle(
                                                  color: Colors.indigoAccent,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                // 列表内容
                                Expanded(
                                  child: (_isAnalyzing || _isPlanningBeats)
                                      ? Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(),
                                              const SizedBox(height: 16),
                                              Text(
                                                _statusMessage ?? '正在运算...',
                                                style: TextStyle(color: context.textSecondary, fontSize: 13),
                                              ),
                                            ],
                                          ),
                                        )
                                      : ListView(
                                          padding: const EdgeInsets.all(16),
                                          children: [
                                            // 全书多季宇宙规划路线图蓝图
                                            if (_seasonsRoadmap.isNotEmpty) ...[
                                              _buildSeasonsRoadmapSection(),
                                            ],

                                            // 故事主线脉络
                                            if (_masterPlot.isNotEmpty) ...[
                                              _buildSectionHeader('📖 全书核心叙事脉络与季终高潮', Colors.blue),
                                              const SizedBox(height: 6),
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: context.bgCard,
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      _masterPlot,
                                                      style: TextStyle(color: context.textPrimary, fontSize: 13, height: 1.5),
                                                    ),
                                                    if (_seasonClimax.isNotEmpty) ...[
                                                      const SizedBox(height: 10),
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                        decoration: BoxDecoration(
                                                          color: Colors.red.withValues(alpha: 0.08),
                                                          borderRadius: BorderRadius.circular(4),
                                                          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                                                        ),
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.local_fire_department, size: 16, color: Colors.deepOrange),
                                                            const SizedBox(width: 6),
                                                            Expanded(
                                                              child: Text(
                                                                '🎯 季终大高潮: $_seasonClimax',
                                                                style: const TextStyle(
                                                                  color: Colors.deepOrange,
                                                                  fontSize: 12,
                                                                  fontWeight: FontWeight.bold,
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
                                              const SizedBox(height: 16),
                                            ],

                                            // 改编边界三分类
                                            if (_mustKeep.isNotEmpty || _canCut.isNotEmpty || _canModify.isNotEmpty) ...[
                                              _buildSectionHeader('⚖️ 改编边界与情节清单', Colors.purple),
                                              const SizedBox(height: 8),
                                              _buildPlotCategoryCard('🟢 必留情节（核心主线与高光名场面）', _mustKeep, Colors.green),
                                              const SizedBox(height: 8),
                                              _buildPlotCategoryCard('🔴 可删情节（冗长心理独白与重复水文）', _canCut, Colors.red),
                                              const SizedBox(height: 8),
                                              _buildPlotCategoryCard('🟠 可改情节（允许合并的边缘配角与过渡）', _canModify, Colors.orange),
                                              const SizedBox(height: 20),
                                            ],

                                            // 角色画像与人物关系矩阵
                                            if (_characters.isNotEmpty || _characterRelations.isNotEmpty) ...[
                                              _buildCharactersAndRelationsSection(),
                                              const SizedBox(height: 16),
                                            ],

                                            // 核心关键道具清单
                                            if (_keyProps.isNotEmpty) ...[
                                              _buildKeyPropsSection(),
                                              const SizedBox(height: 16),
                                            ],

                                            // 宏观篇章大幕（Macro Arcs）
                                            if (_macroArcs.isNotEmpty) ...[
                                              _buildMacroArcsSection(),
                                              const SizedBox(height: 16),
                                            ],

                                            // 全季分集列表
                                            _buildSectionHeader('🎬 全季分集规划与断章钩子', Colors.amber),
                                            const SizedBox(height: 8),
                                            if (_episodes.isEmpty)
                                              _buildEmptyBeatsCard()
                                            else
                                              for (int idx = 0; idx < _episodes.length; idx++)
                                                _buildEpisodeCard(idx, _episodes[idx]),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),

                        // 右侧：制片人与 AI 编剧协同对话研讨
                        Expanded(
                          flex: 4,
                          child: Container(
                            decoration: BoxDecoration(
                              color: context.bgContent,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.borderSubtle),
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  color: context.bgCard,
                                  child: Row(
                                    children: [
                                      const Icon(Icons.chat_bubble_outline, size: 16, color: Colors.blue),
                                      const SizedBox(width: 8),
                                      Text(
                                        '联合编剧协商窗口',
                                        style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const Divider(height: 1),
                                // 对话历史列表
                                Expanded(
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: _chatHistory.length,
                                    itemBuilder: (ctx, i) {
                                      final item = _chatHistory[i];
                                      final isUser = item['role'] == 'user';
                                      return Align(
                                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: const EdgeInsets.only(bottom: 10),
                                          padding: const EdgeInsets.all(10),
                                          constraints: const BoxConstraints(maxWidth: 320),
                                          decoration: BoxDecoration(
                                            color: isUser ? context.accentSolid : context.bgCard,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            item['content'] ?? '',
                                            style: TextStyle(
                                              color: isUser ? Colors.white : context.textPrimary,
                                              fontSize: 12,
                                              height: 1.4,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const Divider(height: 1),
                                // 输入栏
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  color: context.bgCard,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _dialogueCtrl,
                                          style: TextStyle(color: context.textPrimary, fontSize: 12),
                                          decoration: InputDecoration(
                                            hintText: '输入改编指令（如：前三集节奏加快，第一集必须是退婚冲突...）',
                                            hintStyle: TextStyle(color: context.textTertiary, fontSize: 11),
                                            isDense: true,
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(6),
                                              borderSide: BorderSide(color: context.borderSubtle),
                                            ),
                                          ),
                                          onSubmitted: (_) => _sendDialogueInstruction(),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: _isChatting
                                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                            : const Icon(Icons.send, size: 18),
                                        onPressed: _sendDialogueInstruction,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildSectionHeader(String title, Color accent) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildPlotCategoryCard(String header, List<Map<String, dynamic>> items, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(header, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 6),
          if (items.isEmpty)
            Text('无', style: TextStyle(color: context.textTertiary, fontSize: 11))
          else
            for (final it in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        '${it["title"] ?? ""}: ${it["description"] ?? it["suggestion"] ?? ""}',
                        style: TextStyle(color: context.textPrimary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSeasonSwitcher() {
    return Container(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.movie_filter_outlined, size: 14, color: Colors.deepPurpleAccent),
              const SizedBox(width: 4),
              Text(
                '季播切换 (${_seasonsRoadmap.length} 季):',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(_seasonsRoadmap.length, (i) {
                  final s = _seasonsRoadmap[i];
                  final isSelected = i == _selectedSeasonIndex;
                  final sNum = s['season_number'] ?? (i + 1);
                  final sTitle = s['season_title'] ?? '第$sNum季';
                  final epCount = s['recommended_episode_count'] ?? 80;
                  final cRange = (s['adapted_chapters_range'] as String? ?? '').trim();

                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      selected: isSelected,
                      label: Text(
                        '第 $sNum 季 · $sTitle ($epCount集${cRange.isNotEmpty ? " · $cRange" : ""})',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : context.textPrimary,
                        ),
                      ),
                      selectedColor: Colors.deepPurpleAccent,
                      backgroundColor: context.bgCardHover,
                      visualDensity: VisualDensity.compact,
                      tooltip: '【本季主题】${s['season_theme'] ?? ""}\n【季终高潮】${s['season_climax'] ?? ""}',
                      onSelected: (selected) {
                        if (selected && i != _selectedSeasonIndex) {
                          _switchSeason(i);
                        }
                      },
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSeasonsRoadmapSection() {
    if (_seasonsRoadmap.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader('🗺️ 全书多季宇宙规划路线图（Multi-Season Franchise Roadmap）', Colors.deepPurple),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '共规划 ${_seasonsRoadmap.length} 季',
                  style: const TextStyle(color: Colors.deepPurpleAccent, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _seasonsRoadmap.length; i++) ...[
            Builder(builder: (ctx) {
              final s = _seasonsRoadmap[i];
              final isCurrent = i == _selectedSeasonIndex;
              final sNum = s['season_number'] ?? (i + 1);
              final sTitle = s['season_title'] ?? '第$sNum季';
              final cRange = (s['adapted_chapters_range'] as String? ?? '').trim();
              final epCount = s['recommended_episode_count'] ?? 80;
              final theme = (s['season_theme'] as String? ?? '').trim();
              final antagonist = (s['core_antagonist'] as String? ?? '').trim();
              final climax = (s['season_climax'] as String? ?? '').trim();

              return InkWell(
                onTap: () {
                  if (i != _selectedSeasonIndex) {
                    _switchSeason(i);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? Colors.deepPurple.withValues(alpha: 0.1)
                        : context.bgCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isCurrent
                          ? Colors.deepPurpleAccent
                          : context.borderSubtle,
                      width: isCurrent ? 1.5 : 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isCurrent ? Colors.deepPurpleAccent : context.accentSubtle,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '第 $sNum 季 · $sTitle',
                              style: TextStyle(
                                color: isCurrent ? Colors.white : context.accentText,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (cRange.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                cRange,
                                style: const TextStyle(color: Colors.blue, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '$epCount 集',
                              style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const Spacer(),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check, size: 12, color: Colors.green),
                                  SizedBox(width: 2),
                                  Text(
                                    '当前聚焦',
                                    style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          else
                            Text(
                              '点击切换至该季',
                              style: TextStyle(color: context.textTertiary, fontSize: 10),
                            ),
                        ],
                      ),
                      if (theme.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          '🎯 核心叙事目标: $theme',
                          style: TextStyle(color: context.textPrimary, fontSize: 12),
                        ),
                      ],
                      if (antagonist.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '⚔️ 主要宿敌/对立面: $antagonist',
                          style: TextStyle(color: context.textSecondary, fontSize: 11),
                        ),
                      ],
                      if (climax.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '💥 季终决胜大高潮: $climax',
                          style: const TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroArcsSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader('🏛️ 宏观篇章大幕（Macro Arcs · 全季结构化分幕）', Colors.indigo),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '共 ${_macroArcs.length} 幕',
                  style: const TextStyle(color: Colors.indigo, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final arc in _macroArcs) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.indigo.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          arc['arc_name'] as String? ?? '大幕 ${arc['arc_number'] ?? ''}',
                          style: const TextStyle(
                            color: Colors.indigo,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.accentSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          arc['episode_range'] as String? ?? '',
                          style: TextStyle(
                            color: context.accentText,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if ((arc['core_conflict'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '⚡ 核心戏剧冲突: ${arc['core_conflict']}',
                      style: TextStyle(color: context.textPrimary, fontSize: 12),
                    ),
                  ],
                  if ((arc['climax'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '💥 幕终高潮点: ${arc['climax']}',
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 11, fontWeight: FontWeight.w600),
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

  Widget _buildEmptyBeatsCard() {
    final hasError = _beatsPlanError != null && _beatsPlanError!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: hasError ? Colors.red.withValues(alpha: 0.05) : context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasError ? Colors.red.withValues(alpha: 0.3) : context.borderSubtle,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            hasError ? Icons.error_outline : Icons.movie_creation_outlined,
            size: 38,
            color: hasError ? Colors.red.shade400 : context.textTertiary,
          ),
          const SizedBox(height: 10),
          Text(
            hasError ? '第 $_seasonNumber 季分集规划未完成' : '第 $_seasonNumber 季暂未生成分集大纲',
            style: TextStyle(
              color: hasError ? Colors.red.shade700 : context.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasError
                ? '规划失败原因: $_beatsPlanError\n建议确认网络与大模型配置后重新发起规划：'
                : '可点击下方按钮由 AI 立即规划本季高能两级分幕与分集大纲：',
            style: TextStyle(
              color: hasError ? Colors.red.shade600 : context.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: hasError ? Colors.red.shade600 : Colors.amber.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            icon: _isPlanningBeats
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(hasError ? Icons.refresh : Icons.auto_awesome, size: 16),
            label: Text(
              hasError
                  ? '重新尝试规划第 $_seasonNumber 季大纲 (共 $_targetEpisodeCount 集)'
                  : '立即规划第 $_seasonNumber 季分集大纲 (共 $_targetEpisodeCount 集)',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            onPressed: _isPlanningBeats ? null : _planSeasonBeats,
          ),
        ],
      ),
    );
  }

  Future<void> _showEditChapterRangeDialog(int index, Map<String, dynamic> ep) async {
    final epNum = ep['episode_number'] ?? (index + 1);
    final currentRange = (ep['chapter_range'] as String? ?? '').trim();
    final fallbackDesc = AiConstraintEngine.parseChapterRange(
      null,
      fallbackEpisodeIndex: epNum,
      totalEpisodes: _targetEpisodeCount,
      seasonChaptersRange: _adaptedChaptersRange,
    ).rangeDesc;
    final controller = TextEditingController(
      text: currentRange.isNotEmpty ? currentRange : fallbackDesc,
    );

    final updatedRange = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.auto_stories, size: 18, color: Colors.teal),
            const SizedBox(width: 8),
            Text('修改第 $epNum 集原著章节映射', style: const TextStyle(fontSize: 15)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '请指定本集取材的原著小说章节范围（支持格式如：1-3、1~3 或 1, 2, 3）：',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: '如 1-3 或 22-25',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (updatedRange != null && mounted) {
      final parsed = AiConstraintEngine.parseChapterRange(
        updatedRange,
        fallbackEpisodeIndex: epNum,
        totalEpisodes: _targetEpisodeCount,
        seasonChaptersRange: _adaptedChaptersRange,
      );
      setState(() {
        ep['chapter_range'] = parsed.rangeDesc;
        ep['chapter_indices'] = parsed.indices;
      });
    }
  }

  Widget _buildEpisodeCard(int idx, Map<String, dynamic> ep) {
    final epNum = ep['episode_number'] ?? (idx + 1);
    final title = ep['title'] ?? '第 $epNum 集';
    final conflict = ep['conflict'] ?? '';
    final hook = ep['hook'] ?? '';
    final durationSec = (ep['duration_sec'] as num?)?.toInt() ?? _targetDurationSec;
    final arcName = (ep['arc_name'] as String? ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.accentSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('第 $epNum 集', style: TextStyle(color: context.accentText, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              if (arcName.isNotEmpty) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    arcName,
                    style: const TextStyle(color: Colors.indigo, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              // 原著章节徽章（方案 A：展示并支持点击手动微调）
              Builder(builder: (ctx) {
                final chapterRange = (ep['chapter_range'] as String? ?? '').trim();
                final displayRange = chapterRange.isNotEmpty
                    ? chapterRange
                    : AiConstraintEngine.parseChapterRange(
                        null,
                        fallbackEpisodeIndex: epNum,
                        totalEpisodes: _targetEpisodeCount,
                        seasonChaptersRange: _adaptedChaptersRange,
                      ).rangeDesc;
                return InkWell(
                  onTap: () => _showEditChapterRangeDialog(idx, ep),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_stories, size: 10, color: Colors.teal),
                        const SizedBox(width: 3),
                        Text(
                          '原著第 $displayRange 章',
                          style: const TextStyle(
                            color: Colors.teal,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.edit, size: 9, color: Colors.teal),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: context.bgCardHover,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_outlined, size: 12, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      '${durationSec}s · 约 ${(durationSec * 3.5).round()}~${(durationSec * 4.5).round()} 字',
                      style: TextStyle(color: context.textSecondary, fontSize: 10, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('核心冲突: $conflict', style: TextStyle(color: context.textSecondary, fontSize: 12)),
          if (hook.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.flash_on, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '断章钩子: $hook',
                    style: const TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
          Builder(builder: (ctx) {
            final chars = (ep['characters'] as List? ?? []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            final epProps = (ep['key_props'] as List? ?? []).map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
            if (chars.isEmpty && epProps.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final c in chars)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.person, size: 10, color: Colors.blue),
                          const SizedBox(width: 3),
                          Text(c, style: const TextStyle(color: Colors.blue, fontSize: 10)),
                        ],
                      ),
                    ),
                  for (final p in epProps)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.token, size: 10, color: Colors.amber),
                          const SizedBox(width: 3),
                          Text(p, style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCharactersAndRelationsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader('👥 核心角色画像与关系矩阵', Colors.teal),
              const Spacer(),
              if (_characters.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.teal,
                  ),
                  icon: _isSyncingCharacters
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.teal))
                      : const Icon(Icons.sync_alt, size: 14),
                  label: const Text('一键沉淀至 IP 资产库', style: TextStyle(fontSize: 12)),
                  onPressed: _isSyncingCharacters ? null : () => _syncCharactersToIpLibrary(),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 角色列表卡片
          if (_characters.isNotEmpty) ...[
            Text('🎭 角色谱系 (${_characters.length} 位)',
                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            for (final char in _characters) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          char['name'] as String? ?? '未命名',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            char['role'] as String? ?? '核心角色',
                            style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    if ((char['personality'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('• 性格: ${char['personality']}',
                          style: TextStyle(color: context.textSecondary, fontSize: 11)),
                    ],
                    if ((char['appearance_features'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('• 外貌/立绘: ${char['appearance_features']}',
                          style: TextStyle(color: context.textSecondary, fontSize: 11)),
                    ],
                    if ((char['motivation'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('• 核心动机: ${char['motivation']}',
                          style: TextStyle(color: context.textSecondary, fontSize: 11)),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
          // 关系矩阵
          if (_characterRelations.isNotEmpty) ...[
            Text('🕸️ 人物关系张力 (${_characterRelations.length} 条)',
                style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 8),
            for (final rel in _characterRelations) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: Row(
                  children: [
                    Text(
                      '${rel['from'] ?? ''} ➔ ${rel['to'] ?? ''}',
                      style: TextStyle(color: context.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.purple.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        rel['relation_type'] as String? ?? '关联',
                        style: const TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rel['description'] as String? ?? '',
                        style: TextStyle(color: context.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildKeyPropsSection() {
    if (_keyProps.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildSectionHeader('🗡️ 核心关键道具清单', Colors.amber.shade800),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: Colors.amber.shade800,
                ),
                icon: _isSyncingProps
                    ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber.shade800))
                    : const Icon(Icons.sync_alt, size: 14),
                label: const Text('一键沉淀至 IP 资产库', style: TextStyle(fontSize: 12)),
                onPressed: _isSyncingProps ? null : () => _syncPropsToIpLibrary(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('📦 关键道具 (${_keyProps.length} 件)',
              style: TextStyle(color: Colors.amber.shade900, fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 8),
          for (final prop in _keyProps) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        prop['name'] as String? ?? '未命名道具',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          prop['category'] as String? ?? '核心道具',
                          style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  if ((prop['significance'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('• 戏剧作用: ${prop['significance']}',
                        style: TextStyle(color: context.textSecondary, fontSize: 11)),
                  ],
                  if ((prop['appearance'] as String? ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('• 外观/材质: ${prop['appearance']}',
                        style: TextStyle(color: context.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
