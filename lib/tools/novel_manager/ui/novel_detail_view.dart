import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_repository.dart';
import '../services/novel_ai_editor_service.dart';
import 'chapter_editor_view.dart';
import 'site_rule_manager_dialog.dart';
import 'novel_export_dialog.dart';
import 'novel_edit_properties_dialog.dart';
import '../services/novel_cron_service.dart';
import '../services/novel_scraper_coordinator.dart';

/// 小说详情与章节目录管理主视图
class NovelDetailView extends StatefulWidget {
  final String novelId;
  final VoidCallback onBack;

  const NovelDetailView({
    super.key,
    required this.novelId,
    required this.onBack,
  });

  @override
  State<NovelDetailView> createState() => _NovelDetailViewState();
}

class _NovelDetailViewState extends State<NovelDetailView> {
  final NovelRepository _repo = NovelRepository.instance;
  final NovelAiEditorService _aiEditor = NovelAiEditorService.instance;

  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;

  NovelMetadata? _novel;
  List<NovelChapterIndex> _chapters = [];
  bool _isLoading = true;
  int? _selectedChapterIndex;

  @override
  void initState() {
    super.initState();
    _loadData();
    _repo.addListener(_loadDataSilently);
    _coordinator.addListener(_loadDataSilently);
  }

  @override
  void dispose() {
    _repo.removeListener(_loadDataSilently);
    _coordinator.removeListener(_loadDataSilently);
    super.dispose();
  }

  Future<void> _loadDataSilently() async {
    final novel = await _repo.getNovel(widget.novelId);
    final chapters = await _repo.getChapterIndices(widget.novelId);
    if (mounted) {
      setState(() {
        _novel = novel;
        _chapters = chapters;
        if (chapters.isNotEmpty && _selectedChapterIndex == null) {
          _selectedChapterIndex = chapters.first.chapterIndex;
        }
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final novel = await _repo.getNovel(widget.novelId);
    final chapters = await _repo.getChapterIndices(widget.novelId);

    if (mounted) {
      setState(() {
        _novel = novel;
        _chapters = chapters;
        _isLoading = false;
        if (chapters.isNotEmpty && _selectedChapterIndex == null) {
          _selectedChapterIndex = chapters.first.chapterIndex;
        }
      });
    }
  }

  Future<void> _insertNewChapter({int? atIndex}) async {
    final targetIndex = atIndex ?? (_chapters.isNotEmpty ? _chapters.last.chapterIndex + 1 : 1);
    final titleController = TextEditingController(text: '第 $targetIndex 章');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(atIndex != null ? '在第 $targetIndex 章处插入新章节' : '添加新章节'),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: '章节标题', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('创建空白章节')),
        ],
      ),
    );

