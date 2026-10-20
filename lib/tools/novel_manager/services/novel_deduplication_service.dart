import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../../../services/ai_service.dart';
import '../models/novel_models.dart';

/// 小说智能识别与去重清洗服务
class NovelDeduplicationService {
  NovelDeduplicationService._();
  static final NovelDeduplicationService instance = NovelDeduplicationService._();

  final AiService _aiService = AiService.instance;

  /// 常见盗版/SEO 冗余垃圾后缀与前缀正则模式
  static final RegExp _noiseSuffixRegExp = RegExp(
    r'(全文免费阅读|小说免费阅读|免费阅读全文|免费阅读|全文阅读|无删减完整版|无删减版|无删减|未删减|完整版|全本免费阅读|最新章节免费阅读|最新章节更新|最新章节目录|最新章节列表|最新章节无弹窗|最新更新章节|最新更新完整版|最新更新|刚刚更新内容|刚刚更新|最快更新|无弹窗最新章节|无弹窗免费阅读|无弹窗|全本目录更新|全本完结版|完结版|完结篇|大结局|全集免费观看|全集免费阅读|全集|TXT下载|TXT|在线阅读|小说在线阅读|在线免费阅读|小说|百度云|后续|番外).*$',
    caseSensitive: false,
  );

  /// 本地快速启发式提取纯净核心书名
  String cleanTitle(String rawTitle) {
    var t = rawTitle.trim();
    // 移除各类括弧
    t = t.replaceAll(RegExp(r'^[《<\[(【]+|[》>\])】]+$'), '').trim();
    // 移除尾部 SEO 垃圾词
    t = t.replaceAll(_noiseSuffixRegExp, '').trim();
    // 移除末尾多余标点
    t = t.replaceAll(RegExp(r'[,，!！_—\-]+$'), '').trim();
    return t.isNotEmpty ? t : rawTitle.trim();
  }

  /// 依据优先级对备选小说打分（优先保留“无删减”、“全集”、“完整版”）
  int _scoreItem(DiscoveredNovelItem item) {
    int score = 0;
    final raw = item.rawTitle;
    if (raw.contains('无删减') || raw.contains('未删减')) score += 50;
    if (raw.contains('全集')) score += 40;
    if (raw.contains('完整版') || raw.contains('完结') || raw.contains('全本')) score += 30;
    if (raw.contains('正版') || raw.contains('原著')) score += 20;
    if (raw.contains('最新章节') || raw.contains('大结局')) score += 10;
    return score;
  }

  /// 第一阶段：本地主干前缀快速分桶预聚类
  Map<String, List<DiscoveredNovelItem>> preCluster(List<DiscoveredNovelItem> rawItems) {
    final Map<String, List<DiscoveredNovelItem>> clusters = {};

    for (final item in rawItems) {
      final core = cleanTitle(item.rawTitle);
      // 聚合 key: 核心书名
      clusters.putIfAbsent(core, () => []).add(item);
    }

    return clusters;
  }

  /// 本地启发式去重与书名净化（作为 AI 失败或无网络时的快速兜底）
  List<DiscoveredNovelItem> deduplicateLocally(List<DiscoveredNovelItem> rawItems) {
    final clusters = preCluster(rawItems);
    final List<DiscoveredNovelItem> results = [];

    for (final entry in clusters.entries) {
      final group = entry.value;
      if (group.isEmpty) continue;

      // 组内排序：按评分降序
      group.sort((a, b) => _scoreItem(b).compareTo(_scoreItem(a)));
      final best = group.first;

      // 净化作者与标题
      var author = best.author.trim();
      final coreTitle = cleanTitle(entry.key);
      if (author.isEmpty || author == best.rawTitle) {
        author = '网络作者';
      }

      results.add(best.copyWith(
        title: coreTitle,
        author: author,
      ));
    }

    return results;
  }

