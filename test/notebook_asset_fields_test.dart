import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

void main() {
  group('Asset fields migration & queries', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      await db.insertNote(NotesCompanion.insert(
        id: 'plain_note',
        title: '普通笔记',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
      await db.insertNote(NotesCompanion.insert(
        id: 'asset_note',
        title: '豆浆机延保',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        assetCategory: const Value('延保服务'),
        assetExpiryDate: Value(now.add(const Duration(days: 20))),
      ));
    });

    tearDown(() async => await db.close());

    test('旧笔记资产字段为空', () async {
      final note = await db.noteById('plain_note');
      expect(note, isNotNull);
      expect(note!.assetCategory, isNull);
      expect(note.assetExpiryDate, isNull);
    });

    test('资产笔记字段持久化', () async {
      final note = await db.noteById('asset_note');
      expect(note, isNotNull);
      expect(note!.assetCategory, '延保服务');
      expect(note.assetExpiryDate, isNotNull);
    });

    test('assetsDueSoon 命中即将到期资产', () async {
      final due = await db.assetsDueSoon(30);
      expect(due.length, 1);
      expect(due.first.id, 'asset_note');
    });

    test('assetsDueSoon 不命中过期资产', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'expired_asset',
        title: '过期会员',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        assetCategory: const Value('会员'),
        assetExpiryDate: Value(now.subtract(const Duration(days: 1))),
      ));
      final due = await db.assetsDueSoon(30);
      expect(due.length, 1);
      expect(due.first.id, 'asset_note');
    });

    test('allAssets 返回所有资产笔记（任一资产字段非空）', () async {
      final all = await db.allAssets();
      expect(all.length, 1);
      expect(all.first.id, 'asset_note');
    });
  });

  group('Attachment credential flag', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      await db.insertNote(NotesCompanion.insert(
        id: 'n1',
        title: 'n',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
      ));
      await db.insertAttachment(AttachmentsCompanion.insert(
        id: 'att1',
        noteId: 'n1',
        localPath: '/tmp/att1.png',
        createdAt: now,
      ));
      await db.insertAttachment(AttachmentsCompanion.insert(
        id: 'att2',
        noteId: 'n1',
        localPath: '/tmp/att2.png',
        createdAt: now,
        isCredential: const Value(true),
      ));
    });

    tearDown(() async => await db.close());

    test('凭证标识默认 false', () async {
      final atts = await db.attachmentsForNote('n1');
      final att1 = atts.firstWhere((a) => a.id == 'att1');
      expect(att1.isCredential, false);
    });

    test('凭证附件可查回', () async {
      final creds = await db.credentialsForNote('n1');
      expect(creds.length, 1);
      expect(creds.first.id, 'att2');
    });

    test('标记/取消标记凭证', () async {
      await db.setAttachmentCredential('att1', true);
      var creds = await db.credentialsForNote('n1');
      expect(creds.map((a) => a.id).toSet(), {'att1', 'att2'});

      await db.setAttachmentCredential('att2', false);
      creds = await db.credentialsForNote('n1');
      expect(creds.map((a) => a.id).toSet(), {'att1'});
    });
  });

  group('note_links table (占位，阶段三启用)', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      await db.insertNote(NotesCompanion.insert(
        id: 'a', title: 'A', deltaJson: '[]', createdAt: now, updatedAt: now,
      ));
      await db.insertNote(NotesCompanion.insert(
        id: 'b', title: 'B', deltaJson: '[]', createdAt: now, updatedAt: now,
      ));
    });

    tearDown(() async => await db.close());

    test('note_links 表存在且可插入', () async {
      await db.customStatement(
        "INSERT INTO note_links (source_note_id, target_note_id, relation, reason, created_at) "
        "VALUES ('a', 'b', 'related_to', '同订单', ?)",
        [now.millisecondsSinceEpoch],
      );
      final rows = await db.customSelect(
        'SELECT source_note_id, target_note_id, relation, reason FROM note_links',
      ).get();
      expect(rows.length, 1);
      expect(rows.first.data['relation'], 'related_to');
      expect(rows.first.data['reason'], '同订单');
    });
  });
}
