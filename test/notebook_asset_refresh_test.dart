import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/ui/asset_fields_panel.dart';

/// 资产字段的连续保存与刷新契约。
///
/// 防的是「弹窗持有打开时的快照」：保存后重开弹窗看到旧值，用户侧表现为
/// 「内容丢失」。数据库一直是单一数据源——问题从来不是读得慢，是没人去读。
void main() {
  final now = DateTime.now();

  group('asset chip 文案', () {
    Note noteWith({
      String? category,
      DateTime? expiry,
      DateTime? service,
      DateTime? purchase,
    }) {
      return Note(
        id: 'n',
        title: 't',
        deltaJson: '[]',
        notebookId: null,
        isPinned: false,
        isDeleted: false,
        createdAt: now,
        updatedAt: now,
        assetCategory: category,
        assetPurchaseDate: purchase,
        assetServiceUntil: service,
        assetExpiryDate: expiry,
      );
    }

    test('无资产数据时返回 null（调用方回落到裸「资产」）', () {
      expect(assetChipLabel(noteWith()), isNull);
    });

    test('有品类时优先显示品类', () {
      expect(assetChipLabel(noteWith(category: '延保服务')), '延保服务');
    });

    test('空品类不算有数据，回落到到期倒计时', () {
      final label = assetChipLabel(
        noteWith(category: '  ', expiry: now.add(const Duration(days: 30))),
      );
      // 天数按当前时刻计算，跨过午夜会少 1——只断言形状与量级。
      expect(label, matches(RegExp(r'^(29|30) 天$')));
    });

    test('到期日已过显示「已过期」', () {
      expect(
        assetChipLabel(noteWith(expiry: now.subtract(const Duration(days: 1)))),
        '已过期',
      );
    });

    test('只有服务期时显示服务期剩余天数', () {
      final label = assetChipLabel(
        noteWith(service: now.add(const Duration(days: 120))),
      );
      expect(label, matches(RegExp(r'^服务期 (119|120) 天$')));
    });

    test('hasAssetData 在仅有购买日时也为真', () {
      expect(hasAssetData(noteWith(purchase: now)), isTrue);
      expect(hasAssetData(noteWith()), isFalse);
    });
  });

  group('连续保存不回退', () {
    late NoteDatabase db;

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
      await db.insertNote(
        NotesCompanion.insert(
          id: 'asset_note',
          title: '豆浆机延保',
          deltaJson: '[]',
          createdAt: now,
          updatedAt: now,
        ),
      );
    });

    tearDown(() async => await db.close());

    test('第二次保存基于第一次的结果，不回退', () async {
      await db.updateNote(
        'asset_note',
        NotesCompanion(assetCategory: const Value('延保服务')),
      );
      await db.updateNote(
        'asset_note',
        NotesCompanion(
          assetExpiryDate: Value(now.add(const Duration(days: 400))),
        ),
      );

      final note = await db.noteById('asset_note');
      expect(note!.assetCategory, '延保服务', reason: '第二次保存不应清掉品类');
      expect(note.assetExpiryDate, isNotNull, reason: '第二次保存应写入到期日');
    });

    test('外部改动后重新读取拿到新值', () async {
      await db.updateNote(
        'asset_note',
        NotesCompanion(assetCategory: const Value('保险')),
      );

      // 模拟弹窗重新打开：按 id 从数据库读，而非信任旧快照。
      final reloaded = await db.noteById('asset_note');
      expect(reloaded!.assetCategory, '保险');
    });

    test('清空品类只清品类，不动日期', () async {
      await db.updateNote(
        'asset_note',
        NotesCompanion(
          assetCategory: const Value('会员'),
          assetExpiryDate: Value(now.add(const Duration(days: 10))),
        ),
      );
      await db.updateNote(
        'asset_note',
        NotesCompanion(assetCategory: const Value(null)),
      );

      final note = await db.noteById('asset_note');
      expect(note!.assetCategory, isNull);
      expect(note.assetExpiryDate, isNotNull, reason: '清空品类不应影响到期日');
    });
  });
}
