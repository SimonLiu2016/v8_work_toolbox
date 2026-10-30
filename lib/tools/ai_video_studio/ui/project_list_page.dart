/// 剧集库页：所有剧集项目的列表、新建与删除。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/studio_project_manager.dart';
import 'studio_shell.dart';

class ProjectListPage extends StatefulWidget {
  const ProjectListPage({
    super.key,
    required this.session,
    required this.onChanged,
    this.onNavigateStage,
  });

  final StudioSession session;
  final VoidCallback onChanged;
  final void Function(StudioStage stage)? onNavigateStage;

  @override
  State<ProjectListPage> createState() => _ProjectListPageState();
}

class _ProjectListPageState extends State<ProjectListPage> {
  final _manager = StudioProjectManager.instance;
  List<StudioSeries> _series = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.session.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await _manager.listSeries();
    if (!mounted) return;
    setState(() {
      _series = list;
      _loading = false;
    });
    // 首屏默认选中最近改过的那部（listSeries 已按时间倒序）。
    if (widget.session.series == null && list.isNotEmpty) {
      widget.session.select(list.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Text(
                '剧集库',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_series.length} 部',
                style: TextStyle(color: context.textTertiary, fontSize: 13),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _createSeries,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新建剧集'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _series.isEmpty
              ? _buildEmpty(context)
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  itemCount: _series.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _SeriesCard(
                    series: _series[i],
                    selected: widget.session.series?.id == _series[i].id,
                    session: widget.session,
                    onOpen: () => widget.session.select(_series[i]),
                    onDelete: () => _confirmDelete(_series[i]),
                    onRenamed: _load,
                    onNavigateStage: widget.onNavigateStage,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.movie_outlined, size: 48, color: context.textTertiary),
          const SizedBox(height: 12),
          Text(
            '还没有剧集。先从模糊想法开始，AI 会帮你拆成能拍的结构。',
            style: TextStyle(color: context.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _createSeries,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('新建第一部剧集'),
          ),
        ],
      ),
    );
  }

  Future<void> _createSeries() async {
    final result = await showDialog<({String name, StudioProductionType type, String? ipId})>(
      context: context,
      builder: (_) => const NewSeriesDialog(),
    );
    if (result == null) return;
    final series = await _manager.createSeries(
      name: result.name,
      productionType: result.type,
      ipId: result.ipId,
    );
    widget.session.select(series);
    widget.onChanged();
    await _load();
  }

  Future<void> _confirmDelete(StudioSeries series) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('删除《${series.name}》', style: TextStyle(color: context.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本操作将彻底删除该剧集的全部剧本、分镜看板及音视频渲染文件。',
              style: TextStyle(color: context.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.accentSubtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.accentText.withAlpha(60)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 16, color: context.accentText),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '安全保护：关联的【IP 主库】（角色卡、场景库、世界观）与【全局资产库】将完好保留，不受任何影响。',
                      style: TextStyle(color: context.accentText, fontSize: 12, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.errorText),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _manager.deleteSeries(series.id);
    if (widget.session.series?.id == series.id) {
      widget.session.select(null);
    }
    widget.onChanged();
    await _load();
  }
}

class _SeriesCard extends StatefulWidget {
  const _SeriesCard({
    required this.series,
    required this.selected,
    required this.session,
    required this.onOpen,
    required this.onDelete,
    required this.onRenamed,
    this.onNavigateStage,
  });

