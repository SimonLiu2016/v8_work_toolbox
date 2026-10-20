import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/novel_models.dart';
import 'novel_repository.dart';
import 'site_scraper_rule_service.dart';
import 'http_rule_scraper.dart';
import 'anti_bot_bypass_scraper.dart';

/// 采集进度通知事件
class ScrapeProgressEvent {
  final String novelId;
  final String novelTitle;
  final int totalChapters;
  final int currentChapter;
  final String currentChapterTitle;
  final bool isCompleted;
  final String? error;

  const ScrapeProgressEvent({
    required this.novelId,
    required this.novelTitle,
    required this.totalChapters,
    required this.currentChapter,
    required this.currentChapterTitle,
    this.isCompleted = false,
    this.error,
  });
}

/// 章节级事务调度器：负责幂等过滤、断点续采、单章事务落盘与重试
class NovelScraperCoordinator extends ChangeNotifier {
  NovelScraperCoordinator._();
  static final NovelScraperCoordinator instance = NovelScraperCoordinator._();

  final NovelRepository _repo = NovelRepository.instance;
  final SiteScraperRuleService _ruleService = SiteScraperRuleService.instance;

  final Map<String, bool> _activeJobs = {};
  final Map<String, ScrapeProgressEvent> _activeEvents = {};

  bool isNovelScraping(String novelId) => _activeJobs[novelId] == true;

  /// 获取当前指定小说或全局最近的采集进度快照
  ScrapeProgressEvent? getProgressForNovel(String novelId) => _activeEvents[novelId];
  List<ScrapeProgressEvent> get activeEventsList => _activeEvents.values.toList();

  final _progressController = StreamController<ScrapeProgressEvent>.broadcast();
  Stream<ScrapeProgressEvent> get progressStream => _progressController.stream;

  void _dispatchProgress(ScrapeProgressEvent event) {
    if (event.isCompleted) {
      _activeEvents.remove(event.novelId);
    } else {
      _activeEvents[event.novelId] = event;
    }
    _progressController.add(event);
    notifyListeners();
  }

  /// 取消指定小说的采集任务
  void cancelScrape(String novelId) {
    _activeJobs[novelId] = false;
    _activeEvents.remove(novelId);
    _progressController.add(ScrapeProgressEvent(
      novelId: novelId,
      novelTitle: '',
      totalChapters: 0,
      currentChapter: 0,
      currentChapterTitle: '已取消',
      isCompleted: true,
    ));
    notifyListeners();
  }

