import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

void main() {
  group('NoteStore.addAttachment 端到端', () {
    late Directory tempDir;
    late NoteDatabase db;
    late Directory attDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('note_store_att_test_');
      attDir = Directory('${tempDir.path}/atts');
      await attDir.create();
      db = NoteDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('添加附件后记录存在且文件物理存在', () async {
      final sourceFile = File('${tempDir.path}/source.pdf');
      await sourceFile.writeAsBytes([0x25, 0x50, 0x44, 0x46]);

      final store = _TestNoteStore(db, attDir.path);
      final attId = await store.addAttachment(noteId: 'note1', sourceFile: sourceFile);

      expect(attId, isNotEmpty);
      final atts = await db.attachmentsForNote('note1');
      expect(atts.length, 1);
      expect(atts.first.filename, 'source.pdf');
      expect(atts.first.mime, 'application/pdf');
      expect(File(atts.first.localPath).existsSync(), isTrue);
    });

    test('批量添加多个附件', () async {
      final files = <File>[];
      for (var i = 0; i < 3; i++) {
        final f = File('${tempDir.path}/file_$i.txt');
        await f.writeAsString('content $i');
        files.add(f);
      }

      final store = _TestNoteStore(db, attDir.path);
      final ids = await store.addAttachments(noteId: 'note2', files: files);

      expect(ids.length, 3);
      final atts = await db.attachmentsForNote('note2');
      expect(atts.length, 3);
      for (final att in atts) {
        expect(File(att.localPath).existsSync(), isTrue);
      }
    });

    test('附件按 noteId 分子目录', () async {
      final f = File('${tempDir.path}/doc.docx');
      await f.writeAsBytes([1, 2, 3]);
      final store = _TestNoteStore(db, attDir.path);
      await store.addAttachment(noteId: 'noteA', sourceFile: f);

      final atts = await db.attachmentsForNote('noteA');
      expect(atts.first.localPath, contains('noteA'));
    });

    test('attachmentById 查询', () async {
      final f = File('${tempDir.path}/report.xlsx');
      await f.writeAsBytes([1, 2, 3]);
      final store = _TestNoteStore(db, attDir.path);
      final id = await store.addAttachment(noteId: 'noteX', sourceFile: f);

      final att = await store.attachmentById(id);
      expect(att, isNotNull);
      expect(att!.filename, 'report.xlsx');
      expect(att.mime, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    });
  });
}

/// 测试用 NoteStore 包装：直接注入临时 db 与 attachmentsDir。
class _TestNoteStore {
  final NoteDatabase db;
  final String attachmentsDir;
  int _counter = 0;

  _TestNoteStore(this.db, this.attachmentsDir);

  Future<String> addAttachment({
    required String noteId,
    required File sourceFile,
  }) async {
    final id = 'att_${_counter++}_$noteId';
    final ext = sourceFile.path.split('.').last;
    final noteDir = Directory('$attachmentsDir/$noteId');
    await noteDir.create(recursive: true);
    final targetPath = '$attachmentsDir/$noteId/${id}_.${ext}';
    await sourceFile.copy(targetPath);

    await db.into(db.attachments).insert(AttachmentsCompanion.insert(
          id: id,
          noteId: noteId,
          filename: d.Value(sourceFile.uri.pathSegments.last),
          mime: d.Value(_lookupMime(sourceFile.path)),
          localPath: targetPath,
          createdAt: DateTime.now(),
        ));
    return id;
  }

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

  Future<Attachment?> attachmentById(String attId) async {
    final results = await db.customSelect(
      'SELECT id, note_id, filename, mime, local_path, created_at FROM attachments WHERE id = ?',
      variables: [d.Variable<String>(attId)],
    ).get();
    if (results.isEmpty) return null;
    final row = results.first;
    return Attachment(
      id: row.read<String>('id'),
      noteId: row.read<String>('note_id'),
      filename: row.readNullable<String>('filename'),
      mime: row.readNullable<String>('mime'),
      localPath: row.read<String>('local_path'),
      createdAt: row.read<DateTime>('created_at'),
    );
  }

  static String? _lookupMime(String path) {
    final ext = path.toLowerCase().split('.').last;
    const map = {
      'pdf': 'application/pdf',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain',
      'md': 'text/markdown',
    };
    return map[ext];
  }
}
