/// CoderSlingo 听力页面的抓取与解析。
///
/// 站点是 Astro 静态站，对话正文在 `<pre class="transcript-text">` 里，每块
/// transcript 是一个独立对话。页面里的轮次形如：
///
///   `Lena (Scrum Master): "Good morning everyone. Let\'s keep it quick."`
///   `IC: "Do we have a theory on root cause yet?"`
///
/// 开头的方括号行（如 `[Live incident bridge call — SEV-1. ...]`）是场景说明，
/// 不是对话轮次。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/listening_models.dart';
import 'listening_source.dart';

/// 抓取失败的原因分类。
///
/// 分开报而不是笼统的"抓取失败"：站点改版（结构变化）与网络故障需要完全
/// 不同的处置方式，混在一起会让用户无法判断该重试还是该等站点修。
enum FetchFailureKind {
  networkUnreachable,
  httpNotFound,
  httpError,
  structureChanged,
  emptyPage,
  robotsDisallowed,
}

/// 站点搜索索引的单条记录。
class SearchIndexEntry {
  /// 条目类型（'Page' / 分类名）。
  final String type;

  /// 条目标题。
  final String title;

  /// 站内路径（以 `/` 开头）。
  final String url;

  /// 条目描述。
  final String description;

  const SearchIndexEntry({
    required this.type,
    required this.title,
    required this.url,
    required this.description,
  });

  /// 从搜索索引的一条记录解析。
  ///
  /// 站点的字段是单字母（`t`/`d`/`u`/`c`），这里做一次形状映射。
  static SearchIndexEntry? fromJson(Map<String, dynamic> json) {
    final url = json['u'] as String? ?? '';
    if (url.isEmpty) return null;
    return SearchIndexEntry(
      type: json['t'] as String? ?? '',
      title: json['d'] as String? ?? '',
      url: url,
      description: json['c'] as String? ?? '',
    );
  }
}

/// 抓取失败异常。
class ClipFetchException implements Exception {
  final FetchFailureKind kind;
  final String message;
  final int? statusCode;

  const ClipFetchException(this.kind, this.message, {this.statusCode});

  @override
  String toString() => message;
}

/// 一个抓取到的对话块（尚未合成的原始素材）。
class FetchedDialogue {
  /// 所属场景。
  final MeetingScene scene;

  /// 来源栏目（站点侧）。
  final String column;

  /// 原文页面地址。
  final String pageUrl;

  /// 块在页面中的序号。
  final int blockIndex;

  /// 场景说明行（可为空）。
  final String scenarioNote;

  /// 说话人轮次。
  final List<SpeakerTurn> turns;

  /// 站点栏目 slug（如 "standup-dialogues"）。
  ///
  /// 与 [column]（展示名）分开：slug 是稳定标识，用于拼素材 id；展示名可能改。
  final String columnSlug;

  const FetchedDialogue({
    required this.scene,
    required this.columnSlug,
    required this.column,
    required this.pageUrl,
    required this.blockIndex,
    required this.scenarioNote,
    required this.turns,
  });

  /// 片段标识：`{sourceId}_{sceneId}_{columnSlug}_{block}`。
  ///
  /// **含来源标识**——两个来源都提供"站会"场景时，若不带源前缀，
  /// 素材 id 会撞车，音频与文稿文件互相覆盖。
  String get clipId =>
      '${CoderSlingoSource.sourceIdentifier}_${scene.id}_${columnSlug}_$blockIndex';
}

/// 站点栏目 → 内部场景的显式映射。
///
/// **刻意不做名称模糊匹配**：站点栏目名是中文的（"站会对白" / "Live Incident
/// Bridge Calls"），靠模糊匹配会随站点改版静默漂移。显式表在站点改版时会
/// 明确报"页面结构已变化"，而不是产出错误的素材。
class CoderSlingoSource implements ListeningSource {
  /// 来源站点稳定标识。
  ///
  /// 多来源下区分素材的依据，也是素材 id 的组成部分。**不随展示名变化**。
  static const String sourceIdentifier = 'coderslingo';

  @override
  String get sourceId => CoderSlingoSource.sourceIdentifier;

  /// 站点展示名。
  static const String siteName = 'CoderSlingo';

  @override
  String get displayName => CoderSlingoSource.siteName;

  @override
  String get license => CoderSlingoSource.licenseId;

  /// 站点根。
  static const String siteRoot = 'https://coderslingo.com';

  /// 许可标识。
  static const String licenseId = 'CC BY 4.0';

