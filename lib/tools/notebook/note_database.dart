import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

import 'cjk_tokenizer.dart';

part 'note_database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get stack => text().nullable()();
  TextColumn get icon => text().withDefault(const Constant('📓'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 500)();
  TextColumn get deltaJson => text()(); // Quill Delta JSON
  TextColumn get notebookId => text().nullable().references(Notebooks, #id)();
  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // 资产字段（可空，普通笔记为空）：用户选择加列到 Notes（A 方案）。
  // 让耐用消费品资产（延保/订阅/保险/会员）带可查询的到期日，供提醒与 RAG 命中。
  TextColumn get assetCategory => text().nullable()();
  DateTimeColumn get assetPurchaseDate => dateTime().nullable()();
  DateTimeColumn get assetServiceUntil => dateTime().nullable()();
  DateTimeColumn get assetExpiryDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 100).unique()();
  TextColumn get color => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class NoteTags extends Table {
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get tagId => text().references(Tags, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {noteId, tagId};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get noteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get filename => text().nullable()();
  TextColumn get mime => text().nullable()();
  TextColumn get localPath => text()();
  DateTimeColumn get createdAt => dateTime()();
  // 凭证标识：资产笔记的"凭证附件"用于 RAG 命中后指引用户定位凭证。
  BoolColumn get isCredential => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// 关联边（阶段三启用，阶段一先建表占位以避免后续二次迁移）
// ---------------------------------------------------------------------------

/// 笔记间泛化关联（B 方案：relation 恒 'related_to'，语义由 reason 自由文本承载）。
/// 双向可见通过查询（WHERE source=? OR target=?），不双写。
class NoteLinks extends Table {
  TextColumn get sourceNoteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get targetNoteId => text().references(Notes, #id, onDelete: KeyAction.cascade)();
  TextColumn get relation => text().withDefault(const Constant('related_to'))();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {sourceNoteId, targetNoteId};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Notebooks, Notes, Tags, NoteTags, Attachments, NoteLinks])
class NoteDatabase extends _$NoteDatabase {
  NoteDatabase() : super(_openConnection());

  /// 测试用构造函数：注入自定义连接（内存 db 等）
  NoteDatabase.forTesting(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      // Create FTS5 virtual table for full-text search
      await customStatement(
        "CREATE VIRTUAL TABLE IF NOT EXISTS notes_fts USING fts5("
        "title, content, note_id UNINDEXED"
        ")",
      );
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        try {
          await m.addColumn(notebooks, notebooks.stack);
        } catch (_) {}
      }
      if (from < 3) {
        // 资产字段 + 凭证标识 + 关联边表
        try { await m.addColumn(notes, notes.assetCategory); } catch (_) {}
        try { await m.addColumn(notes, notes.assetPurchaseDate); } catch (_) {}
        try { await m.addColumn(notes, notes.assetServiceUntil); } catch (_) {}
        try { await m.addColumn(notes, notes.assetExpiryDate); } catch (_) {}
        try { await m.addColumn(attachments, attachments.isCredential); } catch (_) {}
        try { await m.createTable(noteLinks); } catch (_) {}
      }
    },
    beforeOpen: (details) async {
      try {
        await customStatement('ALTER TABLE notebooks ADD COLUMN stack TEXT;');
      } catch (_) {
        // Column already exists, ignore safely
      }
      // 资产列与凭证标识：旧库升级时 beforeOpen 兜底（onUpgrade 已处理，此处幂等）
      for (final stmt in [
        'ALTER TABLE notes ADD COLUMN asset_category TEXT;',
        'ALTER TABLE notes ADD COLUMN asset_purchase_date INTEGER;',
        'ALTER TABLE notes ADD COLUMN asset_service_until INTEGER;',
        'ALTER TABLE notes ADD COLUMN asset_expiry_date INTEGER;',
        'ALTER TABLE attachments ADD COLUMN is_credential INTEGER DEFAULT 0;',
      ]) {
        try { await customStatement(stmt); } catch (_) {}
      }
      try { await customStatement(
        'CREATE TABLE IF NOT EXISTS note_links ('
        'source_note_id TEXT NOT NULL, '
        'target_note_id TEXT NOT NULL, '
        'relation TEXT NOT NULL DEFAULT \'related_to\', '
        'reason TEXT, '
        'created_at INTEGER NOT NULL, '
        'PRIMARY KEY (source_note_id, target_note_id), '
        'FOREIGN KEY (source_note_id) REFERENCES notes(id) ON DELETE CASCADE, '
        'FOREIGN KEY (target_note_id) REFERENCES notes(id) ON DELETE CASCADE'
        ');',
      ); } catch (_) {}
      // SQLite 默认**忽略外键约束**——不开启此 pragma，声明在 attachments /
      // note_tags / note_links 上的 ON DELETE CASCADE 全部不生效，删除笔记会
      // 留下孤儿行。实测确认：删笔记后三张子表计数均不变。
      try {
        await customStatement('PRAGMA foreign_keys = ON;');
      } catch (_) {}
      await _normalizeTextTimestamps();
    },
  );

  /// 自愈：把 TEXT 形式的日期时间戳归一化为 drift 期望的 unix 秒整数。
  ///
  /// drift 的 DateTimeColumn 读取时会对原始值做 int 解析，一旦某行被外部工具
  /// （如手工 sqlite3 脚本）写入 `datetime('now')` 这类 TEXT 时间戳，读取即抛
  /// FormatException，导致笔记本列表、自动补全、导入预创建全部失败。此处
  /// 在数据库打开时统一修复，避免整库不可用。
  Future<void> _normalizeTextTimestamps() async {
    const tables = {
      'notebooks': ['created_at', 'updated_at'],
      'notes': ['created_at', 'updated_at'],
    };
    for (final entry in tables.entries) {
      for (final column in entry.value) {
        try {
          await customStatement(
            'UPDATE ${entry.key} SET $column = strftime(\'%s\', $column) '
            'WHERE typeof($column) = \'text\';',
          );
        } catch (_) {
          // 表或列不存在时静默跳过
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Notebook CRUD
  // ---------------------------------------------------------------------------

  Future<List<Notebook>> allNotebooks() =>
      (select(notebooks)..orderBy([(t) => OrderingTerm.asc(t.sortOrder)])).get();

  Future<Notebook?> notebookById(String id) =>
      (select(notebooks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertNotebook(NotebooksCompanion entry) =>
      into(notebooks).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateNotebook(String id, NotebooksCompanion entry) =>
      (update(notebooks)..where((t) => t.id.equals(id))).write(entry);

  Future<void> updateNotebookStack(String id, String? stack) =>
      (update(notebooks)..where((t) => t.id.equals(id))).write(
        NotebooksCompanion(stack: Value(stack), updatedAt: Value(DateTime.now())),
      );

  Future<void> deleteNotebook(String id) =>
      (delete(notebooks)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // Note CRUD
  // ---------------------------------------------------------------------------

  Future<List<Note>> notesForNotebook(String? notebookId, {bool includeDeleted = false}) {
    final query = select(notes);
    if (!includeDeleted) {
      query.where((t) => t.isDeleted.equals(false));
    }
    if (notebookId != null) {
      query.where((t) => t.notebookId.equals(notebookId));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.isPinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return query.get();
  }

  Future<List<Note>> notesForNotebookIds(List<String> notebookIds, {bool includeDeleted = false}) {
    final query = select(notes);
    if (!includeDeleted) {
      query.where((t) => t.isDeleted.equals(false));
    }
    if (notebookIds.isNotEmpty) {
      query.where((t) => t.notebookId.isIn(notebookIds));
    }
    query.orderBy([
      (t) => OrderingTerm.desc(t.isPinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return query.get();
  }

  Future<List<Note>> notesForTag(String tagId, {bool includeDeleted = false}) {
    final query = select(notes).join([
      innerJoin(noteTags, noteTags.noteId.equalsExp(notes.id)),
    ]);
    if (!includeDeleted) {
      query.where(notes.isDeleted.equals(false));
    }
    query.where(noteTags.tagId.equals(tagId));
    query.orderBy([OrderingTerm.desc(notes.updatedAt)]);
    return query.map((row) => row.readTable(notes)).get();
  }

  Future<Note?> noteById(String id) =>
      (select(notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> insertNote(NotesCompanion entry) =>
      into(notes).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateNote(String id, NotesCompanion entry) =>
      (update(notes)..where((t) => t.id.equals(id))).write(entry);

  Future<void> softDeleteNote(String id) =>
      (update(notes)..where((t) => t.id.equals(id))).write(
        NotesCompanion(isDeleted: const Value(true), updatedAt: Value(DateTime.now())),
      );

  Future<void> batchSoftDeleteNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(notes)..where((t) => t.id.isIn(ids))).write(
      NotesCompanion(isDeleted: const Value(true), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> restoreNote(String id) =>
      (update(notes)..where((t) => t.id.equals(id))).write(
        NotesCompanion(isDeleted: const Value(false), updatedAt: Value(DateTime.now())),
      );

  Future<void> batchRestoreNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    await (update(notes)..where((t) => t.id.isIn(ids))).write(
      NotesCompanion(isDeleted: const Value(false), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> permanentlyDeleteNote(String id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

  Future<void> batchPermanentlyDeleteNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    await (delete(notes)..where((t) => t.id.isIn(ids))).go();
  }

  Future<List<Note>> deletedNotes() {
    final query = select(notes)..where((t) => t.isDeleted.equals(true));
    query.orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.get();
  }

  // ---------------------------------------------------------------------------
  // Asset queries（阶段一）
  // ---------------------------------------------------------------------------

  /// 到期日 ≤ now+leadDays 且未过期（到期日 ≥ now）且未删除的资产笔记。
  /// 供 AssetReminderService 扫描提醒。
  Future<List<Note>> assetsDueSoon(int leadDays) {
    final now = DateTime.now();
    final horizon = now.add(Duration(days: leadDays));
    final query = select(notes)
      ..where((t) => t.isDeleted.equals(false))
      ..where((t) => t.assetExpiryDate.isNotNull())
      ..where((t) => t.assetExpiryDate.isBiggerOrEqualValue(now))
      ..where((t) => t.assetExpiryDate.isSmallerOrEqualValue(horizon))
      ..orderBy([(t) => OrderingTerm.asc(t.assetExpiryDate)]);
    return query.get();
  }

  /// 所有未删除的资产笔记（资产字段任一非空），按到期日升序。
  Future<List<Note>> allAssets() {
    final query = select(notes)
      ..where((t) => t.isDeleted.equals(false))
      ..where((t) =>
          t.assetCategory.isNotNull() |
          t.assetPurchaseDate.isNotNull() |
          t.assetServiceUntil.isNotNull() |
          t.assetExpiryDate.isNotNull())
      ..orderBy([(t) => OrderingTerm.asc(t.assetExpiryDate)]);
    return query.get();
  }

  /// 标记/取消标记附件为凭证。
  Future<void> setAttachmentCredential(String attachmentId, bool isCredential) =>
      (update(attachments)..where((t) => t.id.equals(attachmentId))).write(
        AttachmentsCompanion(isCredential: Value(isCredential)),
      );

  /// 资产笔记的凭证附件。
  Future<List<Attachment>> credentialsForNote(String noteId) =>
      (select(attachments)
            ..where((t) => t.noteId.equals(noteId))
            ..where((t) => t.isCredential.equals(true)))
          .get();

  // ---------------------------------------------------------------------------
  // Note links（阶段三）
  // ---------------------------------------------------------------------------

  /// 某笔记的全部关联（**双向**：该笔记作为 source 或 target 均返回）。
  /// 单行存储、双向可见，不双写——见 design D2。
  Future<List<NoteLink>> linksForNote(String noteId) =>
      (select(noteLinks)
            ..where((t) =>
                t.sourceNoteId.equals(noteId) | t.targetNoteId.equals(noteId)))
          .get();

  /// 建立关联。同向重复插入时忽略（复合主键冲突）。
  Future<void> insertLink(NoteLinksCompanion entry) =>
      into(noteLinks).insert(entry, mode: InsertMode.insertOrIgnore);

  /// 删除指定有向关联。
  Future<void> deleteLink(String sourceNoteId, String targetNoteId) =>
      (delete(noteLinks)
            ..where((t) => t.sourceNoteId.equals(sourceNoteId))
            ..where((t) => t.targetNoteId.equals(targetNoteId)))
          .go();

  /// 全部关联（供星图视图使用）。
  Future<List<NoteLink>> allLinks() => select(noteLinks).get();

  // ---------------------------------------------------------------------------
  // Tag CRUD
  // ---------------------------------------------------------------------------

  Future<List<Tag>> allTags() => select(tags).get();

  Future<void> insertTag(TagsCompanion entry) =>
      into(tags).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> deleteTag(String id) =>
      (delete(tags)..where((t) => t.id.equals(id))).go();

  // Note-Tag associations
  Future<List<Tag>> tagsForNote(String noteId) {
    final query = select(tags).join([
      innerJoin(noteTags, noteTags.tagId.equalsExp(tags.id)),
    ]);
    query.where(noteTags.noteId.equals(noteId));
    return query.map((row) => row.readTable(tags)).get();
  }

  Future<void> setNoteTags(String noteId, List<String> tagIds) async {
    await (delete(noteTags)..where((t) => t.noteId.equals(noteId))).go();
    for (final tagId in tagIds) {
      await into(noteTags).insert(NoteTagsCompanion(
        noteId: Value(noteId),
        tagId: Value(tagId),
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Attachment CRUD
  // ---------------------------------------------------------------------------

  Future<List<Attachment>> attachmentsForNote(String noteId) =>
      (select(attachments)..where((t) => t.noteId.equals(noteId))).get();

  Future<void> insertAttachment(AttachmentsCompanion entry) =>
      into(attachments).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> deleteAttachment(String id) =>
      (delete(attachments)..where((t) => t.id.equals(id))).go();

  // ---------------------------------------------------------------------------
  // Full-Text Search
  // ---------------------------------------------------------------------------

  /// 中文全文检索。
  ///
  /// 查询经 CJK bigram 分词后以 OR 拼接（见 [cjkFtsQuery]），靠 `bm25()` 把命中
  /// bigram 更多的笔记排序在前。`unicode61` 默认分词对中文失效，故索引与查询
  /// 两侧都做 bigram 化。
  Future<List<Note>> searchNotes(String query) async {
    final ftsQuery = cjkFtsQuery(query);
    // 查询无有效 token（纯标点/空白）时直接返回空，避免 MATCH 空表达式报错。
    if (ftsQuery.isEmpty) return [];

    final results = await customSelect(
      "SELECT note_id FROM notes_fts WHERE notes_fts MATCH ?1 "
      "ORDER BY bm25(notes_fts)",
      variables: [Variable.withString(ftsQuery)],
    ).get();

    final ids = results.map((r) => r.data['note_id'] as String).toList();
    if (ids.isEmpty) return [];

    // 保持 bm25 的相关性顺序，而非按 updatedAt 重排。
    final notesById = <String, Note>{};
    for (final n in await (select(notes)
          ..where((t) => t.id.isIn(ids) & t.isDeleted.equals(false)))
        .get()) {
      notesById[n.id] = n;
    }
    return ids.map((id) => notesById[id]).whereType<Note>().toList();
  }

  /// 写入 FTS 索引。title 与 content 均经 CJK bigram 化后存储，
  /// 与 [searchNotes] 的查询侧分词保持一致。
  Future<void> indexNote(String noteId, String title, String plainContent) async {
    // Remove old index entry
    await customStatement(
      "DELETE FROM notes_fts WHERE note_id = ?",
      [noteId],
    );
    // Insert new index entry（bigram 化后的文本）
    await customStatement(
      "INSERT INTO notes_fts (title, content, note_id) VALUES (?1, ?2, ?3)",
      [cjkIndexText(title), cjkIndexText(plainContent), noteId],
    );
  }

  /// 清空 FTS 索引。分词方案变更后配合重建使用（`notes_fts` 是派生数据）。
  Future<void> clearFtsIndex() => customStatement("DELETE FROM notes_fts");

  /// 所有未删除笔记，供 FTS 索引重建遍历。
  Future<List<Note>> allNotesForIndexing() =>
      (select(notes)..where((t) => t.isDeleted.equals(false))).get();

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  Future<int> noteCount({String? notebookId, bool includeDeleted = false}) async {
    final query = selectOnly(notes)..addColumns([notes.id.count()]);
    if (!includeDeleted) {
      query.where(notes.isDeleted.equals(false));
    }
    if (notebookId != null) {
      query.where(notes.notebookId.equals(notebookId));
    }
    final result = await query.getSingle();
    return result.read(notes.id.count()) ?? 0;
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    return SqfliteQueryExecutor.inDatabaseFolder(path: 'notebook.db');
  });
}
