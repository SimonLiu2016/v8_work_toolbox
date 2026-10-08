/// 渗透会话持久化（drift，独立库文件 `<AppPaths.root>/security/security.db`）。
///
/// 不并进 note.db：一个会话的 Finding 就可能有上千条，安全库的体积增长曲线与
/// 笔记库完全不同，分开后导出、备份、手工排查都互不影响。
///
/// 表只增不改——后续加列走 schemaVersion +1 的迁移，不动既有列。
/// 主键一律 TEXT UUID：与 notebook / ops 表风格一致，便于跨表引用与手工排查。
library;

import 'package:drift/drift.dart';
import 'package:drift_sqflite/drift_sqflite.dart';

import '../../../services/app_paths.dart';
import 'package:path/path.dart' as p;

part 'security_database.g.dart';

/// 一次渗透测试会话。
class PentestSessions extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get type => text().withDefault(const Constant('lan'))();
  TextColumn get scope => text().withDefault(const Constant('[]'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 会话内发现的主机或 URL。
class SessionAssets extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(PentestSessions, #id)();
  TextColumn get type => text().withDefault(const Constant('host'))();
  TextColumn get address => text()();

  /// JSON：os / mac / vendor / ports / techStack / statusCode / title 等。
  TextColumn get metadata => text().withDefault(const Constant('{}'))();

  /// critical / high / medium / low / info / unknown。
  TextColumn get riskLevel => text().withDefault(const Constant('unknown'))();

  /// 用户手工备注；扫描结果合并时不得覆盖（见 spec「资产手动标注」）。
  TextColumn get userNote => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 一条漏洞发现物。
class SessionFindings extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(PentestSessions, #id)();
  TextColumn get assetId =>
      text().nullable().references(SessionAssets, #id, onDelete: KeyAction.setNull)();
  TextColumn get cveId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
  RealColumn get cvssScore => real().nullable()();
  TextColumn get status => text().withDefault(const Constant('open'))();
  TextColumn get evidence => text().nullable()();
  TextColumn get source => text().withDefault(const Constant('manual'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 会话内的一条操作事件。
class SessionTimelineEvents extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(PentestSessions, #id)();
  TextColumn get eventType => text()();
  TextColumn get title => text()();

  /// JSON：command / args / durationMs / aiText 等。
  TextColumn get detail => text().withDefault(const Constant('{}'))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// 威胁情报缓存（NVD / CISA KEV / GitHub PoC 合并结果）。
class ThreatIntelEntries extends Table {
  TextColumn get cveId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  RealColumn get cvssScore => real().nullable()();
  TextColumn get severity => text().withDefault(const Constant('info'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  DateTimeColumn get published => dateTime().nullable()();

  /// 是否在 CISA KEV 目录中（0/1）。
  IntColumn get isKev => integer().withDefault(const Constant(0))();
  TextColumn get pocUrl => text().nullable()();
  DateTimeColumn get syncedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {cveId};
}

/// 报告的历史版本。
class ReportVersionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(PentestSessions, #id)();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get format => text().withDefault(const Constant('technical'))();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    PentestSessions,
    SessionAssets,
    SessionFindings,
    SessionTimelineEvents,
    ThreatIntelEntries,
    ReportVersionsTable,
  ],
)
class SecurityDatabase extends _$SecurityDatabase {
  SecurityDatabase() : super(_openConnection());

  /// 测试用：注入内存/临时连接。
  SecurityDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      // 新建表时 drift 已建好；外键约束要显式开——SQLite 默认忽略它，
      // 不开则 finding.assetId 的 SET NULL 与级联删除全部不生效。
      await customStatement('PRAGMA foreign_keys = ON;');
    },
  );
}

/// 独立库文件路径：`<AppPaths.root>/security/security.db`。
///
/// 不并进 note.db：安全库体积增长快（一个会话的 Finding 就可能有上千条），
/// 与笔记库分开后导出/备份互不影响。
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = AppPaths.securityDir;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return SqfliteQueryExecutor(path: p.join(dir.path, 'security.db'));
  });
}
