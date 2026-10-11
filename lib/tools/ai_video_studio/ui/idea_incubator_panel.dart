/// 创意孵化面板：模糊想法 → 3 个结构化故事方向（spec 10.1 / 10.2 / 10.3）。
///
/// 支持「全剧主线孵化」与「单集续写扩写」双模式，支持创意方案持久化与全量抽屉编辑。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/ai_constraint_engine.dart';
import '../services/studio_project_manager.dart';
import 'studio_shell.dart';


enum IncubationMode {
  seriesMain('全剧主线孵化', '从模糊概念提炼主线钩子、反转与全剧节奏'),
  episodeContinuation('单集续写扩写', '基于已有世界观与上一集前情钩子续写下一集');

  final String label;
  final String description;
  const IncubationMode(this.label, this.description);
}

class IdeaIncubatorPanel extends StatefulWidget {
  const IdeaIncubatorPanel({
    super.key,
    required this.session,
    required this.onConfirmed,
  });

  final StudioSession session;

  /// 用户确认某个方向后的跳转（去 IP 主库）。
  final VoidCallback onConfirmed;

  @override
  State<IdeaIncubatorPanel> createState() => _IdeaIncubatorPanelState();
}

class _IdeaIncubatorPanelState extends State<IdeaIncubatorPanel> {
  final _controller = TextEditingController();
  final _manager = StudioProjectManager.instance;

  IncubationMode _mode = IncubationMode.seriesMain;
  int? _targetEpisodeIndex;
  List<StudioEpisode> _existingEpisodes = const [];

  bool _running = false;
  String? _error;
  List<IdeaDirection> _directions = const [];
  String? _rawText;

  bool _novelImporting = false;
  String _novelImportStatus = '';

  @override
  void initState() {
    super.initState();
    _loadHistoryAndEpisodes();
  }

