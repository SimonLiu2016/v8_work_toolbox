import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../novel_manager/models/novel_models.dart';
import '../../novel_manager/services/novel_repository.dart';
import '../models/studio_models.dart';
import '../services/studio_project_manager.dart';

/// 小说正文影视化改编的提取结果
class ScreenplayNovelAdaptResult {
  /// 用于剧本改编的小说完整文本（多章拼接或直接粘贴的文本）
  final String novelText;

  /// 章节标题或本集主题简要
  final String? chapterTitle;

  /// 所属小说 ID（若来源为本地小说库）
  final String? novelId;

  /// 选取的章节序号列表
  final List<int> selectedChapterIndices;

  const ScreenplayNovelAdaptResult({
    required this.novelText,
    this.chapterTitle,
    this.novelId,
    this.selectedChapterIndices = const [],
  });
}

/// 剧本工作台「从小说正文生成剧本」双通道弹窗
class ScreenplayNovelAdaptDialog extends StatefulWidget {
  const ScreenplayNovelAdaptDialog({
    super.key,
    required this.series,
    required this.episodeIndex,
    this.targetChapterRange = '',
    this.targetChapterIndices = const [],
    this.onSeriesUpdated,
  });

  final StudioSeries series;
  final int episodeIndex;
  final String targetChapterRange;
  final List<int> targetChapterIndices;
  final ValueChanged<StudioSeries>? onSeriesUpdated;

  @override
  State<ScreenplayNovelAdaptDialog> createState() =>
      _ScreenplayNovelAdaptDialogState();
}