  /// 第二阶段：调用 AI 仲裁与书名智能净化
  Future<List<DiscoveredNovelItem>> deduplicateWithAi(
    List<DiscoveredNovelItem> rawItems, {
    void Function(String status)? onProgress,
  }) async {
    if (rawItems.isEmpty) return [];

    onProgress?.call('正在进行第一阶段本地主干特征预聚合...');
    final clusters = preCluster(rawItems);

    // 如果本身就没有重复簇，或簇数量极大，分批送给 AI
    onProgress?.call('正在调用 AI 进行作品语义识别、版本优选与书名净化...');

    // 准备发送给 AI 的候选组数据结构
    final List<Map<String, dynamic>> groupsPayload = [];
    final Map<String, DiscoveredNovelItem> idToItemMap = {};

    clusters.forEach((coreName, items) {
      for (final it in items) {
        idToItemMap[it.detailUrl] = it;
      }

      groupsPayload.add({
        'suggested_core_name': coreName,
        'candidates': items.map((it) => {
          'url': it.detailUrl,
          'raw_title': it.rawTitle,
          'author': it.author,
          'latest_chapter': it.latestChapter ?? '',
        }).toList(),
      });
    });

    try {
      // 采用分批处理（每批最多 25 个候选组），规避单次请求上下文溢出
      final List<DiscoveredNovelItem> finalResults = [];
      const int batchSize = 25;

      for (int i = 0; i < groupsPayload.length; i += batchSize) {
        final end = (i + batchSize < groupsPayload.length) ? i + batchSize : groupsPayload.length;
        final batch = groupsPayload.sublist(i, end);

        onProgress?.call('AI 正在智能识别并去重第 ${i + 1} ~ $end 组小说作品...');

        final prompt = '''
你是一个专业的小说数据整理与去重引擎。
以下是爬虫从盗版小说网站抓取到的候选组列表。由于源站经常针对同一部小说生成带有大量SEO关键词的不同虚假标题条目（如“...全文无弹窗”、“...最后结局”）。
请针对每个候选组中的 candidates 进行识别与去重：
1. 从中挑选出最优的一个候选版本（严格优先规则：优先选择包含“无删减”、“全集”、“完整版”的条目 URL）。
2. 将该书的名字净化为真实的、干净的书名（去掉“免费阅读”、“小说全文”、“大结局”等一切噪点词汇，纯净书名如《人族镇魔司，一剑镇邪神》）。
3. 提取纠正真实的作者名（若作者混入了书名，请纠偏）。

请严格输出 JSON 数组，格式如下，不要附带任何解释文字：
[
  {
    "selected_url": "该组中挑出的最优 candidate 的 url",
    "clean_title": "纯净书名",
    "clean_author": "清洗后的作者"
  }
]

输入数据:
${jsonEncode(batch)}
''';

        final chatRes = await _aiService.chat(
          messages: [
            {'role': 'user', 'content': prompt},
          ],
          timeout: const Duration(seconds: 45),
        );

        final text = chatRes.text.trim();
        List<dynamic>? parsed;
        try {
          // 提取可能被 markdown 代码块包裹的 json
          var cleanJson = text;
          if (cleanJson.contains('```')) {
            cleanJson = cleanJson.replaceAll(RegExp(r'```json\s*'), '').replaceAll(RegExp(r'```\s*'), '');
          }
          final match = RegExp(r'\[[\s\S]*\]').firstMatch(cleanJson);
          if (match != null) {
            parsed = jsonDecode(match.group(0)!);
          }
        } catch (e) {
          debugPrint('[NovelDeduplicationService] JSON parse error: $e');
        }

        if (parsed != null) {
          for (final row in parsed) {
            final selUrl = row['selected_url'] as String? ?? '';
            final cleanTitle = row['clean_title'] as String? ?? '';
            final cleanAuthor = row['clean_author'] as String? ?? '';

            final original = idToItemMap[selUrl];
            if (original != null) {
              finalResults.add(original.copyWith(
                title: cleanTitle.isNotEmpty ? cleanTitle : original.title,
                author: cleanAuthor.isNotEmpty ? cleanAuthor : original.author,
              ));
            }
          }
        } else {
          // 若本批次 AI 解析异常，降级使用本地启发式去重填充
          for (final groupData in batch) {
            final cands = (groupData['candidates'] as List)
                .map((c) => idToItemMap[c['url']])
                .whereType<DiscoveredNovelItem>()
                .toList();
            finalResults.addAll(deduplicateLocally(cands));
          }
        }
      }

      onProgress?.call('AI 智能去重与书名净化完成，共保留 ${finalResults.length} 部独立作品！');
      return finalResults.isNotEmpty ? finalResults : deduplicateLocally(rawItems);
    } catch (e) {
      debugPrint('[NovelDeduplicationService] AI deduplication error: $e, fallback to local');
      onProgress?.call('AI 服务响应异常，已自动无缝切换为本地智能规则去重...');
      return deduplicateLocally(rawItems);
    }
  }
}
