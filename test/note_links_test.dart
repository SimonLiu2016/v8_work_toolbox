import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/note_store.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

/// note_links 关联边测试。
///
/// NoteStore 是单例且依赖 path_provider，此处直接测 NoteDatabase 层的
/// 关联 CRUD 与级联——NoteStore 的 relatedNotes 只是在其上解析标题。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NoteDatabase db;
  final now = DateTime.now();

  Future<void> seedNote(String id, String title, {bool deleted = false}) async {
    await db.insertNote(NotesCompanion.insert(
      id: id,
      title: title,
      deltaJson: '[]',
      createdAt: now,
      updatedAt: now,
      isDeleted: Value(deleted),
    ));
  }

  setUp(() async {
    db = NoteDatabase.forTesting(NativeDatabase.memory());
    await seedNote('a', '豆浆机延保');
    await seedNote('b', '豆浆机订单');
    await seedNote('c', '无关笔记');
  });

  tearDown(() async => await db.close());

  group('关联边 CRUD', () {
    test('建立关联后可查回', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a',
        targetNoteId: 'b',
        reason: const Value('同一订单'),
        createdAt: now,
      ));
      final links = await db.linksForNote('a');
      expect(links.length, 1);
      expect(links.first.sourceNoteId, 'a');
      expect(links.first.targetNoteId, 'b');
      expect(links.first.relation, 'related_to');
      expect(links.first.reason, '同一订单');
    });

    test('双向可见：target 侧也能查到同一关联', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a',
        targetNoteId: 'b',
        createdAt: now,
      ));
      final fromB = await db.linksForNote('b');
      expect(fromB.length, 1, reason: '单行存储但查询需双向可见，不双写');
      expect(fromB.first.sourceNoteId, 'a');
    });

    test('重复插入被忽略而非抛异常', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', createdAt: now,
      ));
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', reason: const Value('重复'), createdAt: now,
      ));
      final links = await db.linksForNote('a');
      expect(links.length, 1);
      // 原记录不被覆盖
      expect(links.first.reason, isNull);
    });

    test('删除关联', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', createdAt: now,
      ));
      await db.deleteLink('a', 'b');
      expect(await db.linksForNote('a'), isEmpty);
      expect(await db.linksForNote('b'), isEmpty);
    });

    test('无关联的笔记返回空列表', () async {
      expect(await db.linksForNote('c'), isEmpty);
    });

    test('allLinks 返回全部关联', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', createdAt: now,
      ));
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'b', targetNoteId: 'c', createdAt: now,
      ));
      expect((await db.allLinks()).length, 2);
    });
  });

  group('关联级联删除', () {
    test('删除笔记时其作为 source 的关联被清除', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', createdAt: now,
      ));
      await db.permanentlyDeleteNote('a');
      expect(await db.allLinks(), isEmpty);
      // 对方笔记仍在
      expect(await db.noteById('b'), isNotNull);
    });

    test('删除笔记时其作为 target 的关联也被清除', () async {
      await db.insertLink(NoteLinksCompanion.insert(
        sourceNoteId: 'a', targetNoteId: 'b', createdAt: now,
      ));
      await db.permanentlyDeleteNote('b');
      expect(await db.allLinks(), isEmpty);
      expect(await db.noteById('a'), isNotNull);
    });
  });

  group('外键约束已启用（既有孤儿行 bug 修复）', () {
    test('为不存在的笔记插附件会被拒绝', () async {
      await expectLater(
        db.insertAttachment(AttachmentsCompanion.insert(
          id: 'att1',
          noteId: 'nonexistent',
          localPath: '/tmp/x',
          createdAt: now,
        )),
        throwsA(anything),
        reason: 'PRAGMA foreign_keys = ON 后外键应生效',
      );
    });

    test('为不存在的笔记建关联会被拒绝', () async {
      await expectLater(
        db.insertLink(NoteLinksCompanion.insert(
          sourceNoteId: 'a',
          targetNoteId: 'nonexistent',
          createdAt: now,
        )),
        throwsA(anything),
      );
    });

    test('删除笔记时附件与标签一并清除', () async {
      await db.insertAttachment(AttachmentsCompanion.insert(
        id: 'att1', noteId: 'a', localPath: '/tmp/x', createdAt: now,
      ));
      await db.insertTag(TagsCompanion.insert(id: 't1', name: 'tag1'));
      await db.setNoteTags('a', ['t1']);

      await db.permanentlyDeleteNote('a');

      final atts = await db.customSelect('SELECT count(*) c FROM attachments').getSingle();
      final nts = await db.customSelect('SELECT count(*) c FROM note_tags').getSingle();
      expect(atts.data['c'], 0, reason: '之前因未启用外键而残留孤儿行');
      expect(nts.data['c'], 0);
    });
  });

  group('RelatedNote 模型', () {
    test('携带对方笔记信息与理由', () {
      const r = RelatedNote(
        noteId: 'n1',
        title: '豆浆机订单',
        reason: '同一订单',
      );
      expect(r.noteId, 'n1');
      expect(r.title, '豆浆机订单');
      expect(r.reason, '同一订单');
      expect(r.outgoing, isTrue);
    });
  });
}
