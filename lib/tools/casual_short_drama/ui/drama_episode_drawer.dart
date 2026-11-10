import 'package:flutter/material.dart';
import '../services/casual_short_drama_controller.dart';

/// 短剧选集抽屉面板
/// 支持分段切换集数、当前播放高亮及批量离线下载
class DramaEpisodeDrawer extends StatefulWidget {
  final CasualShortDramaController controller;
  final VoidCallback onClose;

  const DramaEpisodeDrawer({
    super.key,
    required this.controller,
    required this.onClose,
  });

  @override
  State<DramaEpisodeDrawer> createState() => _DramaEpisodeDrawerState();
}

class _DramaEpisodeDrawerState extends State<DramaEpisodeDrawer> {
  int _selectedTabRange = 0; // 0: 1-30, 1: 31-60, ...
  static const int _rangeSize = 30;

  @override
  void initState() {
    super.initState();
    final curEp = widget.controller.currentEp;
    _selectedTabRange = (curEp - 1) ~/ _rangeSize;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final drama = widget.controller.currentDrama;
    final totalEpisodes = drama?.totalEpisodes != null && drama!.totalEpisodes > 0
        ? drama.totalEpisodes
        : (drama?.episodes.length ?? 0);

    final rangeCount = (totalEpisodes / _rangeSize).ceil().clamp(1, 99);

    return Container(
      width: 340,
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        '剧集选集',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        '共 $totalEpisodes 集 · 纯本地私密记录',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.download_rounded),
                  tooltip: '批量下载整剧或多集',
                  onPressed: () => _showBatchDownloadDialog(context, totalEpisodes),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭选集抽屉',
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),

          // 分段 Tab (如果集数超过 30 集)
          if (rangeCount > 1)
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: rangeCount,
                itemBuilder: (context, idx) {
                  final start = idx * _rangeSize + 1;
                  final end = ((idx + 1) * _rangeSize).clamp(1, totalEpisodes);
                  final isSelected = _selectedTabRange == idx;

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: ChoiceChip(
                      label: Text('$start-$end'),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) setState(() => _selectedTabRange = idx);
                      },
                    ),
                  );
                },
              ),
            ),

          // 集数网格列表
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.15,
              ),
              itemCount: _calculateCurrentRangeCount(totalEpisodes),
              itemBuilder: (context, index) {
                final epNum = _selectedTabRange * _rangeSize + index + 1;
                final isCurrent = widget.controller.currentEp == epNum;

                return InkWell(
                  onTap: () {
                    widget.controller.playEpisode(epNum);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (isCurrent) ...[
                          const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 2),
                        ],
                        Text(
                          epNum.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent
                                ? theme.colorScheme.onPrimary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
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

  int _calculateCurrentRangeCount(int total) {
    final start = _selectedTabRange * _rangeSize + 1;
    if (start > total) return 0;
    final end = ((_selectedTabRange + 1) * _rangeSize).clamp(1, total);
    return end - start + 1;
  }

  void _showBatchDownloadDialog(BuildContext context, int total) {
    int start = 1;
    int end = total.clamp(1, 20);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('批量下载至私密库'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('选择需要下载的集数范围：', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('从第 '),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true),
                          controller: TextEditingController(text: start.toString()),
                          onChanged: (val) {
                            start = int.tryParse(val) ?? 1;
                          },
                        ),
                      ),
                      const Text(' 集 至第 '),
                      SizedBox(
                        width: 50,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(isDense: true),
                          controller: TextEditingController(text: end.toString()),
                          onChanged: (val) {
                            end = int.tryParse(val) ?? total;
                          },
                        ),
                      ),
                      const Text(' 集'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '总集数: $total 集（短剧将下载保存至本地私密隔离空间）',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final safeStart = start.clamp(1, total);
                    final safeEnd = end.clamp(safeStart, total);
                    final list = List.generate(safeEnd - safeStart + 1, (i) => safeStart + i);
                    final tasks = await widget.controller.downloadEpisodes(list);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('已添加 ${tasks.length} 集到私密下载队列')),
                      );
                    }
                  },
                  child: const Text('加入下载队列'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
