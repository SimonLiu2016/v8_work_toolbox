import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Batch, ConflictAlgorithm, Database, QueryCursor, Transaction;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/ops_tool/database/ops_database.dart';

/// 本地数据路径源的单一性回归。
///
/// 这个文件存在的原因是：本项目曾经三套路径解析并存（硬编码 HOME 拼接、平台
/// API、drift 默认目录），应用被授予文件访问授权后其中两套漂移到带 bundle id
/// 的目录，导致运维数据库与笔记附件整体失联。上面那组断言让「某模块又开始
/// 自己拼路径」这类回退无法悄悄发生。
void main() {
  group('AppPaths 路径源单一性', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('app_paths_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('全部导出文件路径都以 root 为前缀', () {
      for (final file in AppPaths.allFiles) {
        expect(
          file.path.startsWith(tempDir.path),
          isTrue,
          reason: '${file.path} 不在根目录 ${tempDir.path} 之下',
        );
      }
    });

    test('全部导出目录路径都以 root 为前缀', () {
      for (final dir in AppPaths.allDirs) {
        expect(
          dir.path.startsWith(tempDir.path),
          isTrue,
          reason: '${dir.path} 不在根目录 ${tempDir.path} 之下',
        );
      }
    });

    test('未初始化时抛出带说明的 StateError，而不是返回 null 路径', () {
      AppPaths.resetForTesting();
      expect(AppPaths.isInitialized, isFalse);
      expect(
        () => AppPaths.aiConfigFile,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('AppPaths 尚未初始化'),
          ),
        ),
      );
    });

    test('覆写 root 后全部子路径随之改变', () {
      final other = Directory.systemTemp.createTempSync('app_paths_other');
      try {
        final before = AppPaths.aiConfigFile.path;
        AppPaths.overrideRootForTesting(other);
        final after = AppPaths.aiConfigFile.path;
        expect(after, isNot(before));
        expect(after.startsWith(other.path), isTrue);
        // 运维工具库与 AI 配置同根（integrate-fs-ops-tool 的设计承诺）
        expect(AppPaths.opsToolDbFile.parent.parent.path, AppPaths.root.path);
      } finally {
        other.deleteSync(recursive: true);
      }
    });

    test('运维工具库与 AI 配置位于同一根目录', () {
      expect(
        AppPaths.opsToolDir.parent.path,
        AppPaths.root.path,
        reason: 'ops_tool 必须与 ai_config.json 同目录',
      );
    });

    test('笔记主库与笔记附件同根', () {
      expect(AppPaths.noteDbFile.parent.path, AppPaths.root.path);
      expect(AppPaths.attachmentsDir.parent.path, AppPaths.root.path);
    });

    test('OpsDatabase 落盘位置随 root 改变', () async {
      // 经 debugOverrideDir 注入临时目录后，其数据库文件必须落在该目录下。
      // 测试环境没有 sqflite 平台通道，用 debugOpenOverride 注入内存替身。
      final dbDir = Directory(p.join(tempDir.path, 'ops_tool_injected'));
      OpsDatabase.instance.debugOpenOverride = () async => _InMemoryDb();
      OpsDatabase.instance.resetForTesting(dir: dbDir);
      final db = await OpsDatabase.instance.database;
      expect(db.path, ':memory:');
      await OpsDatabase.instance.resetForTesting();
    });
  });
}

/// 最小 `Database` 替身：只为让 `OpsDatabase._initDatabase` 的注入分支跑通，
/// 不执行任何真实 SQL。
class _InMemoryDb implements Database {
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
    ConflictAlgorithm? conflictAlgorithm,
  }) async => 1;

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
  }) async => const [];

  @override
  Future<int> delete(
    String table, {
    String? where,
    List<Object?>? whereArgs,
  }) async => 0;

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async => 0;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async => const [];

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => throw UnimplementedError();

  @override
  Future<T> readTransaction<T>(
    Future<T> Function(Transaction txn) action,
  ) => throw UnimplementedError();

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
  Batch batch() => throw UnimplementedError();

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) async => 0;

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => throw UnimplementedError();

  @override
  Future<QueryCursor> queryCursor(
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
  Database get database => this;
}
