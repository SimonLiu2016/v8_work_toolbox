import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'private_browser_store.dart';

/// 浏览器标签页模型
class BrowserTabItem {
  final String id;
  final String url;
  final String title;
  final double scrollX;
  final double scrollY;
  final int orderIndex;
  final DateTime createdAt;

  const BrowserTabItem({
    required this.id,
    required this.url,
    required this.title,
    this.scrollX = 0,
    this.scrollY = 0,
    this.orderIndex = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'url': url,
    'title': title,
    'scroll_x': scrollX,
    'scroll_y': scrollY,
    'order_index': orderIndex,
    'created_at': createdAt.toIso8601String(),
  };

  factory BrowserTabItem.fromMap(Map<String, dynamic> map) => BrowserTabItem(
    id: map['id'] as String,
    url: map['url'] as String? ?? '',
    title: map['title'] as String? ?? '新标签页',
    scrollX: (map['scroll_x'] as num?)?.toDouble() ?? 0,
    scrollY: (map['scroll_y'] as num?)?.toDouble() ?? 0,
    orderIndex: map['order_index'] as int? ?? 0,
    createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
  );

  BrowserTabItem copyWith({
    String? url,
    String? title,
    double? scrollX,
    double? scrollY,
    int? orderIndex,
  }) => BrowserTabItem(
    id: id,
    url: url ?? this.url,
    title: title ?? this.title,
    scrollX: scrollX ?? this.scrollX,
    scrollY: scrollY ?? this.scrollY,
    orderIndex: orderIndex ?? this.orderIndex,
    createdAt: createdAt,
  );
}

/// 浏览器书签模型
class BrowserBookmarkItem {
  final String id;
  final String url;
  final String title;
  final String? faviconPath;
  final DateTime createdAt;

  const BrowserBookmarkItem({
    required this.id,
    required this.url,
    required this.title,
    this.faviconPath,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'url': url,
    'title': title,
    'favicon_path': faviconPath,
    'created_at': createdAt.toIso8601String(),
  };

  factory BrowserBookmarkItem.fromMap(Map<String, dynamic> map) => BrowserBookmarkItem(
    id: map['id'] as String,
    url: map['url'] as String? ?? '',
    title: map['title'] as String? ?? '未命名书签',
    faviconPath: map['favicon_path'] as String?,
    createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
  );
}

/// N 宫格快捷方式模型
class HomepageShortcutItem {
  final String id;
  final String name;
  final String url;
  final String? faviconUrl;
  final String? faviconPath;
  final int orderIndex;

  const HomepageShortcutItem({
    required this.id,
    required this.name,
    required this.url,
    this.faviconUrl,
    this.faviconPath,
    this.orderIndex = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'url': url,
    'favicon_url': faviconUrl,
    'favicon_path': faviconPath,
    'order_index': orderIndex,
  };

  factory HomepageShortcutItem.fromMap(Map<String, dynamic> map) => HomepageShortcutItem(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    url: map['url'] as String? ?? '',
    faviconUrl: map['favicon_url'] as String?,
    faviconPath: map['favicon_path'] as String?,
    orderIndex: map['order_index'] as int? ?? 0,
  );

  HomepageShortcutItem copyWith({
    String? name,
    String? url,
    String? faviconUrl,
    String? faviconPath,
    int? orderIndex,
  }) => HomepageShortcutItem(
    id: id,
    name: name ?? this.name,
    url: url ?? this.url,
    faviconUrl: faviconUrl ?? this.faviconUrl,
    faviconPath: faviconPath ?? this.faviconPath,
    orderIndex: orderIndex ?? this.orderIndex,
  );
}

/// 视频分类树节点模型
class VideoCategoryItem {
  final String id;
  final String name;
  final String? parentId;
  final String? icon;
  final int displayOrder;

