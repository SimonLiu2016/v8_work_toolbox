/// 随心短剧数据模型定义
library;

class DramaCard {
  final int id;
  final String title;
  final String cover;
  final String? description;
  final List<String> tags;
  final double score;
  final int episodeCount;
  final int totalEpisodes;
  final int hot;
  final int likeCount;
  final int collectCount;
  final bool isFinished;
  final String? authorName;
  final int? lastEpAt;

  const DramaCard({
    required this.id,
    required this.title,
    required this.cover,
    this.description,
    this.tags = const [],
    this.score = 0.0,
    this.episodeCount = 0,
    this.totalEpisodes = 0,
    this.hot = 0,
    this.likeCount = 0,
    this.collectCount = 0,
    this.isFinished = false,
    this.authorName,
    this.lastEpAt,
  });

  factory DramaCard.fromJson(Map<String, dynamic> json) {
    List<String> parsedTags = [];
    if (json['tags'] is List) {
      parsedTags = (json['tags'] as List).map((e) => e.toString()).toList();
    }
    String? author;
    if (json['author'] is Map && json['author']['name'] != null) {
      author = json['author']['name'].toString();
    }

    return DramaCard(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      description: json['description']?.toString(),
      tags: parsedTags,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['total_episodes'] as num?)?.toInt() ?? 0,
      hot: (json['hot'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      collectCount: (json['collect_count'] as num?)?.toInt() ?? 0,
      isFinished: json['is_finished'] == true || json['is_finished'] == 1,
      authorName: author,
      lastEpAt: (json['last_ep_at'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'cover': cover,
    'description': description,
    'tags': tags,
    'score': score,
    'episode_count': episodeCount,
    'total_episodes': totalEpisodes,
    'hot': hot,
    'like_count': likeCount,
    'collect_count': collectCount,
    'is_finished': isFinished,
    'author_name': authorName,
    'last_ep_at': lastEpAt,
  };
}

class DramaEpisode {
  final int epNum;
  final String title;
  final int duration;
  final int status;

  const DramaEpisode({
    required this.epNum,
    required this.title,
    this.duration = 0,
    this.status = 1,
  });

  factory DramaEpisode.fromJson(Map<String, dynamic> json) {
    return DramaEpisode(
      epNum: (json['ep_num'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '第${json['ep_num']}集',
      duration: (json['duration'] as num?)?.toInt() ?? 0,
      status: (json['status'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'ep_num': epNum,
    'title': title,
    'duration': duration,
    'status': status,
  };
}

class DramaDetail {
  final int id;
  final String title;
  final String description;
  final String cover;
  final List<String> tags;
  final double score;
  final int episodeCount;
  final int totalEpisodes;
  final List<DramaEpisode> episodes;
  final String? authorName;
  final int hot;
  final int collectCount;
  final int likeCount;
  final bool isFinished;
  final String? defaultVideoUrl;

  const DramaDetail({
    required this.id,
    required this.title,
    required this.description,
    required this.cover,
    this.tags = const [],
    this.score = 0.0,
    this.episodeCount = 0,
    this.totalEpisodes = 0,
    this.episodes = const [],
    this.authorName,
    this.hot = 0,
    this.collectCount = 0,
    this.likeCount = 0,
    this.isFinished = false,
    this.defaultVideoUrl,
  });

  factory DramaDetail.fromJson(Map<String, dynamic> json) {
    List<String> parsedTags = [];
    if (json['tags'] is List) {
      parsedTags = (json['tags'] as List).map((e) => e.toString()).toList();
    }
    List<DramaEpisode> eps = [];
    if (json['episodes'] is List) {
      eps = (json['episodes'] as List)
          .map((e) => DramaEpisode.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    String? author;
    if (json['author'] is Map && json['author']['name'] != null) {
      author = json['author']['name'].toString();
    }

    int hotVal = 0;
    int collectVal = 0;
    int likeVal = 0;
    if (json['counts'] is Map) {
      hotVal = (json['counts']['hot'] as num?)?.toInt() ?? 0;
      collectVal = (json['counts']['collect'] as num?)?.toInt() ?? 0;
      likeVal = (json['counts']['like'] as num?)?.toInt() ?? 0;
    }

    return DramaDetail(
      id: (json['id'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      tags: parsedTags,
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      episodeCount: (json['episode_count'] as num?)?.toInt() ?? 0,
      totalEpisodes: (json['total_episodes'] as num?)?.toInt() ?? 0,
      episodes: eps,
      authorName: author,
      hot: hotVal,
      collectCount: collectVal,
      likeCount: likeVal,
      isFinished: json['is_finished'] == true || json['is_finished'] == 1,
      defaultVideoUrl: json['video_url']?.toString(),
    );
  }
}

class DramaPlayInfo {
  final int id;
  final int epNum;
  final int duration;
  final String title;
  final String videoUrl;
  final String? videoUrlHevc;

  const DramaPlayInfo({
    required this.id,
    required this.epNum,
    this.duration = 0,
    required this.title,
    required this.videoUrl,
    this.videoUrlHevc,
  });

  factory DramaPlayInfo.fromJson(Map<String, dynamic> json) {
    // 兼容上游最新 POST playback 协议返回的嵌套 episode 或根层级平铺数据
    final epMap = json['episode'] is Map
        ? Map<String, dynamic>.from(json['episode'] as Map)
        : json;
    final streams = json['streams'] is Map
        ? Map<String, dynamic>.from(json['streams'] as Map)
        : const <String, dynamic>{};

    final mainStream = streams['main']?.toString() ?? '';
    final previewStream = streams['preview']?.toString() ?? '';
    final hevcStream = streams['hevc']?.toString() ?? '';
    final directUrl = json['video_url']?.toString() ?? '';

    // 优先取 main 流，其次取 preview 流，再次取 hevc 流，最后回退 directUrl
    final resolvedVideoUrl = mainStream.isNotEmpty
        ? mainStream
        : (previewStream.isNotEmpty
            ? previewStream
            : (hevcStream.isNotEmpty ? hevcStream : directUrl));

    final parsedId = _safeInt(epMap['id'] ?? epMap['video_id'] ?? json['id'] ?? json['video_id']);
    final parsedEp = _safeInt(
      epMap['ep_num'] ?? epMap['ep'] ?? json['ep_num'] ?? json['ep'],
      1,
    );
    final parsedDuration = _safeInt(epMap['duration'] ?? json['duration']);

    return DramaPlayInfo(
      id: parsedId,
      epNum: parsedEp,
      duration: parsedDuration,
      title: epMap['title']?.toString() ?? json['title']?.toString() ?? '',
      videoUrl: resolvedVideoUrl,
      videoUrlHevc: hevcStream.isNotEmpty ? hevcStream : json['video_url_hevc']?.toString(),
    );
  }

  static int _safeInt(dynamic val, [int fallback = 0]) {
    if (val == null) return fallback;
    if (val is num) return val.toInt();
    if (val is String) {
      final trimmed = val.trim();
      return int.tryParse(trimmed) ?? (double.tryParse(trimmed)?.toInt() ?? fallback);
    }
    return fallback;
  }
}

class LineItem {
  final String name;
  final String url;
  final int? latencyMs;
  final bool isReachable;

  const LineItem({
    required this.name,
    required this.url,
    this.latencyMs,
    this.isReachable = true,
  });

  LineItem copyWith({
    String? name,
    String? url,
    int? latencyMs,
    bool? isReachable,
  }) {
    return LineItem(
      name: name ?? this.name,
      url: url ?? this.url,
      latencyMs: latencyMs ?? this.latencyMs,
      isReachable: isReachable ?? this.isReachable,
    );
  }
}

class LineState {
  final String currentBase;
  final List<LineItem> fixedLines;
  final List<LineItem> mirrorLines;

  const LineState({
    required this.currentBase,
    required this.fixedLines,
    this.mirrorLines = const [],
  });
}

class DramaFavoriteItem {
  final int dramaId;
  final String title;
  final String cover;
  final int episodeCount;
  final DateTime addedAt;

  const DramaFavoriteItem({
    required this.dramaId,
    required this.title,
    required this.cover,
    required this.episodeCount,
    required this.addedAt,
  });

  factory DramaFavoriteItem.fromMap(Map<String, dynamic> map) {
    return DramaFavoriteItem(
      dramaId: map['drama_id'] as int,
      title: map['title'] as String,
      cover: map['cover'] as String,
      episodeCount: (map['episode_count'] as int?) ?? 0,
      addedAt: DateTime.fromMillisecondsSinceEpoch(map['added_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
    'drama_id': dramaId,
    'title': title,
    'cover': cover,
    'episode_count': episodeCount,
    'added_at': addedAt.millisecondsSinceEpoch,
  };
}

class DramaHistoryItem {
  final int dramaId;
  final String title;
  final String cover;
  final int lastWatchedEp;
  final int positionMs;
  final int durationMs;
  final DateTime updatedAt;

  const DramaHistoryItem({
    required this.dramaId,
    required this.title,
    required this.cover,
    required this.lastWatchedEp,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAt,
  });

  factory DramaHistoryItem.fromMap(Map<String, dynamic> map) {
    return DramaHistoryItem(
      dramaId: map['drama_id'] as int,
      title: map['title'] as String,
      cover: map['cover'] as String,
      lastWatchedEp: (map['last_watched_ep'] as int?) ?? 1,
      positionMs: (map['position_ms'] as int?) ?? 0,
      durationMs: (map['duration_ms'] as int?) ?? 0,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
    'drama_id': dramaId,
    'title': title,
    'cover': cover,
    'last_watched_ep': lastWatchedEp,
    'position_ms': positionMs,
    'duration_ms': durationMs,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// 片库排序类型
enum DramaSortType {
  defaultOrder('默认排序'),
  scoreDesc('评分最高 ★'),
  episodesDesc('集数最多');

  final String label;
  const DramaSortType(this.label);
}
