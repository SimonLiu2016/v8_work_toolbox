/// 内容来源抽象层。
///
/// 把「从某个站点取会议对话」这件事抽成接口，使素材库、烘焙器、播放器与界面
/// **对具体站点无感知**。新增一个来源不需要改上层代码。
///
/// 站点特有的东西（URL 拼接、HTML 解析、失败诊断、场景映射）全部封在实现内部；
/// 对外只暴露统一的对话内容结构。
library;

import '../models/listening_models.dart';

/// 一个站点栏目。
///
/// [slug] 是站点侧稳定标识（拼素材 id 用），[displayName] 是展示名（可能改）。
class SourceColumn {
  /// 所属来源的稳定标识。
  final String sourceId;

  /// 站点栏目 slug（如 "standup-dialogues"）。
  final String slug;

  /// 站点侧栏目名（如 "Stand-up Meeting Dialogues"）。
  final String displayName;

  /// 映射到的内部会议场景。
  final MeetingScene scene;

  /// 该栏目的站点页面地址（用于抓取）。
  final String pageUrl;

  const SourceColumn({
    required this.sourceId,
    required this.slug,
    required this.displayName,
    required this.scene,
    required this.pageUrl,
  });

  @override
  String toString() => 'SourceColumn($slug → ${scene.id})';
}

/// 从来源抓取到的一段对话（尚未合成）。
class SourceDialogue {
  /// 所属栏目。
  final SourceColumn column;

  /// 原文页面地址。
  final String pageUrl;

  /// 块在栏目内的序号。
  final int blockIndex;

  /// 场景说明行（可为空）。
  final String scenarioNote;

  /// 说话人轮次。
  final List<SpeakerTurn> turns;

  const SourceDialogue({
    required this.column,
    required this.pageUrl,
    required this.blockIndex,
    required this.scenarioNote,
    required this.turns,
  });

  /// 片段标识：`{sourceId}_{sceneId}_{columnSlug}_{block}`。
  ///
  /// **含来源标识**——两个来源都提供"站会"场景时，不带源前缀会撞 id，
  /// 音频与文稿文件互相覆盖。
  String get clipId =>
      '${column.sourceId}_${column.scene.id}_${column.slug}_$blockIndex';
}

/// 内容来源。
///
/// 实现者需保证：抓取失败时抛出带**具体原因**的异常，而不是笼统的"失败"——
/// 站点改版与网络故障需要完全不同的处置。
abstract class ListeningSource {
  /// 来源站点稳定标识（如 "coderslingo"）。
  ///
  /// 多来源下区分素材的依据，也是素材 id 的组成部分。**不随展示名变化**。
  String get sourceId;

  /// 来源站点展示名（如 "CoderSlingo"）。
  String get displayName;

  /// 许可标识（如 "CC BY 4.0"）。
  String get license;

  /// 该来源采用的栏目（站点侧 slug → 内部场景的显式映射）。
  ///
  /// **只收录有完整对话的栏目**。单句问答形态的栏目（选项里引用一句对话）
  /// 不构成听力材料——合成出来是"一句孤立的话"，不是会议。
  Map<String, SourceColumn> get columns;

  /// 发现该来源上存在、但尚未映射到内部场景的栏目。
  ///
  /// 用于向用户报告"站点新增了 N 个栏目，尚未接入"，而不是静默忽略。
  /// 默认返回空（不提供发现的来源）。
  Future<List<SourceColumn>> discoverUnmappedColumns() async => const [];

  /// 抓取某个栏目的全部对话。
  ///
  /// 抛出的异常必须携带**具体失败原因**（网络不可达 / HTTP 非 200 /
  /// 页面结构变化 / 空页面）。
  Future<List<SourceDialogue>> fetchDialogues(String columnSlug);

  /// 站点级变更标识。
  ///
  /// 返回 null 表示该来源不提供站点级标识——此时每次更新都要全量抓取。
  /// 返回值应随站点内容变化而变化（典型是构建时间或发布标识）。
  Future<String?> siteChangeToken() async => null;
}

/// 来源注册表。
///
/// 供上层按 id 查找来源。新增来源 = 实现 [ListeningSource] + 注册到这里。
class ListeningSourceRegistry {
  ListeningSourceRegistry._();

  static final ListeningSourceRegistry instance = ListeningSourceRegistry._();

  final Map<String, ListeningSource> _sources = {};

  /// 注册一个来源（同 id 覆盖）。
  void register(ListeningSource source) {
    _sources[source.sourceId] = source;
  }

  /// 按 id 查找。
  ListeningSource? byId(String sourceId) => _sources[sourceId];

  /// 全部已注册来源。
  List<ListeningSource> get all => _sources.values.toList();
}