  /// 执行或接续采集小说任务（幂等/断点续采）
  Future<void> startScrape({
    required String novelId,
    required String tocUrl,
    required String ruleId,
  }) async {
    if (_activeJobs[novelId] == true) {
      debugPrint('[NovelScraperCoordinator] Task already running for $novelId');
      return;
    }

    _activeJobs[novelId] = true;
    notifyListeners();

    try {
      final rule = await _ruleService.getRule(ruleId);
      if (rule == null) {
        throw StateError('Scraper rule $ruleId not found');
      }

      final novel = await _repo.getNovel(novelId);
      var novelTitle = novel?.title ?? '未知小说';

      // 1. 获取目录（优先使用高性能且穿透优化后的直接规则抓取器）
      List<ScrapedChapterEntry> remoteEntries = [];
      final httpScraper = HttpRuleScraper(rule);
      try {
        try {
          remoteEntries = await httpScraper.scrapeTableOfContents(tocUrl);
        } catch (e) {
          if (rule.enableBypass) {
            debugPrint('[NovelScraperCoordinator] httpScraper failed, trying bypass: $e');
            final bypass = AntiBotBypassScraper(rule);
            remoteEntries = await bypass.scrapeTableOfContents(tocUrl);
          } else {
            rethrow;
          }
        }

        // 若小说标题是占位符或信息不全，自动提取真实书名、作者、简介与封面
        if (novel != null && (novel.title.startsWith('网络采集小说') || novel.author == '网络作者')) {
          try {
            final meta = await httpScraper.extractNovelMetadata(tocUrl);
            final realTitle = meta['title']?.isNotEmpty == true ? meta['title']! : novel.title;
            final realAuthor = meta['author']?.isNotEmpty == true ? meta['author']! : novel.author;
            final realDesc = meta['description']?.isNotEmpty == true ? meta['description']! : novel.description;
            final realCover = meta['coverUrl']?.isNotEmpty == true ? meta['coverUrl']! : novel.coverUrl;

            novelTitle = realTitle;
            await _repo.saveNovel(novel.copyWith(
              title: realTitle,
              author: realAuthor,
              description: realDesc,
              coverUrl: realCover,
            ));
          } catch (_) {}
        }
      } finally {
        httpScraper.close();
      }

      if (remoteEntries.isEmpty) {
        throw StateError('未能从目录页抓取到任何章节');
      }

      // 2. 幂等比对：查询本地已有章节索引
      final existingIndices = await _repo.getChapterIndices(novelId);
      final existingUrls = existingIndices
          .map((c) => c.originChapterUrl)
          .where((u) => u != null && u.isNotEmpty)
          .toSet();

      // 找出尚未采集的章节队列（过滤已采章节，实现绝对幂等）
      final pendingEntries = remoteEntries.where((e) {
        return !existingUrls.contains(e.chapterUrl);
      }).toList();

      debugPrint('[NovelScraperCoordinator] Novel $novelId: Total remote ${remoteEntries.length}, Existing ${existingIndices.length}, Pending ${pendingEntries.length}');

      // 3. 逐章事务采集并落盘
      int processedCount = existingIndices.length;
      final totalCount = remoteEntries.length;

      _dispatchProgress(ScrapeProgressEvent(
        novelId: novelId,
        novelTitle: novelTitle,
        totalChapters: totalCount,
        currentChapter: processedCount,
        currentChapterTitle: pendingEntries.isNotEmpty ? '开始增量续采...' : '已全部是最新章节',
      ));

      if (pendingEntries.isEmpty) {
        _dispatchProgress(ScrapeProgressEvent(
          novelId: novelId,
          novelTitle: novelTitle,
          totalChapters: totalCount,
          currentChapter: totalCount,
          currentChapterTitle: '全部章节均已在本地（无需更新）',
          isCompleted: true,
        ));
        return;
      }

      final chapterHttpScraper = HttpRuleScraper(rule);
      try {
        for (final entry in pendingEntries) {
          // 检查是否被手动取消
          if (_activeJobs[novelId] == false) {
            debugPrint('[NovelScraperCoordinator] Scrape canceled by user for $novelId');
            break;
          }

          _dispatchProgress(ScrapeProgressEvent(
            novelId: novelId,
            novelTitle: novelTitle,
            totalChapters: totalCount,
            currentChapter: processedCount + 1,
            currentChapterTitle: entry.title,
          ));

          // 单章独立容错与重试，避免单个网络异常击穿整个大循环
          ScrapedChapterResult? chapterResult;
          for (int retry = 0; retry < 2; retry++) {
            try {
              chapterResult = await chapterHttpScraper.scrapeChapter(entry.chapterUrl);
              break;
            } catch (e) {
              if (rule.enableBypass) {
                try {
                  final bypass = AntiBotBypassScraper(rule);
                  chapterResult = await bypass.scrapeChapter(entry.chapterUrl);
                  break;
                } catch (_) {}
              }
              if (retry == 0) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
            }
          }

          if (chapterResult != null) {
            final title = chapterResult.title.isNotEmpty ? chapterResult.title : entry.title;
            final content = chapterResult.content;

            // 单章事务：落盘 + 入库
            await _repo.saveChapter(
              novelId: novelId,
              chapterIndex: entry.chapterIndex,
              title: title,
              content: content,
              originChapterUrl: entry.chapterUrl,
              status: ChapterStatus.synced,
            );
          } else {
            debugPrint('[NovelScraperCoordinator] Failed to scrape chapter ${entry.chapterIndex}: ${entry.title}, skipping to next.');
          }

          processedCount++;

          // 延时防限频
          if (rule.requestDelayMs > 0) {
            await Future.delayed(Duration(milliseconds: rule.requestDelayMs));
          }
        }
      } finally {
        chapterHttpScraper.close();
      }

      // 4. 采集完成，更新站点最后采集时间
      await _ruleService.saveRule(rule.copyWith(
        lastCrawledAt: DateTime.now(),
      ));

      _dispatchProgress(ScrapeProgressEvent(
        novelId: novelId,
        novelTitle: novelTitle,
        totalChapters: totalCount,
        currentChapter: processedCount,
        currentChapterTitle: '采集完成',
        isCompleted: true,
      ));
    } catch (e, stack) {
      debugPrint('[NovelScraperCoordinator] error during scrape: $e\n$stack');
      _dispatchProgress(ScrapeProgressEvent(
        novelId: novelId,
        novelTitle: '',
        totalChapters: 0,
        currentChapter: 0,
        currentChapterTitle: '',
        isCompleted: true,
        error: e.toString(),
      ));
    } finally {
      _activeJobs[novelId] = false;
      notifyListeners();
    }
  }

  /// 探索指定源站的小说目录列表（用于展示源站所有可抓取小说并支持批量勾选）
  Future<List<DiscoveredNovelItem>> exploreSiteNovels(SiteScraperRule rule) async {
    final catalogUrl = rule.catalogUrl.isNotEmpty ? rule.catalogUrl : rule.baseUrl;
    final httpScraper = HttpRuleScraper(rule);
    try {
      return await httpScraper.scrapeCatalog(catalogUrl);
    } finally {
      httpScraper.close();
    }
  }

  /// 按分类及页码范围多页并发/流水线探索
  Future<CatalogPageResult> exploreCategoryPages({
    required SiteScraperRule rule,
    required String categoryKey,
    required int startPage,
    required int endPage,
    void Function(int currentPage, int totalPages, int itemCount)? onProgress,
  }) async {
    final httpScraper = HttpRuleScraper(rule);
    try {
      // 1. 先抓取起始页获取总数
      final firstResult = await httpScraper.scrapeCategoryPage(
        categoryKey: categoryKey,
        pageIndex: startPage,
      );

      final totalCount = firstResult.totalCount;
      final totalPages = firstResult.totalPages;
      final List<DiscoveredNovelItem> aggregated = List.from(firstResult.items);

      onProgress?.call(startPage, endPage, aggregated.length);

      final actualEnd = endPage.clamp(startPage, totalPages > 0 ? totalPages : endPage);

      // 2. 依次遍历后续页面
      for (int p = startPage + 1; p <= actualEnd; p++) {
        try {
          final pageRes = await httpScraper.scrapeCategoryPage(
            categoryKey: categoryKey,
            pageIndex: p,
          );
          aggregated.addAll(pageRes.items);
          onProgress?.call(p, actualEnd, aggregated.length);
        } catch (e) {
          debugPrint('[NovelScraperCoordinator] Failed to scrape page $p: $e');
        }
        // 微小延时防限频
        await Future.delayed(const Duration(milliseconds: 150));
      }

      return CatalogPageResult(
        items: aggregated,
        totalCount: totalCount,
        totalPages: totalPages,
        currentPage: startPage,
      );
    } finally {
      httpScraper.close();
    }
  }
}

