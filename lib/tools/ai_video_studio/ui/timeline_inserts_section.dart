import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/studio_models.dart';
import '../services/asset_library.dart';
import '../services/studio_project_manager.dart';
import 'asset_picker_dialog.dart';

/// 合成时间轴上的资产片段插入区。
///
/// 与角色/场景参考图共用 [AssetPickerDialog]，但这里的语义不同：选进来的
/// 不是"参考"，是"时间轴上的一段正片"。所以插入要记位置（哪个镜号之后），
/// 而不只是记资产 id。
///
/// **位置语义**：`afterShotNumber` = 插在这个镜号之后，0 = 最前面。
class TimelineInsertsSection extends StatefulWidget {
  const TimelineInsertsSection({
    super.key,
    required this.episode,
    required this.onChanged,
  });

  final StudioEpisode? episode;
  final VoidCallback onChanged;

  @override
  State<TimelineInsertsSection> createState() =>
      _TimelineInsertsSectionState();
}

class _TimelineInsertsSectionState extends State<TimelineInsertsSection> {
  final _manager = StudioProjectManager.instance;

  @override
  Widget build(BuildContext context) {
    final episode = widget.episode;
    if (episode == null) return const SizedBox.shrink();

    final inserts = episode.timelineInserts;

    return Container(
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
              Icon(Icons.timeline_outlined,
                  size: 15, color: context.textSecondary),
              const SizedBox(width: 6),
              Text(
                '时间轴素材插入',
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '从资产库选片段插到某个分镜之后。分镜顺序不变——'
                  '插入是剪辑决策，不是改剧本。',
                  style: TextStyle(
                    color: context.textTertiary,
                    fontSize: 10,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _pickAndInsert,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('插入片段', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          if (inserts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '还没有插入。合成与剪映导出都会按这里的配置展开时间轴。',
                style: TextStyle(color: context.textTertiary, fontSize: 10),
              ),
            )
          else
            ...inserts.asMap().entries.map(
                  (e) => _InsertRow(
                    index: e.key,
                    insert: e.value,
                    episode: episode,
                    onRemoved: widget.onChanged,
                  ),
                ),
        ],
      ),
    );
  }

  Future<void> _pickAndInsert() async {
    final episode = widget.episode;
    if (episode == null) return;
    // 预载索引：选择器读的是内存态。
    await AssetLibrary.instance.ensureLoaded();
    if (!mounted) return;

    final asset = await AssetPickerDialog.show(
      context,
      kind: AssetKind.clip,
      title: '选择要插入的视频片段',
    );
    if (asset == null || !mounted) return;

    // 问插在哪：默认最后一个有视频的镜号之后——那是最常见的心智
    // （"加在片子结尾"）。给一个可改的输入而不是只能接受默认。
    final defaultAfter = episode.shots.isEmpty
        ? 0
        : episode.shots.last.number;
    final chosen = await _askPosition(
      context,
      defaultAfter,
      episode.shots,
    );
    if (chosen == null || !mounted) return;

    final updated = episode.copyWith(
      timelineInserts: [
        ...episode.timelineInserts,
        StudioTimelineInsert(assetId: asset.id, afterShotNumber: chosen),
      ],
    );
    await _manager.saveEpisode(updated);
    widget.onChanged();
  }

  /// 询问插入位置。返回镜号；取消返回 null。
  static Future<int?> _askPosition(
    BuildContext context,
    int defaultAfter,
    List<StudioShot> shots,
  ) async {
    var value = defaultAfter;
    return showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: context.bgCard,
          title: const Text('插到哪个分镜之后？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '0 表示最前面。分镜本身的顺序不会被改变。',
                style: TextStyle(
                  color: context.textTertiary,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int>(
                initialValue: value,
                decoration: const InputDecoration(labelText: '插入位置'),
                items: [
                  const DropdownMenuItem(value: 0, child: Text('最前面（0）')),
                  // shots 由调用方传入。曾经想用 findAncestorStateOfType
                  // 从弹窗 context 往上找 section State——那是行不通的，
                  // 弹窗跑在独立路由里，找不到会静默返回 null，下拉就只剩
                  // "最前面"一项，而没有任何报错。
                  for (final shot in shots)
                    DropdownMenuItem(
                      value: shot.number,
                      child: Text('分镜 ${shot.number} 之后'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => value = v);
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
              onPressed: () => Navigator.pop(ctx, value),
              child: const Text('插入'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InsertRow extends StatelessWidget {
  const _InsertRow({
    required this.index,
    required this.insert,
    required this.episode,
    required this.onRemoved,
  });

  final int index;
  final StudioTimelineInsert insert;
  final StudioEpisode episode;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    final manager = StudioProjectManager.instance;
    final asset = AssetLibrary.instance.assetSync(insert.assetId);
    final missing = asset == null || !asset.file.existsSync();

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            missing ? Icons.error_outline : Icons.video_library_outlined,
            size: 14,
            color: missing ? context.errorText : context.textSecondary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              missing
                  ? '资产 ${insert.assetId} 已丢失'
                  : '${insert.afterShotNumber == 0 ? '最前面' : '分镜 ${insert.afterShotNumber} 之后'}'
                        ' · ${asset.id}'
                        ' · ${(asset.durationSec ?? 5).toStringAsFixed(0)}s',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: missing ? context.errorText : context.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: '移除插入',
            icon: const Icon(Icons.close, size: 14),
            onPressed: () async {
              // 按 index 删，不用 identical 比对象：const 实例的规范化
              // 行为不该成为删除正确性的依赖——两条字段相同的插入
              // 删错一条是可能的。
              final list = episode.timelineInserts.toList();
              if (index >= 0 && index < list.length) {
                list.removeAt(index);
              }
              final updated = episode.copyWith(timelineInserts: list);
              await manager.saveEpisode(updated);
              onRemoved();
            },
          ),
        ],
      ),
    );
  }
}
