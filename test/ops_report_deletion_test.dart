import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:V8WorkToolbox/tools/ops_tool/database/ops_database.dart';
import 'package:V8WorkToolbox/tools/ops_tool/models/ops_models.dart';
import 'package:V8WorkToolbox/tools/ops_tool/ui/ops_report_editor_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDatabase fakeDb;

  setUp(() async {
    await OpsDatabase.instance.resetForTesting();
    fakeDb = _FakeDatabase();
    OpsDatabase.instance.debugOpenOverride = () async => fakeDb;
  });

  tearDown(() async {
    await OpsDatabase.instance.closeForTesting();
  });

  group('Report 模型与持久化单元测试', () {
    test('toMap 包含 sections_json 且序列化正确', () {
      final report = Report(
        id: 'rep-001',
        title: '周运维报告',
        date: '2026-09-23',
        htmlContent: '<p>HTML内容</p>',
        sections: [
          const ReportSection(
            sectionType: 'sales_overview',
            title: '销售总览',
            content: '本周营收正常',
            order: 1,
          ),
          const ReportSection(
            sectionType: 'custom',
            title: '日常运维',
            content: '服务全部在线',
            order: 2,
          ),
        ],
      );

      final map = report.toMap();
      expect(map['id'], 'rep-001');
      expect(map['title'], '周运维报告');
      expect(map['sections_json'], isNotNull);

      final decoded = jsonDecode(map['sections_json'] as String) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['title'], '销售总览');
      expect(decoded[0]['content'], '本周营收正常');
      expect(decoded[1]['title'], '日常运维');
    });

    test('fromMap 能够正确反序列化 sections_json', () {
      final map = {
        'id': 'rep-002',
        'title': '自动生成报告',
        'date': '2026-09-23',
        'html_content': '<div>测试</div>',
        'sections_json': jsonEncode([
          {
            'section_type': 'custom',
            'title': '分段标题',
            'content': '分段正文 Markdown',
            'order': 1,
          }
        ]),
        'created_at': '2026-09-23T10:00:00Z',
        'updated_at': '2026-09-23T10:00:00Z',
      };

      final report = Report.fromMap(map);
      expect(report.id, 'rep-002');
      expect(report.title, '自动生成报告');
      expect(report.sections.length, 1);
      expect(report.sections.first.title, '分段标题');
      expect(report.sections.first.content, '分段正文 Markdown');
    });

    test('fromMap 在 sections_json 为 null、空串或损坏时安全回退', () {
      final mapNull = {
        'id': 'rep-003',
        'title': '旧报告',
        'date': '2026-09-23',
        'html_content': '',
      };
      final repNull = Report.fromMap(mapNull);
      expect(repNull.sections, isEmpty);

      final mapBroken = {
        'id': 'rep-004',
        'title': '坏数据',
        'date': '2026-09-23',
        'html_content': '',
        'sections_json': 'invalid-json{{{',
      };
      final repBroken = Report.fromMap(mapBroken);
      expect(repBroken.sections, isEmpty);
    });

    test('OpsDatabase.saveReport 与 loadReport 完整保存并还原 sections', () async {
      final report = Report(
        id: 'rep-db-001',
        title: '持久化测试报告',
        date: '2026-09-23',
        sections: [
          const ReportSection(
            sectionType: 'custom',
            title: '核心数据',
            content: '### 指标汇总\n\n无异常',
            order: 1,
          ),
        ],
      );

      await OpsDatabase.instance.saveReport(report);
      final loaded = await OpsDatabase.instance.loadReport('rep-db-001');
      expect(loaded, isNotNull);
      expect(loaded!.title, '持久化测试报告');
      expect(loaded.sections.length, 1);
      expect(loaded.sections.first.title, '核心数据');
      expect(loaded.sections.first.content, '### 指标汇总\n\n无异常');
    });
  });

  group('报告中心删除交互与选区退避 Widget 测试', () {
    testWidgets('点击删除弹出二次确认弹窗，取消不删除，确认才删除且弹出 SnackBar', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final report = Report(
        id: 'rep-single',
        title: '待删除测试报告',
        date: '2026-09-23',
        sections: [
          const ReportSection(sectionType: 'custom', title: '概览', content: '测试内容', order: 1),
        ],
      );
      await OpsDatabase.instance.saveReport(report);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OpsReportEditorView(
            onSendEmail: (_, __) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('待删除测试报告'), findsWidgets);

      // 点击删除按钮（垃圾桶图标）
      final deleteBtn = find.widgetWithIcon(IconButton, Icons.delete_outline);
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // 验证二次确认弹窗出现
      expect(find.text('删除报告确认'), findsOneWidget);
      expect(find.textContaining('确定要删除报告「待删除测试报告」吗？'), findsOneWidget);

      // 点击取消
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      // 弹窗关闭且报告仍在
      expect(find.text('删除报告确认'), findsNothing);
      expect(await OpsDatabase.instance.loadReport('rep-single'), isNotNull);
      expect(find.text('待删除测试报告'), findsWidgets);

      // 再次点击删除并确认
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 数据库中已删除
      expect(await OpsDatabase.instance.loadReport('rep-single'), isNull);

      // 弹出 SnackBar 反馈
      expect(find.text('报告已删除'), findsOneWidget);

      // 唯一报告删除后，退避到空状态
      expect(find.text('暂无历史报告'), findsOneWidget);
      expect(find.text('请选择或新建一份报告'), findsOneWidget);
    });

    testWidgets('多份报告时删除当前选中报告，自动退避选中剩余第一项', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final r1 = Report(
        id: 'rep-1',
        title: '第一份报告',
        date: '2026-09-23',
        sections: [const ReportSection(sectionType: 'custom', title: 'R1', content: '内容1', order: 1)],
      );
      final r2 = Report(
        id: 'rep-2',
        title: '第二份报告',
        date: '2026-09-22',
        sections: [const ReportSection(sectionType: 'custom', title: 'R2', content: '内容2', order: 1)],
      );
      await OpsDatabase.instance.saveReport(r1);
      await OpsDatabase.instance.saveReport(r2);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OpsReportEditorView(
            onSendEmail: (_, __) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 默认当前选中第一份报告
      expect(find.widgetWithText(TextField, '第一份报告'), findsOneWidget);

      // 点击第一份报告的删除按钮
      final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_outline);
      expect(deleteButtons, findsNWidgets(2));
      await tester.tap(deleteButtons.first);
      await tester.pumpAndSettle();

      // 确认删除
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 确认自动退避选中第二份报告
      expect(find.text('第一份报告'), findsNothing);
      expect(find.widgetWithText(TextField, '第二份报告'), findsOneWidget);
    });

    testWidgets('多份报告时删除非当前选中报告，当前报告与编辑内容保持不变', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final r1 = Report(
        id: 'rep-keep',
        title: '当前在看报告',
        date: '2026-09-23',
        sections: [const ReportSection(sectionType: 'custom', title: '正在写', content: '草稿内容', order: 1)],
      );
      final r2 = Report(
        id: 'rep-to-del',
        title: '待删闲置报告',
        date: '2026-09-22',
      );
      await OpsDatabase.instance.saveReport(r1);
      await OpsDatabase.instance.saveReport(r2);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OpsReportEditorView(
            onSendEmail: (_, __) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 当前正在看 r1，并输入了一些未保存草稿
      await tester.enterText(find.byType(TextField).last, '草稿内容 - 刚刚键入的新文字');
      await tester.pumpAndSettle();

      // 删除列表中第二项（非当前项）
      final deleteButtons = find.widgetWithIcon(IconButton, Icons.delete_outline);
      await tester.tap(deleteButtons.last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      // 验证未选中报告被删，但当前编辑草稿未被冲掉
      expect(find.text('待删闲置报告'), findsNothing);
      expect(find.widgetWithText(TextField, '当前在看报告'), findsOneWidget);
      expect(find.textContaining('刚刚键入的新文字'), findsWidgets);
    });

    testWidgets('Excel 传入初始报告消费后置空，回调 onInitialReportConsumed', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final initialReport = Report(
        id: 'rep-excel',
        title: 'Excel导入报告',
        date: '2026-09-23',
        sections: [const ReportSection(sectionType: 'template', title: 'TPL', content: '模版渲染正文', order: 1)],
      );

      bool consumed = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: OpsReportEditorView(
            initialReport: initialReport,
            onInitialReportConsumed: () => consumed = true,
            onSendEmail: (_, __) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(consumed, isTrue);
      expect(find.widgetWithText(TextField, 'Excel导入报告'), findsOneWidget);
    });
  });
}

