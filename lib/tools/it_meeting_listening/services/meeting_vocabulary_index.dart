/// 跨会议词汇表与反查索引。
///
/// 两级结构：
///
/// ```
/// perMeeting: {meetingId: {word: count}}   分场计数（删除一场会 = 删一个 key）
/// postings:   {word: [出现位置...]}         倒排（词 → 会议 / 轮次 / 句子）
/// ```
///
/// **为什么按会议分开记**（design D5）：删除或重导某一场会时，只需扣掉它的那一份，
/// 不必重扫整个语料。全量重建只是把每场会的计数重新加一次，结果必须与增量维护
/// 完全一致——这是最容易悄悄漂移的地方，所以有一条测试专门比对两者。
///
/// **噪声折叠的口径**（design D6）：全语料出现 ≤1 次 ∧ 不在内置停用词表 ∧
/// 不在该文稿「关键词」段。三条同时成立才折叠。**不查在线词典**——`lookup_panel`
/// 的词典是网络服务，导入时离线不可用；而会议记录系统自己产出的「关键词」段
/// 正是现成的真术语白名单。
///
/// **折叠不等于丢失**：折叠的词照样计数、照样可查。折叠只影响主列表的默认
/// 展示顺序，不影响任何数字。
library;

import 'dart:convert';
import 'dart:io';

import '../../../services/app_paths.dart';
import '../models/real_meeting_models.dart';

/// 一个词在语料中的汇总。
class VocabularyEntry {
  /// 归一化形态（小写、去所有格与引号），作为键。
  final String word;

  /// 首次出现的原文形态（展示用，尽量保留原来的大小写）。
  final String display;

  /// 全语料累计次数。
  final int count;

  /// 分场次数（会议标识 → 次数）。
  final Map<String, int> byMeeting;

  /// 是否被折叠进「疑似转写噪声」分组。
  final bool noisy;