  final StudioSeries series;
  final bool selected;
  final StudioSession session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final VoidCallback onRenamed;
  final void Function(StudioStage stage)? onNavigateStage;

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  final _manager = StudioProjectManager.instance;
  bool _expanded = false;
  List<StudioEpisode>? _episodes;
  int _cachedEpisodeCount = 0;
  bool _loading = false;
  bool _creating = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _fetchEpisodeCount();
  }

  @override
  void didUpdateWidget(covariant _SeriesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.id != widget.series.id ||
        oldWidget.series.updatedAt != widget.series.updatedAt ||
        oldWidget.series.name != widget.series.name) {
      _fetchEpisodeCount();
      if (_expanded) {
        _loadEpisodes();
      }
    }
  }

  Future<void> _fetchEpisodeCount() async {
    final eps = await _manager.listEpisodes(widget.series.id);
    if (mounted) {
      setState(() {
        _cachedEpisodeCount = eps.length;
        if (_episodes != null) {
          _episodes = eps;
        }
      });
    }
  }

  Future<void> _renameSeries(BuildContext context) async {
    final controller = TextEditingController(text: widget.series.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        title: Text('修改剧集名称', style: TextStyle(color: ctx.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: ctx.textPrimary),
          decoration: InputDecoration(
            labelText: '剧集名称',
            labelStyle: TextStyle(color: ctx.textSecondary),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            final trimmed = val.trim();
            if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newName != null && newName.trim().isNotEmpty && newName.trim() != widget.series.name) {
      final updated = widget.series.copyWith(name: newName.trim());
      await _manager.saveSeries(updated);
      if (widget.session.series?.id == widget.series.id) {
        widget.session.select(updated);
      }
      widget.onRenamed();
    }
  }

  Future<void> _renameEpisode(BuildContext context, StudioEpisode ep) async {
    final controller = TextEditingController(text: ep.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        title: Text('修改分集名称', style: TextStyle(color: ctx.textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: ctx.textPrimary),
          decoration: InputDecoration(
            labelText: '分集名称',
            labelStyle: TextStyle(color: ctx.textSecondary),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (val) {
            final trimmed = val.trim();
            if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(ctx, trimmed);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (newTitle != null && newTitle.trim().isNotEmpty && newTitle.trim() != ep.title) {
      final updated = ep.copyWith(title: newTitle.trim());
      await _manager.saveEpisode(updated);
      await _manager.upsertEpisodeMemory(
        seriesId: widget.series.id,
        episodeId: ep.id,
        title: newTitle.trim(),
      );
      if (widget.session.episode?.id == ep.id) {
        widget.session.updateEpisode(updated);
      }
      if (widget.session.series?.id == widget.series.id) {
        final refreshed = _manager.readSeries(widget.series.id);
        if (refreshed != null) {
          widget.session.updateSeries(refreshed);
        }
      }
      await _loadEpisodes();
    }
  }

  Future<void> _loadEpisodes() async {
    setState(() => _loading = true);
    final eps = await _manager.listEpisodes(widget.series.id);
    if (!mounted) return;
    setState(() {
      _episodes = eps;
      _cachedEpisodeCount = eps.length;
      _loading = false;
    });
  }

  Future<void> _createEpisode() async {
    setState(() => _creating = true);
    try {
      final res = await _manager.createEpisode(seriesId: widget.series.id);
      await _loadEpisodes();
      widget.session.select(widget.series);
      widget.session.selectEpisode(res.episode);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已创建第 ${res.episode.index} 集: ${res.episode.title}'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Future<void> _confirmDeleteLastEpisode() async {
    final eps = _episodes;
    if (eps == null || eps.isEmpty) return;
    final lastEp = eps.last;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        title: Text('删除最后一集（第 ${lastEp.index} 集）', style: TextStyle(color: ctx.textPrimary, fontSize: 16)),
        content: Text(
          '确定删除最后一集《${lastEp.title}》吗？\n\n'
          '该集的分镜、剧本及音视频素材将被彻底清理，剧情记忆库同步移除。此操作不可撤销。',
          style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.errorText),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await _manager.deleteLastEpisode(widget.series.id);
      if (widget.session.episode?.id == lastEp.id) {
        widget.session.selectEpisode(null);
      }
      if (widget.session.series?.id == widget.series.id) {
        final refreshed = _manager.readSeries(widget.series.id);
        if (refreshed != null) widget.session.updateSeries(refreshed);
      }
      await _loadEpisodes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除第 ${lastEp.index} 集: ${lastEp.title}')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _confirmClearAllEpisodes() async {
    final eps = _episodes;
    if (eps == null || eps.isEmpty) return;
    final count = eps.length;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.bgCard,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: ctx.errorText, size: 20),
            const SizedBox(width: 8),
            Text('一键清空全部分集', style: TextStyle(color: ctx.textPrimary, fontSize: 16)),
          ],
        ),
        content: Text(
          '确定清空当前剧集的全部 $count 个分集吗？\n\n'
          '• 将同步清理所有分集对应的剧本、场次、分镜、生成素材及跨集记忆；\n'
          '• IP 主库与角色资产库将完整保留，不受任何影响。\n\n'
          '此操作不可撤销！',
          style: TextStyle(color: ctx.textSecondary, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: ctx.errorText),
            child: const Text('确认全部清空'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    setState(() => _deleting = true);
    try {
      await _manager.clearAllEpisodes(widget.series.id);
      if (widget.session.series?.id == widget.series.id) {
        widget.session.selectEpisode(null);
        final refreshed = _manager.readSeries(widget.series.id);
        if (refreshed != null) widget.session.updateSeries(refreshed);
      }
      await _loadEpisodes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空全部分集（共清理 $count 集）')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && _episodes == null) {
        _loadEpisodes();
      }
    });
  }

  Widget _buildSeasonBadge(BuildContext context) {
    final match = RegExp(r'第\s*(\d+)\s*季').firstMatch(widget.series.name);
    final seasonText = match != null ? '第 ${match.group(1)} 季' : null;
    final badgeLabel = seasonText != null
        ? '$seasonText · $_cachedEpisodeCount 集'
        : '共 $_cachedEpisodeCount 集';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: context.accentText.withValues(alpha: 0.3)),
      ),
      child: Text(
        badgeLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: context.accentText,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.selected ? context.bgSelected : context.bgCard,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(
          color: widget.selected ? context.accentText : context.borderSubtle,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: widget.onOpen,
            borderRadius: AppTheme.borderRadiusSmall,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: context.accentSubtle,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.movie_outlined, color: context.accentText),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.series.name,
                                style: TextStyle(
                                  color: context.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.edit_outlined, size: 15, color: context.textTertiary),
                              tooltip: '修改剧集名称',
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              padding: EdgeInsets.zero,
                              onPressed: () => _renameSeries(context),
                            ),
                            const SizedBox(width: 6),
                            _TypeBadge(type: widget.series.productionType),
                            const SizedBox(width: 6),
                            _buildSeasonBadge(context),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_cachedEpisodeCount 集 · ${widget.series.memories.length} 个剧情记忆 · 更新于 '
                          '${_formatDate(widget.series.updatedAt)}',
                          style: TextStyle(
                            color: context.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                        if (widget.series.worldview.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            widget.series.worldview.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _toggleExpand,
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: context.textSecondary,
                    ),
                    tooltip: _expanded ? '收起分集' : '展开分集',
                  ),
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: context.textTertiary,
                      size: 18,
                    ),
                    tooltip: '删除',
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, color: context.borderSubtle),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              color: context.bgWindow.withAlpha(80),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.video_library_outlined, size: 15, color: context.accentText),
                      const SizedBox(width: 6),
                      Text(
                        '分集列表 (${_episodes?.length ?? 0} 集)',
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: _creating ? null : _createEpisode,
                        icon: _creating
                            ? const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.add, size: 14),
                        label: Text(
                          _creating
                              ? '创建中…'
                              : '新建第 ${(_episodes?.length ?? 0) + 1} 集',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: (_episodes == null || _episodes!.isEmpty || _creating || _deleting)
                            ? null
                            : _confirmDeleteLastEpisode,
                        icon: const Icon(Icons.undo, size: 14),
                        label: const Text('删除最后一集', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: (_episodes == null || _episodes!.isEmpty || _creating || _deleting)
                              ? null
                              : context.errorText,
                          side: BorderSide(
                            color: (_episodes == null || _episodes!.isEmpty || _creating || _deleting)
                                ? context.borderSubtle
                                : context.errorText.withAlpha(140),
                          ),
                        ),
                        onPressed: (_episodes == null || _episodes!.isEmpty || _creating || _deleting)
                            ? null
                            : _confirmClearAllEpisodes,
                        icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                        label: const Text('一键清空', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else if (_episodes == null || _episodes!.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.bgCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Text(
                        '暂无分集，请点击右上角「新建第 1 集」开始策划分镜',
                        style: TextStyle(color: context.textTertiary, fontSize: 12),
                      ),
                    )
                  else
                    for (final ep in _episodes!)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: widget.session.episode?.id == ep.id
                              ? context.bgSelected
                              : context.bgCard,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: widget.session.episode?.id == ep.id
                                ? context.accentText.withAlpha(120)
                                : context.borderSubtle,
                          ),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '第 ${ep.index} 集: ${ep.title}',
                                  style: TextStyle(
                                    color: context.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(
                                  Icons.edit_outlined,
                                  size: 14,
                                  color: context.textTertiary,
                                ),
                                tooltip: '修改分集名称',
                                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                padding: EdgeInsets.zero,
                                onPressed: () => _renameEpisode(context, ep),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            ep.synopsis.isEmpty
                                ? '${ep.shots.length} 个分镜'
                                : '${ep.shots.length} 个分镜 · ${ep.synopsis}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: context.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '进入看板',
                                style: TextStyle(
                                  color: context.accentText,
                                  fontSize: 11,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: context.accentText,
                              ),
                            ],
                          ),
                          onTap: () {
                            widget.session.select(widget.series);
                            widget.session.selectEpisode(ep);
                            widget.onNavigateStage?.call(StudioStage.storyboard);
                          },
                        ),
                      ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-'
      '${t.day.toString().padLeft(2, '0')}';
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.type});

  final StudioProductionType type;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: context.accentSubtle,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.label,
        style: TextStyle(color: context.accentText, fontSize: 10),
      ),
    );
  }
}

