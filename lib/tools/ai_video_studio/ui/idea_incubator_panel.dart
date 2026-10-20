/// 创意孵化面板：模糊想法 → 3 个结构化故事方向（spec 10.1 / 10.2 / 10.3）。
///
/// 支持「全剧主线孵化」与「单集续写扩写」双模式，支持创意方案持久化与全量抽屉编辑。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/ai_constraint_engine.dart';
import '../services/novel_import_task_service.dart';
import '../services/studio_project_manager.dart';
import '../../../tools/novel_manager/models/novel_models.dart';
import 'novel_selector_dialog.dart';
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
    this.onNavigateStage,
  });

  final StudioSession session;

  /// 用户确认某个方向后的跳转（去 IP 主库）。
  final VoidCallback onConfirmed;

  /// 导航到其他工序页的回调。
  final ValueChanged<StudioStage>? onNavigateStage;

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

  /// 本面板发起、且仍在进行的导入任务 id。用于把面板内的进度卡片指向
  /// 正确的任务；切走再回来时它可能已被服务标记为终态，届时卡片自行隐藏。
  String? _activeImportId;

  /// 导入刚终态，需要刷新剧集上下文并通知外壳跳转。
  bool _needsContextRefresh = false;

  Future<void> _importNovelFromLibrary() async {
    final series = widget.session.series;
    if (series == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先选择或创建一部剧集')),
        );
      }
      return;
    }

    final result = await showDialog<NovelSelectionResult>(
      context: context,
      builder: (_) => NovelSelectorDialog(
        initialTargetEpisodeIndex: _targetEpisodeIndex ??
            (_existingEpisodes.isNotEmpty ? _existingEpisodes.length + 1 : 1),
        initialIsFullSeason:
            _mode == IncubationMode.seriesMain && _existingEpisodes.isEmpty,
      ),
    );

    if (result == null) return;
    await _processNovelContent(result);
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

      // 文件导入没有小说库元数据：id 留空（spec 只要求「从小说库选择时」带
      // 来源标识），标题取文件名去掉扩展名——任务记录里显示「未命名小说」
      // 会让用户分不清是哪一次导入。
      await _processNovelContent(
        NovelSelectionResult(
          novel: NovelMetadata(
            id: '',
            title: p.basenameWithoutExtension(path),
            author: '',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
          selectedChapterIndices: const [],
          combinedText: novelContent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('选择文件失败: $e')),
      );
    }
  }

  /// 把选中的小说交给导入任务服务执行。
  ///
  /// 任务归属在服务层（`NovelImportTaskService`），这里只负责收集参数与提交。
  /// 进度展示由 [build] 里的 `ListenableBuilder` 订阅同一个服务——切页签、
  /// 关窗重开都不再让进度消失，因为 Widget 只是订阅者，不是持有者。
  Future<void> _processNovelContent(NovelSelectionResult selection) async {
    final series = widget.session.series;
    if (series == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未选中剧集，无法导入小说')),
        );
      }
      return;
    }

    final bool isFullSeason;
    final int targetEpisodeIndex;
    if (selection.novel.id.isNotEmpty) {
      // 从小说库选择时已在弹窗内直接指定了模式（全季/单集）与集序号，无需二次弹窗
      isFullSeason = selection.isFullSeason;
      targetEpisodeIndex = selection.targetEpisodeIndex;
    } else {
      // 外部单文件导入：无小说库元数据，弹出范围选择弹窗
      final scopeChoice = await _showImportScopeDialog(selection.combinedText);
      if (scopeChoice == null || !mounted) return;
      isFullSeason = scopeChoice.isFullSeason;
      targetEpisodeIndex = scopeChoice.targetEpisodeIndex;
    }

    if (NovelImportTaskService.instance.hasRunningFor(series.id)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该剧集已有正在进行的导入任务，请等待其完成')),
        );
      }
      return;
    }

    try {
      final localId = await NovelImportTaskService.instance.submit(
        seriesId: series.id,
        novelText: selection.combinedText,
        isFullSeason: isFullSeason,
        targetEpisodeIndex: targetEpisodeIndex,
        novelId: selection.novel.id.isNotEmpty ? selection.novel.id : null,
        novelTitle: selection.novel.title,
        selectedChapterIndices: selection.selectedChapterIndices,
      );
      if (!mounted) return;
      setState(() {
        _activeImportId = localId;
        _needsContextRefresh = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已启动《${selection.novel.title}》漫剧解构流水线'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入提交失败: $e')),
      );
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
                    const SizedBox(height: 8),
                    // 开始前告知工作量（spec: 导入任务在开始前告知预期工作量）。
                    // 只给构成、不给具体分钟数承诺：模型速度不可知，且正文会被
                    // 长文截断，按字数线性推必然失真——给一个达不到的预估比不给
                    // 更糟。关窗（红叉）不会中断任务，退出应用才会，这点也要说。
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: context.accentSubtle,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.schedule_outlined,
                              size: 14, color: context.accentText),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '这是分钟级任务：'
                              '${isFullSeason ? '两遍深度分析（IP 资产解构 + 分集规划）' : '两遍深度分析（资产解构 + 单章影视化）'}，'
                              '每遍最长 4 分钟、失败最多重试 3 次。'
                              '任务期间可切页签或关闭窗口，任务会继续并在顶栏显示进度。',
                              style: TextStyle(
                                  color: context.accentText, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
      _activeImportId = null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHistoryAndEpisodes();
    // 订阅服务：导入完成时刷新剧集与集数（导入会重建集数结构），并让外壳
    // 跳转到 IP 主库。没有这一步，任务在后台成功后面板仍显示旧集数。
    NovelImportTaskService.instance.addListener(_onImportTaskChanged);
  }

  @override
  void dispose() {
    NovelImportTaskService.instance.removeListener(_onImportTaskChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onImportTaskChanged() {
    if (!mounted) return;
    final task = _activeTask;
    if (task == null || !task.isRunning) {
      // 终态：刷新一次上下文并放开按钮态。
      final id = _activeImportId;
      if (id != null && NovelImportTaskService.instance.taskOf(id) == null) {
        _activeImportId = null;
      }
      if (_needsContextRefresh) {
        _needsContextRefresh = false;
        _loadHistoryAndEpisodes();
        // 仅在成功导入后切换工序：单集导入直接进入剧本工作台，全季导入切到 IP 主库
        if (task?.phase == ImportPhase.done) {
          if (task != null && !task.isFullSeason && task.targetEpisodeIndex != null) {
            final series = widget.session.series;
            if (series != null) {
              _manager.listEpisodes(series.id).then((eps) {
                if (!mounted) return;
                final targetEp = eps.firstWhere(
                  (e) => e.index == task.targetEpisodeIndex,
                  orElse: () => eps.first,
                );
                widget.session.selectEpisode(targetEp);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('已成功解构第 ${targetEp.index} 集文学剧本，已进入剧本工作台'),
                    duration: const Duration(seconds: 2),
                  ),
                );
                if (widget.onNavigateStage != null) {
                  widget.onNavigateStage!(StudioStage.screenplay);
                } else {
                  widget.onConfirmed();
                }
              });
              return;
            }
          }
          widget.onConfirmed();
        } else if (task?.phase == ImportPhase.failed && task?.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(task!.error!),
              backgroundColor: context.errorSolid,
            ),
          );
        }
      }
    }
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

  /// 本面板发起、且仍在进行的导入任务。服务是进程级单例，所以切走再回来
  /// 仍能拿到同一个任务——这正是本次改动要保证的性质。
  /// 本剧集活跃或最近的导入任务（正在运行、已完成或中断）。
  /// 服务启动时已水合还原，因此窗口重开也能读取到最近任务。
  NovelImportTask? get _activeTask {
    final service = NovelImportTaskService.instance;
    final id = _activeImportId;
    if (id != null) {
      final task = service.taskOf(id);
      if (task != null) return task;
    }
    final series = widget.session.series;
    if (series != null) {
      return service.latestTaskFor(series.id);
    }
    return null;
  }

  /// 是否有导入在进行。用于禁用「生成创意方向」与两个导入按钮——同时提交
  /// 会让两遍 AI 调用交错写同一份 `series_profile.json`，而那是 IP 主库的
  /// 唯一事实来源。
  bool get _importBusy => NovelImportTaskService.instance.runningCount > 0;

  @override
  Widget build(BuildContext context) {
    final series = widget.session.series;
    // 订阅服务而不是本地状态：进度在服务里，Widget 只是观察者。这是「切页签
    // 不丢进度」的UI侧保证——否则切回来看到的是一个刚建的空面板。
    return ListenableBuilder(
      listenable: NovelImportTaskService.instance,
      builder: (context, _) => SingleChildScrollView(
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
          // 三个按钮横排在窄窗口（或测试的默认 800px 表面）下会溢出 56px。
          // 用 Wrap 而不是 Expanded 把文字截断：按钮文案本身是可读性的一部
          // 分，「从小说库选择」被省略成「从小说…」比换行更难认。
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _running || _importBusy ? null : _generate,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_running ? '生成中…' : '生成创意方向'),
              ),
              OutlinedButton.icon(
                onPressed: _running || _importBusy ? null : _importNovelFromLibrary,
                icon: _importBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_stories, size: 18, color: Colors.blueAccent),
                label: Text(_importBusy ? '解构入库中…' : '从小说库选择'),
              ),
              OutlinedButton.icon(
                onPressed: _running || _importBusy ? null : _importNovelFile,
                icon: _importBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(_importBusy ? '解构入库中…' : '导入文本文件 (.txt/.md)'),
              ),
            ],
          ),
          if (_activeTask != null) ...[
            const SizedBox(height: 16),
            if (_activeTask!.isRunning)
              _ImportProgressCard(task: _activeTask!)
            else if (_activeTask!.phase == ImportPhase.done)
              _ImportSummaryCard(
                task: _activeTask!,
                series: series,
                onViewResult: widget.onConfirmed,
                onReimport: _importNovelFromLibrary,
              )
            else
              _ImportInterruptedCard(
                task: _activeTask!,
                onRetry: _importNovelFromLibrary,
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

/// 导入进度卡片。
///
/// 只读 [NovelImportTask] 快照，不持有任何状态——刷新由外层的
/// `ListenableBuilder` 订阅服务驱动。这样卡片本身可以在任何页面复用。
///
/// **没有百分比**：执行方不提供进度百分比，编一个会让用户以为"还差 30%"，
/// 而真实情况可能刚发出请求（spec: 不得编造百分比进度）。
class _ImportProgressCard extends StatefulWidget {
  const _ImportProgressCard({required this.task});

  final NovelImportTask task;

  @override
  State<_ImportProgressCard> createState() => _ImportProgressCardState();
}

class _ImportProgressCardState extends State<_ImportProgressCard> {
  final ScrollController _logScrollController = ScrollController();
  bool _showLogs = true;

  @override
  void didUpdateWidget(covariant _ImportProgressCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.task.liveLogs.length != oldWidget.task.liveLogs.length && _showLogs) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final elapsed = task.elapsed.inSeconds;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.accentText.withAlpha(90)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.accentSubtle,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '《${task.novelTitle}》漫剧深度解构流水线 · 正在运行',
                    style: TextStyle(
                      color: context.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.accentText.withAlpha(50)),
                  ),
                  child: Text(
                    task.scopeLabel,
                    style: TextStyle(
                      color: context.accentText,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '已耗时 ${elapsed}s',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 六阶段流水线时间轴节点
                _buildPipelineTimeline(context, task),
                const SizedBox(height: 14),

                // 实时解构资产池
                if (task.discoveredCharacters.isNotEmpty ||
                    task.discoveredScenes.isNotEmpty ||
                    task.plannedSceneCount > 0 ||
                    task.protectedUtteranceCount > 0) ...[
                  _buildDiscoveredAssetsSection(context, task),
                  const SizedBox(height: 14),
                ],

                // 实时执行控制台终端
                _buildConsoleLogSection(context, task),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineTimeline(BuildContext context, NovelImportTask task) {
    final stages = PipelineStage.values;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Row(
        children: [
          for (var i = 0; i < stages.length; i++) ...[
            Expanded(
              child: _buildStageNode(context, stages[i], task),
            ),
            if (i < stages.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: context.textSecondary.withAlpha(80),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildStageNode(
    BuildContext context,
    PipelineStage stage,
    NovelImportTask task,
  ) {
    final status = task.stageStatuses[stage] ?? StageStatus.pending;
    final isCurrent = task.currentStage == stage && status == StageStatus.running;

    Color iconColor;
    Widget statusIcon;
    Color textColor;

    switch (status) {
      case StageStatus.success:
        iconColor = context.successText;
        statusIcon = Icon(Icons.check_circle_rounded, size: 16, color: iconColor);
        textColor = context.textPrimary;
        break;
      case StageStatus.running:
        iconColor = context.accentText;
        statusIcon = SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: iconColor),
        );
        textColor = iconColor;
        break;
      case StageStatus.failed:
        iconColor = context.errorText;
        statusIcon = Icon(Icons.error_outline_rounded, size: 16, color: iconColor);
        textColor = iconColor;
        break;
      case StageStatus.pending:
        iconColor = context.textSecondary.withAlpha(70);
        statusIcon = Icon(Icons.radio_button_unchecked, size: 14, color: iconColor);
        textColor = context.textSecondary;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
      decoration: isCurrent
          ? BoxDecoration(
              color: context.accentSubtle.withAlpha(120),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          statusIcon,
          const SizedBox(height: 4),
          Text(
            stage.label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              color: textColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _stageStatusLabel(stage, status),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: status == StageStatus.running
                  ? iconColor
                  : context.textSecondary.withAlpha(140),
            ),
          ),
        ],
      ),
    );
  }

  String _stageStatusLabel(PipelineStage stage, StageStatus status) {
    switch (status) {
      case StageStatus.pending:
        return '等待中';
      case StageStatus.running:
        return '执行中…';
      case StageStatus.success:
        return '已就绪';
      case StageStatus.failed:
        return '异常';
    }
  }

  Widget _buildDiscoveredAssetsSection(BuildContext context, NovelImportTask task) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 15, color: context.accentText),
              const SizedBox(width: 6),
              Text(
                '实时解构资产池',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const Spacer(),
              if (task.plannedSceneCount > 0)
                _buildMetricChip(context, '戏剧场次', '${task.plannedSceneCount} 幕'),
              if (task.protectedUtteranceCount > 0)
                _buildMetricChip(context, '锁定金句', '${task.protectedUtteranceCount} 条'),
              if (task.auditPassRate > 0)
                _buildMetricChip(
                  context,
                  '门禁质检',
                  '${task.auditPassRate.toStringAsFixed(0)}分',
                  color: context.successText,
                ),
            ],
          ),
          if (task.discoveredCharacters.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    '登场角色:',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: task.discoveredCharacters.map((name) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.accentSubtle,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.accentText.withAlpha(40)),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(fontSize: 11, color: context.textPrimary),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
          if (task.discoveredScenes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    '地标场景:',
                    style: TextStyle(fontSize: 11, color: context.textSecondary),
                  ),
                ),
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: task.discoveredScenes.map((name) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.bgInput,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(fontSize: 11, color: context.textPrimary),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricChip(BuildContext context, String label, String value, {Color? color}) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? context.accentText).withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: (color ?? context.accentText).withAlpha(50)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color ?? context.accentText,
        ),
      ),
    );
  }

  Widget _buildConsoleLogSection(BuildContext context, NovelImportTask task) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF141416),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 终端控制条
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 14, color: Colors.greenAccent),
                const SizedBox(width: 6),
                const Text(
                  '实时流水线控制台',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                Text(
                  '${task.liveLogs.length} 条记录',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.white38,
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => setState(() => _showLogs = !_showLogs),
                  child: Icon(
                    _showLogs ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          if (_showLogs)
            Container(
              height: 120,
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Colors.white10)),
              ),
              child: task.liveLogs.isEmpty
                  ? const Center(
                      child: Text(
                        '等待执行日志输出…',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Colors.white30,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      itemCount: task.liveLogs.length,
                      itemBuilder: (context, index) {
                        final line = task.liveLogs[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            line,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: Color(0xFFB3E5FC),
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}

class _ImportSummaryCard extends StatefulWidget {
  const _ImportSummaryCard({
    required this.task,
    required this.series,
    required this.onViewResult,
    required this.onReimport,
  });

  final NovelImportTask task;
  final StudioSeries? series;
  final VoidCallback onViewResult;
  final VoidCallback onReimport;

  @override
  State<_ImportSummaryCard> createState() => _ImportSummaryCardState();
}

class _ImportSummaryCardState extends State<_ImportSummaryCard> {
  int _charCount = 0;
  int _sceneCount = 0;
  int _epCount = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(covariant _ImportSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.localId != widget.task.localId ||
        oldWidget.series?.id != widget.series?.id) {
      _loadStats();
    }
  }

  Future<void> _loadStats() async {
    final s = widget.series;
    if (s == null) return;
    try {
      final chars = await StudioProjectManager.instance.listCharacters(s.id);
      final scenes = await StudioProjectManager.instance.listScenes(s.id);
      final eps = await StudioProjectManager.instance.listEpisodes(s.id);
      if (mounted) {
        setState(() {
          _charCount = chars.length;
          _sceneCount = scenes.length;
          _epCount = eps.length;
          _loaded = true;
        });
      }
    } catch (_) {}
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final finishTime = task.isTerminalAt ?? task.startedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.successText.withAlpha(70)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 20, color: context.successText),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '《${task.novelTitle}》小说资产解构已就绪',
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '完成于 ${_formatTime(finishTime)} · 耗时 ${task.elapsed.inSeconds}s · 模式：${task.scopeLabel}',
                      style: TextStyle(color: context.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.onViewResult,
                icon: const Icon(Icons.people_outline, size: 15),
                label: const Text('前往 IP 主库查看', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onReimport,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('重新导入', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (_loaded) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _buildStatBadge(context, Icons.movie_outlined, '$_epCount 集分集大纲'),
                _buildStatBadge(context, Icons.person_outline, '$_charCount 个主要角色'),
                _buildStatBadge(context, Icons.landscape_outlined, '$_sceneCount 个常驻场景'),
                if (widget.series?.props.isNotEmpty == true)
                  _buildStatBadge(context, Icons.shield_outlined, '${widget.series!.props.length} 个关键道具'),
                if (task.protectedUtteranceCount > 0)
                  _buildStatBadge(context, Icons.format_quote_rounded, '${task.protectedUtteranceCount} 条锁定金句'),
                if (task.auditPassRate > 0)
                  _buildStatBadge(context, Icons.verified_outlined, '门禁质检 ${task.auditPassRate.toStringAsFixed(0)}分'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatBadge(BuildContext context, IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: context.accentText),
          const SizedBox(width: 5),
          Text(text, style: TextStyle(color: context.accentText, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ImportInterruptedCard extends StatelessWidget {
  const _ImportInterruptedCard({
    required this.task,
    required this.onRetry,
  });

  final NovelImportTask task;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isInterrupted = task.phase == ImportPhase.interrupted;
    final color = isInterrupted ? context.warningText : context.errorText;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isInterrupted ? Icons.pause_circle_outline : Icons.error_outline,
            size: 20,
            color: color,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '《${task.novelTitle}》小说导入${isInterrupted ? '已中断' : '失败'}',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  task.error ?? (isInterrupted ? '工坊窗口关闭导致任务中断' : 'AI 提炼解析失败'),
                  style: TextStyle(color: color, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '模式：${task.scopeLabel} · 可点击右侧重新导入按钮一键重走导入',
                  style: TextStyle(color: context.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('重新导入', style: TextStyle(fontSize: 12)),
          ),
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