  const VideoCategoryItem({
    required this.id,
    required this.name,
    this.parentId,
    this.icon,
    this.displayOrder = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'parent_id': parentId,
    'icon': icon,
    'display_order': displayOrder,
  };

  factory VideoCategoryItem.fromMap(Map<String, dynamic> map) => VideoCategoryItem(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    parentId: map['parent_id'] as String?,
    icon: map['icon'] as String?,
    displayOrder: map['display_order'] as int? ?? 0,
  );

  VideoCategoryItem copyWith({
    String? name,
    String? parentId,
    String? icon,
    int? displayOrder,
  }) => VideoCategoryItem(
    id: id,
    name: name ?? this.name,
    parentId: parentId ?? this.parentId,
    icon: icon ?? this.icon,
    displayOrder: displayOrder ?? this.displayOrder,
  );
}

/// 标签模型
class VideoTagItem {
  final String id;
  final String name;
  final String? color;
  final int usageCount;

  const VideoTagItem({
    required this.id,
    required this.name,
    this.color,
    this.usageCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'color': color,
    'usage_count': usageCount,
  };

  factory VideoTagItem.fromMap(Map<String, dynamic> map) => VideoTagItem(
    id: map['id'] as String,
    name: map['name'] as String? ?? '',
    color: map['color'] as String?,
    usageCount: map['usage_count'] as int? ?? 0,
  );

  VideoTagItem copyWith({
    String? name,
    String? color,
    int? usageCount,
  }) => VideoTagItem(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    usageCount: usageCount ?? this.usageCount,
  );
}

/// 视频收藏记录模型
class VideoBookmarkItem {
  final String id;
  final String title;
  final String url;
  final String platform;
  final String? thumbnailPath;
  final int duration;
  final DateTime addedAt;
  final String? categoryId;
  final int rating;
  final String? notes;
  final String? aiSummary;
  final List<String> aiTags;
  final List<String> tagIds;

  const VideoBookmarkItem({
    required this.id,
    required this.title,
    required this.url,
    required this.platform,
    this.thumbnailPath,
    this.duration = 0,
    required this.addedAt,
    this.categoryId,
    this.rating = 0,
    this.notes,
    this.aiSummary,
    this.aiTags = const [],
    this.tagIds = const [],
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'title': title,
    'url': url,
    'platform': platform,
    'thumbnail_path': thumbnailPath,
    'duration': duration,
    'added_at': addedAt.toIso8601String(),
    'category_id': categoryId,
    'rating': rating,
    'notes': notes,
    'ai_summary': aiSummary,
    'ai_tags_json': jsonEncode(aiTags),
  };

  factory VideoBookmarkItem.fromMap(
    Map<String, dynamic> map, {
    List<String> tags = const [],
  }) {
    List<String> parsedAiTags = const [];
    final rawAi = map['ai_tags_json'];
    if (rawAi is String && rawAi.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAi);
        if (decoded is List) {
          parsedAiTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }

    return VideoBookmarkItem(
      id: map['id'] as String,
      title: map['title'] as String? ?? '未命名视频',
      url: map['url'] as String? ?? '',
      platform: map['platform'] as String? ?? 'web',
      thumbnailPath: map['thumbnail_path'] as String?,
      duration: map['duration'] as int? ?? 0,
      addedAt: DateTime.tryParse(map['added_at'] as String? ?? '') ?? DateTime.now(),
      categoryId: map['category_id'] as String?,
      rating: map['rating'] as int? ?? 0,
      notes: map['notes'] as String?,
      aiSummary: map['ai_summary'] as String?,
      aiTags: parsedAiTags,
      tagIds: tags,
    );
  }

  VideoBookmarkItem copyWith({
    String? title,
    String? url,
    String? platform,
    String? thumbnailPath,
    int? duration,
    String? categoryId,
    int? rating,
    String? notes,
    String? aiSummary,
    List<String>? aiTags,
    List<String>? tagIds,
  }) => VideoBookmarkItem(
    id: id,
    title: title ?? this.title,
    url: url ?? this.url,
    platform: platform ?? this.platform,
    thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    duration: duration ?? this.duration,
    addedAt: addedAt,
    categoryId: categoryId ?? this.categoryId,
    rating: rating ?? this.rating,
    notes: notes ?? this.notes,
    aiSummary: aiSummary ?? this.aiSummary,
    aiTags: aiTags ?? this.aiTags,
    tagIds: tagIds ?? this.tagIds,
  );
}

/// 隐私空间私密浏览器与视频库 Repository
class PrivateBrowserRepository {
  final PrivateBrowserStore _store;
  static const _uuid = Uuid();