  Future<void> _importNovelFile() async {
    final series = widget.session.series;
    if (series == null) return;

    try {
      final pickResult = await FilePicker.platform.pickFiles(
        dialogTitle: '选择小说文本文件 (.txt / .md)',
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
      );
      if (pickResult == null || pickResult.files.isEmpty) return;

      final path = pickResult.files.single.path;
      if (path == null) return;
      final file = File(path);
      if (!await file.exists()) return;

      final novelContent = await file.readAsString();
      if (novelContent.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所选文本文件为空')),
        );
        return;
      }

      // 弹出导入范围与意图确认弹窗
      final scopeChoice = await _showImportScopeDialog(novelContent);
      if (scopeChoice == null || !mounted) return;

      var elapsedSec = 0;
      var currentPhaseText = scopeChoice.isFullSeason
          ? '正在分析原著内容，提取世界观设定、角色卡与场景库… (Pass 1/2)'
          : '正在分析本章内容，提炼增量角色卡、场景库与世界观… (Pass 1/2)';

      final ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
        elapsedSec++;
        if (mounted && _novelImporting) {
          setState(() {
            _novelImportStatus = '$currentPhaseText [已耗时 ${elapsedSec}s]';
          });
        }
      });

      try {
        setState(() {
          _novelImporting = true;
          _novelImportStatus = '$currentPhaseText [已耗时 0s]';
          _error = null;
          _rawText = null;
        });

        // Pass 1: 提取世界观设定、角色卡库与场景库 (重型任务，内置 240s 自适应超时)
        final masterResult = await AiConstraintEngine.extractNovelMaster(
          novelText: novelContent,
          productionType: series.productionType.id,
        );

        if (!mounted) return;

        if (scopeChoice.isFullSeason) {
          // 全案多集解构流程
          elapsedSec = 0;
          currentPhaseText = '正在基于小说剧情高潮点规划全季推荐分集与前情钩子… (Pass 2/2)';
          setState(() {
            _novelImportStatus = '$currentPhaseText [已耗时 0s]';
          });

          // 提取角色名称列表供 Pass 2 上下文关联
          final charList = (masterResult.data['characters'] as List?) ?? const [];
          final charNames = charList
              .whereType<Map>()
              .map((c) => (c['name'] as String? ?? '').trim())
              .where((n) => n.isNotEmpty)
              .toList();

          final segmentResult = await AiConstraintEngine.segmentNovelEpisodes(
            novelText: novelContent,
            worldview: masterResult.data['worldview'] as String? ?? '',
            characterNames: charNames,
            productionType: series.productionType.id,
          );

          if (!mounted) return;
          currentPhaseText = '正在写入 IP 主库与全季分集大纲…';
          setState(() {
            _novelImportStatus = currentPhaseText;
          });

          final updatedSeries = await _manager.importNovelProject(
            seriesId: series.id,
            masterExtraction: masterResult.data,
            episodeSegmentation: segmentResult.data,
          );

          widget.session.select(updatedSeries);
          await _loadHistoryAndEpisodes();

          if (!mounted) return;
          setState(() {
            _novelImporting = false;
            _novelImportStatus = '';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '全案小说解构成功！增量入库 ${(masterResult.data['characters'] as List).length} 个角色、'
                '${(masterResult.data['scenes'] as List).length} 个场景，重构 ${(segmentResult.data['episodes'] as List).length} 集大纲。',
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        } else {
          // 单章/单集扩写流程：不破坏已有集数，深度提炼全章影视大纲并沉淀至目标集
          elapsedSec = 0;
          currentPhaseText = '正在深入分析本章全篇情节，提炼起承转合影视剧本大纲… (Pass 2/2)';
          setState(() {
            _novelImportStatus = '$currentPhaseText [已耗时 0s]';
          });

          // 提取可用角色名称
          final charList = (masterResult.data['characters'] as List?) ?? const [];
          final charNames = charList
              .whereType<Map>()
              .map((c) => (c['name'] as String? ?? '').trim())
              .where((n) => n.isNotEmpty)
              .toList();

          // 提取已有剧情记忆作为前情上下文
          final memoryContext = _manager.buildMemoryContext(series);

          // 提炼单章影视剧本大纲（全篇剧情深度理解，不截断）
          final adaptResult = await AiConstraintEngine.adaptNovelChapter(
            novelText: novelContent,
            seriesName: series.name,
            worldview: (masterResult.data['worldview'] as String? ?? series.worldview).trim(),
            characterNames: charNames,
            productionType: series.productionType.id,
            episodeIndex: scopeChoice.targetEpisodeIndex,
            memoryContext: memoryContext,
          );

          if (!mounted) return;
          currentPhaseText = '正在写入第 ${scopeChoice.targetEpisodeIndex} 集大纲并增量更新资产…';
          setState(() {
            _novelImportStatus = currentPhaseText;
          });

          // 从文本中提炼备用标题
          final chapterLines = novelContent
              .split('\n')
              .map((l) => l.trim())
              .where((l) => l.isNotEmpty)
              .toList();
          final guessedTitle = chapterLines.isNotEmpty && chapterLines.first.length <= 20
              ? chapterLines.first
              : '第 ${scopeChoice.targetEpisodeIndex} 集';

          final adaptedTitle = (adaptResult.data['title'] as String? ?? '').trim();
          final adaptedSynopsis = (adaptResult.data['synopsis'] as String? ?? '').trim();
          final adaptedSummary = (adaptResult.data['summary'] as String? ?? '').trim();
          final adaptedHook = (adaptResult.data['hook'] as String? ?? '').trim();

          final updatedSeries = await _manager.importChapterToEpisode(
            seriesId: series.id,
            masterExtraction: masterResult.data,
            targetEpisodeIndex: scopeChoice.targetEpisodeIndex,
            episodeTitle: adaptedTitle.isNotEmpty ? adaptedTitle : guessedTitle,
            episodeSynopsis: adaptedSynopsis.isNotEmpty ? adaptedSynopsis : novelContent,
            episodeSummary: adaptedSummary.isNotEmpty
                ? adaptedSummary
                : '【第${scopeChoice.targetEpisodeIndex}集前情】$adaptedSynopsis',
            episodeHook: adaptedHook.isNotEmpty ? adaptedHook : '章节末尾悬念展开',
          );

          widget.session.select(updatedSeries);
          await _loadHistoryAndEpisodes();

          if (!mounted) return;
          setState(() {
            _novelImporting = false;
            _novelImportStatus = '';
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '单章导入成功！已提炼整章影视大纲并沉淀至「第 ${scopeChoice.targetEpisodeIndex} 集」，增量扩充了角色与场景库。',
              ),
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
          );
        }

        // 通知上层跳转至 IP 主库/分镜看板
        widget.onConfirmed();
      } finally {
        ticker.cancel();
      }
    } on ConstraintParseError catch (e) {
      if (!mounted) return;
      setState(() {
        _novelImporting = false;
        _novelImportStatus = '';
        _error = 'AI 输出无法解析，已保留原文供查看';
        _rawText = e.rawText;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _novelImporting = false;
        _novelImportStatus = '';
        _error = '小说导入解析失败: $e';
      });
    }
  }

  Future<_NovelImportScope?> _showImportScopeDialog(String novelContent) async {
    final existingEpCount = _existingEpisodes.length;
    // 智能推断默认模式：如果在单集续写模式或已有剧集，默认单章扩写；否则为全季解构
    bool isFullSeason = _mode == IncubationMode.seriesMain && existingEpCount == 0;
    int targetEp = _targetEpisodeIndex ?? (existingEpCount > 0 ? existingEpCount + 1 : 1);

    return showDialog<_NovelImportScope>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final wordCount = novelContent.length;
            final lineCount = novelContent.split('\n').length;

            return AlertDialog(
              backgroundColor: context.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  Icon(Icons.auto_stories, color: context.accentSolid, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    '确认小说导入范围',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: context.bgInput,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '文本统计: 共约 $wordCount 字 / $lineCount 行',
                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '请选择本次导入文本的性质与沉淀目标：',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 选项 1: 单章 / 单集扩写
                    InkWell(
                      onTap: () => setDialogState(() => isFullSeason = false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: !isFullSeason ? context.accentSubtle.withAlpha(40) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: !isFullSeason ? context.accentText : context.borderSubtle,
                            width: !isFullSeason ? 1.5 : 1.0,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Radio<bool>(
                                  value: false,
                                  groupValue: isFullSeason,
                                  onChanged: (v) => setDialogState(() => isFullSeason = false),
                                  activeColor: context.accentText,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '单集 / 连载章节内容（增量扩写）',
                                        style: TextStyle(
                                          color: context.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '适用于导入某一回/某一章节。增量提取角色卡与场景库并注入本剧，不破坏已有其他分集。',
                                        style: TextStyle(color: context.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (!isFullSeason) ...[
                              const SizedBox(height: 10),
                              Padding(
                                padding: const EdgeInsets.only(left: 36),
                                child: Row(
                                  children: [
                                    Text('归属或追加至: ', style: TextStyle(color: context.textPrimary, fontSize: 12)),
                                    const SizedBox(width: 8),
                                    DropdownButton<int>(
                                      value: targetEp,
                                      isDense: true,
                                      dropdownColor: context.bgInput,
                                      style: TextStyle(color: context.textPrimary, fontSize: 13),
                                      items: [
                                        for (int i = 1; i <= existingEpCount; i++)
                                          DropdownMenuItem(
                                            value: i,
                                            child: Text('沉淀/更新至 第 $i 集'),
                                          ),
                                        DropdownMenuItem(
                                          value: existingEpCount + 1,
                                          child: Text('追加为新的一集 (第 ${existingEpCount + 1} 集)'),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v != null) {
                                          setDialogState(() => targetEp = v);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 选项 2: 全案多集解构
                    InkWell(
                      onTap: () => setDialogState(() => isFullSeason = true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isFullSeason ? context.accentSubtle.withAlpha(40) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isFullSeason ? context.accentText : context.borderSubtle,
                            width: isFullSeason ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Radio<bool>(
                              value: true,
                              groupValue: isFullSeason,
                              onChanged: (v) => setDialogState(() => isFullSeason = true),
                              activeColor: context.accentText,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '完整长篇小说（全案重构）',
                                    style: TextStyle(
                                      color: context.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '适用于包含多章节的长篇小说。AI 将深度全案分析，提取全剧 IP 库并自动规划推荐全季分集大纲。',
                                    style: TextStyle(color: context.textSecondary, fontSize: 12),
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
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('取消', style: TextStyle(color: context.textSecondary)),
                ),
                FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx, _NovelImportScope(
                      isFullSeason: isFullSeason,
                      targetEpisodeIndex: targetEp,
                    ));
                  },
                  child: const Text('开始导入'),
                ),
              ],
            );
          },
        );
      },
    );
  }


  @override
  void didUpdateWidget(covariant IdeaIncubatorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.series?.id != widget.session.series?.id) {
      _loadHistoryAndEpisodes();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadHistoryAndEpisodes() async {
    final series = widget.session.series;
    if (series == null) return;
    final history = await _manager.listIdeaHistory(series.id);
    final episodes = await _manager.listEpisodes(series.id);
    if (!mounted) return;
    setState(() {
      _directions = history;
      _existingEpisodes = episodes;
      _targetEpisodeIndex = (episodes.isNotEmpty) ? episodes.length + 1 : 1;
    });
  }

  Future<void> _generate() async {
    final idea = _controller.text.trim();
    if (idea.isEmpty) return;
    final series = widget.session.series;
    if (series == null) return;

    setState(() {
      _running = true;
      _error = null;
      _rawText = null;
    });

    try {
      String memoryContext = '';
      if (_mode == IncubationMode.episodeContinuation) {
        memoryContext = _manager.buildMemoryContext(series);
      }

      final result = await AiConstraintEngine.ideaIncubation(
        rawIdea: idea,
        productionTypeLabel: series.productionType.label,
        seriesName: series.name,
        worldview: _mode == IncubationMode.episodeContinuation ? series.worldview : '',
        existingEpisodesContext: memoryContext,
        targetEpisodeIndex: _mode == IncubationMode.episodeContinuation ? _targetEpisodeIndex : null,
      );

      final rawList = (result.data['directions'] as List).cast<Map<String, dynamic>>();
      final now = DateTime.now();
      final list = rawList.map((d) {
        return IdeaDirection(
          id: 'idea_${now.microsecondsSinceEpoch}_${rawList.indexOf(d)}',
          title: d['title']?.toString() ?? '未命名方向',
          hook: d['hook']?.toString() ?? '',
          twist: d['twist']?.toString() ?? '',
          pacing: d['pacing']?.toString() ?? '',
          strategy: d['strategy']?.toString() ?? '',
          createdAt: now,
        );
      }).toList();

      await _manager.saveIdeaHistory(series.id, list);

      if (!mounted) return;
      setState(() {
        _directions = list;
        _running = false;
      });
    } on ConstraintParseError catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'AI 输出无法解析，已保留原文供查看';
        _rawText = e.rawText;
        _running = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _running = false;
      });
    }
  }

  Future<void> _confirm(IdeaDirection direction) async {
    final series = widget.session.series;
    if (series == null) return;

    final updatedDirections = _directions.map((d) {
      return d.copyWith(accepted: d.id == direction.id);
    }).toList();

    await _manager.saveIdeaHistory(series.id, updatedDirections);

    final worldview = [
      if (series.worldview.trim().isNotEmpty && _mode == IncubationMode.episodeContinuation) ...[
        series.worldview.trim(),
        '---',
      ],
      '【主线钩子】${direction.hook}',
      '【核心反转】${direction.twist}',
      '【分集节奏】${direction.pacing}',
      '【内容策略】${direction.strategy}',
    ].join('\n');

    await _manager.saveSeries(series.copyWith(
      name: series.name,
      worldview: worldview,
    ));

    widget.session.select(_manager.readSeries(series.id));

    if (!mounted) return;
    setState(() => _directions = updatedDirections);
    widget.onConfirmed();
  }

  void _openDetailDrawer(IdeaDirection direction) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => _IdeaDetailSheet(
        direction: direction,
        onSave: (updated) async {
          final series = widget.session.series;
          if (series == null) return;
          final updatedList = _directions.map((d) => d.id == updated.id ? updated : d).toList();
          await _manager.saveIdeaHistory(series.id, updatedList);
          if (mounted) setState(() => _directions = updatedList);
        },
        onAdopt: () {
          Navigator.pop(ctx);
          _confirm(direction);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.session.series;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '创意孵化',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              if (series != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.accentSubtle,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '当前剧集: 《${series.name}》',
                    style: TextStyle(color: context.accentText, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '用一句模糊的想法开始。AI 会拆出三个能直接开拍的故事方向。',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          // 模式切换
          SegmentedButton<IncubationMode>(
            segments: [
              ButtonSegment(
                value: IncubationMode.seriesMain,
                label: Text(IncubationMode.seriesMain.label),
                icon: const Icon(Icons.auto_awesome, size: 16),
              ),
              ButtonSegment(
                value: IncubationMode.episodeContinuation,
                label: Text(IncubationMode.episodeContinuation.label),
                icon: const Icon(Icons.update, size: 16),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (set) {
              setState(() => _mode = set.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _mode.description,
            style: TextStyle(color: context.textTertiary, fontSize: 12),
          ),
          if (_mode == IncubationMode.episodeContinuation) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.accentSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.accentText.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: context.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已自动加载本剧世界观设定及 ${_existingEpisodes.length} 个历史分集前情钩子。',
                      style: TextStyle(color: context.textPrimary, fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('目标集数: ', style: TextStyle(color: context.textSecondary, fontSize: 12)),
                  DropdownButton<int>(
                    value: _targetEpisodeIndex,
                    isDense: true,
                    items: List.generate(
                      _existingEpisodes.length + 3,
                      (i) => DropdownMenuItem(value: i + 1, child: Text('第 ${i + 1} 集')),
                    ),
                    onChanged: (v) => setState(() => _targetEpisodeIndex = v),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 4,
            enabled: !_running,
            style: TextStyle(color: context.textPrimary),
            decoration: InputDecoration(
              labelText: _mode == IncubationMode.seriesMain ? '你的初步想法（不限长度）' : '本集期望发生的核心事件或转折',
              labelStyle: TextStyle(color: context.textSecondary),
              hintText: _mode == IncubationMode.seriesMain
                  ? '例如：一个关于雨夜、错过与重逢的故事'
                  : '例如：主角发现对方的真实身份，两人在地下车库正面摊牌',
              hintStyle: TextStyle(color: context.textDisabled),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _running || _novelImporting ? null : _generate,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_running ? '生成中…' : '生成创意方向'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _running || _novelImporting ? null : _importNovelFile,
                icon: _novelImporting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(_novelImporting ? '解构入库中…' : '直接导入小说文本 (.txt/.md)'),
              ),
            ],
          ),
          if (_novelImporting) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.accentSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.accentText.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '小说全案深度解构中',
                          style: TextStyle(
                            color: context.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _novelImportStatus,
                          style: TextStyle(
                            color: context.accentText,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.errorText.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_error!, style: TextStyle(color: context.errorText, fontSize: 13)),
                  if (_rawText != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _rawText!,
                      maxLines: 12,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textSecondary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_directions.isNotEmpty) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  '候选创意方向 (${_directions.length})',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text('点击卡片可查看并编辑完整内容', style: TextStyle(color: context.textTertiary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            for (final d in _directions)
              _DirectionCard(
                direction: d,
                onConfirm: () => _confirm(d),
                onDetail: () => _openDetailDrawer(d),
              ),
          ],
        ],
      ),
    );
  }
}

class _DirectionCard extends StatelessWidget {
  const _DirectionCard({
    required this.direction,
    required this.onConfirm,
    required this.onDetail,
  });

  final IdeaDirection direction;
  final VoidCallback onConfirm;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: direction.accepted ? context.accentSubtle.withAlpha(30) : context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: direction.accepted ? context.accentText : context.borderSubtle,
          width: direction.accepted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      direction.title.isEmpty ? '未命名方向' : direction.title,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (direction.accepted) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.successText.withAlpha(30),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.successText),
                        ),
                        child: Text(
                          '已采纳',
                          style: TextStyle(color: context.successText, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: onDetail,
                icon: const Icon(Icons.edit_note, size: 16),
                label: const Text('查看与编辑'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check, size: 16),
                label: Text(direction.accepted ? '重新应用' : '选这个方向'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _Field(label: '主线钩子', value: direction.hook),
          _Field(label: '核心反转', value: direction.twist),
          _Field(label: '分集节奏', value: direction.pacing),
          _Field(label: '内容策略', value: direction.strategy),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: context.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _IdeaDetailSheet extends StatefulWidget {
  const _IdeaDetailSheet({
    required this.direction,
    required this.onSave,
    required this.onAdopt,
  });

  final IdeaDirection direction;
  final ValueChanged<IdeaDirection> onSave;
  final VoidCallback onAdopt;

  @override
  State<_IdeaDetailSheet> createState() => _IdeaDetailSheetState();
}

class _IdeaDetailSheetState extends State<_IdeaDetailSheet> {
  late final TextEditingController _title;
  late final TextEditingController _hook;
  late final TextEditingController _twist;
  late final TextEditingController _pacing;
  late final TextEditingController _strategy;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.direction.title);
    _hook = TextEditingController(text: widget.direction.hook);
    _twist = TextEditingController(text: widget.direction.twist);
    _pacing = TextEditingController(text: widget.direction.pacing);
    _strategy = TextEditingController(text: widget.direction.strategy);
  }

  @override
  void dispose() {
    _title.dispose();
    _hook.dispose();
    _twist.dispose();
    _pacing.dispose();
    _strategy.dispose();
    super.dispose();
  }

  void _save() {
    final updated = widget.direction.copyWith(
      title: _title.text.trim(),
      hook: _hook.text.trim(),
      twist: _twist.text.trim(),
      pacing: _pacing.text.trim(),
      strategy: _strategy.text.trim(),
    );
    widget.onSave(updated);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('创意方案修改已保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '创意方向详情与编辑',
                style: TextStyle(color: context.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.onAdopt,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('采纳该方案'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save, size: 16),
                label: const Text('保存修改'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              children: [
                TextField(
                  controller: _title,
                  style: TextStyle(color: context.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(labelText: '方向标题'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _hook,
                  maxLines: 4,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '主线钩子 (Hook)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _twist,
                  maxLines: 4,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '核心反转 (Twist)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _pacing,
                  maxLines: 4,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '分集节奏 (Pacing)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _strategy,
                  maxLines: 4,
                  style: TextStyle(color: context.textPrimary, fontSize: 13),
                  decoration: const InputDecoration(labelText: '内容策略 (Strategy)'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NovelImportScope {
  final bool isFullSeason;
  final int targetEpisodeIndex;

  const _NovelImportScope({
    required this.isFullSeason,
    required this.targetEpisodeIndex,
  });
}