/// 新建剧集对话框：名称 + 三选一制作类型（每型带说明，spec 9.3）。
class NewSeriesDialog extends StatefulWidget {
  const NewSeriesDialog({super.key});

  @override
  State<NewSeriesDialog> createState() => _NewSeriesDialogState();
}

class _NewSeriesDialogState extends State<NewSeriesDialog> {
  final _nameController = TextEditingController();
  StudioProductionType _type = StudioProductionType.drama;
  final _manager = StudioProjectManager.instance;
  List<StudioSeries> _availableIps = const [];
  String? _selectedIpId;

  @override
  void initState() {
    super.initState();
    _loadIps();
  }

  Future<void> _loadIps() async {
    final ips = await _manager.listAvailableIps();
    if (!mounted) return;
    setState(() => _availableIps = ips);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('新建剧集项目', style: TextStyle(color: context.textPrimary)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(color: context.textPrimary),
              decoration: InputDecoration(
                labelText: '剧集名称',
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: '例如：雨夜回声',
                hintStyle: TextStyle(color: context.textDisabled),
              ),
            ),
            if (_availableIps.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '关联已有 IP 企划（可选）',
                style: TextStyle(
                  color: context.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String?>(
                initialValue: _selectedIpId,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                dropdownColor: context.bgCard,
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text('不关联（独立新建全新 IP）', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                  ),
                  for (final ip in _availableIps)
                    DropdownMenuItem(
                      value: ip.id,
                      child: Text('继承 IP: ${ip.name}', style: TextStyle(color: context.textPrimary, fontSize: 13)),
                    ),
                ],
                onChanged: (v) => setState(() => _selectedIpId = v),
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '制作类型',
              style: TextStyle(
                color: context.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            RadioGroup<StudioProductionType>(
              groupValue: _type,
              onChanged: (v) {
                if (v != null) setState(() => _type = v);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final type in StudioProductionType.values)
                    RadioListTile<StudioProductionType>(
                      value: type,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: context.accentText,
                      title: Text(
                        type.label,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        type.description,
                        style: TextStyle(
                          color: context.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            name: _nameController.text,
            type: _type,
            ipId: _selectedIpId,
          )),
          child: const Text('创建'),
        ),
      ],
    );
  }
}