    if (confirmed == true) {
      if (atIndex != null && atIndex <= _chapters.length) {
        await _repo.insertChapter(
          novelId: widget.novelId,
          targetIndex: targetIndex,
          title: titleController.text.trim(),
          content: '',
        );
      } else {
        await _repo.saveChapter(
          novelId: widget.novelId,
          chapterIndex: targetIndex,
          title: titleController.text.trim(),
          content: '',
          status: ChapterStatus.draft,
        );
      }
      await _loadData();
      setState(() => _selectedChapterIndex = targetIndex);
    }
  }

  Future<void> _checkUpdateAndScrape() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await NovelCronService.instance.triggerManualUpdate(widget.novelId);
      messenger.showSnackBar(const SnackBar(content: Text('已启动增量网络更新采集！')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('触发更新失败: $e')));
    }
  }

  Future<void> _aiGenerateNextChapter({int? atIndex}) async {
    final targetIndex = atIndex ?? (_chapters.isNotEmpty ? _chapters.last.chapterIndex + 1 : 1);
    final promptController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Colors.amber),
            SizedBox(width: 8),
            Text('AI 剧情大纲续写/生成新章节'),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('将生成第 $targetIndex 章，请填写本章剧情设定要求（可选）：'),
              const SizedBox(height: 10),
              TextField(
                controller: promptController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '如：主角突破瓶颈，并发现了潜藏在背后的反派线索...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton.icon(
            icon: const Icon(Icons.bolt),
            label: const Text('开始生成'),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // 显示加载提示
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('AI 正在根据前文剧情推演撰写新章节...'),
                ],
              ),
            ),
          ),
        ),
      );

      try {
        final generated = await _aiEditor.generateNextChapter(
          novelId: widget.novelId,
          nextChapterIndex: targetIndex,
          userPrompt: promptController.text,
        );

        Navigator.pop(context); // close loading

        await _repo.saveChapter(
          novelId: widget.novelId,
          chapterIndex: targetIndex,
          title: generated['title'] ?? '第 $targetIndex 章',
          content: generated['content'] ?? '',
          status: ChapterStatus.aiRewritten,
        );

        await _loadData();
        setState(() => _selectedChapterIndex = targetIndex);
      } catch (e) {
        Navigator.pop(context);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('AI 续写失败: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _novel == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final novel = _novel!;

    return Scaffold(
      body: Column(
        children: [
          // 顶部信息与导航条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                  tooltip: '返回小说列表',
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(novel.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      '作者: ${novel.author} | 总字数: ${novel.totalWordCount} | 状态: ${novel.status.name}',
                      style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 12),
                    ),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text('编辑属性'),
                  onPressed: () async {
                    final updated = await showDialog<bool>(
                      context: context,
                      builder: (_) => NovelEditPropertiesDialog(novel: novel),
                    );
                    if (updated == true) _loadData();
                  },
                ),
                const SizedBox(width: 8),
                if (novel.sourceUrl.isNotEmpty) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.green),
                    label: const Text('检查更新与续采'),
                    onPressed: _checkUpdateAndScrape,
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore, size: 16),
                  label: const Text('网络采集配置'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => SiteRuleManagerDialog(
                        targetNovelId: novel.id,
                        targetNovelTitle: novel.title,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.download, size: 16),
                  label: const Text('检索导出'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => NovelExportDialog(
                        novel: novel,
                        chapters: _chapters,
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('AI 续写新章'),
                  onPressed: () => _aiGenerateNextChapter(),
                ),
              ],
            ),
          ),

          // 详情页实时采集进度条（若当前小说正在采集或增量更新中）
          AnimatedBuilder(
            animation: _coordinator,
            builder: (ctx, _) {
              final event = _coordinator.getProgressForNovel(novel.id);
              if (event == null || event.isCompleted) {
                return const SizedBox.shrink();
              }
              final progressPct = event.totalChapters > 0
                  ? (event.currentChapter / event.totalChapters).clamp(0.0, 1.0)
                  : 0.0;

              return Container(
                color: Colors.green.withValues(alpha: 0.12),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '正在采集/更新最新章节: ${event.currentChapter}/${event.totalChapters} (${(progressPct * 100).toStringAsFixed(1)}%) • ${event.currentChapterTitle}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () => _coordinator.cancelScrape(novel.id),
                      child: const Text('停止采集', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            },
          ),

          // 主体双栏：左侧章节列表，右侧章节阅读/编辑器
          Expanded(
            child: Row(
              children: [
                // 章节侧边栏
                SizedBox(
                  width: 280,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(right: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Text('章节列表 (${_chapters.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.add, size: 18),
                                tooltip: '增加新章节',
                                onPressed: _insertNewChapter,
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _chapters.length,
                            itemBuilder: (ctx, i) {
                              final ch = _chapters[i];
                              final isSelected = ch.chapterIndex == _selectedChapterIndex;
                              return ListTile(
                                dense: true,
                                selected: isSelected,
                                selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.1),
                                title: Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${ch.wordCount} 字'),
                                trailing: PopupMenuButton<String>(
                                  icon: const Icon(Icons.more_vert, size: 16),
                                  onSelected: (action) async {
                                    if (action == 'insert_before') {
                                      _insertNewChapter(atIndex: ch.chapterIndex);
                                    } else if (action == 'insert_after') {
                                      _insertNewChapter(atIndex: ch.chapterIndex + 1);
                                    } else if (action == 'ai_generate_after') {
                                      _aiGenerateNextChapter(atIndex: ch.chapterIndex + 1);
                                    } else if (action == 'delete') {
                                      await _repo.deleteChapter(novelId: novel.id, chapterIndex: ch.chapterIndex);
                                      _loadData();
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    const PopupMenuItem(value: 'insert_before', child: Text('在此章前插入新章')),
                                    const PopupMenuItem(value: 'insert_after', child: Text('在此章后插入新章')),
                                    const PopupMenuItem(value: 'ai_generate_after', child: Text('在此章后 AI 续写新章')),
                                    const PopupMenuDivider(),
                                    const PopupMenuItem(value: 'delete', child: Text('删除本章', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                                onTap: () => setState(() => _selectedChapterIndex = ch.chapterIndex),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 右侧编辑器
                Expanded(
                  child: _selectedChapterIndex == null
                      ? const Center(child: Text('请在左侧选择要查看或编辑的章节'))
                      : ChapterEditorView(
                          key: ValueKey('${novel.id}-$_selectedChapterIndex'),
                          novelId: novel.id,
                          chapterIndex: _selectedChapterIndex!,
                          onChapterSaved: () => _loadData(),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
