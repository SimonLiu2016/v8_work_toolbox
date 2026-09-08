import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'note_database.g.dart';

// ---------------------------------------------------------------------------
// Tables
// ---------------------------------------------------------------------------

class Notebooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
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

  @override
  Set<Column> get primaryKey => {id};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

@DriftDatabase(tables: [Notebooks, Notes, Tags, NoteTags, Attachments])
class NoteDatabase extends _$NoteDatabase {
  NoteDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

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
  );

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

  Future<void> restoreNote(String id) =>
      (update(notes)..where((t) => t.id.equals(id))).write(
        NotesCompanion(isDeleted: const Value(false), updatedAt: Value(DateTime.now())),
      );

  Future<void> permanentlyDeleteNote(String id) =>
      (delete(notes)..where((t) => t.id.equals(id))).go();

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

  Future<List<Note>> searchNotes(String query) async {
    final results = await customSelect(
      "SELECT note_id FROM notes_fts WHERE notes_fts MATCH ?1 ORDER BY rank",
      variables: [Variable.withString(query)],
    ).get();

    final ids = results.map((r) => r.data['note_id'] as String).toList();
    if (ids.isEmpty) return [];

    return (select(notes)
          ..where((t) => t.id.isIn(ids) & t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  Future<void> indexNote(String noteId, String title, String plainContent) async {
    // Remove old index entry
    await customStatement(
      "DELETE FROM notes_fts WHERE note_id = ?",
      [noteId],
    );
    // Insert new index entry
    await customStatement(
      "INSERT INTO notes_fts (title, content, note_id) VALUES (?1, ?2, ?3)",
      [title, plainContent, noteId],
    );
  }

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
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'notebook.db');
    return SqfliteQueryExecutor.inDatabaseFolder(path: 'notebook.db');
  });
}
