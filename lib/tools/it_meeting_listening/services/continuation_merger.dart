/// 续句分组：把被 ASR 切断的一句话重新拼回一个合成单元。
///
/// **问题**：会议记录系统的说话人切分会在句子中间断掉。实测样稿 152 轮里有
/// 59 轮（39%）以非句首的形式开头——上一轮说到 "…, uh, during"（无终止标点），
/// 下一轮从 "the...I can take the command" 接着往下说，却被标给了另一个
/// 说话人。逐轮合成会在**半句话中间换声音**，这是合成音频里最刺耳的瑕疵。
///
/// **处理方式**：只在**合成层**合并，展示层与索引层保持原样。
/// ```
/// 展示： [发言人1: "...during"] [发言人2: "the...I can take..."]
/// 合成： [发言人1 的音色一次念完 "...during the...I can take..."]
/// ```
/// 展示层是用户核对"会上到底说了什么"的唯一依据，任何合并都是信息损失；
/// 而音频层只需要"听起来是连贯的一句话"。两层分开，两边的目标各自满足。
///
/// **代价**：组内后几轮明明可能是另一个人说的，却被算到组首说话人头上。
/// 这是没有标准答案时的必然损失，规则选的是"听觉连续性优先"。
library;

import '../models/real_meeting_models.dart';

/// 一个续句组。
///
/// [turnIndices] 是组内轮次的原稿下标（顺序即念的顺序）；[slotId] 取组首轮的
/// 说话人——整组用他的音色念完。
class TurnGroup {
  final List<int> turnIndices;
  final String slotId;

  const TurnGroup({required this.turnIndices, required this.slotId});

  /// 组内轮次数。
  int get length => turnIndices.length;

  /// 是否是一个被合并过的组（多于一轮）。
  bool get isMerged => turnIndices.length > 1;
}

/// 续句分组器。
class ContinuationMerger {
  /// 句末标点。
  ///
  /// 只认这三种：它们是"一句话说完了"的强信号。逗号、分号、破折号都不算——
  /// 那些位置本来就是话轮的常见停顿点，按它们切会把正常换人当成续句。
  static const Set<String> _sentenceEnd = {'.', '?', '!'};

  /// 判断 [turn] 是否是 [prev] 的续句。
  ///
  /// 两个条件同时成立：
  /// 1. [prev] 的正文不以 `.` `?` `!` 结尾
  /// 2. [turn] 的正文以**小写拉丁字母**开头
  ///
  /// 第 2 条刻意只认 ASCII 小写字母，而不是"非大写字符"：中文、数字、引号
  /// 开头的轮次都可能是新人开口，把它们并进上一句会制造比换声更严重的错误
  /// （把 A 的中文并给 B 的英文，词频统计会连带受灾）。
  static bool isContinuation(MeetingTurn turn, MeetingTurn? prev) {
    if (prev == null) return false;
    final prevText = prev.text.trimRight();
    if (prevText.isEmpty) return false;
    if (_sentenceEnd.contains(prevText[prevText.length - 1])) return false;

    final text = turn.text.trimLeft();
    if (text.isEmpty) return false;
    final first = text.codeUnitAt(0);
    // a-z
    return first >= 0x61 && first <= 0x7A;
  }

  /// 把轮次切成续句组。
  ///
  /// 返回的组按原顺序排列，且**每个轮次恰好属于一个组**——这是后续按组
  /// 合成、按组回填时间戳的前提。
  static List<TurnGroup> group(List<MeetingTurn> turns) {
    if (turns.isEmpty) return const [];

    final groups = <TurnGroup>[];
    var current = <int>[turns.first.index];
    var currentSlot = turns.first.slotId;

    for (var i = 1; i < turns.length; i++) {
      final turn = turns[i];
      if (isContinuation(turn, turns[i - 1])) {
        current.add(turn.index);
        continue;
      }
      groups.add(TurnGroup(turnIndices: List.unmodifiable(current), slotId: currentSlot));
      current = <int>[turn.index];
      currentSlot = turn.slotId;
    }
    groups.add(TurnGroup(turnIndices: List.unmodifiable(current), slotId: currentSlot));
    return groups;
  }

  /// 组内各轮正文拼成送 TTS 的文本。
  ///
  /// 用单个空格连接：续句本来就是同一句话被切开的两段，中间不该再引入标点
  /// 或停顿。真正的清洗（破折号、空白折叠）在 `sanitizeForSynthesis` 里做，
  /// 这里只负责"把碎片接上"。
  static String synthesisText(List<MeetingTurn> turns, TurnGroup group) {
    final byIndex = {for (final t in turns) t.index: t};
    return group.turnIndices
        .map((i) => byIndex[i]?.text.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .join(' ');
  }
}