  /// 采用的栏目：站点路径 → (内部场景, 站点侧栏目名)。
  ///
  /// **只收录"整段对话"形态的栏目**。站点的听力区有两种内容形态：
  /// - 对话转写（`standup-dialogues` 等）：正文是 `<pre class="transcript-text">`
  ///   里的逐句对话，能直接切出说话人轮次。
  /// - 单句问答（`conference-panels/*`、`executive-briefings/*`）：正文是一道
  ///   选择题，选项里**引用**了一句对话（"A panellist says: '...'")，但没有
  ///   完整对话、没有说话人结构、也没有音频时长。
  ///
  /// 后者不适合当听力材料——它是一道词汇题，不是一段会议。所以它们既不在
  /// 映射表里，也不会被抓取（抓取只走映射表里的栏目）。
  static const Map<String, (MeetingScene, String)> _columnMapping = {
    'standup-dialogues': (MeetingScene.standup, 'Stand-up Meeting Dialogues'),
    'incident-calls': (MeetingScene.incident, 'Live Incident Bridge Calls'),
    'sprint-planning': (MeetingScene.sprintPlanning, 'Sprint Planning & Retrospectives'),
    'architecture-talks': (MeetingScene.architecture, 'Architecture Decision Discussions'),
    'customer-support-calls': (MeetingScene.stakeholder, 'Customer Support & Help-Desk Calls'),
    'job-interviews': (MeetingScene.jobInterview, 'Job Interview Conversations'),
    'onboarding-calls': (MeetingScene.onboarding, 'Team Onboarding Calls'),
    'product-demos': (MeetingScene.productDemo, 'Product Demo Recordings'),
    'tech-talks': (MeetingScene.techTalk, 'Tech Talks & Conference Excerpts'),
    'technical-interviews': (MeetingScene.technicalInterview, 'Technical Interview Listening'),
  };

  /// 该来源采用的栏目（抽象层形态）。
  @override
  Map<String, SourceColumn> get columns => {
        for (final entry in _columnMapping.entries)
          entry.key: SourceColumn(
            sourceId: CoderSlingoSource.sourceIdentifier,
            slug: entry.key,
            displayName: entry.value.$2,
            scene: entry.value.$1,
            pageUrl: '$listeningRoot/${entry.key}/',
          ),
      };

  /// 该来源采用的栏目（静态元组形态，供需要静态访问的调用方）。
  static Map<String, (MeetingScene, String)> get columnMapping => _columnMapping;

  /// 听力栏目所在路径前缀。
  static const String listeningRoot = '$siteRoot/exercises/listening';

  /// 站点 sitemap（变更标识来源）。
  static const String sitemapUrl = '$siteRoot/sitemap.xml';

  /// 听力栏目索引页。
  ///
  /// **栏目发现走这个页面而不是 `search-index.json`**：实测后者的索引里
  /// 只有 `/exercises/listening/` 一条聚合入口，18 个子栏目一个都没有——
  /// 那份索引是给"页面搜索"用的，不覆盖子栏目。听力索引页的导航里有全部
  /// 子栏目的链接，那才是可靠的发现来源。
  static const String listeningIndexUrl = '$listeningRoot/';

  /// 发现站点上存在的听力栏目。
  ///
  /// 返回的是**站点侧**的栏目（路径 + 名称），与 [columns] 的内部映射表
  /// 交叉比对后即可知道：哪些栏目被采用、哪些还没被映射。
  Future<List<SearchIndexEntry>> discoverListeningColumns() async {
    final html = await _fetch(listeningIndexUrl);
    final out = <SearchIndexEntry>[];
    final seen = <String>{};
    // 索引页的每个子栏目都有一个指向自己的链接。
    for (final m in RegExp(r'href="(/exercises/listening/([a-z0-9-]+)/)"')
        .allMatches(html)) {
      final url = m.group(1)!;
      final slug = m.group(2)!;
      if (!seen.add(slug)) continue;
      out.add(SearchIndexEntry(
        type: 'Listening',
        title: '',
        url: url,
        description: '',
      ));
    }
    return out;
  }

