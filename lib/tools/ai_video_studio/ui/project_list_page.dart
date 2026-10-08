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
    _load();
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
    final result = await showDialog<({String name, StudioProductionType type})>(
      context: context,
      builder: (_) => const NewSeriesDialog(),
    );
    if (result == null) return;
    final series = await _manager.createSeries(
      name: result.name,
      productionType: result.type,
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
        content: Text(
          '将删除该剧的全部素材、角色卡与分镜，且无法恢复。',
          style: TextStyle(color: context.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: context.errorText),
            child: const Text('删除'),
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
    this.onNavigateStage,
  });

  final StudioSeries series;
  final bool selected;
  final StudioSession session;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final void Function(StudioStage stage)? onNavigateStage;

  @override
  State<_SeriesCard> createState() => _SeriesCardState();
}

class _SeriesCardState extends State<_SeriesCard> {
  final _manager = StudioProjectManager.instance;
  bool _expanded = false;
  List<StudioEpisode>? _episodes;
  bool _loading = false;
  bool _creating = false;

  Future<void> _loadEpisodes() async {
    setState(() => _loading = true);
    final eps = await _manager.listEpisodes(widget.series.id);
    if (!mounted) return;
    setState(() {
      _episodes = eps;
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

  void _toggleExpand() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && _episodes == null) {
        _loadEpisodes();
      }
    });
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
                            Text(
                              widget.series.name,
                              style: TextStyle(
                                color: context.textPrimary,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _TypeBadge(type: widget.series.productionType),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.series.memories.length} 个前情记录 · 更新于 '
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
                          title: Text(
                            '第 ${ep.index} 集: ${ep.title}',
                            style: TextStyle(
                              color: context.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
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
          )),
          child: const Text('创建'),
        ),
      ],
    );
  }
}
