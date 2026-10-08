import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../notebook/note_database.dart';
import '../../notebook/note_store.dart';
import '../models/vocab_entry.dart';

/// 生词本存储服务（单例）
class VocabStore {
  VocabStore._();
  static final VocabStore instance = VocabStore._();

  static const _uuid = Uuid();

  final StreamController<void> _changeController = StreamController<void>.broadcast();

  /// 数据变更事件流。外部（如 VocabBookPage）订阅此流以实现即时刷新。
  Stream<void> get onEntriesChanged => _changeController.stream;

  void _notifyChanged() {
    if (!_changeController.isClosed) {
      _changeController.add(null);
    }
  }

  @visibleForTesting
  NoteDatabase? testDb;

  // 复用 NoteStore 已有的数据库实例（notebook 与生词本共享同一 SQLite 文件）
  NoteDatabase get _db => testDb ?? NoteStore.instance.db;

  Future<List<VocabEntryModel>> queryAll() async {
    final rows = await _db.allVocabEntries();
    return rows.map(VocabEntryModel.fromRow).toList();
  }

  Future<List<VocabEntryModel>> queryByTag(String tag) async {
    final rows = await _db.vocabEntriesByTag(tag);
    return rows.map(VocabEntryModel.fromRow).toList();
  }

  Future<List<VocabEntryModel>> queryByMastery(int min, int max) async {
    final all = await queryAll();
    return all.where((e) => e.masteryLevel >= min && e.masteryLevel <= max).toList();
  }

  Future<bool> existsWord(String word) => _db.vocabEntryExists(word);

  Future<VocabEntryModel?> findByWord(String word) async {
    final row = await _db.vocabEntryByWord(word);
    if (row == null) return null;
    return VocabEntryModel.fromRow(row);
  }

  Future<String> insertEntry(VocabEntryModel entry) async {
    final id = entry.id.isNotEmpty ? entry.id : _uuid.v4();
    final model = entry.copyWith(id: id);
    await _db.insertVocabEntry(_toCompanion(model));
    _notifyChanged();
    return id;
  }

  /// 从词典查询结果构建并插入词条
  Future<String> insertFromDictionary({
    required String word,
    String? phonetic,
    String? audioUrl,
    String? partOfSpeech,
    required List<String> definitions,
    required List<String> examples,
    List<String> phrases = const [],
    String? sourceContext,
  }) {
    return insertEntry(VocabEntryModel(
      id: _uuid.v4(),
      word: word,
      phonetic: phonetic,
      audioUrl: audioUrl,
      partOfSpeech: partOfSpeech,
      definitions: definitions,
      examples: examples,
      phrases: phrases,
      sourceContext: sourceContext,
      masteryLevel: 0,
      tags: const [],
      addedAt: DateTime.now(),
    ));
  }

  Future<void> deleteEntry(String id) async {
    await _db.deleteVocabEntry(id);
    _notifyChanged();
  }

  Future<void> deleteEntries(List<String> ids) async {
    await _db.deleteVocabEntries(ids);
    _notifyChanged();
  }

  Future<void> updateMasteryLevel(String id, int level) async {
    await _db.updateVocabEntry(
      id,
      VocabEntriesCompanion(masteryLevel: Value(level.clamp(0, 5))),
    );
    _notifyChanged();
  }

  Future<void> updateTags(String id, List<String> tags) async {
    await _db.updateVocabEntry(
      id,
      VocabEntriesCompanion(tags: Value(jsonEncode(tags))),
    );
    _notifyChanged();
  }

  Future<List<String>> allTags() async {
    final all = await queryAll();
    final tagSet = <String>{};
    for (final e in all) {
      tagSet.addAll(e.tags);
    }
    return tagSet.toList()..sort();
  }

  VocabEntriesCompanion _toCompanion(VocabEntryModel m) {
    return VocabEntriesCompanion(
      id: Value(m.id),
      word: Value(m.word),
      phonetic: Value(m.phonetic),
      audioUrl: Value(m.audioUrl),
      partOfSpeech: Value(m.partOfSpeech),
      definitions: Value(jsonEncode(m.definitions)),
      examples: Value(jsonEncode(m.examples)),
      phrases: Value(jsonEncode(m.phrases)),
      sourceContext: Value(m.sourceContext),
      masteryLevel: Value(m.masteryLevel),
      tags: Value(jsonEncode(m.tags)),
      addedAt: Value(m.addedAt),
    );
  }
}
