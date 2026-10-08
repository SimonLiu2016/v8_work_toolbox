/// 创意孵化面板：模糊想法 → 3 个结构化故事方向（spec 10.1 / 10.2 / 10.3）。
///
/// 支持「全剧主线孵化」与「单集续写扩写」双模式，支持创意方案持久化与全量抽屉编辑。
library;

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

  @override
  void initState() {
    super.initState();
    _loadHistoryAndEpisodes();
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
                onPressed: _running ? null : _generate,
                icon: _running
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(_running ? '生成中…' : '生成创意方向'),
              ),
            ],
          ),
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
