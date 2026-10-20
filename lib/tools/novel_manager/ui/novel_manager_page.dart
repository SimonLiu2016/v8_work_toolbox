import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_repository.dart';
import '../services/novel_import_service.dart';
import '../services/novel_scraper_coordinator.dart';
import '../services/novel_cron_service.dart';
import 'novel_detail_view.dart';
import 'site_rule_manager_dialog.dart';
import 'novel_scrape_wizard_dialog.dart';
import 'site_catalog_discovery_dialog.dart';

/// 小说管理器主界面
class NovelManagerPage extends StatefulWidget {
  const NovelManagerPage({super.key});

  @override
  State<NovelManagerPage> createState() => _NovelManagerPageState();
}

class _NovelManagerPageState extends State<NovelManagerPage> {
  final NovelRepository _repo = NovelRepository.instance;
  final NovelImportService _importService = NovelImportService.instance;
  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;
  final NovelCronService _cronService = NovelCronService.instance;

  List<NovelMetadata> _novels = [];
  bool _isLoading = true;
  String _selectedGenre = '全部';
  String _searchQuery = '';
  String? _openedNovelId;

  final List<String> _genres = ['全部', '都市', '科幻', '仙侠', '玄幻', '悬疑', '历史', '奇幻'];

  @override
  void initState() {
    super.initState();
    _cronService.startBackgroundScheduler();
    _loadNovels();
    _repo.addListener(_loadNovels);
  }

  @override
  void dispose() {
    _repo.removeListener(_loadNovels);
    super.dispose();
  }

  Future<void> _loadNovels() async {
    setState(() => _isLoading = true);
    final list = await _repo.getNovels(
      query: _searchQuery,
      genre: _selectedGenre,
    );
    if (mounted) {
      setState(() {
        _novels = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _importFile() async {
    final pick = await FilePicker.platform.pickFiles(
      dialogTitle: '选择导入小说文件 (.txt 或 .epub)',
      type: FileType.custom,
      allowedExtensions: ['txt', 'epub'],
    );

    if (pick == null || pick.files.isEmpty) return;
    final path = pick.files.single.path;
    if (path == null) return;
    final file = File(path);

    if (!mounted) return;
    String statusMsg = '正在导入中...';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(statusMsg)),
            ],
          ),
        ),
      ),
    );

    try {
      final res = await _importService.importFile(
        file,
        enableAiFallback: true,
        onProgress: (msg) {
          if (mounted) setState(() => statusMsg = msg);
        },
      );

      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('成功导入《${res.novel.title}》，共 ${res.importedChapters} 个章节！${res.usedAiFallback ? '（已调用 AI 自动断章）' : ''}'),
        ),
      );
      _loadNovels();
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_openedNovelId != null) {
      return NovelDetailView(
        novelId: _openedNovelId!,
        onBack: () {
          setState(() => _openedNovelId = null);
          _loadNovels();
        },
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      body: Column(
        children: [
          // 顶部栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('小说管理器', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('标准资产库 • 双模防反爬采集 • 本地EPUB/TXT智能导入 • 跨模块短视频创作', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('书源站点管理'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const SiteRuleManagerDialog(),
                    );
                  },
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_stories, size: 16, color: Colors.indigoAccent),
                  label: const Text('探索源站书库'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const SiteCatalogDiscoveryDialog(),
                    );
                  },
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  icon: const Icon(Icons.travel_explore, size: 16, color: Colors.blueAccent),
                  label: const Text('单本网址采集'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => const NovelScrapeWizardDialog(),
                    );
                  },
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('导入小说'),
                  onPressed: _importFile,
                ),
              ],
            ),
          ),

          // 采集进度监控横条 (多任务状态保持，从详情页返回绝不丢失)
          AnimatedBuilder(
            animation: _coordinator,
            builder: (ctx, _) {
              final activeEvents = _coordinator.activeEventsList;
              if (activeEvents.isEmpty) {
                return const SizedBox.shrink();
              }
              final event = activeEvents.last;
              final progressPct = event.totalChapters > 0
                  ? (event.currentChapter / event.totalChapters).clamp(0.0, 1.0)
                  : 0.0;

              return Container(
                color: Colors.blueAccent.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '正在采集《${event.novelTitle}》: ${event.currentChapter}/${event.totalChapters} (${(progressPct * 100).toStringAsFixed(1)}%) • ${event.currentChapterTitle}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton(
                      onPressed: () => _coordinator.cancelScrape(event.novelId),
                      child: const Text('取消采集'),
                    ),
                  ],
                ),
              );
            },
          ),

          // 搜索与题材分类筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                // 搜索框
                SizedBox(
                  width: 280,
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索书名、作者、简介...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _loadNovels();
                    },
                  ),
                ),
                const SizedBox(width: 16),
                // 题材标签栏
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _genres.map((g) {
                        final isSelected = g == _selectedGenre;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(g),
                            selected: isSelected,
                            onSelected: (val) {
                              if (val) {
                                setState(() => _selectedGenre = g);
                                _loadNovels();
                              }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 小说卡片网格
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _novels.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.auto_stories, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text('小说库空空如也', style: TextStyle(fontSize: 16, color: Colors.grey)),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              icon: const Icon(Icons.file_upload),
                              label: const Text('立即导入本地小说'),
                              onPressed: _importFile,
                            ),
                          ],
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GridView.builder(
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          itemCount: _novels.length,
                          itemBuilder: (ctx, i) {
                            final novel = _novels[i];
                            return _buildNovelCard(novel, theme);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildNovelCard(NovelMetadata novel, ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _openedNovelId = novel.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 50,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.book, color: Colors.blueAccent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          novel.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text('作者: ${novel.author}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text('${novel.totalChapters} 章 • ${novel.totalWordCount} 字', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (novel.description.isNotEmpty) ...[
                Text(
                  novel.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  if (novel.genre.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(novel.genre, style: TextStyle(color: theme.colorScheme.onPrimaryContainer, fontSize: 10)),
                    ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    tooltip: '删除小说',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('确认删除《${novel.title}》？'),
                          content: const Text('将永久删除该小说的全部章节与本地持久化文件，无法撤销。'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('删除')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await _repo.deleteNovel(novel.id);
                        _loadNovels();
                      }
                    },
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
