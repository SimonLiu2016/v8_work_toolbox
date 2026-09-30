import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../services/app_paths.dart';

import 'note_database.dart';
import 'appflowy_codec.dart';
import '../../services/settings_store.dart';

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
    await _migrateLegacyNoteDbIfNeeded();
    _db = NoteDatabase();
    _attachmentsDir = AppPaths.attachmentsDir.path;
    await Directory(_attachmentsDir!).create(recursive: true);
    _initialized = true;

    // 自动为已有但缺少 stack 的笔记本补充印象笔记层级组
    await autoBackfillNotebookStacksFromEvernote();

    // 中文分词上线的一次性索引重建（版本标记驱动，只跑一次）
    await _migrateFtsTokenizerIfNeeded();
  }

  /// 一次性搬迁：把 drift 旧默认目录（macOS 为 `~/Documents/notebook.db`）
  /// 移到 `AppPaths.noteDbFile`。同卷下 `renameSync` 是元数据操作，原子且无
  /// 数据复制风险。校验和比对失败则保留源文件不动并记错误，不阻断启动
  /// （main() 的 fail-soft 契约）。
  Future<void> _migrateLegacyNoteDbIfNeeded() async {
    final target = AppPaths.noteDbFile;
    if (target.existsSync()) return;

    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;
    final legacy = File(p.join(home, 'Documents', 'notebook.db'));
    if (!legacy.existsSync()) return;

    try {
      target.parent.createSync(recursive: true);
      final bytesBefore = legacy.lengthSync();
      legacy.renameSync(target.path);
      final bytesAfter = target.lengthSync();
      if (bytesBefore != bytesAfter) {
        throw StateError('搬迁后字节数不一致: $bytesBefore → $bytesAfter');
      }
      debugPrint('笔记主库已从 ${legacy.path} 搬迁到 ${target.path}');
    } catch (e) {
      debugPrint('笔记主库搬迁失败（保留原位）: $e');
    }
  }

  /// 当前 FTS 索引方案版本。变更此值会触发一次全量索引重建。
  /// v1 = 未分词原始文本（unicode61 直存）
  /// v2 = CJK bigram 分词
  /// v3 = 修复正文提取（v2 用 Quill 解析器读 AppFlowy 格式，正文全空，
  ///      只有标题进索引；v3 改为 AppFlowyCodec.jsonToPlainText）
  static const int ftsTokenizerVersion = 3;

  /// 检测分词方案变更并重建 FTS 索引。旧索引存的是未分词原始文本，
  /// `unicode61` 对中文整串当单 token，不重建则既有笔记搜不到。
  Future<void> _migrateFtsTokenizerIfNeeded() async {
    try {
      final cfg = await SettingsStore.instance.readToolConfig('notebook');
      if ((cfg['ftsTokenizerVersion'] as int?) == ftsTokenizerVersion) return;

      await rebuildFtsIndex();
      cfg['ftsTokenizerVersion'] = ftsTokenizerVersion;
      await SettingsStore.instance.writeToolConfig('notebook', cfg);
    } catch (e) {
      debugPrint('FTS 分词迁移失败: $e');
    }
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
  Future<({Map<String, List<Notebook>> stacks, List<Notebook> unstacked})>
  groupedNotebooks() async {
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

  Future<String> createNotebook(
    String name, {
    String icon = '📓',
    String? stack,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.insertNotebook(
      NotebooksCompanion(
        id: Value(id),
        name: Value(name),
        stack: Value(stack),
        icon: Value(icon),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  Future<void> updateNotebook(
    String id, {
    String? name,
    String? icon,
    String? stack,
  }) async {
    await _db.updateNotebook(
      id,
      NotebooksCompanion(
        name: name != null ? Value(name) : const Value.absent(),
        icon: icon != null ? Value(icon) : const Value.absent(),
        stack: stack != null ? Value(stack) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateNotebookStack(String id, String? stack) =>
      _db.updateNotebookStack(id, stack);

  Future<void> renameNotebook(String id, String newName) async {
    await _db.updateNotebook(
      id,
      NotebooksCompanion(
        name: Value(newName),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteNotebook(String id) => _db.deleteNotebook(id);

  /// 设为笔记捕获默认目标（单事务清空其他并设置目标）
  Future<void> setDefaultCaptureNotebook(String id) =>
      _db.setDefaultCaptureNotebook(id);

  /// 获取当前默认捕获笔记本
  Future<Notebook?> defaultCaptureNotebook() =>
      _db.defaultCaptureNotebook();

  /// 从本地印象笔记 SQLite 数据库自动为现有笔记本补全 stack 分组
  Future<void> autoBackfillNotebookStacksFromEvernote() async {
    try {
      final notebooks = await _db.allNotebooks();
      final needBackfill = notebooks
          .where((nb) => nb.stack == null || nb.stack!.isEmpty)
          .toList();
      if (needBackfill.isEmpty) return;

      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;

      final candidateRoots = [
        p.join(
          home,
          'Library/Containers/com.yinxiang.Mac/Data/Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com',
        ),
        p.join(
          home,
          'Library/Containers/com.evernote.Evernote/Data/Library/Application Support/com.evernote.Evernote/accounts/www.evernote.com',
        ),
        p.join(
          home,
          'Library/Application Support/com.yinxiang.Mac/accounts/app.yinxiang.com',
        ),
        p.join(
          home,
          'Library/Application Support/Evernote/accounts/www.evernote.com',
        ),
      ];

      String? targetDb;
      for (final root in candidateRoots) {
        final dir = Directory(root);
        if (!dir.existsSync()) continue;
        try {
          final accounts = dir.listSync().whereType<Directory>();
          for (final acct in accounts) {
            final dbFile = File(
              p.join(acct.path, 'localNoteStore', 'LocalNoteStore.sqlite'),
            );
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
        'SELECT ZNAME, ZSTACK FROM ZENNOTEBOOK WHERE ZSTACK IS NOT NULL;',
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
      debugPrint(
        '[NoteStore] autoBackfillNotebookStacksFromEvernote error: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Note operations
  // ---------------------------------------------------------------------------

  Future<List<Note>> notesForNotebook(String? notebookId) =>
      _db.notesForNotebook(notebookId);

  Future<List<Note>> notesForStack(String stack) async {
    final nbs = await _db.allNotebooks();
    final matchingIds = nbs
        .where((nb) => nb.stack == stack)
        .map((nb) => nb.id)
        .toList();
    if (matchingIds.isEmpty) return [];
    return _db.notesForNotebookIds(matchingIds);
  }

  Future<List<Note>> notesForTag(String tagId) => _db.notesForTag(tagId);

  Future<List<Note>> deletedNotes() => _db.deletedNotes();

  /// 获取知识库中所有未删除的笔记。
  Future<List<Note>> allNotes() async {
    if (!_initialized) return const [];
    try {
      return await _db.allNotesForIndexing();
    } catch (_) {
      return const [];
    }
  }

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
    await _db.insertNote(
      NotesCompanion(
        id: Value(noteId),
        title: Value(title),
        deltaJson: Value(deltaJson),
        notebookId: Value(notebookId),
        createdAt: Value(createdAt ?? now),
        updatedAt: Value(updatedAt ?? now),
      ),
    );
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

  // ---------------------------------------------------------------------------
  // Asset fields（阶段一）
  // ---------------------------------------------------------------------------

  /// 更新资产字段。传 null 表示清除该字段，传值表示设置；未传的字段不变。
  /// 使用 [Value.absent()] 区分"不更新"与"清空"。
  Future<void> updateAssetFields(
    String noteId, {
    Value<String?> assetCategory = const Value.absent(),
    Value<DateTime?> assetPurchaseDate = const Value.absent(),
    Value<DateTime?> assetServiceUntil = const Value.absent(),
    Value<DateTime?> assetExpiryDate = const Value.absent(),
  }) async {
    await _db.updateNote(
      noteId,
      NotesCompanion(
        assetCategory: assetCategory,
        assetPurchaseDate: assetPurchaseDate,
        assetServiceUntil: assetServiceUntil,
        assetExpiryDate: assetExpiryDate,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// 到期日 ≤ now+leadDays 且未过期的资产笔记。
  Future<List<Note>> assetsDueSoon(int leadDays) => _db.assetsDueSoon(leadDays);

  /// 所有未删除的资产笔记（资产字段任一非空）。
  Future<List<Note>> allAssets() => _db.allAssets();

  /// 标记/取消标记附件为凭证。
  Future<void> flagAttachmentCredential(
    String attachmentId,
    bool isCredential,
  ) => _db.setAttachmentCredential(attachmentId, isCredential);

  /// 资产笔记的凭证附件。
  Future<List<Attachment>> credentialsForNote(String noteId) =>
      _db.credentialsForNote(noteId);

  // ---------------------------------------------------------------------------
  // Note links（阶段三）
  // ---------------------------------------------------------------------------

  /// 建立两笔记间的泛化关联。自关联与重复关联被忽略。
  Future<void> createLink(
    String sourceId,
    String targetId, {
    String? reason,
  }) async {
    if (sourceId == targetId) return;
    await _db.insertLink(
      NoteLinksCompanion.insert(
        sourceNoteId: sourceId,
        targetNoteId: targetId,
        reason: Value(reason),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> deleteLink(String sourceId, String targetId) =>
      _db.deleteLink(sourceId, targetId);

  /// 某笔记的关联，已解析出「对方笔记」的标题，供详情视图直接渲染。
  /// 双向返回：自己作为 source 或 target 的关联都算。
  Future<List<RelatedNote>> relatedNotes(String noteId) async {
    final links = await _db.linksForNote(noteId);
    final out = <RelatedNote>[];
    for (final link in links) {
      final isOutgoing = link.sourceNoteId == noteId;
      final otherId = isOutgoing ? link.targetNoteId : link.sourceNoteId;
      final other = await _db.noteById(otherId);
      if (other == null || other.isDeleted) continue;
      out.add(
        RelatedNote(
          noteId: otherId,
          title: other.title,
          reason: link.reason,
          outgoing: isOutgoing,
        ),
      );
    }
    return out;
  }

  /// 全部关联（供星图视图，阶段四）。
  Future<List<NoteLink>> allLinks() => _db.allLinks();

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
    await _db.insertTag(
      TagsCompanion(id: Value(id), name: Value(name), color: Value(color)),
    );
    return id;
  }

  Future<void> deleteTag(String id) => _db.deleteTag(id);

  Future<List<Tag>> tagsForNote(String noteId) => _db.tagsForNote(noteId);

  Future<void> setNoteTags(String noteId, List<String> tagIds) =>
      _db.setNoteTags(noteId, tagIds);

  /// 在 Delta 末尾追加一条未勾选的待办项，返回新的 Delta JSON。
  ///
  /// 纯函数：不依赖数据库连接，便于单元测试。
  /// 若原文末尾不是换行，先补一个换行使新任务独立成行。
  static String appendTodoTask(String deltaJson) {
    final ops = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(deltaJson);
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) ops.add(Map<String, dynamic>.from(entry));
        }
      }
    } catch (_) {
      // 无法解析时按空文档处理，保留原值不会被写入。
    }

    if (ops.isNotEmpty) {
      final last = ops.last['insert'];
      if (last is String && last.isNotEmpty && !last.endsWith('\n')) {
        ops.add({'insert': '\n'});
      }
    }

    ops.addAll([
      {'insert': '任务：'},
      {
        'insert': '\n',
        'attributes': {'list': 'unchecked'},
      },
    ]);
    return jsonEncode(ops);
  }

  // ---------------------------------------------------------------------------
  // Attachment operations
  // ---------------------------------------------------------------------------

  Future<List<Attachment>> attachmentsForNote(String noteId) =>
      _db.attachmentsForNote(noteId);

  /// 将笔记的全部附件按原始文件名另存到 [outputDir]。
  ///
  /// 内部存储使用 `<id><ext>` 命名，对用户无意义；导出时还原为
  /// [Attachment.filename]，重名追加 `_1`、`_2` 序号。
  /// 返回 `(成功数, 失败数)`。
  Future<(int, int)> exportAttachments({
    required String noteId,
    required String outputDir,
  }) async {
    final attachments = await attachmentsForNote(noteId);
    var copied = 0;
    var failed = 0;

    for (final att in attachments) {
      try {
        final src = File(att.localPath);
        if (!src.existsSync()) {
          failed += 1;
          continue;
        }
        final name = (att.filename ?? '').trim().isEmpty
            ? '附件_${att.id}'
            : att.filename!;
        await src.copy(uniqueExportPath(outputDir, name));
        copied += 1;
      } catch (e) {
        debugPrint('NoteStore: export attachment ${att.id} failed: $e');
        failed += 1;
      }
    }
    return (copied, failed);
  }

  /// 目标目录下重名时追加序号。
  ///
  /// 公开为静态方法以便单元测试，不依赖数据库连接。
  static String uniqueExportPath(String dir, String filename) {
    final dot = filename.lastIndexOf('.');
    final base = dot > 0 ? filename.substring(0, dot) : filename;
    final ext = dot > 0 ? filename.substring(dot) : '';
    var candidate = p.join(dir, filename);
    var n = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '${base}_$n$ext');
      n += 1;
    }
    return candidate;
  }

  /// 保存文件到附件目录并创建数据库记录（返回本地路径）。
  ///
  /// 扁平存储（`attachmentsDir/<id><ext>`），由 Evernote 导入与编辑器粘贴使用。
  /// 新增的 [addAttachment] 按 noteId 分子目录并返回附件 ID。
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

    await _db.insertAttachment(
      AttachmentsCompanion(
        id: Value(id),
        noteId: Value(noteId),
        filename: Value(filename ?? p.basename(sourceFile.path)),
        mime: Value(mime),
        localPath: Value(targetPath),
        createdAt: Value(DateTime.now()),
      ),
    );
    return targetPath;
  }

  /// 用户主动添加附件：复制文件到 `attachmentsDir/<noteId>/` 子目录，
  /// 返回 attachment ID（便于编辑器插入附件块引用）。
  /// 与 [saveAttachment] 的区别：按 noteId 分子目录 + 返回 ID + 自动 MIME 检测。
  Future<String> addAttachment({
    required String noteId,
    required File sourceFile,
  }) async {
    final id = _uuid.v4();
    final ext = p.extension(sourceFile.path);
    final noteDir = Directory(p.join(attachmentsDir, noteId));
    await noteDir.create(recursive: true);
    final targetPath = p.join(noteDir.path, '${id}_$ext'.replaceAll(' ', '_'));
    await sourceFile.copy(targetPath);

    final mime = _lookupMime(sourceFile.path);
    await _db.insertAttachment(
      AttachmentsCompanion(
        id: Value(id),
        noteId: Value(noteId),
        filename: Value(p.basename(sourceFile.path)),
        mime: Value(mime),
        localPath: Value(targetPath),
        createdAt: Value(DateTime.now()),
      ),
    );
    return id;
  }

  /// 批量添加附件，返回 attachment ID 列表。
  Future<List<String>> addAttachments({
    required String noteId,
    required List<File> files,
  }) async {
    final ids = <String>[];
    for (final f in files) {
      ids.add(await addAttachment(noteId: noteId, sourceFile: f));
    }
    return ids;
  }

  /// 按 attachment ID 查询单个附件。
  Future<Attachment?> attachmentById(String attId) async {
    final results = await _db
        .customSelect(
          'SELECT id, note_id, filename, mime, local_path, created_at, is_credential FROM attachments WHERE id = ?',
          variables: [Variable<String>(attId)],
        )
        .get();
    if (results.isEmpty) return null;
    final row = results.first;
    return Attachment(
      id: row.read<String>('id'),
      noteId: row.read<String>('note_id'),
      filename: row.readNullable<String>('filename'),
      mime: row.readNullable<String>('mime'),
      localPath: row.read<String>('local_path'),
      createdAt: row.read<DateTime>('created_at'),
      isCredential: row.read<bool>('is_credential'),
    );
  }

  /// 删除指定附件（文件 + 数据库记录）。
  Future<void> deleteAttachment(String attId) async {
    final results = await _db
        .customSelect(
          'SELECT * FROM attachments WHERE id = ?',
          variables: [Variable<String>(attId)],
        )
        .get();
    if (results.isEmpty) return;
    final row = results.first;
    final localPath = row.read<String>('local_path');
    final f = File(localPath);
    if (f.existsSync()) await f.delete();
    await _db.customStatement('DELETE FROM attachments WHERE id = ?', [attId]);
  }

  static String? _lookupMime(String filePath) {
    // 简易 MIME 检测——依赖 path 包的 extension
    final ext = p.extension(filePath).toLowerCase();
    const map = {
      '.pdf': 'application/pdf',
      '.doc': 'application/msword',
      '.docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      '.xls': 'application/vnd.ms-excel',
      '.xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      '.ppt': 'application/vnd.ms-powerpoint',
      '.pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      '.txt': 'text/plain',
      '.md': 'text/markdown',
      '.png': 'image/png',
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.gif': 'image/gif',
      '.zip': 'application/zip',
      '.csv': 'text/csv',
      '.json': 'application/json',
      '.html': 'text/html',
    };
    return map[ext];
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

    await _db.insertAttachment(
      AttachmentsCompanion(
        id: Value(id),
        noteId: Value(noteId),
        filename: Value(filename),
        mime: Value(mime),
        localPath: Value(targetPath),
        createdAt: Value(DateTime.now()),
      ),
    );
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

  /// 重建全部 FTS 索引。中文分词方案（CJK bigram）上线后必须执行一次——
  /// 旧索引存的是未分词的原始文本，`unicode61` 对中文整串当单 token，不重建
  /// 则既有笔记搜不到。`notes_fts` 是派生数据，可安全清空重灌。
  Future<int> rebuildFtsIndex() async {
    try {
      await _db.clearFtsIndex();
      final all = await _db.allNotesForIndexing();
      var count = 0;
      for (final n in all) {
        try {
          await _indexNote(n.id, n.title, n.deltaJson);
          count++;
        } catch (e) {
          debugPrint('重建 FTS 索引失败 (note ${n.id}): $e');
        }
      }
      debugPrint('FTS 索引重建完成：$count 条笔记');
      return count;
    } catch (e) {
      debugPrint('FTS 索引重建失败: $e');
      return 0;
    }
  }

  /// 从笔记正文提取用于 FTS 索引的纯文本。
  ///
  /// 早期实现用 `jsonDecode(...) as List`（Quill Delta 解析器）解析，对 AppFlowy
  /// 迁移后的 `{"document":{...}}` 格式必然抛异常并静默返回空串——后果是
  /// **正文从未进过索引，只有标题可搜**。现统一走 [AppFlowyCodec.jsonToPlainText]。
  String _extractPlainText(String deltaJson) =>
      AppFlowyCodec.jsonToPlainText(deltaJson);
}

/// 笔记详情中的一条关联（已解析对方标题）。
class RelatedNote {
  final String noteId;
  final String title;

  /// 关联理由（AI 建议时生成，用户手建可空）。
  final String? reason;

  /// 当前笔记是否为关联的 source 方（用于 UI 区分方向，可选展示）。
  final bool outgoing;

  const RelatedNote({
    required this.noteId,
    required this.title,
    this.reason,
    this.outgoing = true,
  });
}