  PrivateBrowserRepository([PrivateBrowserStore? store])
      : _store = store ?? PrivateBrowserStore.instance;

  // ---------------------------------------------------------------------------
  // 1. 标签页操作 (Tabs)
  // ---------------------------------------------------------------------------

  Future<List<BrowserTabItem>> getTabs() async {
    final db = await _store.database;
    final rows = await db.query('browser_tabs', orderBy: 'order_index ASC');
    return rows.map(BrowserTabItem.fromMap).toList();
  }

  Future<void> saveTabs(List<BrowserTabItem> tabs) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.delete('browser_tabs');
      for (int i = 0; i < tabs.length; i++) {
        final t = tabs[i].copyWith(orderIndex: i);
        await txn.insert('browser_tabs', t.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> addTab(BrowserTabItem tab) async {
    final db = await _store.database;
    await db.insert('browser_tabs', tab.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateTab(BrowserTabItem tab) async {
    final db = await _store.database;
    await db.update('browser_tabs', tab.toMap(), where: 'id = ?', whereArgs: [tab.id]);
  }

  Future<void> removeTab(String id) async {
    final db = await _store.database;
    await db.delete('browser_tabs', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // 2. 书签操作 (Bookmarks)
  // ---------------------------------------------------------------------------

  Future<List<BrowserBookmarkItem>> getBookmarks() async {
    final db = await _store.database;
    final rows = await db.query('browser_bookmarks', orderBy: 'created_at DESC');
    return rows.map(BrowserBookmarkItem.fromMap).toList();
  }

  Future<void> addBookmark(BrowserBookmarkItem bookmark) async {
    final db = await _store.database;
    await db.insert('browser_bookmarks', bookmark.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeBookmark(String id) async {
    final db = await _store.database;
    await db.delete('browser_bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<bool> isBookmarked(String url) async {
    final db = await _store.database;
    final rows = await db.query('browser_bookmarks', where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // 3. 首页快捷方式 (Homepage Shortcuts)
  // ---------------------------------------------------------------------------

  Future<List<HomepageShortcutItem>> getShortcuts() async {
    final db = await _store.database;
    final rows = await db.query('homepage_shortcuts', orderBy: 'order_index ASC');
    if (rows.isEmpty) {
      // 预置常用默认站点
      final defaults = [
        HomepageShortcutItem(id: _uuid.v4(), name: 'YouTube', url: 'https://www.youtube.com', orderIndex: 0),
        HomepageShortcutItem(id: _uuid.v4(), name: 'MissAV', url: 'https://missav.ai', orderIndex: 1),
        HomepageShortcutItem(id: _uuid.v4(), name: 'jav.sb', url: 'https://jav.sb', orderIndex: 2),
        HomepageShortcutItem(id: _uuid.v4(), name: 'PornHub', url: 'https://www.pornhub.com', orderIndex: 3),
        HomepageShortcutItem(id: _uuid.v4(), name: '91Porn', url: 'https://91porn.com', orderIndex: 4),
        HomepageShortcutItem(id: _uuid.v4(), name: 'PornLulu', url: 'https://pornlulu.com', orderIndex: 5),
      ];
      for (final s in defaults) {
        await db.insert('homepage_shortcuts', s.toMap());
      }
      return defaults;
    }
    return rows.map(HomepageShortcutItem.fromMap).toList();
  }

  Future<void> saveShortcuts(List<HomepageShortcutItem> list) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.delete('homepage_shortcuts');
      for (int i = 0; i < list.length; i++) {
        final item = list[i].copyWith(orderIndex: i);
        await txn.insert('homepage_shortcuts', item.toMap());
      }
    });
  }

  Future<void> addShortcut(HomepageShortcutItem item) async {
    final db = await _store.database;
    await db.insert('homepage_shortcuts', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeShortcut(String id) async {
    final db = await _store.database;
    await db.delete('homepage_shortcuts', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // 4. 分类树操作 (Categories)
  // ---------------------------------------------------------------------------

  Future<List<VideoCategoryItem>> getCategories() async {
    final db = await _store.database;
    final rows = await db.query('categories', orderBy: 'display_order ASC, name ASC');
    return rows.map(VideoCategoryItem.fromMap).toList();
  }

  Future<void> addCategory(VideoCategoryItem category) async {
    final db = await _store.database;
    await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateCategory(VideoCategoryItem category) async {
    final db = await _store.database;
    await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }

  Future<void> deleteCategory(String id) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      // 将关联到该分类的子分类 parent_id 置为 NULL
      await txn.update('categories', {'parent_id': null}, where: 'parent_id = ?', whereArgs: [id]);
      // 将关联书签的 category_id 置为 NULL
      await txn.update('video_bookmarks', {'category_id': null}, where: 'category_id = ?', whereArgs: [id]);
      await txn.delete('categories', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ---------------------------------------------------------------------------
  // 5. 标签操作 (Tags)
  // ---------------------------------------------------------------------------

  Future<List<VideoTagItem>> getTags() async {
    final db = await _store.database;
    final rows = await db.query('tags', orderBy: 'usage_count DESC, name ASC');
    return rows.map(VideoTagItem.fromMap).toList();
  }

  Future<VideoTagItem> getOrCreateTag(String name, {String? color}) async {
    final db = await _store.database;
    final trimmed = name.trim();
    final rows = await db.query('tags', where: 'name = ?', whereArgs: [trimmed], limit: 1);
    if (rows.isNotEmpty) {
      return VideoTagItem.fromMap(rows.first);
    }
    final tag = VideoTagItem(id: _uuid.v4(), name: trimmed, color: color);
    await db.insert('tags', tag.toMap());
    return tag;
  }

  Future<void> deleteTag(String id) async {
    final db = await _store.database;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // 6. 视频收藏记录 (Video Bookmarks)
  // ---------------------------------------------------------------------------

  Future<List<VideoBookmarkItem>> getBookmarksFiltered({
    String? categoryId,
    String? tagId,
    String? platform,
    int? minRating,
    String? searchQuery,
    String sortOrder = 'added_at_desc',
  }) async {
    final db = await _store.database;

    String? whereClause;
    List<Object?> whereArgs = [];

    if (categoryId != null && categoryId.isNotEmpty) {
      whereClause = 'category_id = ?';
      whereArgs.add(categoryId);
    }

    if (platform != null && platform.isNotEmpty) {
      whereClause = whereClause == null ? 'platform = ?' : '$whereClause AND platform = ?';
      whereArgs.add(platform);
    }

    if (minRating != null && minRating > 0) {
      whereClause = whereClause == null ? 'rating >= ?' : '$whereClause AND rating >= ?';
      whereArgs.add(minRating);
    }

    // 标签过滤联表
    String querySql;
    if (tagId != null && tagId.isNotEmpty) {
      final tagFilter = 'id IN (SELECT bookmark_id FROM bookmark_tags WHERE tag_id = ?)';
      whereArgs.insert(0, tagId);
      whereClause = whereClause == null ? tagFilter : '$tagFilter AND $whereClause';
    }

    // 全文检索过滤
    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final trimmed = searchQuery.trim().replaceAll("'", "''");
      final ftsFilter = '''
        (id IN (SELECT b.id FROM video_bookmarks b JOIN video_bookmarks_fts f ON b.rowid = f.rowid WHERE video_bookmarks_fts MATCH '$trimmed*')
         OR title LIKE ? OR notes LIKE ?)
      ''';
      whereArgs.add('%$trimmed%');
      whereArgs.add('%$trimmed%');
      whereClause = whereClause == null ? ftsFilter : '$whereClause AND $ftsFilter';
    }

    String orderBy;
    switch (sortOrder) {
      case 'rating_desc':
        orderBy = 'rating DESC, added_at DESC';
        break;
      case 'title_asc':
        orderBy = 'title ASC';
        break;
      case 'added_at_desc':
      default:
        orderBy = 'added_at DESC';
        break;
    }

    final rows = await db.query(
      'video_bookmarks',
      where: whereClause,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: orderBy,
    );

    // 提取全部 tag 关联
    final result = <VideoBookmarkItem>[];
    for (final row in rows) {
      final bId = row['id'] as String;
      final tagRows = await db.query('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [bId]);
      final tags = tagRows.map((tr) => tr['tag_id'] as String).toList();
      result.add(VideoBookmarkItem.fromMap(row, tags: tags));
    }
    return result;
  }

  Future<void> addVideoBookmark(VideoBookmarkItem bookmark) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.insert('video_bookmarks', bookmark.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      for (final tid in bookmark.tagIds) {
        await txn.insert('bookmark_tags', {'bookmark_id': bookmark.id, 'tag_id': tid},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await txn.rawUpdate('UPDATE tags SET usage_count = usage_count + 1 WHERE id = ?', [tid]);
      }
    });
  }

  Future<void> updateVideoBookmark(VideoBookmarkItem bookmark) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      await txn.update('video_bookmarks', bookmark.toMap(), where: 'id = ?', whereArgs: [bookmark.id]);

      // 重新同步标签关联
      await txn.delete('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [bookmark.id]);
      for (final tid in bookmark.tagIds) {
        await txn.insert('bookmark_tags', {'bookmark_id': bookmark.id, 'tag_id': tid},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
  }

  Future<void> deleteVideoBookmark(String id) async {
    final db = await _store.database;
    await db.transaction((txn) async {
      // 减 usage_count
      final tagRows = await txn.query('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [id]);
      for (final tr in tagRows) {
        final tid = tr['tag_id'] as String;
        await txn.rawUpdate('UPDATE tags SET usage_count = MAX(0, usage_count - 1) WHERE id = ?', [tid]);
      }
      await txn.delete('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [id]);
      await txn.delete('video_bookmarks', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<VideoBookmarkItem?> getVideoBookmarkById(String id) async {
    final db = await _store.database;
    final rows = await db.query('video_bookmarks', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    final tagRows = await db.query('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [id]);
    final tags = tagRows.map((tr) => tr['tag_id'] as String).toList();
    return VideoBookmarkItem.fromMap(rows.first, tags: tags);
  }

  Future<bool> isVideoBookmarked(String url) async {
    if (url.isEmpty) return false;
    final db = await _store.database;
    final rows = await db.query('video_bookmarks', where: 'url = ?', whereArgs: [url], limit: 1);
    return rows.isNotEmpty;
  }

  Future<VideoBookmarkItem?> getVideoBookmarkByUrl(String url) async {
    if (url.isEmpty) return null;
    final db = await _store.database;
    final rows = await db.query('video_bookmarks', where: 'url = ?', whereArgs: [url], limit: 1);
    if (rows.isEmpty) return null;
    final tagRows = await db.query('bookmark_tags', where: 'bookmark_id = ?', whereArgs: [rows.first['id']]);
    final tags = tagRows.map((tr) => tr['tag_id'] as String).toList();
    return VideoBookmarkItem.fromMap(rows.first, tags: tags);
  }
}
