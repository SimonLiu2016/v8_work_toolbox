import 'package:flutter/foundation.dart';
import '../models/novel_models.dart';
import 'novel_database.dart';

/// 站点源规则配置与管理服务
class SiteScraperRuleService extends ChangeNotifier {
  SiteScraperRuleService._();
  static final SiteScraperRuleService instance = SiteScraperRuleService._();

  final NovelDatabase _db = NovelDatabase.instance;

  /// 获取所有已配置的采集规则
  Future<List<SiteScraperRule>> getRules() async {
    final rules = await _db.getAllRules();
    if (rules.isEmpty) {
      // 预置默认站点规则模版
      await _initDefaultRules();
      return await _db.getAllRules();
    }
    return rules;
  }

  /// 获取单条规则
  Future<SiteScraperRule?> getRule(String id) async {
    return await _db.getRuleById(id);
  }

  /// 保存或更新规则
  Future<void> saveRule(SiteScraperRule rule) async {
    await _db.insertOrUpdateRule(rule);
    notifyListeners();
  }

  /// 删除规则
  Future<void> deleteRule(String id) async {
    await _db.deleteRule(id);
    notifyListeners();
  }

  /// 初始化内置默认站点规则
  Future<void> _initDefaultRules() async {
    final defaultRules = [
      // 1. 测试反爬站点（用户指定的 szlajc.com）
      const SiteScraperRule(
        id: 'szlajc',
        name: '免费小说阅读网 (szlajc.com)',
        baseUrl: 'http://www.szlajc.com',
        enableBypass: false,
        catalogUrl: 'http://www.szlajc.com/class/1_1/',
        catalogSelector: '#newscontent .l ul li',
        categoryMap: {
          '1': '玄幻奇幻',
          '2': '武侠仙侠',
          '3': '女频言情',
          '4': '现代都市',
          '5': '历史军事',
          '6': '游戏竞技',
          '7': '科幻灵异',
          '8': '美文同人',
          '9': '其他类型',
        },
        tocUrlPattern: '{baseUrl}/jie/{bookId}/',
        tocSelector: '#list dd a, .box_con #list dl a',
        contentSelector: '#content, .content',
        titleSelector: '.bookname h1, h1',
        removeSelectors: ['script', 'ins', '.ad', '#ad'],
        requestDelayMs: 300,
      ),
      // 2. 通用经典标准书源模版（常规 HTTP 抓取）
      const SiteScraperRule(
        id: 'standard_generic',
        name: '通用轻量小说源模板',
        baseUrl: 'https://example-novel.com',
        enableBypass: false,
        catalogUrl: 'https://example-novel.com/category/',
        catalogSelector: '.book-list li, .novel-item',
        tocUrlPattern: '{baseUrl}/novel/{bookId}/index.html',
        tocSelector: '.directory-list a, #catalog li a',
        contentSelector: '#chapter-content, .read-content',
        titleSelector: '.title h1, h1',
        removeSelectors: ['script', 'style', '.recommend'],
        requestDelayMs: 600,
      ),
    ];

    for (final r in defaultRules) {
      await _db.insertOrUpdateRule(r);
    }
  }
}
