import 'dart:convert';

import '../../notebook/note_database.dart';

/// 生词本词条数据模型
class VocabEntryModel {
  final String id;
  final String word;
  final String? phonetic;
  final String? audioUrl;
  final String? partOfSpeech;
  final List<String> definitions;
  final List<String> examples;
  final List<String> phrases;
  final String? sourceContext;
  final int masteryLevel; // 0-5
  final List<String> tags;
  final DateTime addedAt;

  const VocabEntryModel({
    required this.id,
    required this.word,
    this.phonetic,
    this.audioUrl,
    this.partOfSpeech,
    required this.definitions,
    required this.examples,
    this.phrases = const [],
    this.sourceContext,
    this.masteryLevel = 0,
    this.tags = const [],
    required this.addedAt,
  });

  factory VocabEntryModel.fromRow(VocabEntry row) {
    List<String> parseList(String json) {
      try {
        return (jsonDecode(json) as List).cast<String>();
      } catch (_) {
        return [];
      }
    }

    return VocabEntryModel(
      id: row.id,
      word: row.word,
      phonetic: row.phonetic,
      audioUrl: row.audioUrl,
      partOfSpeech: row.partOfSpeech,
      definitions: parseList(row.definitions),
      examples: parseList(row.examples),
      phrases: parseList(row.phrases),
      sourceContext: row.sourceContext,
      masteryLevel: row.masteryLevel,
      tags: parseList(row.tags),
      addedAt: row.addedAt,
    );
  }

  VocabEntryModel copyWith({
    String? id,
    String? word,
    String? phonetic,
    String? audioUrl,
    String? partOfSpeech,
    List<String>? definitions,
    List<String>? examples,
    List<String>? phrases,
    String? sourceContext,
    int? masteryLevel,
    List<String>? tags,
    DateTime? addedAt,
  }) {
    return VocabEntryModel(
      id: id ?? this.id,
      word: word ?? this.word,
      phonetic: phonetic ?? this.phonetic,
      audioUrl: audioUrl ?? this.audioUrl,
      partOfSpeech: partOfSpeech ?? this.partOfSpeech,
      definitions: definitions ?? this.definitions,
      examples: examples ?? this.examples,
      phrases: phrases ?? this.phrases,
      sourceContext: sourceContext ?? this.sourceContext,
      masteryLevel: masteryLevel ?? this.masteryLevel,
      tags: tags ?? this.tags,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  /// 词性标注的显示缩写
  String get partOfSpeechAbbr {
    switch (partOfSpeech?.toLowerCase()) {
      case 'noun': return 'n.';
      case 'verb': return 'v.';
      case 'adjective': return 'adj.';
      case 'adverb': return 'adv.';
      case 'preposition': return 'prep.';
      case 'conjunction': return 'conj.';
      case 'pronoun': return 'pron.';
      case 'interjection': return 'interj.';
      default: return partOfSpeech ?? '';
    }
  }

  /// 掌握程度颜色（0=灰, 1-2=红, 3=橙, 4=黄绿, 5=绿）
  static const masteryColors = [
    0xFF9E9E9E, // 0 - 未学
    0xFFE57373, // 1 - 陌生
    0xFFFF8A65, // 2 - 见过
    0xFFFFB74D, // 3 - 模糊
    0xFFAED581, // 4 - 熟悉
    0xFF66BB6A, // 5 - 掌握
  ];

  static const masteryLabels = ['未学', '陌生', '见过', '模糊', '熟悉', '掌握'];
}
