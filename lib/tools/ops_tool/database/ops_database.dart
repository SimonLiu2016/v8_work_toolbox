import 'dart:io';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import '../../../services/app_paths.dart';
import 'package:sqflite/sqflite.dart';
import '../models/ops_models.dart';

class OpsDatabase {
  OpsDatabase._();
  static final OpsDatabase instance = OpsDatabase._();

  Database? _db;

  /// 仅供测试：指定数据库文件所在目录。为 null 时走应用支持目录（生产路径）。
  @visibleForTesting
  Directory? debugOverrideDir;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  /// 仅供测试：把单例重置为「未打开」状态，使下一次访问按 `debugOverrideDir` 重新打开。
  @visibleForTesting
  Future<void> resetForTesting({Directory? dir}) async {
    await closeForTesting();
    debugOverrideDir = dir;
    debugOpenOverride = null;
  }

  /// 仅供测试：关闭当前连接但保留测试钩子，避免前一个用例的异步回调在
  /// tearDown 之后触达数据库时回落到平台通道。
  @visibleForTesting
  Future<void> closeForTesting() async {
    await _db?.close();
    _db = null;
  }

  /// 仅供测试：直接注入已打开的 `Database`（测试环境没有 sqflite 平台通道实现）。
  @visibleForTesting
  Future<Database> Function()? debugOpenOverride;

