import 'package:flutter/material.dart';
import '../../novel_manager/models/novel_models.dart';
import '../../novel_manager/services/novel_repository.dart';

/// 从小说库选择小说或具体章节的选择结果
class NovelSelectionResult {
  final NovelMetadata novel;
  final List<int> selectedChapterIndices; // 若为空则代表整书
  final String combinedText; // 提取合并后的文本 (若为空则由后台任务异步流式读取)
  final bool isFullSeason; // 全季解构 vs 单集扩写
  final int targetEpisodeIndex; // 目标集数序号

  const NovelSelectionResult({
    required this.novel,
    required this.selectedChapterIndices,
    this.combinedText = '',
    this.isFullSeason = true,
    this.targetEpisodeIndex = 1,
  });

  bool get isFullBook => selectedChapterIndices.isEmpty;

  /// 异步读取所选章节并合并为正文（若 combinedText 已有则直接返回，否则向 NovelRepository 批量提取）
  Future<String> loadCombinedText() async {
    if (combinedText.trim().isNotEmpty) return combinedText;
    if (novel.id.isEmpty) return '';

    final repo = NovelRepository.instance;
    var indices = selectedChapterIndices;
    if (indices.isEmpty) {
      final chs = await repo.getChapterIndices(novel.id);
      indices = chs.map((c) => c.chapterIndex).toList();
    }

    final sortedIndices = indices.toList()..sort();
    final sb = StringBuffer();
    for (final idx in sortedIndices) {
      final ch = await repo.getChapter(novel.id, idx);
      if (ch != null && ch.content.trim().isNotEmpty) {
        sb.writeln('=== ${ch.title} ===');
        sb.writeln(ch.content.trim());
        sb.writeln();
      }
    }
    return sb.toString().trim();
  }
}

/// 供“AI短视频工坊”引用的“从小说库选择”弹窗
class NovelSelectorDialog extends StatefulWidget {
  const NovelSelectorDialog({
    super.key,
    this.initialTargetEpisodeIndex = 1,
    this.initialIsFullSeason = true,
  });

  final int initialTargetEpisodeIndex;
  final bool initialIsFullSeason;

  @override
  State<NovelSelectorDialog> createState() => _NovelSelectorDialogState();
}

class _NovelSelectorDialogState extends State<NovelSelectorDialog> {
  final NovelRepository _repo = NovelRepository.instance;

  List<NovelMetadata> _novels = [];
  bool _isLoadingNovels = true;
  String _searchQuery = '';

  NovelMetadata? _selectedNovel;
  List<NovelChapterIndex> _chapters = [];
  bool _isLoadingChapters = false;

  final Set<int> _selectedIndices = {}; // 勾选的章节序号集合
  bool _isSelectingFullBook = true;
  late bool _isFullSeason;
  late int _targetEpisodeIndex;

  @override
  void initState() {
    super.initState();
    _isFullSeason = widget.initialIsFullSeason;
    _targetEpisodeIndex = widget.initialTargetEpisodeIndex;
    _loadNovels();
  }

  Future<void> _loadNovels() async {
    setState(() => _isLoadingNovels = true);
    final list = await _repo.getNovels(query: _searchQuery);
    if (mounted) {
      setState(() {
        _novels = list;
        _isLoadingNovels = false;
        if (list.isNotEmpty && _selectedNovel == null) {
          _selectNovel(list.first);
        }
      });
    }
  }

  Future<void> _selectNovel(NovelMetadata novel) async {
    setState(() {
      _selectedNovel = novel;
      _isLoadingChapters = true;
      _selectedIndices.clear();
      _isSelectingFullBook = true;
    });

    final chs = await _repo.getChapterIndices(novel.id);
    if (mounted) {
      setState(() {
        _chapters = chs;
        _isLoadingChapters = false;
      });
    }
  }

