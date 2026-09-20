import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/cjk_tokenizer.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';

void main() {
  group('cjkBigrams 分词', () {
    test('CJK 连续段切重叠双字', () {
      expect(cjkBigrams('豆浆机'), ['豆浆', '浆机']);
      expect(cjkBigrams('我买了豆浆机'), ['我买', '买了', '了豆', '豆浆', '浆机']);
    });

    test('单字 CJK 保留自身', () {
      expect(cjkBigrams('好'), ['好']);
      expect(cjkBigrams('A好B'), ['a', '好', 'b']);
    });

    test('ASCII 词原样保留并小写化', () {
      expect(cjkBigrams('ABC123'), ['abc123']);
      expect(cjkBigrams('保单号 ABC123'), ['保单', '单号', 'abc123']);
    });

    test('标点与空白作为分隔符丢弃', () {
      expect(cjkBigrams('豆浆机，坏了。'), ['豆浆', '浆机', '坏了']);
      expect(cjkBigrams('   '), isEmpty);
      expect(cjkBigrams('!!!'), isEmpty);
    });

    test('中英混排', () {
      expect(cjkBigrams('买了iPhone 15'), ['买了', 'iphone', '15']);
    });
  });

  group('cjkFtsQuery 查询表达式', () {
    test('OR 拼接且每 token 加引号', () {
      expect(cjkFtsQuery('豆浆机'), '"豆浆" OR "浆机"');
    });

    test('空查询返回空串', () {
      expect(cjkFtsQuery(''), '');
      expect(cjkFtsQuery('，。！'), '');
    });

    test('双引号属分隔符，不作为词的一部分', () {
      // `"` 是标点，被当作分隔符丢弃，故 a 与 b 成为独立 token。
      expect(cjkFtsQuery('a"b'), '"a" OR "b"');
    });

    test('FTS5 语法字符被引号包裹，不会注入', () {
      // 用户输入 FTS5 操作符也不应破坏查询（星号属标点被丢弃）
      final q = cjkFtsQuery('豆浆* OR 保险');
      expect(q, startsWith('"'));
      expect(q.contains('*'), isFalse);
    });
  });

  group('FTS 端到端：中文检索', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      await _seed(db, now, 'n1', '豆浆机延保',
          '我在京东买了豆浆机，同时买了5年换新服务，花了24块钱');
      await _seed(db, now, 'n2', '汽车保险', '车险到2027年到期，保单号 ABC123');
      await _seed(db, now, 'n3', '净水器滤芯', '滤芯每6个月更换，参考价89元');
    });

    tearDown(() async => await db.close());

    test('两字词命中（延保/保险）——unicode61 下这会失效', () async {
      expect((await db.searchNotes('延保')).map((n) => n.id), ['n1']);
      expect((await db.searchNotes('保险')).map((n) => n.id), ['n2']);
      expect((await db.searchNotes('换新')).map((n) => n.id), ['n1']);
      expect((await db.searchNotes('保单')).map((n) => n.id), ['n2']);
    });

    test('三字词命中（豆浆机）', () async {
      final r = await db.searchNotes('豆浆机');
      expect(r.map((n) => n.id), contains('n1'));
    });

    test('自然语言问句命中正确笔记且排首位', () async {
      final r = await db.searchNotes('豆浆机坏了怎么办');
      expect(r, isNotEmpty);
      expect(r.first.id, 'n1', reason: '命中 bigram 最多的笔记应排首位');
    });

    test('不相关查询返回空，无误召回', () async {
      expect(await db.searchNotes('量子计算'), isEmpty);
      expect(await db.searchNotes('不存在的词'), isEmpty);
    });

    test('ASCII 查询不回归', () async {
      final r = await db.searchNotes('ABC123');
      expect(r.map((n) => n.id), ['n2']);
    });

    test('纯标点查询返回空而非报错', () async {
      expect(await db.searchNotes('，。！'), isEmpty);
    });

    test('相关度排序：命中更多 bigram 的排前', () async {
      await _seed(db, now, 'n4', '杂谈', '今天天气不错，顺便提一句豆浆');
      final r = await db.searchNotes('豆浆机延保');
      expect(r.first.id, 'n1', reason: 'n1 命中豆浆/浆机/延保，n4 只命中豆浆');
    });

    test('已删除笔记不出现在结果', () async {
      await (db.update(db.notes)..where((t) => t.id.equals('n1')))
          .write(const NotesCompanion(isDeleted: Value(true)));
      expect(await db.searchNotes('豆浆机'), isEmpty);
    });
  });

  group('FTS 索引重建', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => await db.close());

    test('清空索引后旧笔记搜不到，重建后可搜到', () async {
      await _seed(db, now, 'n1', '豆浆机延保', '买了5年换新服务');
      expect((await db.searchNotes('豆浆机')).map((n) => n.id), ['n1']);

      await db.clearFtsIndex();
      expect(await db.searchNotes('豆浆机'), isEmpty, reason: '索引清空后应搜不到');

      final all = await db.allNotesForIndexing();
      expect(all.length, 1);
      for (final n in all) {
        await db.indexNote(n.id, n.title, '买了5年换新服务');
      }
      expect((await db.searchNotes('豆浆机')).map((n) => n.id), ['n1'],
          reason: '重建后应恢复可搜');
    });

    test('allNotesForIndexing 排除已删除笔记', () async {
      await _seed(db, now, 'n1', 'A', 'a');
      await _seed(db, now, 'n2', 'B', 'b');
      await (db.update(db.notes)..where((t) => t.id.equals('n2')))
          .write(const NotesCompanion(isDeleted: Value(true)));
      final all = await db.allNotesForIndexing();
      expect(all.map((n) => n.id), ['n1']);
    });
  });
}

Future<void> _seed(
  NoteDatabase db,
  DateTime now,
  String id,
  String title,
  String content,
) async {
  await db.insertNote(NotesCompanion.insert(
    id: id,
    title: title,
    deltaJson: '[{"insert":"$content\\n"}]',
    createdAt: now,
    updatedAt: now,
  ));
  // 模拟 NoteStore 的索引行为：Delta → 纯文本 → bigram 化写入
  await db.indexNote(id, title, content);
}