  Future<Database> _initDatabase() async {
    // 测试注入必须最早返回：path_provider 在无平台通道的环境（单测）会直接抛
    // MissingPluginException，任何排在前面的解析都会让注入失效。
    final injected = debugOpenOverride;
    if (injected != null) return await injected();

    final overrideDir = debugOverrideDir;
    final opsDir = overrideDir ?? AppPaths.opsToolDir;
    if (!await opsDir.exists()) {
      await opsDir.create(recursive: true);
    }
    final dbPath = p.join(opsDir.path, 'ops_tool.db');

    return await openDatabase(
      dbPath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        await _migrateReportsSections(db);
      },
    );
  }

  Future<void> _migrateReportsSections(Database db) async {
    try {
      final info = await db.rawQuery('PRAGMA table_info(reports)');
      final hasColumn = info.any((col) => col['name'] == 'sections_json');
      if (!hasColumn) {
        await db.execute('ALTER TABLE reports ADD COLUMN sections_json TEXT');
      }
    } catch (_) {
      // 容错：在不支持 PRAGMA 的测试内存桩中平滑跳过
    }
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS configs (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS reports (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        date TEXT NOT NULL,
        html_content TEXT NOT NULL,
        sections_json TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_templates (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        content TEXT NOT NULL,
        rules TEXT NOT NULL DEFAULT '[]',
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_accounts (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        smtp_host TEXT NOT NULL,
        smtp_port INTEGER NOT NULL,
        username TEXT NOT NULL,
        password_encrypted TEXT NOT NULL,
        use_tls INTEGER NOT NULL DEFAULT 1,
        created_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS email_recipients (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        name TEXT NOT NULL,
        email TEXT NOT NULL,
        group_name TEXT DEFAULT 'default',
        FOREIGN KEY (account_id) REFERENCES email_accounts(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS task_logs (
        id TEXT PRIMARY KEY,
        task_type TEXT NOT NULL,
        status TEXT NOT NULL,
        message TEXT,
        started_at TEXT DEFAULT (datetime('now')),
        finished_at TEXT
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS data_sources (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        source_type TEXT NOT NULL,
        config TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sql_queries (
        id TEXT PRIMARY KEY,
        data_source_id TEXT NOT NULL,
        name TEXT NOT NULL,
        sql_text TEXT NOT NULL,
        description TEXT,
        FOREIGN KEY (data_source_id) REFERENCES data_sources(id) ON DELETE CASCADE
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduled_tasks (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        task_type TEXT NOT NULL,
        config TEXT NOT NULL,
        cron_expr TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_run TEXT,
        next_run TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS devops_connections (
        id TEXT PRIMARY KEY,
        conn_type TEXT NOT NULL,
        name TEXT NOT NULL,
        config TEXT NOT NULL,
        created_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS devops_selected_projects (
        id TEXT PRIMARY KEY,
        project_name TEXT NOT NULL,
        project_id INTEGER,
        group_name TEXT NOT NULL,
        gitlab_url TEXT NOT NULL,
        selected_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS argocd_environments (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        gitlab_url TEXT NOT NULL,
        gitlab_username TEXT,
        gitlab_password TEXT,
        gitlab_token TEXT,
        projects_path TEXT NOT NULL,
        monitor_mode TEXT DEFAULT 'monitor',
        enabled INTEGER DEFAULT 0,
        cron_expr TEXT DEFAULT '300',
        created_at TEXT DEFAULT (datetime('now'))
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS argocd_tags (
        id TEXT PRIMARY KEY,
        env_id TEXT NOT NULL,
        project_name TEXT NOT NULL,
        current_tag TEXT,
        target_tag TEXT,
        muted INTEGER DEFAULT 0,
        enabled INTEGER DEFAULT 1,
        last_checked TEXT,
        FOREIGN KEY (env_id) REFERENCES argocd_environments(id) ON DELETE CASCADE
      );
    ''');
  }

  // ==========================================================================
  // DevOps Connection CRUD
  // ==========================================================================
  Future<List<DevOpsConnection>> loadConnections({String? connType}) async {
    final db = await database;
    final List<Map<String, dynamic>> rows = connType != null
        ? await db.query('devops_connections', where: 'conn_type = ?', whereArgs: [connType])
        : await db.query('devops_connections', orderBy: 'created_at DESC');
    return rows.map((r) => DevOpsConnection.fromMap(r)).toList();
  }

  Future<void> saveConnection(DevOpsConnection conn) async {
    final db = await database;
    await db.insert('devops_connections', conn.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteConnection(String id) async {
    final db = await database;
    await db.delete('devops_connections', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================================================
  // DevOps Selected Projects
  // ==========================================================================
  Future<List<DevOpsSelectedProject>> loadSelectedProjects() async {
    final db = await database;
    final rows = await db.query('devops_selected_projects', orderBy: 'project_name ASC');
    return rows.map((r) => DevOpsSelectedProject.fromMap(r)).toList();
  }

  Future<void> saveSelectedProjects(List<DevOpsSelectedProject> projects) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('devops_selected_projects');
      for (final p in projects) {
        await txn.insert('devops_selected_projects', p.toMap());
      }
    });
  }

  // ==========================================================================
  // ArgoCD Environments & Tags
  // ==========================================================================
  Future<List<ArgoCDEnvironment>> loadArgoCdEnvs() async {
    final db = await database;
    final rows = await db.query('argocd_environments', orderBy: 'created_at DESC');
    return rows.map((r) => ArgoCDEnvironment.fromMap(r)).toList();
  }

  /// 加载启用的 ArgoCD 监控环境（后台巡检仅针对这些环境）。
  Future<List<ArgoCDEnvironment>> loadEnabledArgoCdEnvs() async {
    final db = await database;
    final rows = await db.query('argocd_environments', where: 'enabled = ?', whereArgs: [1]);
    return rows.map((r) => ArgoCDEnvironment.fromMap(r)).toList();
  }

  /// 启用环境中的最小检查间隔（秒）。无启用环境或取值非法时回退默认值。
  Future<int> getMinArgoCdInterval({int fallback = 300}) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT MIN(CAST(cron_expr AS INTEGER)) AS m FROM argocd_environments WHERE enabled = 1');
    if (rows.isEmpty) return fallback;
    final value = (rows.first['m'] as int?) ?? fallback;
    return value > 0 ? value : fallback;
  }


  Future<void> saveArgoCdEnv(ArgoCDEnvironment env) async {
    final db = await database;
    await db.insert('argocd_environments', env.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteArgoCdEnv(String id) async {
    final db = await database;
    await db.delete('argocd_environments', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ArgoCDTag>> loadArgoCdTags(String envId) async {
    final db = await database;
    final rows = await db.query('argocd_tags', where: 'env_id = ?', whereArgs: [envId]);
    return rows.map((r) => ArgoCDTag.fromMap(r)).toList();
  }

  Future<void> saveArgoCdTags(String envId, List<ArgoCDTag> tags) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('argocd_tags', where: 'env_id = ?', whereArgs: [envId]);
      for (final tag in tags) {
        await txn.insert('argocd_tags', tag.toMap());
      }
    });
  }

  Future<void> updateArgoCdTag(ArgoCDTag tag) async {
    final db = await database;
    await db.insert('argocd_tags', tag.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==========================================================================
  // Data Sources & SQL Queries
  // ==========================================================================
  Future<List<DataSource>> loadDataSources() async {
    final db = await database;
    final rows = await db.query('data_sources', orderBy: 'created_at DESC');
    return rows.map((r) => DataSource.fromMap(r)).toList();
  }

  Future<void> saveDataSource(DataSource ds) async {
    final db = await database;
    await db.insert('data_sources', ds.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteDataSource(String id) async {
    final db = await database;
    await db.delete('data_sources', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<SqlQuery>> loadSqlQueries(String dataSourceId) async {
    final db = await database;
    final rows = await db.query('sql_queries',
        where: 'data_source_id = ?', whereArgs: [dataSourceId]);
    return rows.map((r) => SqlQuery.fromMap(r)).toList();
  }

  Future<void> saveSqlQuery(SqlQuery q) async {
    final db = await database;
    await db.insert('sql_queries', q.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteSqlQuery(String id) async {
    final db = await database;
    await db.delete('sql_queries', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================================================
  // Reports & Report Templates
  // ==========================================================================
  Future<List<ReportTemplate>> loadReportTemplates() async {
    final db = await database;
    final rows = await db.query('report_templates', orderBy: 'updated_at DESC');
    return rows.map((r) => ReportTemplate.fromMap(r)).toList();
  }

  Future<void> saveReportTemplate(ReportTemplate t) async {
    final db = await database;
    await db.insert('report_templates', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteReportTemplate(String id) async {
    final db = await database;
    await db.delete('report_templates', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Report>> listReports({int limit = 50, int offset = 0}) async {
    final db = await database;
    final rows = await db.query('reports',
        orderBy: 'date DESC, created_at DESC', limit: limit, offset: offset);
    return rows.map((r) => Report.fromMap(r)).toList();
  }

  Future<int> countReports() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM reports');
    return Sqflite.firstIntValue(res) ?? 0;
  }

  Future<Report?> loadReport(String id) async {
    final db = await database;
    final rows = await db.query('reports', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Report.fromMap(rows.first);
  }

  Future<void> saveReport(Report report) async {
    final db = await database;
    await db.insert('reports', report.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteReport(String id) async {
    final db = await database;
    await db.delete('reports', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================================================
  // Email Accounts & Recipients
  // ==========================================================================
  Future<List<EmailAccount>> loadEmailAccounts() async {
    final db = await database;
    final rows = await db.query('email_accounts', orderBy: 'created_at DESC');
    return rows.map((r) => EmailAccount.fromMap(r)).toList();
  }

  Future<void> saveEmailAccount(EmailAccount acc) async {
    final db = await database;
    await db.insert('email_accounts', acc.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteEmailAccount(String id) async {
    final db = await database;
    await db.delete('email_accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<EmailRecipient>> loadEmailRecipients(String accountId) async {
    final db = await database;
    final rows = await db.query('email_recipients',
        where: 'account_id = ?', whereArgs: [accountId]);
    return rows.map((r) => EmailRecipient.fromMap(r)).toList();
  }

  Future<void> saveEmailRecipient(EmailRecipient r) async {
    final db = await database;
    await db.insert('email_recipients', r.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteEmailRecipient(String id) async {
    final db = await database;
    await db.delete('email_recipients', where: 'id = ?', whereArgs: [id]);
  }

  // ==========================================================================
  // Scheduled Tasks & Task Logs
  // ==========================================================================
  Future<List<ScheduledTask>> loadScheduledTasks() async {
    final db = await database;
    final rows = await db.query('scheduled_tasks', orderBy: 'created_at DESC');
    return rows.map((r) => ScheduledTask.fromMap(r)).toList();
  }

  Future<void> saveScheduledTask(ScheduledTask task) async {
    final db = await database;
    await db.insert('scheduled_tasks', task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteScheduledTask(String id) async {
    final db = await database;
    await db.delete('scheduled_tasks', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> toggleScheduledTask(String id, bool enabled) async {
    final db = await database;
    await db.update('scheduled_tasks', {'enabled': enabled ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TaskLog>> loadTaskLogs({int limit = 50}) async {
    final db = await database;
    final rows = await db.query('task_logs',
        orderBy: 'started_at DESC', limit: limit);
    return rows.map((r) => TaskLog.fromMap(r)).toList();
  }

  Future<void> addTaskLog(TaskLog log) async {
    final db = await database;
    await db.insert('task_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==========================================================================
  // Dashboard Stats
  // ==========================================================================
  Future<Map<String, dynamic>> getDashboardStats() async {
    final db = await database;

    final reportCnt = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM reports')) ??
        0;
    final dsCnt = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM data_sources')) ??
        0;
    final taskCnt = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM scheduled_tasks')) ??
        0;
    final enabledTaskCnt = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM scheduled_tasks WHERE enabled = 1')) ??
        0;
    final successTaskCnt = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM task_logs WHERE status = "success"')) ??
        0;
    final failTaskCnt = Sqflite.firstIntValue(await db.rawQuery(
            'SELECT COUNT(*) FROM task_logs WHERE status = "failed"')) ??
        0;

    final recentReports = await db.query(
      'reports',
      columns: ['id', 'title', 'date'],
      orderBy: 'date DESC, created_at DESC',
      limit: 5,
    );

    return {
      'report_count': reportCnt,
      'data_source_count': dsCnt,
      'task_count': taskCnt,
      'enabled_task_count': enabledTaskCnt,
      'task_success_count': successTaskCnt,
      'task_fail_count': failTaskCnt,
      'recent_reports': recentReports,
    };
  }
}
