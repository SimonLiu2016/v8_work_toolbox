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
    // 确保免盾可用源 piaotia 在规则库中（防止旧数据库缺失），并自愈升级分类字典
    final piaotiaRule = rules.where((r) => r.id == 'piaotia').firstOrNull;
    if (piaotiaRule == null) {
      try {
        await _db.insertOrUpdateRule(defaultPiaotiaRule);
        return await _db.getAllRules();
      } catch (e) {
        // 容错隔离：即使写入出现极端异常，也确保现有规则不丢失并混入默认源返回
        return [...rules, defaultPiaotiaRule];
      }
    } else if (!piaotiaRule.categoryMap.containsKey('0') ||
        piaotiaRule.categoryMap.length < defaultPiaotiaRule.categoryMap.length) {
      try {
        final updatedPiaotia = piaotiaRule.copyWith(
          categoryMap: defaultPiaotiaRule.categoryMap,
        );
        await _db.insertOrUpdateRule(updatedPiaotia);
        return rules.map((r) => r.id == 'piaotia' ? updatedPiaotia : r).toList();
      } catch (e) {
        // 容错忽略
      }
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

  /// 预置的飘天文学默认免盾源
  static const SiteScraperRule defaultPiaotiaRule = SiteScraperRule(
    id: 'piaotia',
    name: '飘天文学 (免盾优质源/直连推荐)',
    baseUrl: 'https://www.piaotia.com',
    enableBypass: false,
    catalogUrl: 'https://www.piaotia.com/booksort{category}/0/{page}.html',
    catalogSelector: 'table tr, #content tr',
    categoryMap: {
      '0': '全部文章 (全站综合)',
      '1': '玄幻魔法 (含穿越/异能)',
      '2': '武侠修真',
      '3': '都市言情',
      '4': '历史军事',
      '5': '网游竞技',
      '6': '科幻小说',
      '7': '恐怖灵异',
      '8': '同人漫画',
      '9': '其他类型',
    },
    tocUrlPattern: '{baseUrl}/html/{bookId}/index.html',
    tocSelector: 'td a[href*="/html/"]',
    contentSelector: 'body',
    titleSelector: 'h1',
    removeSelectors: ['script', 'ins', '#feit2'],
    requestDelayMs: 300,
  );

  /// 初始化内置默认站点规则
  Future<void> _initDefaultRules() async {
    final defaultRules = [
      // 1. 免盾真实可用优质源（首选推荐）
      defaultPiaotiaRule,
      // 2. 带反爬防护站点（演示 Cloudflare Turnstile 挑战盾）
      const SiteScraperRule(
        id: 'szlajc',
        name: '免费小说阅读网 (szlajc.com) [CF强盾]',
        baseUrl: 'http://www.szlajc.com',
        enableBypass: true,
        catalogUrl: 'http://www.szlajc.com/class/{category}_{page}/',
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
      // 3. 通用经典标准书源模版（常规 HTTP 抓取自定义参考）
      const SiteScraperRule(
        id: 'standard_generic',
        name: '通用轻量小说源模板 (示例)',
        baseUrl: 'https://example-novel.com',
        enableBypass: false,
        catalogUrl: 'https://example-novel.com/class/{category}_{page}.html',
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
