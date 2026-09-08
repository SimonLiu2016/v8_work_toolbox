import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'note_database.dart';

/// 笔记存储服务（单例）
/// 封装 NoteDatabase，提供高层业务操作
class NoteStore {
  NoteStore._();
  static final NoteStore instance = NoteStore._();

  late final NoteDatabase _db;
  bool _initialized = false;
  String? _attachmentsDir;

  static const _uuid = Uuid();

  Future<void> init() async {
    if (_initialized) return;
    _db = NoteDatabase();
    final dir = await getApplicationSupportDirectory();
    _attachmentsDir = p.join(dir.path, 'notebook_attachments');
    await Directory(_attachmentsDir!).create(recursive: true);
    _initialized = true;
  }

  NoteDatabase get db {
    assert(_initialized, 'NoteStore.init() must be called first');
    return _db;
  }

  String get attachmentsDir {
    assert(_initialized, 'NoteStore.init() must be called first');
    return _attachmentsDir!;
  }

  // ---------------------------------------------------------------------------
  // Notebook operations
  // ---------------------------------------------------------------------------

  Future<List<Notebook>> allNotebooks() => _db.allNotebooks();

  Future<String> createNotebook(String name, {String icon = '📓'}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertNotebook(NotebooksCompanion(
      id: Value(id),
      name: Value(name),
      icon: Value(icon),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return id;
  }

  Future<void> renameNotebook(String id, String newName) async {
    await _db.updateNotebook(id, NotebooksCompanion(
      name: Value(newName),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteNotebook(String id) => _db.deleteNotebook(id);

  // ---------------------------------------------------------------------------
  // Note operations
  // ---------------------------------------------------------------------------

  Future<List<Note>> notesForNotebook(String? notebookId) =>
      _db.notesForNotebook(notebookId);

  Future<List<Note>> notesForTag(String tagId) => _db.notesForTag(tagId);

  Future<Note?> noteById(String id) => _db.noteById(id);

  Future<String> createNote({
    required String title,
    required String deltaJson,
    String? notebookId,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertNote(NotesCompanion(
      id: Value(id),
      title: Value(title),
      deltaJson: Value(deltaJson),
      notebookId: Value(notebookId),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    // Index for FTS
    await _indexNote(id, title, deltaJson);
    return id;
  }

  Future<void> updateNote({
    required String id,
    String? title,
    String? deltaJson,
    String? notebookId,
    bool? isPinned,
  }) async {
    final companion = NotesCompanion(
      title: title != null ? Value(title) : const Value.absent(),
      deltaJson: deltaJson != null ? Value(deltaJson) : const Value.absent(),
      notebookId: notebookId != null ? Value(notebookId) : const Value.absent(),
      isPinned: isPinned != null ? Value(isPinned) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    );
    await _db.updateNote(id, companion);

    // Re-index FTS if content changed
    if (title != null || deltaJson != null) {
      final note = await _db.noteById(id);
      if (note != null) {
        await _indexNote(id, note.title, note.deltaJson);
      }
    }
  }

  Future<void> softDeleteNote(String id) => _db.softDeleteNote(id);

  Future<void> restoreNote(String id) => _db.restoreNote(id);

  Future<void> permanentlyDeleteNote(String id) async {
    // Delete associated attachments from disk
    final attachments = await _db.attachmentsForNote(id);
    for (final att in attachments) {
      final file = File(att.localPath);
      if (await file.exists()) {
        await file.delete();
      }
    }
    await _db.permanentlyDeleteNote(id);
  }

  // ---------------------------------------------------------------------------
  // Tag operations
  // ---------------------------------------------------------------------------

  Future<List<Tag>> allTags() => _db.allTags();

  Future<String> createTag(String name, {String? color}) async {
    final id = _uuid.v4();
    await _db.insertTag(TagsCompanion(
      id: Value(id),
      name: Value(name),
      color: Value(color),
    ));
    return id;
  }

  Future<void> deleteTag(String id) => _db.deleteTag(id);

  Future<List<Tag>> tagsForNote(String noteId) => _db.tagsForNote(noteId);

  Future<void> setNoteTags(String noteId, List<String> tagIds) =>
      _db.setNoteTags(noteId, tagIds);

  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  Future<List<Attachment>> attachmentsForNote(String noteId) =>
      _db.attachmentsForNote(noteId);

  /// 保存文件到附件目录并创建数据库记录
  Future<String> saveAttachment({
    required String noteId,
    required File sourceFile,
    String? filename,
    String? mime,
  }) async {
    final id = _uuid.v4();
    final ext = p.extension(sourceFile.path);
    final targetPath = p.join(attachmentsDir, '$id$ext');
    await sourceFile.copy(targetPath);

    await _db.insertAttachment(AttachmentsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      filename: Value(filename ?? p.basename(sourceFile.path)),
      mime: Value(mime),
      localPath: Value(targetPath),
      createdAt: Value(DateTime.now()),
    ));
    return targetPath;
  }

  /// 从 base64 数据保存附件
  Future<String> saveAttachmentFromBytes({
    required String noteId,
    required List<int> bytes,
    required String filename,
    String? mime,
  }) async {
    final id = _uuid.v4();
    final ext = p.extension(filename);
    final targetPath = p.join(attachmentsDir, '$id$ext');
    await File(targetPath).writeAsBytes(bytes);

    await _db.insertAttachment(AttachmentsCompanion(
      id: Value(id),
      noteId: Value(noteId),
      filename: Value(filename),
      mime: Value(mime),
      localPath: Value(targetPath),
      createdAt: Value(DateTime.now()),
    ));
    return targetPath;
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  Future<List<Note>> searchNotes(String query) => _db.searchNotes(query);

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  Future<int> noteCount({String? notebookId}) =>
      _db.noteCount(notebookId: notebookId);

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _indexNote(String noteId, String title, String deltaJson) async {
    try {
      // Extract plain text from Delta JSON for FTS indexing
      final plainText = _extractPlainText(deltaJson);
      await _db.indexNote(noteId, title, plainText);
    } catch (e) {
      debugPrint('FTS index error for note $noteId: $e');
    }
  }

  String _extractPlainText(String deltaJson) {
    try {
      final ops = jsonDecode(deltaJson) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in ops) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
      }
      return buffer.toString();
    } catch (_) {
      return '';
    }
  }
}
