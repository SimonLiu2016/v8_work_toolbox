import 'dart:convert';

/// 小说连载/状态枚举
enum NovelStatus {
  ongoing,   // 连载中
  completed, // 已完结
  draft,     // 本地草稿/创作中
}

/// 章节状态枚举
enum ChapterStatus {
  synced,    // 已同步/标准
  draft,     // 本地草稿
  aiRewritten, // AI改写完成
}

/// 小说元数据模型
class NovelMetadata {
  final String id;
  final String title;
  final String author;
  final String description; // 故事背景描述/简介
  final List<String> tags;   // 类型标签
  final String genre;        // 主题材 (如: 科幻、玄幻、都市)
  final String coverUrl;     // 封面图片 URL 或本地绝对路径
  final String sourceUrl;    // 来源网址（若是抓取所得）
  final String sourceSiteId; // 抓取站点标识
  final int totalChapters;
  final int totalWordCount;
  final int readCount;       // 阅读量
  final double heatScore;    // 热度 (0-100)
  final double recommendScore; // 推荐指数 (0-100)
  final NovelStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NovelMetadata({
    required this.id,
    required this.title,
    required this.author,
    this.description = '',
    this.tags = const [],
    this.genre = '',
    this.coverUrl = '',
    this.sourceUrl = '',
    this.sourceSiteId = '',
    this.totalChapters = 0,
    this.totalWordCount = 0,
    this.readCount = 0,
    this.heatScore = 0.0,
    this.recommendScore = 0.0,
    this.status = NovelStatus.ongoing,
    required this.createdAt,
    required this.updatedAt,
  });

