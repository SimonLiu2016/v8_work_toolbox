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

    // 自动为已有但缺少 stack 的笔记本补充印象笔记层级组
    await autoBackfillNotebookStacksFromEvernote();
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

  /// 获取按 Stack 分组的笔记本结构：
  /// - stacks: `Map<String, List<Notebook>>` (Stack 名称 -> 该组下的笔记本列表)
  /// - unstacked: `List<Notebook>` (未归入任何组的独立笔记本)
  Future<({Map<String, List<Notebook>> stacks, List<Notebook> unstacked})> groupedNotebooks() async {
    final all = await _db.allNotebooks();
    final Map<String, List<Notebook>> stacks = {};
    final List<Notebook> unstacked = [];

    for (final nb in all) {
      final s = nb.stack?.trim();
      if (s != null && s.isNotEmpty) {
        stacks.putIfAbsent(s, () => []).add(nb);
      } else {
        unstacked.add(nb);
      }
    }
    return (stacks: stacks, unstacked: unstacked);
  }

  Future<String> createNotebook(String name, {String icon = '📓', String? stack}) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertNotebook(NotebooksCompanion(
      id: Value(id),
      name: Value(name),
      stack: Value(stack),
      icon: Value(icon),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));
    return id;
  }

  Future<void> updateNotebook(String id, {String? name, String? icon, String? stack}) async {
    await _db.updateNotebook(id, NotebooksCompanion(
      name: name != null ? Value(name) : const Value.absent(),
      icon: icon != null ? Value(icon) : const Value.absent(),
      stack: stack != null ? Value(stack) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> updateNotebookStack(String id, String? stack) =>
      _db.updateNotebookStack(id, stack);

  Future<void> renameNotebook(String id, String newName) async {
    await _db.updateNotebook(id, NotebooksCompanion(
      name: Value(newName),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> deleteNotebook(String id) => _db.deleteNotebook(id);

  /// 从本地印象笔记 SQLite 数据库自动为现有笔记本补全 stack 分组
  Future<void> autoBackfillNotebookStacksFromEvernote() async {
    try {
      final notebooks = await _db.allNotebooks();
      final needBackfill = notebooks.where((nb) => nb.stack == null || nb.stack!.isEmpty).toList();
      if (needBackfill.isEmpty) return;

      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final candidateRoots = [
        p.join(home, 'Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com'),
        p.join(home, 'Library/Containers/com.evernote.Evernote/Data/Library/Application Support/com.evernote.Evernote/accounts/www.evernote.com'),
        p.join(home, 'Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com'),
        p.join(home, 'Library/Application Support/Evernote/accounts/www.evernote.com'),
      ];

      String? targetDb;
      for (final root in candidateRoots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        try {
          final accounts = dir.listSync().whereType<Directory>();
          for (final acct in accounts) {
            final dbFile = File(p.join(acct.path, 'localNoteStore', 'LocalNoteStore.sqlite'));
            if (dbFile.existsSync()) {
              targetDb = dbFile.path;
              break;
            }
          }
        } catch (_) {}
        if (targetDb != null) break;
      }

      if (targetDb == null) return;

      final res = await Process.run('sqlite3', [
        targetDb,
        'SELECT ZNAME, ZSTACK FROM ZENNOTEBOOK WHERE ZSTACK IS NOT NULL;'
      ]);
      if (res.exitCode != 0) return;

      final lines = (res.stdout as String).split('\n');
      final stackMap = <String, String>{};
      for (final line in lines) {
        final parts = line.split('|');
        if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
          stackMap[parts[0].trim()] = parts[1].trim();
        }
      }

      for (final nb in needBackfill) {
        final stack = stackMap[nb.name];
        if (stack != null && stack.isNotEmpty) {
          await updateNotebookStack(nb.id, stack);
          debugPrint('[NoteStore] 自动补全笔记本层级组: "${nb.name}" -> "$stack"');
        }
      }
    } catch (e) {
      debugPrint('[NoteStore] autoBackfillNotebookStacksFromEvernote error: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Note operations
  // ---------------------------------------------------------------------------

  Future<List<Note>> notesForNotebook(String? notebookId) =>
      _db.notesForNotebook(notebookId);

  Future<List<Note>> notesForStack(String stack) async {
    final nbs = await _db.allNotebooks();
    final matchingIds = nbs.where((nb) => nb.stack == stack).map((nb) => nb.id).toList();
    if (matchingIds.isEmpty) return [];
    return _db.notesForNotebookIds(matchingIds);
  }

  Future<List<Note>> notesForTag(String tagId) => _db.notesForTag(tagId);

  Future<List<Note>> deletedNotes() => _db.deletedNotes();

  Future<Note?> noteById(String id) => _db.noteById(id);

  Future<String> createNote({
    String? id,
    required String title,
    required String deltaJson,
    String? notebookId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final noteId = id ?? _uuid.v4();
    final now = DateTime.now();
    await _db.insertNote(NotesCompanion(
      id: Value(noteId),
      title: Value(title),
      deltaJson: Value(deltaJson),
      notebookId: Value(notebookId),
      createdAt: Value(createdAt ?? now),
      updatedAt: Value(updatedAt ?? now),
    ));
    // Index for FTS
    await _indexNote(noteId, title, deltaJson);
    return noteId;
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

  Future<void> batchSoftDeleteNotes(List<String> ids) =>
      _db.batchSoftDeleteNotes(ids);

  Future<void> restoreNote(String id) => _db.restoreNote(id);

  Future<void> batchRestoreNotes(List<String> ids) =>
      _db.batchRestoreNotes(ids);

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

  Future<void> batchPermanentlyDeleteNotes(List<String> ids) async {
    if (ids.isEmpty) return;
    for (final id in ids) {
      final attachments = await _db.attachmentsForNote(id);
      for (final att in attachments) {
        final file = File(att.localPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    }
    await _db.batchPermanentlyDeleteNotes(ids);
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