  void _confirmSelection() {
    final novel = _selectedNovel;
    if (novel == null) return;

    final targetIndices = _isSelectingFullBook
        ? (_chapters.isNotEmpty
            ? _chapters.map((c) => c.chapterIndex).toList()
            : <int>[])
        : (_selectedIndices.toList()..sort());

    if (!_isSelectingFullBook && targetIndices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('按章节引用时，请至少在列表中勾选一个章节')),
      );
      return;
    }

    // 立即秒关弹窗，将文本读取与解构全权移交至后台任务流式处理，杜绝界面死等转圈
    Navigator.of(context).pop(NovelSelectionResult(
      novel: novel,
      selectedChapterIndices: targetIndices,
      combinedText: '',
      isFullSeason: _isFullSeason,
      targetEpisodeIndex: _targetEpisodeIndex,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 860,
        height: 600,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部标题
            Row(
              children: [
                const Icon(Icons.auto_stories, color: Colors.blueAccent),
                const SizedBox(width: 8),
                const Text(
                  '从本地小说库引用资产',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // 主体左右分栏
            Expanded(
              child: Row(
                children: [
                  // 左栏：小说列表与搜索
                  SizedBox(
                    width: 300,
                    child: Column(
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            hintText: '搜索书名、作者...',
                            prefixIcon: const Icon(Icons.search, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onChanged: (val) {
                            _searchQuery = val;
                            _loadNovels();
                          },
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: _isLoadingNovels
                              ? const Center(child: CircularProgressIndicator())
                              : _novels.isEmpty
                                  ? const Center(child: Text('小说库暂无数据\n请在小说管理器中导入或采集', textAlign: TextAlign.center))
                                  : ListView.builder(
                                      itemCount: _novels.length,
                                      itemBuilder: (ctx, i) {
                                        final n = _novels[i];
                                        final isSelected = n.id == _selectedNovel?.id;
                                        return ListTile(
                                          dense: true,
                                          selected: isSelected,
                                          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                                          subtitle: Text('${n.author} • ${n.totalChapters} 章'),
                                          onTap: () => _selectNovel(n),
                                        );
                                      },
                                    ),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 24),

                  // 右栏：选中小说的章节与引用方式选择
                  Expanded(
                    child: _selectedNovel == null
                        ? const Center(child: Text('请在左侧选择一部小说'))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 选中小说的概要信息
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedNovel!.title,
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '作者: ${_selectedNovel!.author} | 总字数: ${_selectedNovel!.totalWordCount} 字',
                                      style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12),
                                    ),
                                    if (_selectedNovel!.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _selectedNovel!.description,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),

                              // 剧本工程范围与集号配置
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        const Text('制作模式: ', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                        ChoiceChip(
                                          label: const Text('全季解构 (全书大纲与资产)'),
                                          selected: _isFullSeason,
                                          visualDensity: VisualDensity.compact,
                                          onSelected: (v) => setState(() {
                                            _isFullSeason = true;
                                            _isSelectingFullBook = true;
                                          }),
                                        ),
                                        ChoiceChip(
                                          label: const Text('单集扩写 (场次节拍与分镜)'),
                                          selected: !_isFullSeason,
                                          visualDensity: VisualDensity.compact,
                                          onSelected: (v) => setState(() {
                                            _isFullSeason = false;
                                            _isSelectingFullBook = false;
                                          }),
                                        ),
                                      ],
                                    ),
                                    if (!_isFullSeason) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Text('目标注入集号: ', style: TextStyle(fontSize: 12)),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 80,
                                            height: 32,
                                            child: TextFormField(
                                              initialValue: '$_targetEpisodeIndex',
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                prefixText: '第 ',
                                                suffixText: ' 集',
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                              ),
                                              onChanged: (val) {
                                                final num = int.tryParse(val.trim());
                                                if (num != null && num > 0) {
                                                  _targetEpisodeIndex = num;
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '将所选章节的高潮剧情精细化提炼并注入对应分集',
                                            style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 11),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),

                              // 章节选取范围
                              Row(
                                children: [
                                  ChoiceChip(
                                    label: const Text('整书全文'),
                                    selected: _isSelectingFullBook,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (v) => setState(() => _isSelectingFullBook = true),
                                  ),
                                  const SizedBox(width: 8),
                                  ChoiceChip(
                                    label: Text('按章节自选 (${_selectedIndices.length} / ${_chapters.length} 章)'),
                                    selected: !_isSelectingFullBook,
                                    visualDensity: VisualDensity.compact,
                                    onSelected: (v) => setState(() => _isSelectingFullBook = false),
                                  ),
                                  const Spacer(),
                                  if (!_isSelectingFullBook) ...[
                                    TextButton(
                                      onPressed: () => setState(() => _selectedIndices.addAll(_chapters.map((c) => c.chapterIndex))),
                                      child: const Text('全选', style: TextStyle(fontSize: 12)),
                                    ),
                                    TextButton(
                                      onPressed: () => setState(() => _selectedIndices.clear()),
                                      child: const Text('清空', style: TextStyle(fontSize: 12)),
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 8),

                              // 章节列表
                              Expanded(
                                child: _isLoadingChapters
                                    ? const Center(child: CircularProgressIndicator())
                                    : Opacity(
                                        opacity: _isSelectingFullBook ? 0.5 : 1.0,
                                        child: ListView.builder(
                                          itemCount: _chapters.length,
                                          itemBuilder: (ctx, i) {
                                            final ch = _chapters[i];
                                            final isChecked = _selectedIndices.contains(ch.chapterIndex);
                                            return CheckboxListTile(
                                              dense: true,
                                              value: _isSelectingFullBook ? true : isChecked,
                                              title: Text(ch.title),
                                              subtitle: Text('${ch.wordCount} 字'),
                                              onChanged: _isSelectingFullBook
                                                  ? null
                                                  : (val) {
                                                      setState(() {
                                                        if (val == true) {
                                                          _selectedIndices.add(ch.chapterIndex);
                                                        } else {
                                                          _selectedIndices.remove(ch.chapterIndex);
                                                        }
                                                      });
                                                    },
                                            );
                                          },
                                        ),
                                      ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),

            // 底部操作按钮
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('确认引用并注入短视频工坊'),
                  onPressed: _selectedNovel == null ? null : _confirmSelection,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