// ============================================================================
// Fake Database Implementation for In-Memory SQLite Testing
// ============================================================================

class _FakeDatabase implements sqflite.Database {
  final Map<String, List<Map<String, Object?>>> _tables = {};

  List<Map<String, Object?>> _bucket(String table) =>
      _tables.putIfAbsent(table, () => []);

  @override
  bool get isOpen => true;

  @override
  String get path => ':memory:';

  @override
  Future<void> close() async {}

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) async {
    _bucket(table)
      ..removeWhere((r) => r['id'] == values['id'])
      ..add(Map<String, Object?>.from(values));
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    var rows = _bucket(table);
    if (where != null && whereArgs != null && whereArgs.isNotEmpty) {
      final col = where.split('=').first.trim();
      final val = whereArgs.first;
      rows = rows.where((r) => r[col] == val).toList();
    }
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async {
    final bucket = _bucket(table);
    if (where == null) {
      final n = bucket.length;
      bucket.clear();
      return n;
    }
    final col = where.split('=').first.trim();
    final val = whereArgs?.first;
    bucket.removeWhere((r) => r[col] == val);
    return 1;
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final bucket = _bucket(table);
    final col = where?.split('=').first.trim();
    final val = whereArgs?.first;
    for (final r in bucket) {
      if (col == null || r[col] == val) {
        r.addAll(values);
      }
    }
    return 1;
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const [];

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => 1;

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction txn) action, {
    bool? exclusive,
  }) async => throw UnimplementedError();

  @override
  Future<T> readTransaction<T>(
    Future<T> Function(sqflite.Transaction txn) action,
  ) async => throw UnimplementedError();

  @override
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      throw UnimplementedError();

  @override
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) => throw UnimplementedError();

  @override
  sqflite.Batch batch() => throw UnimplementedError();

  @override
  Future<sqflite.QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => throw UnimplementedError();

  @override
  Future<sqflite.QueryCursor> queryCursor(
    String? table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => throw UnimplementedError();

  @override
  sqflite.Database get database => this;
}
