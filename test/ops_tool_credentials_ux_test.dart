import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:V8WorkToolbox/theme/app_theme.dart';
import 'package:V8WorkToolbox/tools/ops_tool/database/ops_database.dart';
import 'package:V8WorkToolbox/tools/ops_tool/models/ops_models.dart';
import 'package:V8WorkToolbox/tools/ops_tool/ui/ops_devops_view.dart';
import 'package:V8WorkToolbox/tools/ops_tool/ui/ops_email_view.dart';

/// 凭据 UX 三组要求的可测面（specs: 凭据字段默认脱敏且支持临时显示明文 /
/// 编辑既有凭据时留空表示保持原值 / ArgoCD 监控环境的管理入口可发现且破坏性操作需确认）。
///
/// `OpsDatabase` 是单例且内部用全局 `openDatabase`（走 sqflite 的平台通道），
/// 测试环境没有 method channel 实现。这里经 `debugOpenOverride` 注入一个
/// 纯 Dart 的内存 `Database` 替身（`_FakeDatabase`），使 DAO 的真实 SQL
/// 语句与返回映射都能被驱动，而不依赖平台通道。
///
/// 两处实现约束，改动时需同步（否则用例会挂起或失配）：
/// 1. `setUp` 必须先 `resetForTesting()` 再设 `debugOpenOverride` ——
///    `resetForTesting` 内部会把 override 清空。
/// 2. ArgoCD 监控 Tab 有 750ms 闪烁 Timer（spec 的不一致行高亮），
///    不能用 `pumpAndSettle`，改为 pump 轮询到目标 widget 出现。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeDatabase fakeDb;

  setUp(() async {
    await OpsDatabase.instance.resetForTesting();
    fakeDb = _FakeDatabase();
    OpsDatabase.instance.debugOpenOverride = () async => fakeDb;
  });

  tearDown(() async {
    // 只关闭连接，不清 debugOpenOverride：前一个用例遗留下来的异步回调
    // 可能在此后才触达数据库，清掉 override 会使其回落到平台通道而抛
    // MissingPluginException。
    await OpsDatabase.instance.closeForTesting();
  });

  group('凭据字段默认脱敏且支持临时显示明文', () {
    testWidgets('ArgoCD 环境弹窗：默认脱敏，点眼睛变明文，重开恢复脱敏', (tester) async {
      await _pumpArgocdTab(tester);

      await tester.tap(find.text('新建环境'));
      await tester.pumpAndSettle();

      expect(_argocdObscureCount(tester), 2, reason: '密码与 Token 默认必须脱敏');

      // 点眼睛 → 明文
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.visibility_off).first,
      );
      await tester.pumpAndSettle();
      expect(_argocdObscureCount(tester), 1, reason: '点击显示按钮后该字段应切换为明文');

      // 关掉弹窗重开 → 恢复脱敏（明文态不得跨会话保留）
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建环境'));
      await tester.pumpAndSettle();
      expect(_argocdObscureCount(tester), 2, reason: '重新打开弹窗后明文态必须复位为脱敏');
    });

    testWidgets('邮件账户弹窗：默认脱敏，点眼睛变明文，重开恢复脱敏', (tester) async {
      await tester.pumpWidget(_host(const OpsEmailView()));
      await _settleEmailView(tester);

      await tester.tap(find.byTooltip('添加账户'));
      await tester.pump();
      await _settleEmailDialog(tester);

      expect(_emailPassObscure(tester), isTrue);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.visibility_off).first,
      );
      await tester.pump();
      expect(_emailPassObscure(tester), isFalse);

      await tester.tap(find.text('取消'));
      await tester.pump();
      await _settleEmailView(tester);
      await tester.tap(find.byTooltip('添加账户'));
      await tester.pump();
      await _settleEmailDialog(tester);
      expect(_emailPassObscure(tester), isTrue);
    });
  });

  group('编辑既有凭据时留空表示保持原值', () {
    testWidgets('编辑已存环境：密码框为空且带提示，留空保存不覆盖库中凭据', (tester) async {
      await OpsDatabase.instance.saveArgoCdEnv(
        ArgoCDEnvironment(
          id: 'env-keep',
          name: 'SIT',
          gitlabUrl: 'https://gitlab.example.internal/repository/config',
          gitlabUsername: 'liuzhongren',
          gitlabPassword: 'original-secret',
          gitlabToken: 'original-token',
          projectsPath: '/tree/master/argocd/projects',
          enabled: true,
        ),
      );

      await _pumpArgocdTab(tester);

      // 通过详情卡的「编辑环境」入口打开（spec: 编辑入口可发现）
      await tester.tap(find.text('编辑环境'));
      await tester.pump();

      expect(_credentialCount(tester), 2, reason: '环境弹窗应含密码与 Token 两个脱敏字段');
      final credTexts = _credentialTexts(tester);
      expect(credTexts.first, isEmpty, reason: '编辑态 MUST NOT 回填已存密码');
      expect(credTexts.last, isEmpty, reason: '编辑态 MUST NOT 回填已存 Token');
      expect(find.text('留空则保持原有凭据不变'), findsWidgets);

      // 只改名称，凭据留空
      await tester.enterText(
        find.widgetWithText(TextField, 'SIT'),
        'SIT-renamed',
      );
      await tester.tap(find.text('保存'));
      await tester.pump();

      final saved = await OpsDatabase.instance.loadArgoCdEnvs();
      final env = saved.firstWhere((e) => e.id == 'env-keep');
      expect(env.name, 'SIT-renamed');
      expect(
        env.gitlabPassword,
        'original-secret',
        reason: '留空保存 MUST NOT 覆盖既有密码',
      );
      expect(
        env.gitlabToken,
        'original-token',
        reason: '留空保存 MUST NOT 覆盖既有 Token',
      );
    });
  });

  group('ArgoCD 监控环境的管理入口可发现且破坏性操作需确认', () {
    testWidgets('凭据全空的环境保存被拒绝', (tester) async {
      await OpsDatabase.instance.saveArgoCdEnv(
        ArgoCDEnvironment(
          id: 'env-weak',
          name: '缺凭据',
          gitlabUrl: 'https://gitlab.example.internal/repository/config',
          projectsPath: '/tree/master/argocd/projects',
          enabled: false,
        ),
      );

      await _pumpArgocdTab(tester);

      // 选中环境 → 打开编辑 → 直接保存（两个凭据框均为空）
      await tester.tap(find.text('缺凭据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑环境'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(
        find.textContaining('请填写 GitLab 密码或 Personal Access Token'),
        findsOneWidget,
        reason: '缺少可用凭据时 MUST 拒绝保存',
      );

      // 该环境仍保持未启用（不得进入巡检集合）
      final envs = await OpsDatabase.instance.loadEnabledArgoCdEnvs();
      expect(envs.where((e) => e.id == 'env-weak'), isEmpty);
    });

    testWidgets('删除环境前要求确认，取消则不删除', (tester) async {
      await OpsDatabase.instance.saveArgoCdEnv(
        ArgoCDEnvironment(
          id: 'env-del',
          name: '待删除',
          gitlabUrl: 'https://gitlab.example.internal/repository/config',
          gitlabPassword: 'pw',
          projectsPath: '/tree/master/argocd/projects',
          enabled: true,
        ),
      );
      await OpsDatabase.instance.updateArgoCdTag(
        ArgoCDTag(
          id: 'env-del_dc-order',
          envId: 'env-del',
          projectName: 'dc-order',
          currentTag: 'v1.0.0',
          targetTag: 'v1.0.0',
        ),
      );

      await _pumpArgocdTab(tester);

      await tester.tap(find.byTooltip('删除环境'));
      await tester.pump();

      expect(
        find.textContaining('将同时清除其名下全部 Tag 配置行'),
        findsOneWidget,
        reason: '确认对话框 MUST 明示级联影响',
      );

      await tester.tap(find.text('取消'));
      await tester.pump();

      final envs = await OpsDatabase.instance.loadArgoCdEnvs();
      final tags = await OpsDatabase.instance.loadArgoCdTags('env-del');
      expect(
        envs.where((e) => e.id == 'env-del'),
        isNotEmpty,
        reason: '取消删除后环境必须保留',
      );
      expect(tags, hasLength(1), reason: '取消删除后级联 Tag 必须保留');
    });
  });
}

/// 用真实 `OpsArgoCdMonitorTab` 承载被测弹窗；窗口宽度放宽以容纳详情卡按钮。
Future<void> _pumpArgocdTab(WidgetTester tester) async {
  tester.view.physicalSize = const Size(2400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(const OpsArgoCdMonitorTab()));
  // 注意：不能用 pumpAndSettle —— _ArgoCdMonitorTab 有 750ms 的闪烁 Timer
  // （spec 要求的不一致行高亮），持续动画会让 pumpAndSettle 永久超时。
  // 改为轮询到环境标签渲染完成（_loadEnvs 是异步的）。
  await tester.pump();
  for (var i = 0; i < 50; i++) {
    if (find.text('编辑环境').evaluate().isNotEmpty) break;
    await tester.pump(const Duration(milliseconds: 20));
  }
  // 用例结束时卸载，触发 dispose 取消 750ms 闪烁 Timer；
  // 否则该 Timer 跨用例存活并最终使 test isolate 崩溃（SIGTERM）。
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// 重新定位「当前渲染中」第一个与眼睛按钮同属一个 InputDecoration 的 TextField，
/// 避免 Finder 缓存指向 setDialogState 之前的旧 widget。
/// 读 ArgoCD 环境弹窗内密码框（第 4 个 TextField：名称/URL/用户名/密码）的 `obscureText`。
/// 不用 `find.ancestor(of: find.byIcon(...))`：切换后图标从 `visibility_off` 变为
/// `visibility`，该 Finder 会立刻失配。
/// 轮询到账户弹窗内的凭据字段就绪（含 StatefulBuilder 首帧）。
Future<void> _settleEmailDialog(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    if (find
        .widgetWithIcon(IconButton, Icons.visibility_off)
        .evaluate()
        .isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// `OpsEmailView` 首帧渲染 `CircularProgressIndicator`（`_loading` 为真），
/// `pumpAndSettle` 会在此类持续动画上超时；改为轮询到账户面板就绪。
Future<void> _settleEmailView(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    if (find.byTooltip('添加账户').evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// 环境弹窗内脱敏字段的数量：密码 + Token 默认共 2 个；
/// 点开任一个的眼睛后该字段转为明文，数量减一。
int _argocdObscureCount(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .where((f) => f.obscureText)
    .length;

/// 读邮件账户弹窗内授权码框（第 4 个 TextField：名称/服务器/端口/用户名/授权码
/// 中的第 5 个，因端口与服务器同行）。
bool _emailPassObscure(WidgetTester tester) {
  final obscure = tester
      .widgetList<TextField>(find.byType(TextField))
      .where((f) => f.obscureText)
      .toList();
  return obscure.length == 1 && obscure.single.obscureText;
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(body: child),
);

/// 弹窗内所有脱敏字段的 controller 文本（即时快照）。
/// 不返回 Finder：`find.byWidget` 指向具体实例，弹窗任一重绘后即失配。
List<String> _credentialTexts(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .where((f) => f.obscureText)
    .map((f) => (f.controller as TextEditingController).text)
    .toList();

int _credentialCount(WidgetTester tester) => tester
    .widgetList<TextField>(find.byType(TextField))
    .where((f) => f.obscureText)
    .length;

/// 内存 `Database` 替身：按表名分桶存放 Map 行。
/// 覆盖被测行为实际触达的方法（insert(replace) / query / delete / update /
/// rawQuery / transaction），其余方法保持最小可编译实现。
class _FakeDatabase implements sqflite.Database {
  final Map<String, List<Map<String, Object?>>> _tables = {};

  List<Map<String, Object?>> _bucket(String table) =>
      _tables.putIfAbsent(table, () => <Map<String, Object?>>[]);

  @override
  String get path => ':memory:';

  @override
  bool get isOpen => true;

  @override
  Future<void> close() async {}

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => 1;

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
  ]) async {
    return const [];
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(sqflite.Transaction txn) action, {
    bool? exclusive,
  }) async {
    return action(_FakeTransaction(this));
  }

  @override
  Future<T> readTransaction<T>(
    Future<T> Function(sqflite.Transaction txn) action,
  ) => transaction(action);

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
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

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

class _FakeTransaction extends sqflite.Transaction {
  final _FakeDatabase _db;
  _FakeTransaction(this._db);

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) => _db.insert(table, values, conflictAlgorithm: conflictAlgorithm);

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
  }) => _db.query(
    table,
    where: where,
    whereArgs: whereArgs,
    orderBy: orderBy,
    limit: limit,
  );

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _db.delete(table, where: where, whereArgs: whereArgs);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    sqflite.ConflictAlgorithm? conflictAlgorithm,
  }) => _db.update(table, values, where: where, whereArgs: whereArgs);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) async => 1;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const [];

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

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
  sqflite.Batch batch() => throw UnimplementedError();

  @override
  sqflite.Database get database => _db;
}