  /// 发现栏目并**带上站点侧名称**。
  ///
  /// 名称来自各栏目页自己的 `<h1>`——索引页的链接文本里混着图标与
  /// 装饰元素，正则取出来是空的。18 个栏目各抓一次，只在需要展示时调用。
  Future<List<SearchIndexEntry>> discoverListeningColumnsWithNames() async {
    final columns = await discoverListeningColumns();
    final out = <SearchIndexEntry>[];
    for (final c in columns) {
      var title = '';
      try {
        final html = await _fetch('${CoderSlingoSource.siteRoot}${c.url}');
        final m = RegExp(r'<h1[^>]*>(.*?)</h1>', dotAll: true).firstMatch(html);
        if (m != null) {
          title = m
              .group(1)!
              .replaceAll(RegExp(r'<[^>]+>'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
        }
      } catch (_) {
        // 单个栏目取名失败不影响整体发现。
      }
      out.add(SearchIndexEntry(
        type: c.type,
        title: title,
        url: c.url,
        description: c.description,
      ));
    }
    return out;
  }

  /// 站点上存在、但尚未映射到内部场景的听力栏目。
  ///
  /// 这些栏目**不进入素材库**（design D10：显式映射，不做名称模糊匹配），
  /// 但把它们列出来，界面上可以提示"站点新增了 N 个栏目，尚未接入"。
  @override
  Future<List<SourceColumn>> discoverUnmappedColumns() async {
    try {
      final all = await discoverListeningColumns();
      final out = <SourceColumn>[];
      for (final e in all) {
        final slug = _slugOf(e.url);
        if (_columnMapping.containsKey(slug)) continue;
        out.add(SourceColumn(
          sourceId: CoderSlingoSource.sourceIdentifier,
          slug: slug,
          displayName: e.title,
          // 未映射的栏目没有对应场景——用一个"其它"占位，
          // 界面据此提示"尚未接入"而不是把它算进某个场景。
          scene: MeetingScene.fromId(null),
          pageUrl: '${CoderSlingoSource.siteRoot}${e.url}',
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// 从站内路径取出栏目 slug。
  static String _slugOf(String url) {
    final parts = url.split('/').where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    return parts.last;
  }

  /// 抓取用的 User-Agent。
  static const String userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  /// 请求间隔（毫秒）。站点未声明限流阈值，但保持低频是基本礼貌。
  static const Duration requestInterval = Duration(milliseconds: 800);

  /// 单次请求超时。
  static const Duration timeout = Duration(seconds: 30);

  final http.Client _client;

  CoderSlingoSource({http.Client? client}) : _client = client ?? http.Client();

  /// 抓取一个栏目下的全部对话块。
  ///
  /// [columnSlug] 必须是 [columns] 中的键。
  Future<List<FetchedDialogue>> fetchColumn(String columnSlug) async {
    final mapping = _columnMapping[columnSlug];
    if (mapping == null) {
      throw ArgumentError.value(
          columnSlug, 'columnSlug', '未在显式映射表中登记的栏目');
    }
    final (scene, columnName) = mapping;
    final url = '$listeningRoot/$columnSlug/';
    final html = await _fetch(url);
    final blocks = extractTranscriptBlocks(html);
    if (blocks.isEmpty) {
      throw const ClipFetchException(
        FetchFailureKind.structureChanged,
        '页面结构已变化：未能从页面中解析出任何对话内容',
      );
    }

    final dialogues = <FetchedDialogue>[];
    for (var i = 0; i < blocks.length; i++) {
      final parsed = parseDialogue(blocks[i]);
      if (parsed.turns.isEmpty) continue;
      dialogues.add(FetchedDialogue(
        scene: scene,
        columnSlug: columnSlug,
        column: columnName,
        pageUrl: url,
        blockIndex: i,
        scenarioNote: parsed.note,
        turns: parsed.turns,
      ));
    }
    if (dialogues.isEmpty) {
      throw const ClipFetchException(
        FetchFailureKind.structureChanged,
        '页面结构已变化：页面有内容但无法解析出任何说话人轮次',
      );
    }
    return dialogues;
  }

  /// 站点级变更标识。
  ///
  /// 用 `sitemap.xml` 的最大 `lastmod` 作为站点构建标识——站点重新构建时它会变。
  /// **注意其粒度是"站点是否重建"而非"某栏目是否改过"**（实测 listening 区
  /// 95 页的 lastmod 全部相同），所以内容级变更检测由同步状态里的文本哈希兜底。
  @override
  Future<String?> siteChangeToken() async {
    try {
      final xml = await _fetch(sitemapUrl);
      final matches =
          RegExp(r'<lastmod>([^<]+)</lastmod>').allMatches(xml).toList();
      if (matches.isEmpty) return null;
      var latest = '';
      for (final m in matches) {
        final v = m.group(1) ?? '';
        if (v.compareTo(latest) > 0) latest = v;
      }
      return latest.isEmpty ? null : latest;
    } catch (_) {
      return null;
    }
  }

  /// 抽象层形态的抓取：把内部 [FetchedDialogue] 转成统一的 [SourceDialogue]。
  @override
  Future<List<SourceDialogue>> fetchDialogues(String columnSlug) async {
    final column = columns[columnSlug];
    if (column == null) {
      throw ArgumentError.value(
          columnSlug, 'columnSlug', '未在显式映射表中登记的栏目');
    }
    final out = <SourceDialogue>[];
    for (final d in await fetchColumn(columnSlug)) {
      out.add(SourceDialogue(
        column: column,
        pageUrl: d.pageUrl,
        blockIndex: d.blockIndex,
        scenarioNote: d.scenarioNote,
        turns: d.turns,
      ));
    }
    return out;
  }

  Future<String> _fetch(String url) async {
    http.Response response;
    try {
      response = await _client.get(
        Uri.parse(url),
        headers: {'User-Agent': userAgent, 'Accept': 'text/html'},
      ).timeout(timeout);
    } catch (e) {
      throw ClipFetchException(
        FetchFailureKind.networkUnreachable,
        '网络不可达，无法访问 $url（$e）',
      );
    }
    if (response.statusCode == 404) {
      throw ClipFetchException(
        FetchFailureKind.httpNotFound,
        '页面不存在（HTTP 404）：$url',
        statusCode: 404,
      );
    }
    if (response.statusCode != 200) {
      throw ClipFetchException(
        FetchFailureKind.httpError,
        '站点返回异常状态（HTTP ${response.statusCode}）：$url',
        statusCode: response.statusCode,
      );
    }
    // 站点的 Content-Type 是 `text/html` 且**不带 charset**。Dart 的
    // `response.body` 在这种情况下按 latin1 解码，UTF-8 的 em dash（E2 80 94）
    // 会变成 "â\x80\x94" —— 破折号清洗随之失效（实测：合成文本里仍残留
    // 乱码破折号）。必须自己按 UTF-8 解码字节。
    return utf8.decode(response.bodyBytes, allowMalformed: false);
  }

  /// 从 HTML 中取出所有 transcript 块。
  ///
  /// 容错：站点改用单引号属性或改变标签名时，这里返回空列表而不是抛异常，
  /// 由调用方翻译成"页面结构已变化"。
  static List<String> extractTranscriptBlocks(String html) {
    final blocks = <String>[];
    final pattern = RegExp(
      r'<pre[^>]*class="[^"]*transcript-text[^"]*"[^>]*>(.*?)</pre>',
      dotAll: true,
      caseSensitive: false,
    );
    for (final m in pattern.allMatches(html)) {
      final text = _decodeEntities(m.group(1) ?? '').trim();
      if (text.isNotEmpty) blocks.add(text);
    }
    return blocks;
  }

  /// HTML 实体解码。站点输出的是标准实体（`&quot;` `&#39;` `&amp;` `&mdash;`）。
  static String _decodeEntities(String input) {
    return input
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&nbsp;', ' ');
  }

  /// 把一段对话正文切分为说话人轮次。
  ///
  /// 返回 (场景说明, 轮次列表)。场景说明是开头的方括号行（若有）。
  static ({String note, List<SpeakerTurn> turns}) parseDialogue(String block) {
    final turns = <SpeakerTurn>[];
    var note = '';
    SpeakerTurn? current;

    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (current == null && line.startsWith('[')) {
        // 开头的方括号行是场景说明，不是对话。
        note = line.replaceAll(RegExp(r'^\[|\]$'), '').trim();
        continue;
      }

      final parsed = _parseSpeakerLine(line);
      if (parsed != null) {
        if (current != null) turns.add(current);
        current = parsed;
      } else if (current != null) {
        // 排版折行的续行并入当前轮次。
        current = current.copyWith(rawText: '${current.rawText} $line');
      }
    }
    if (current != null) turns.add(current);
    return (note: note, turns: turns);
  }

  /// 解析一行说话人话语。
  ///
  /// 支持 `Name (Role): "..."` 与 `Name: "..."` 两种形式。
  static SpeakerTurn? _parseSpeakerLine(String line) {
    final m = RegExp(r"^([A-Za-z][A-Za-z0-9 .'\-]{0,40}?)(?:\s*\(([^)]{1,40})\))?\s*:\s*(.*)$")
        .firstMatch(line);
    if (m == null) return null;
    final speaker = (m.group(1) ?? '').trim();
    if (speaker.isEmpty) return null;
    final role = (m.group(2) ?? '').trim();
    var said = (m.group(3) ?? '').trim();
    // 剥掉包裹整句的引号；句内引号保留。
    said = _stripWrappingQuotes(said);
    return SpeakerTurn(
      speaker: speaker,
      role: role,
      rawText: said,
      synthesisText: said,
      voice: '',
    );
  }

  static String _stripWrappingQuotes(String text) {
    if (text.length < 2) return text;
    const pairs = <String, String>{
      '"': '"',
      '“': '”',
      '‘': '’',
    };
    for (final e in pairs.entries) {
      if (text.startsWith(e.key) && text.endsWith(e.value)) {
        return text.substring(1, text.length - 1).trim();
      }
    }
    return text;
  }
}