class _ScreenplayNovelAdaptDialogState extends State<ScreenplayNovelAdaptDialog>
    with SingleTickerProviderStateMixin {
  final NovelRepository _repo = NovelRepository.instance;
  late TabController _tabController;

  // 通道 A：小说库状态
  NovelMetadata? _boundNovel;
  List<NovelChapterIndex> _chapters = [];
  final Set<int> _selectedChapterIndices = {};
  bool _isLoadingNovel = false;
  bool _isReadingText = false;

  // 通道 B：自由粘贴状态
  final TextEditingController _pasteTextController = TextEditingController();
  final TextEditingController _customTitleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _pasteTextController.addListener(() => setState(() {}));
    _initNovelChannel();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pasteTextController.dispose();
    _customTitleController.dispose();
    super.dispose();
  }

  Future<void> _initNovelChannel() async {
    final novelId = widget.series.novelId;
    if (novelId != null && novelId.isNotEmpty) {
      await _loadNovelById(novelId);
    }
  }

  Future<void> _loadNovelById(String novelId) async {
    setState(() => _isLoadingNovel = true);
    try {
      final novel = await _repo.getNovel(novelId);
      final chapters = await _repo.getChapterIndices(novelId);
      if (mounted) {
        setState(() {
          _boundNovel = novel;
          _chapters = chapters;
          _isLoadingNovel = false;
          // 默认自动勾选研讨室规划对应的章节，若无则勾选与当前集序号相匹配的章节
          if (_selectedChapterIndices.isEmpty) {
            if (widget.targetChapterIndices.isNotEmpty) {
              final validIndices = widget.targetChapterIndices
                  .where((idx) => chapters.any((c) => c.chapterIndex == idx));
              _selectedChapterIndices.addAll(validIndices);
            }
            if (_selectedChapterIndices.isEmpty) {
              final match = chapters.any((c) => c.chapterIndex == widget.episodeIndex);
              if (match) {
                _selectedChapterIndices.add(widget.episodeIndex);
              } else if (chapters.isNotEmpty) {
                _selectedChapterIndices.add(chapters.first.chapterIndex);
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingNovel = false);
      }
    }
  }

  Future<void> _pickAndBindNovel() async {
    final novels = await _repo.getNovels();
    if (!mounted) return;

    if (novels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('本地小说库暂无已入库的小说，请先在小说管理器中导入或采集小说')),
      );
      return;
    }

    final chosen = await showDialog<NovelMetadata>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.library_books, size: 20),
              SizedBox(width: 8),
              Text('选择要关联的小说', style: TextStyle(fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 480,
            height: 380,
            child: ListView.separated(
              itemCount: novels.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final n = novels[i];
                return ListTile(
                  title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '作者: ${n.author.isNotEmpty ? n.author : "未知"} · 共 ${n.totalChapters} 章 · ${n.totalWordCount} 字',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 18),
                  onTap: () => Navigator.of(ctx).pop(n),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );

    if (chosen != null && mounted) {
      final updatedSeries = widget.series.copyWith(novelId: chosen.id);
      await StudioProjectManager.instance.saveSeries(updatedSeries);
      widget.onSeriesUpdated?.call(updatedSeries);
      await _loadNovelById(chosen.id);
    }
  }

  int get _selectedChannelAWordCount {
    var count = 0;
    for (final c in _chapters) {
      if (_selectedChapterIndices.contains(c.chapterIndex)) {
        count += c.wordCount;
      }
    }
    return count;
  }

  Widget _buildWordCountBadge(BuildContext context, int wordCount) {
    if (wordCount == 0) return const SizedBox.shrink();

    Color color;
    IconData icon;
    String tip;

    if (wordCount >= 3000 && wordCount <= 8000) {
      color = Colors.green;
      icon = Icons.check_circle_outline;
      tip = '黄金精读区间（3,000~8,000 字），最适合单集深度影视化改编，细节与张力饱满！';
    } else if (wordCount < 3000) {
      color = Colors.blue;
      icon = Icons.info_outline;
      tip = '篇幅较精炼（$wordCount 字），AI 将强化环境细节、心理潜台词与微表情。';
    } else if (wordCount <= 12000) {
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
      tip = '剧情信息量较大（$wordCount 字），AI 将进行紧凑剪裁，聚焦核心冲突。';
    } else {
      color = Colors.redAccent;
      icon = Icons.error_outline;
      tip = '字数超出 12,000 字上限！强烈建议减少勾选章节并拆分为多集，避免 AI 遗漏重要情节或截断。';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前已选 $wordCount 字 · $tip',
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelA(BuildContext context) {
    if (_isLoadingNovel) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_boundNovel == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined, size: 54, color: context.textTertiary),
              const SizedBox(height: 16),
              Text(
                '当前剧集尚未关联本地小说库中的作品',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '关联后，剧本工作台可直接读取原著章节目录与正文，无缝改编为影视分场剧本。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: context.textSecondary),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _pickAndBindNovel,
                icon: const Icon(Icons.link, size: 16),
                label: const Text('从本地小说库挑选作品关联'),
              ),
            ],
          ),
        ),
      );
    }

    final novel = _boundNovel!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部小说绑定卡片
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: context.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(Icons.book, size: 20, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      novel.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '作者: ${novel.author.isNotEmpty ? novel.author : "未知"} · 总字数: ${novel.totalWordCount} 字 · 共 ${_chapters.length} 章',
                      style: TextStyle(fontSize: 12, color: context.textSecondary),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickAndBindNovel,
                icon: const Icon(Icons.swap_horiz, size: 14),
                label: const Text('更换小说', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        if (widget.targetChapterIndices.isNotEmpty || widget.targetChapterRange.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '编剧研讨室推荐章节：第 ${widget.targetChapterRange.isNotEmpty ? widget.targetChapterRange : widget.targetChapterIndices.join(', ')} 章（已自动为您预选）',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.teal,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedChapterIndices.clear();
                      _selectedChapterIndices.addAll(widget.targetChapterIndices);
                    });
                  },
                  child: const Text('重设为推荐', style: TextStyle(fontSize: 11, color: Colors.teal)),
                ),
              ],
            ),
          ),

        // 快捷勾选工具栏
        Row(
          children: [
            Text(
              '请勾选本集改编所对应的章节：',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textSecondary,
              ),
            ),
            const Spacer(),
            if (widget.targetChapterIndices.length > 1) ...[
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedChapterIndices.clear();
                    _selectedChapterIndices.addAll(widget.targetChapterIndices);
                  });
                },
                icon: const Icon(Icons.bookmarks_outlined, size: 14),
                label: Text(
                  '选推荐章节 (${widget.targetChapterIndices.length}章)',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 4),
            ],
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedChapterIndices.clear();
                  if (_chapters.any((c) => c.chapterIndex == widget.episodeIndex)) {
                    _selectedChapterIndices.add(widget.episodeIndex);
                  }
                });
              },
              icon: const Icon(Icons.adjust, size: 14),
              label: Text(
                '仅选第 ${widget.episodeIndex} 章',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                setState(() => _selectedChapterIndices.clear());
              },
              child: const Text('清空', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 4),

        // 章节列表
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.borderSubtle),
            ),
            child: _chapters.isEmpty
                ? const Center(child: Text('当前小说无章节内容'))
                : ListView.separated(
                    itemCount: _chapters.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: context.borderSubtle),
                    itemBuilder: (ctx, i) {
                      final ch = _chapters[i];
                      final isSelected =
                          _selectedChapterIndices.contains(ch.chapterIndex);
                      final isCurrentEp = ch.chapterIndex == widget.episodeIndex;

                      final primaryColor = Theme.of(context).colorScheme.primary;
                      return CheckboxListTile(
                        dense: true,
                        value: isSelected,
                        activeColor: primaryColor,
                        title: Row(
                          children: [
                            Text(
                              '第 ${ch.chapterIndex} 章  ${ch.title}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: context.textPrimary,
                              ),
                            ),
                            if (isCurrentEp) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: primaryColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '对应本集',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '${ch.wordCount} 字',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.textTertiary,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedChapterIndices.add(ch.chapterIndex);
                            } else {
                              _selectedChapterIndices.remove(ch.chapterIndex);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
        ),
        const SizedBox(height: 10),

        // 字数统计与推荐区间横幅
        _buildWordCountBadge(context, _selectedChannelAWordCount),
      ],
    );
  }

  Widget _buildChannelB(BuildContext context) {
    final textLen = _pasteTextController.text.trim().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _customTitleController,
          decoration: InputDecoration(
            labelText: '单集/章节主题（选填）',
            hintText: '如：第 ${widget.episodeIndex} 集 决战前夕',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: context.borderSubtle),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: TextField(
            controller: _pasteTextController,
            maxLines: null,
            expands: true,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: context.textPrimary,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: '在此直接粘贴外部小说章节或故事正文（推荐 3,000~8,000 字）...\n'
                  'AI 将深度通读正文，提炼场次、动作对白、保留原著金句与核心事实。',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: context.borderSubtle),
              ),
              fillColor: context.bgCard,
              filled: true,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _buildWordCountBadge(context, textLen),
      ],
    );
  }

  Future<void> _submitAdaptation() async {
    final isChannelA = _tabController.index == 0;

    if (isChannelA) {
      if (_boundNovel == null || _selectedChapterIndices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请至少勾选一个原著章节')),
        );
        return;
      }

      setState(() => _isReadingText = true);
      try {
        final sortedIndices = _selectedChapterIndices.toList()..sort();
        final textBuffer = StringBuffer();
        final titles = <String>[];

        for (final idx in sortedIndices) {
          final ch = await _repo.getChapter(_boundNovel!.id, idx);
          if (ch != null && ch.content.trim().isNotEmpty) {
            titles.add(ch.title);
            textBuffer.writeln('### ${ch.title}');
            textBuffer.writeln(ch.content.trim());
            textBuffer.writeln();
          }
        }

        final combinedText = textBuffer.toString().trim();
        if (combinedText.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('所选章节内容为空，无法进行改编')),
            );
          }
          return;
        }

        if (mounted) {
          Navigator.of(context).pop(
            ScreenplayNovelAdaptResult(
              novelText: combinedText,
              chapterTitle: titles.join(' · '),
              novelId: _boundNovel!.id,
              selectedChapterIndices: sortedIndices,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _isReadingText = false);
        }
      }
    } else {
      // Channel B
      final text = _pasteTextController.text.trim();
      if (text.length < 50) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('粘贴的正文内容太短（至少 50 字）')),
        );
        return;
      }

      final customTitle = _customTitleController.text.trim();
      Navigator.of(context).pop(
        ScreenplayNovelAdaptResult(
          novelText: text,
          chapterTitle: customTitle.isNotEmpty ? customTitle : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Dialog(
      backgroundColor: context.bgWindow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 680,
          maxHeight: 620,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题栏
              Row(
                children: [
                  Icon(Icons.auto_stories,
                      color: primaryColor, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '从小说正文生成剧本（第 ${widget.episodeIndex} 集）',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '深入通读原著章节细节，提炼戏剧场次、动作微表情，并契约化锁定原著对白与核心事实',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 页签
              TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: context.textSecondary,
                indicatorColor: primaryColor,
                tabs: const [
                  Tab(
                    icon: Icon(Icons.menu_book, size: 16),
                    text: '从小说库选择章节',
                  ),
                  Tab(
                    icon: Icon(Icons.content_paste, size: 16),
                    text: '直接粘贴正文',
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 内容区
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildChannelA(context),
                    _buildChannelB(context),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 底部操作栏
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isReadingText ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _isReadingText ? null : _submitAdaptation,
                    icon: _isReadingText
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_stories, size: 16),
                    label: Text(
                      _isReadingText ? '正在读取正文...' : '开始 AI 深度改编剧本',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
