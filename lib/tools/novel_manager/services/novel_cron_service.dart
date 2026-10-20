import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/novel_models.dart';
import 'novel_repository.dart';
import 'site_scraper_rule_service.dart';
import 'novel_scraper_coordinator.dart';

/// 小说定时巡检与后台更新服务
class NovelCronService extends ChangeNotifier {
  NovelCronService._();
  static final NovelCronService instance = NovelCronService._();

  final SiteScraperRuleService _ruleService = SiteScraperRuleService.instance;
  final NovelRepository _repo = NovelRepository.instance;
  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;

  Timer? _timer;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  DateTime? _lastCheckTime;
  DateTime? get lastCheckTime => _lastCheckTime;

  /// 启动后台周期轮询巡检（默认每 15 分钟检查一次是否有满足 Cron 计划的站点或小说）
  void startBackgroundScheduler() {
    if (_isRunning) return;
    _isRunning = true;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => _tick());
    debugPrint('[NovelCronService] Background scheduler started');
    notifyListeners();
  }

  /// 停止定时轮询
  void stopBackgroundScheduler() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    debugPrint('[NovelCronService] Background scheduler stopped');
    notifyListeners();
  }

  /// 检查并执行满足条件的自动续采
  Future<void> _tick() async {
    _lastCheckTime = DateTime.now();
    try {
      final rules = await _ruleService.getRules();
      final enabledRules = rules.where((r) => r.isCronEnabled).toList();
      if (enabledRules.isEmpty) return;

      // 查询所有处于连载状态的小说
      final novels = await _repo.getNovels();
      final ongoingNovels = novels.where((n) => n.status == NovelStatus.ongoing && n.sourceUrl.isNotEmpty).toList();

      for (final novel in ongoingNovels) {
        final rule = enabledRules.firstWhere(
          (r) => r.id == novel.sourceSiteId || (r.baseUrl.isNotEmpty && novel.sourceUrl.startsWith(r.baseUrl)),
          orElse: () => const SiteScraperRule(id: '', name: '', baseUrl: ''),
        );

        if (rule.id.isNotEmpty && !_coordinator.isNovelScraping(novel.id)) {
          debugPrint('[NovelCronService] Triggering auto-update for novel: ${novel.title}');
          await _coordinator.startScrape(
            novelId: novel.id,
            tocUrl: novel.sourceUrl,
            ruleId: rule.id,
          );
        }
      }
    } catch (e) {
      debugPrint('[NovelCronService] Error in scheduler tick: $e');
    }
  }

  /// 手动触发单本小说最新章节抓取
  Future<void> triggerManualUpdate(String novelId) async {
    final novel = await _repo.getNovel(novelId);
    if (novel == null || novel.sourceUrl.isEmpty) {
      throw StateError('该小说未绑定采集来源网址');
    }

    final rules = await _ruleService.getRules();
    SiteScraperRule? matchedRule;
    if (novel.sourceSiteId.isNotEmpty) {
      matchedRule = rules.firstWhere((r) => r.id == novel.sourceSiteId, orElse: () => rules.first);
    } else {
      matchedRule = rules.firstWhere(
        (r) => r.baseUrl.isNotEmpty && novel.sourceUrl.startsWith(r.baseUrl),
        orElse: () => rules.first,
      );
    }

    await _coordinator.startScrape(
      novelId: novel.id,
      tocUrl: novel.sourceUrl,
      ruleId: matchedRule.id,
    );
  }
}
