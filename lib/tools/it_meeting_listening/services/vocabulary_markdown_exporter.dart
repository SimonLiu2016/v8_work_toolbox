/// 重点关注词汇的全量 Markdown 导出。
///
/// 纯逻辑层：接收词汇索引与助学存储，组装可读的 Markdown 文本，
/// 不依赖任何 Flutter Widget，可独立单元测试。
library;

import 'meeting_vocabulary_index.dart';
import 'vocabulary_study_store.dart';

/// 重点关注词汇 Markdown 导出器。
class VocabularyMarkdownExporter {
  VocabularyMarkdownExporter._();

  /// 组装「⭐ 重点关注」词汇的 Markdown 文本。
  ///
  /// [index] 提供词汇出处（`postingsFor`）与展示词形（`display`）；
  /// [studyStore] 提供重点关注集合、音标/词性/释义与例句中文翻译；
  /// [now] 用于导出时间戳（测试可注入固定时间）。
  static String build({
    required MeetingVocabularyIndex index,
    required VocabularyStudyStore studyStore,
    DateTime? now,
  }) {
    final exportTime = now ?? DateTime.now();
    final words = studyStore.focusedWords
        .where((w) => w.trim().isNotEmpty)
        .toList()
      ..sort();

    final buf = StringBuffer();
    buf.writeln('# 听力练习重点关注词汇表');
    buf.writeln();
    buf.writeln('> - **导出时间**: ${_formatDateTime(exportTime)}');
    buf.writeln('> - **词汇总量**: ${words.length} 个重点词');
    buf.writeln('> - **素材来源**: IT 会议听力真实语料库');
    buf.writeln();
    buf.writeln('---');
    buf.writeln();

    for (final word in words) {
      _writeWord(buf, index, studyStore, word);
    }
    return buf.toString();
  }

  static void _writeWord(
    StringBuffer buf,
    MeetingVocabularyIndex index,
    VocabularyStudyStore studyStore,
    String word,
  ) {
    final display = index.display[word] ?? word;
    final profile = studyStore.profileFor(word);
    final postings = index.postingsFor(word);

    buf.writeln('## $display');
    buf.writeln();
    if (profile != null) {
      if (profile.phonetic.trim().isNotEmpty) {
        buf.writeln('- **音标**: `${profile.phonetic.trim()}`');
      }
      if (profile.partOfSpeech.trim().isNotEmpty) {
        buf.writeln('- **词性**: `${profile.partOfSpeech.trim()}`');
      }
      if (profile.definitionZh.trim().isNotEmpty) {
        buf.writeln('- **释义**: ${profile.definitionZh.trim()}');
      }
    }
    buf.writeln('- **全语料频次**: ${postings.length} 次');
    buf.writeln();

    // 例句去重：以归一化句文本为键（与助学缓存同一套归一化），
    // 同一句中词出现多次只保留一条；去重后保持原排序（会议标题、轮次）。
    final seen = <String>{};
    final unique = <VocabularyPosting>[];
    for (final p in postings) {
      final key = VocabularyStudyStore.normalizeSentenceKey(p.sentence);
      if (key.isEmpty || !seen.add(key)) continue;
      unique.add(p);
    }

    buf.writeln('- **出处例句** (共 ${unique.length} 句):');
    for (var i = 0; i < unique.length; i++) {
      final p = unique[i];
      final translation = studyStore.translationForSentence(p.sentence);
      buf.writeln('  ${i + 1}. ${p.sentence.trim()}');
      if (translation != null && translation.trim().isNotEmpty) {
        buf.writeln('     > **中文**: ${translation.trim()}');
      }
      final speaker = p.slotId.trim().isEmpty ? '' : ' · ${p.slotId.trim()}';
      buf.writeln('     > **出处**: *${p.meetingTitle}* (轮次 ${p.turnIndex}$speaker · ${_fmtTimestamp(p.timestampMs)})');
    }
    buf.writeln();
    buf.writeln('---');
    buf.writeln();
  }

  /// 格式化为 `YYYY-MM-DD HH:mm`。
  static String _formatDateTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  /// 毫秒时间戳格式化为 `MM:SS`。
  static String _fmtTimestamp(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