  NovelMetadata copyWith({
    String? id,
    String? title,
    String? author,
    String? description,
    List<String>? tags,
    String? genre,
    String? coverUrl,
    String? sourceUrl,
    String? sourceSiteId,
    int? totalChapters,
    int? totalWordCount,
    int? readCount,
    double? heatScore,
    double? recommendScore,
    NovelStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NovelMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      genre: genre ?? this.genre,
      coverUrl: coverUrl ?? this.coverUrl,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceSiteId: sourceSiteId ?? this.sourceSiteId,
      totalChapters: totalChapters ?? this.totalChapters,
      totalWordCount: totalWordCount ?? this.totalWordCount,
      readCount: readCount ?? this.readCount,
      heatScore: heatScore ?? this.heatScore,
      recommendScore: recommendScore ?? this.recommendScore,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'description': description,
      'tags': jsonEncode(tags),
      'genre': genre,
      'cover_url': coverUrl,
      'source_url': sourceUrl,
      'source_site_id': sourceSiteId,
      'total_chapters': totalChapters,
      'total_word_count': totalWordCount,
      'read_count': readCount,
      'heat_score': heatScore,
      'recommend_score': recommendScore,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory NovelMetadata.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = [];
    if (map['tags'] != null) {
      try {
        final decoded = jsonDecode(map['tags'] as String);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return NovelMetadata(
      id: map['id'] as String,
      title: map['title'] as String? ?? '未命名小说',
      author: map['author'] as String? ?? '佚名',
      description: map['description'] as String? ?? '',
      tags: parsedTags,
      genre: map['genre'] as String? ?? '',
      coverUrl: map['cover_url'] as String? ?? '',
      sourceUrl: map['source_url'] as String? ?? '',
      sourceSiteId: map['source_site_id'] as String? ?? '',
      totalChapters: map['total_chapters'] as int? ?? 0,
      totalWordCount: map['total_word_count'] as int? ?? 0,
      readCount: map['read_count'] as int? ?? 0,
      heatScore: (map['heat_score'] as num?)?.toDouble() ?? 0.0,
      recommendScore: (map['recommend_score'] as num?)?.toDouble() ?? 0.0,
      status: NovelStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => NovelStatus.ongoing,
      ),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 章节目录轻量索引模型（用于列表展现与断点比对）
class NovelChapterIndex {
  final String id;
  final String novelId;
  final int chapterIndex; // 从 1 开始自然递增
  final String title;
  final int wordCount;
  final String? summary; // AI提取的剧情高潮/关键场景简要
  final String? originChapterUrl; // 原始采集 URL（幂等与续采对比标识）
  final ChapterStatus status;
  final DateTime updatedAt;

  const NovelChapterIndex({
    required this.id,
    required this.novelId,
    required this.chapterIndex,
    required this.title,
    this.wordCount = 0,
    this.summary,
    this.originChapterUrl,
    this.status = ChapterStatus.synced,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'novel_id': novelId,
      'chapter_index': chapterIndex,
      'title': title,
      'word_count': wordCount,
      'summary': summary,
      'origin_chapter_url': originChapterUrl,
      'status': status.name,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory NovelChapterIndex.fromMap(Map<String, dynamic> map) {
    return NovelChapterIndex(
      id: map['id'] as String,
      novelId: map['novel_id'] as String,
      chapterIndex: map['chapter_index'] as int,
      title: map['title'] as String? ?? '',
      wordCount: map['word_count'] as int? ?? 0,
      summary: map['summary'] as String?,
      originChapterUrl: map['origin_chapter_url'] as String?,
      status: ChapterStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => ChapterStatus.synced,
      ),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// 完整章节模型（包含正文）
class NovelChapter {
  final NovelChapterIndex index;
  final String content; // 章节完整纯文本/Markdown

  const NovelChapter({
    required this.index,
    required this.content,
  });

  String get id => index.id;
  String get novelId => index.novelId;
  int get chapterIndex => index.chapterIndex;
  String get title => index.title;
  int get wordCount => content.length;
}

/// 采集站点配置与解析规则模型
class SiteScraperRule {
  final String id;
  final String name;             // 站点名称，如: 书海中文网
  final String baseUrl;          // 根域名，如: https://www.szlajc.com
  final bool enableBypass;       // 是否启用反爬穿透 (Firecrawl / 原生 WebView)
  final String tocUrlPattern;    // 目录页 URL 规则模板
  final String tocSelector;      // 目录章节超链接 CSS 选择器
  final String contentSelector;  // 正文容器 CSS 选择器
  final String titleSelector;    // 章节标题 CSS 选择器
  final String catalogUrl;       // 站点小说库/书库列表页面 URL，如: https://www.szlajc.com/class/1_1/
  final String catalogSelector;  // 站点小说库书籍条目 CSS 选择器，如: #newscontent ul li
  final List<String> removeSelectors; // 需移除的广告干扰选择器
  final Map<String, String> customHeaders;
  final int requestDelayMs;      // 章节间抓取延时（防限频）
  final bool isCronEnabled;      // 是否开启定时巡检任务
  final String cronExpression;   // Cron 表达式或巡检间隔
  final DateTime? lastCrawledAt;

  final Map<String, String> categoryMap; // 分类字典映射，如 {'1': '玄幻奇幻', '2': '武侠仙侠', ...}

  const SiteScraperRule({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.enableBypass = false,
    this.tocUrlPattern = '',
    this.tocSelector = '',
    this.contentSelector = '',
    this.titleSelector = '',
    this.catalogUrl = '',
    this.catalogSelector = '',
    this.categoryMap = const {},
    this.removeSelectors = const [],
    this.customHeaders = const {},
    this.requestDelayMs = 500,
    this.isCronEnabled = false,
    this.cronExpression = '0 */6 * * *',
    this.lastCrawledAt,
  });

  SiteScraperRule copyWith({
    String? id,
    String? name,
    String? baseUrl,
    bool? enableBypass,
    String? tocUrlPattern,
    String? tocSelector,
    String? contentSelector,
    String? titleSelector,
    String? catalogUrl,
    String? catalogSelector,
    Map<String, String>? categoryMap,
    List<String>? removeSelectors,
    Map<String, String>? customHeaders,
    int? requestDelayMs,
    bool? isCronEnabled,
    String? cronExpression,
    DateTime? lastCrawledAt,
  }) {
    return SiteScraperRule(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      enableBypass: enableBypass ?? this.enableBypass,
      tocUrlPattern: tocUrlPattern ?? this.tocUrlPattern,
      tocSelector: tocSelector ?? this.tocSelector,
      contentSelector: contentSelector ?? this.contentSelector,
      titleSelector: titleSelector ?? this.titleSelector,
      catalogUrl: catalogUrl ?? this.catalogUrl,
      catalogSelector: catalogSelector ?? this.catalogSelector,
      categoryMap: categoryMap ?? this.categoryMap,
      removeSelectors: removeSelectors ?? this.removeSelectors,
      customHeaders: customHeaders ?? this.customHeaders,
      requestDelayMs: requestDelayMs ?? this.requestDelayMs,
      isCronEnabled: isCronEnabled ?? this.isCronEnabled,
      cronExpression: cronExpression ?? this.cronExpression,
      lastCrawledAt: lastCrawledAt ?? this.lastCrawledAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'base_url': baseUrl,
      'enable_bypass': enableBypass ? 1 : 0,
      'toc_url_pattern': tocUrlPattern,
      'toc_selector': tocSelector,
      'content_selector': contentSelector,
      'title_selector': titleSelector,
      'catalog_url': catalogUrl,
      'catalog_selector': catalogSelector,
      'category_map': jsonEncode(categoryMap),
      'remove_selectors': jsonEncode(removeSelectors),
      'custom_headers': jsonEncode(customHeaders),
      'request_delay_ms': requestDelayMs,
      'is_cron_enabled': isCronEnabled ? 1 : 0,
      'cron_expression': cronExpression,
      'last_crawled_at': lastCrawledAt?.toIso8601String(),
    };
  }

  factory SiteScraperRule.fromMap(Map<String, dynamic> map) {
    List<String> removes = [];
    if (map['remove_selectors'] != null) {
      try {
        final decoded = jsonDecode(map['remove_selectors'] as String);
        if (decoded is List) removes = decoded.map((e) => e.toString()).toList();
      } catch (_) {}
    }

    Map<String, String> headers = {};
    if (map['custom_headers'] != null) {
      try {
        final decoded = jsonDecode(map['custom_headers'] as String);
        if (decoded is Map) {
          headers = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    Map<String, String> parsedCategories = {};
    if (map['category_map'] != null) {
      try {
        final decoded = jsonDecode(map['category_map'] as String);
        if (decoded is Map) {
          parsedCategories = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    return SiteScraperRule(
      id: map['id'] as String,
      name: map['name'] as String? ?? '未命名书源',
      baseUrl: map['base_url'] as String? ?? '',
      enableBypass: (map['enable_bypass'] as int? ?? 0) == 1,
      tocUrlPattern: map['toc_url_pattern'] as String? ?? '',
      tocSelector: map['toc_selector'] as String? ?? '',
      contentSelector: map['content_selector'] as String? ?? '',
      titleSelector: map['title_selector'] as String? ?? '',
      catalogUrl: map['catalog_url'] as String? ?? '',
      catalogSelector: map['catalog_selector'] as String? ?? '',
      categoryMap: parsedCategories,
      removeSelectors: removes,
      customHeaders: headers,
      requestDelayMs: map['request_delay_ms'] as int? ?? 500,
      isCronEnabled: (map['is_cron_enabled'] as int? ?? 0) == 1,
      cronExpression: map['cron_expression'] as String? ?? '0 */6 * * *',
      lastCrawledAt: DateTime.tryParse(map['last_crawled_at'] as String? ?? ''),
    );
  }
}

/// 站点书库探索发现的小说条目（用于批量勾选采集）
class DiscoveredNovelItem {
  final String title;
  final String rawTitle; // 原始标题（含SEO尾巴，去重仲裁用）
  final String author;
  final String detailUrl;
  final String? coverUrl;
  final String? category;
  final String? latestChapter;
  final String? lastUpdated;

  const DiscoveredNovelItem({
    required this.title,
    String? rawTitle,
    required this.author,
    required this.detailUrl,
    this.coverUrl,
    this.category,
    this.latestChapter,
    this.lastUpdated,
  }) : rawTitle = rawTitle ?? title;

  /// 从 detailUrl 中智能提取小说数字或字符串 ID
  String get bookId {
    final uri = Uri.tryParse(detailUrl);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return segs.last;
    }
    return detailUrl;
  }

  DiscoveredNovelItem copyWith({
    String? title,
    String? rawTitle,
    String? author,
    String? detailUrl,
    String? coverUrl,
    String? category,
    String? latestChapter,
    String? lastUpdated,
  }) {
    return DiscoveredNovelItem(
      title: title ?? this.title,
      rawTitle: rawTitle ?? this.rawTitle,
      author: author ?? this.author,
      detailUrl: detailUrl ?? this.detailUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      category: category ?? this.category,
      latestChapter: latestChapter ?? this.latestChapter,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}