  const VocabularyEntry({
    required this.word,
    required this.display,
    required this.count,
    required this.byMeeting,
    this.noisy = false,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'display': display,
        'count': count,
        'byMeeting': byMeeting,
        'noisy': noisy,
      };

  factory VocabularyEntry.fromJson(Map<String, dynamic> json) => VocabularyEntry(
        word: json['word'] as String? ?? '',
        display: json['display'] as String? ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
        byMeeting: ((json['byMeeting'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', (v as num).toInt())),
        noisy: (json['noisy'] as bool?) ?? false,
      );
}

/// 一次出现。
class VocabularyPosting {
  final String meetingId;
  final String meetingTitle;

  /// 轮次下标。
  final int turnIndex;

  /// 说话人槽位标识（原稿）。展示名在界面层按当前设定解析——改名不该要求重建索引。
  final String slotId;

  /// 该轮的原稿时间戳（毫秒）。
  final int timestampMs;

  /// 该轮的句子原文。
  final String sentence;

  const VocabularyPosting({
    required this.meetingId,
    required this.meetingTitle,
    required this.turnIndex,
    required this.slotId,
    required this.timestampMs,
    required this.sentence,
  });

  Map<String, dynamic> toJson() => {
        'meetingId': meetingId,
        'meetingTitle': meetingTitle,
        'turnIndex': turnIndex,
        'slotId': slotId,
        'timestampMs': timestampMs,
        'sentence': sentence,
      };

  factory VocabularyPosting.fromJson(Map<String, dynamic> json) =>
      VocabularyPosting(
        meetingId: json['meetingId'] as String? ?? '',
        meetingTitle: json['meetingTitle'] as String? ?? '',
        turnIndex: (json['turnIndex'] as num?)?.toInt() ?? 0,
        slotId: json['slotId'] as String? ?? '',
        timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
        sentence: json['sentence'] as String? ?? '',
      );
}

/// 词汇索引。
class MeetingVocabularyIndex {
  /// 结构版本（将来改口径时用于判定"需要重建"）。
  static const int version = 1;

  /// 会议标识 → (归一化词 → 次数)。
  final Map<String, Map<String, int>> perMeeting;

  /// 会议标识 → 该文稿「关键词」段的归一化词集合。
  final Map<String, Set<String>> keywords;

  /// 归一化词 → 首次出现的原文形态。
  final Map<String, String> display;

  /// 归一化词 → 出现位置。
  final Map<String, List<VocabularyPosting>> postings;

  const MeetingVocabularyIndex({
    this.perMeeting = const {},
    this.keywords = const {},
    this.display = const {},
    this.postings = const {},
  });

  bool get isEmpty => postings.isEmpty;

  /// 从会议列表全量构建。
  ///
  /// [includeAnswers] 为真时把用户插入的回答也计入词频（默认不计入：
  /// 那是"我写的"，不是"会上说的"，混进去会让词频失真）。
  static MeetingVocabularyIndex build(
    List<RealMeeting> meetings, {
    bool includeAnswers = false,
    Map<String, List<InsertedAnswer>> answersByMeeting = const {},
  }) {
    final perMeeting = <String, Map<String, int>>{};
    final keywords = <String, Set<String>>{};
    final display = <String, String>{};
    final postings = <String, List<VocabularyPosting>>{};

    for (final m in meetings) {
      final counts = <String, int>{};
      keywords[m.id] = m.keywords.map(normalizeWord).where((w) => w.isNotEmpty).toSet();

      void ingest(String text, int turnIndex, String slotId, int ts) {
        for (final token in tokenize(text)) {
          final key = normalizeWord(token);
          if (key.isEmpty) continue;
          counts[key] = (counts[key] ?? 0) + 1;
          display.putIfAbsent(key, () => token);
          postings.putIfAbsent(key, () => []).add(VocabularyPosting(
                meetingId: m.id,
                meetingTitle: m.title,
                turnIndex: turnIndex,
                slotId: slotId,
                timestampMs: ts,
                sentence: text,
              ));
        }
      }

      for (final t in m.turns) {
        ingest(t.text, t.index, t.slotId, t.timestampMs);
      }
      if (includeAnswers) {
        for (final a in answersByMeeting[m.id] ?? const <InsertedAnswer>[]) {
          ingest(a.textEn, a.anchorTurnIndex, a.speakerName, 0);
        }
      }
      perMeeting[m.id] = counts;
    }

    return MeetingVocabularyIndex(
      perMeeting: perMeeting,
      keywords: keywords,
      display: display,
      postings: postings,
    );
  }

  /// 加一场会（增量）。
  MeetingVocabularyIndex addMeeting(
    RealMeeting meeting, {
    bool includeAnswers = false,
    List<InsertedAnswer> answers = const [],
  }) {
    final fresh = MeetingVocabularyIndex.build(
      [meeting],
      includeAnswers: includeAnswers,
      answersByMeeting: {meeting.id: answers},
    );
    final newPerMeeting = Map<String, Map<String, int>>.from(perMeeting)
      ..[meeting.id] = fresh.perMeeting[meeting.id] ?? const {};
    final newKeywords = Map<String, Set<String>>.from(keywords)
      ..[meeting.id] = fresh.keywords[meeting.id] ?? const {};
    final newDisplay = Map<String, String>.from(display)..addAll(fresh.display);
    final newPostings = <String, List<VocabularyPosting>>{
      for (final e in postings.entries) e.key: [...e.value.where((p) => p.meetingId != meeting.id)],
    };
    fresh.postings.forEach((word, list) {
      newPostings.putIfAbsent(word, () => []).addAll(list);
    });
    return MeetingVocabularyIndex(
      perMeeting: newPerMeeting,
      keywords: newKeywords,
      display: newDisplay,
      postings: newPostings,
    );
  }

  /// 删一场会（增量）。
  MeetingVocabularyIndex removeMeeting(String meetingId) {
    final newPerMeeting = Map<String, Map<String, int>>.from(perMeeting)
      ..remove(meetingId);
    final newKeywords = Map<String, Set<String>>.from(keywords)
      ..remove(meetingId);
    final newPostings = <String, List<VocabularyPosting>>{};
    postings.forEach((word, list) {
      final kept = list.where((p) => p.meetingId != meetingId).toList();
      if (kept.isNotEmpty) newPostings[word] = kept;
    });
    // display 里被删会议独有的词不必清理：它是"原文形态"的缓存，留着无害，
    // 且删了会在下次同一词出现时改变展示形态。
    return MeetingVocabularyIndex(
      perMeeting: newPerMeeting,
      keywords: newKeywords,
      display: display,
      postings: newPostings,
    );
  }

  /// 全部词条（按次数降序，次数相同按字母序）。
  ///
  /// [includeStopwords] 默认假：不藏的话前 20 名全被 `the` / `to` / `we` 占满。
  /// [includeNoisy] 默认假：疑似转写噪声默认折叠。
  List<VocabularyEntry> entries({
    bool includeStopwords = false,
    bool includeNoisy = false,
  }) {
    final out = <VocabularyEntry>[];
    for (final e in postings.entries) {
      final word = e.key;
      final isStop = stopwords.contains(word);
      if (isStop && !includeStopwords) continue;
      final noisy = _isNoisy(word);
      if (noisy && !includeNoisy) continue;
      final byMeeting = <String, int>{};
      for (final p in e.value) {
        byMeeting[p.meetingId] = (byMeeting[p.meetingId] ?? 0) + 1;
      }
      out.add(VocabularyEntry(
        word: word,
        display: display[word] ?? word,
        count: e.value.length,
        byMeeting: byMeeting,
        noisy: noisy,
      ));
    }
    out.sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      return byCount != 0 ? byCount : a.word.compareTo(b.word);
    });
    return out;
  }

  /// 某个词的全部出现位置（按会议标题、轮次排序）。
  ///
  /// **不看折叠、不看停用词**：用户主动查一个词时必须给结果。折叠只是默认
  /// 列表的展示策略，不是访问控制。
  List<VocabularyPosting> postingsFor(String word) {
    final list = postings[normalizeWord(word)] ?? const <VocabularyPosting>[];
    final sorted = [...list];
    sorted.sort((a, b) {
      final byTitle = a.meetingTitle.compareTo(b.meetingTitle);
      return byTitle != 0 ? byTitle : a.turnIndex.compareTo(b.turnIndex);
    });
    return sorted;
  }

  /// 查词时把原词换成归一化形态（供界面显示"实际查的是哪个词"）。
  String normalizeForQuery(String word) => normalizeWord(word);

  /// 是否折叠进噪声分组。
  bool _isNoisy(String word) {
    if (stopwords.contains(word)) return false;
    final positions = postings[word];
    if (positions == null || positions.length > 1) return false;
    // 任一会议的「关键词」段里出现过 → 是真术语，不折叠。
    for (final set in keywords.values) {
      if (set.contains(word)) return false;
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'perMeeting': perMeeting,
        'keywords': keywords.map((k, v) => MapEntry(k, v.toList())),
        'display': display,
        'postings': postings.map(
            (k, v) => MapEntry(k, v.map((p) => p.toJson()).toList())),
      };

  factory MeetingVocabularyIndex.fromJson(Map<String, dynamic> json) {
    final perMeetingRaw = (json['perMeeting'] as Map?) ?? const {};
    final keywordsRaw = (json['keywords'] as Map?) ?? const {};
    final postingsRaw = (json['postings'] as Map?) ?? const {};
    return MeetingVocabularyIndex(
      perMeeting: perMeetingRaw.map((k, v) => MapEntry(
            '$k',
            Map<String, int>.from((v as Map).map(
                (ck, cv) => MapEntry('$ck', (cv as num).toInt()))),
          )),
      keywords: keywordsRaw.map((k, v) => MapEntry(
            '$k',
            ((v as List?) ?? const []).map((e) => '$e').toSet(),
          )),
      display: ((json['display'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', '$v')),
      postings: postingsRaw.map((k, v) => MapEntry(
            '$k',
            ((v as List?) ?? const [])
                .map((e) => VocabularyPosting.fromJson(
                    Map<String, dynamic>.from(e as Map)))
                .toList(),
          )),
    );
  }

  // ---------------------------------------------------------------------
  // 分词
  // ---------------------------------------------------------------------

  /// 词边界分词。
  ///
  /// 与 `TermHighlighter._tokenize` 同一套规则（字母开头、允许内部连字符），
  /// 但额外要求**首字符是字母**：纯数字（版本号、时间）不该进词汇表，
  /// 否则 `2026`、`10` 这类会挤满词频榜。
  static final RegExp _token = RegExp(r"[A-Za-z][A-Za-z0-9'\-]*");

  static List<String> tokenize(String text) =>
      _token.allMatches(text).map((m) => m.group(0)!).toList();

  /// 归一化：小写、去首尾引号、去所有格末缀。
  ///
  /// `Zest's` → `zest`、`customer's` → `customer`、`they're` 保留为 `they're`
  /// （那不是所有格，拆开会得到没有意义的 `they`）。
  static String normalizeWord(String raw) {
    var w = raw.toLowerCase().trim();
    // 去所有格：只处理 *'s / ’s 结尾（前面至少还有一个字母）。
    if (w.length > 2 && (w.endsWith("'s") || w.endsWith('’s'))) {
      w = w.substring(0, w.length - 2);
    }
    w = w.replaceAll(RegExp(r"^['’]+|['’]+$"), '');
    return w;
  }

  /// 内置停用词表（约 120 个）。
  ///
  /// 硬编码而不是查词典：这里只需要"高频功能词"，不需要词性、释义或大小写
  /// 变体；引一个词典依赖为这点需求不值得。填充词（`uh` / `yeah` / `okay`）
  /// 一并列入——它们在逐字稿里出现极多，但对"这场会讲了什么"零信息量。
  static final Set<String> stopwords = {
    'a', 'an', 'the', 'and', 'or', 'but', 'if', 'then', 'so', 'as', 'of',
    'to', 'in', 'on', 'at', 'for', 'with', 'from', 'by', 'about', 'into',
    'over', 'after', 'before', 'between', 'under', 'up', 'down', 'out',
    'is', 'are', 'was', 'were', 'be', 'been', 'being', 'am',
    'do', 'does', 'did', 'doing', 'done', 'have', 'has', 'had', 'having',
    'will', 'would', 'shall', 'should', 'can', 'could', 'may', 'might',
    'must', 'i', 'me', 'my', 'we', 'us', 'our', 'you', 'your', 'he', 'him',
    'his', 'she', 'her', 'it', 'its', 'they', 'them', 'their', 'this',
    'that', 'these', 'those', 'there', 'here', 'what', 'which', 'who',
    'whom', 'when', 'where', 'why', 'how', 'all', 'any', 'both', 'each',
    'few', 'more', 'most', 'other', 'some', 'such', 'no', 'not', 'only',
    'own', 'same', 'than', 'too', 'very', 'just', 'now', 'also', 'yes',
    'yeah', 'okay', 'ok', 'uh', 'um', 'hmm', 'well', 'like', 'really',
    'right', 'actually', 'maybe', 'going', 'got', 'get', 'one', 'two',
    'know', 'think', 'want', 'need', 'see', 'say', 'said', 'let', 'make',
  };
}

/// 词汇索引的读写。
class MeetingVocabularyStore {
  File get _file => AppPaths.meetingVocabularyIndexFile;

  /// 读取索引；缺失或损坏返回 null（由调用方决定是否重建）。
  Future<MeetingVocabularyIndex?> load() async {
    if (!await _file.exists()) return null;
    try {
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      if ((json['version'] as num?)?.toInt() != MeetingVocabularyIndex.version) {
        // 口径变了：旧索引不可信，让调用方重建。
        return null;
      }
      return MeetingVocabularyIndex.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(MeetingVocabularyIndex index) async {
    await _file.parent.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent(' ').convert(index.toJson()),
      flush: true,
    );
    await tmp.rename(_file.path);
  }

  /// 全量重建（从会议原稿）。
  Future<MeetingVocabularyIndex> rebuild(
    List<RealMeeting> meetings, {
    bool includeAnswers = false,
    Map<String, List<InsertedAnswer>> answersByMeeting = const {},
  }) async {
    final index = MeetingVocabularyIndex.build(
      meetings,
      includeAnswers: includeAnswers,
      answersByMeeting: answersByMeeting,
    );
    await save(index);
    return index;
  }
}
