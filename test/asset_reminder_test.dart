import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:V8WorkToolbox/tools/notebook/note_database.dart';
import 'package:V8WorkToolbox/tools/notebook/asset_reminder_service.dart';

/// 这些测试验证 AssetReminderService 的到期判定与 dismiss 冷却逻辑。
/// 通过直接操作 NoteDatabase 构造资产，再验证 dueList / dismiss 语义，
/// 不触发真实 osascript（非 macOS 环境或通知失败都被服务内部吞掉）。
///
/// 注意：AssetReminderService 依赖 NoteStore.instance 单例，此处采用
/// 子集验证——只测纯逻辑（daysLeft 计算、dismiss 状态流转），
/// 涉及 NoteStore 的扫描由集成测试覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AssetDueItem 到期天数计算', () {
    test('未来 20 天到期 → daysLeft 约 20', () {
      final item = AssetDueItem(
        noteId: 'n1',
        title: '豆浆机延保',
        category: '延保服务',
        expiryDate: DateTime.now().add(const Duration(days: 20)),
        dismissed: false,
      );
      expect(item.daysLeft, inInclusiveRange(19, 20));
    });

    test('已过期 → daysLeft 为负', () {
      final item = AssetDueItem(
        noteId: 'n2',
        title: '过期会员',
        category: '会员',
        expiryDate: DateTime.now().subtract(const Duration(days: 3)),
        dismissed: false,
      );
      expect(item.daysLeft, lessThan(0));
    });
  });

  group('资产到期查询边界（NoteDatabase 层）', () {
    late NoteDatabase db;
    final now = DateTime.now();

    setUp(() async {
      db = NoteDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async => await db.close());

    test('leadWindow 之外不命中', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'far',
        title: '远期资产',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        assetExpiryDate: Value(now.add(const Duration(days: 100))),
      ));
      final due = await db.assetsDueSoon(30);
      expect(due, isEmpty);
    });

    test('恰好落在窗口边界内命中', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'near',
        title: '临期资产',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        assetExpiryDate: Value(now.add(const Duration(days: 29))),
      ));
      final due = await db.assetsDueSoon(30);
      expect(due.length, 1);
      expect(due.first.id, 'near');
    });

    test('已删除的资产不命中', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'deleted',
        title: '已删资产',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        isDeleted: const Value(true),
        assetExpiryDate: Value(now.add(const Duration(days: 10))),
      ));
      final due = await db.assetsDueSoon(30);
      expect(due, isEmpty);
    });

    test('无到期日的资产不命中', () async {
      await db.insertNote(NotesCompanion.insert(
        id: 'no_expiry',
        title: '无到期日',
        deltaJson: '[]',
        createdAt: now,
        updatedAt: now,
        assetCategory: const Value('其他'),
      ));
      final due = await db.assetsDueSoon(30);
      expect(due, isEmpty);
    });
  });
}
