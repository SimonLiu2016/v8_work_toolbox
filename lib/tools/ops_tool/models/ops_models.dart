import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ============================================================================
// DevOps Models
// ============================================================================

class DevOpsConnection {
  final String id;
  final String connType; // 'gitlab' | 'jenkins' | 'argocd'
  final String name;
  final String config;
  final String createdAt;

  DevOpsConnection({
    String? id,
    required this.connType,
    required this.name,
    required this.config,
    String? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> getConfigMap() {
    try {
      return jsonDecode(config) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'conn_type': connType,
        'name': name,
        'config': config,
        'created_at': createdAt,
      };

  factory DevOpsConnection.fromMap(Map<String, dynamic> map) => DevOpsConnection(
        id: map['id'] as String,
        connType: map['conn_type'] as String,
        name: map['name'] as String,
        config: map['config'] as String,
        createdAt: map['created_at'] as String?,
      );
}

class ProjectInfo {
  final int id;
  final String name;
  final String path;
  final String pathWithNamespace;
  final String defaultBranch;
  final String webUrl;

  const ProjectInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.pathWithNamespace,
    required this.defaultBranch,
    required this.webUrl,
  });

  factory ProjectInfo.fromJson(Map<String, dynamic> json) => ProjectInfo(
        id: json['id'] as int? ?? 0,
        name: json['name'] as String? ?? '',
        path: json['path'] as String? ?? '',
        pathWithNamespace: json['path_with_namespace'] as String? ?? '',
        defaultBranch: json['default_branch'] as String? ?? 'master',
        webUrl: json['web_url'] as String? ?? '',
      );
}

class DevOpsSelectedProject {
  final String id;
  final String projectName;
  final int? projectId;
  final String groupName;
  final String gitlabUrl;
  final String selectedAt;

  DevOpsSelectedProject({
    String? id,
    required this.projectName,
    this.projectId,
    required this.groupName,
    required this.gitlabUrl,
    String? selectedAt,
  })  : id = id ?? _uuid.v4(),
        selectedAt = selectedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'project_name': projectName,
        'project_id': projectId,
        'group_name': groupName,
        'gitlab_url': gitlabUrl,
        'selected_at': selectedAt,
      };

  factory DevOpsSelectedProject.fromMap(Map<String, dynamic> map) => DevOpsSelectedProject(
        id: map['id'] as String,
        projectName: map['project_name'] as String,
        projectId: map['project_id'] as int?,
        groupName: map['group_name'] as String,
        gitlabUrl: map['gitlab_url'] as String,
        selectedAt: map['selected_at'] as String?,
      );
}

class ArgoCDEnvironment {
  final String id;
  final String name;
  final String gitlabUrl;
  final String? gitlabUsername;
  final String? gitlabPassword;
  final String? gitlabToken;
  final String projectsPath;
  final String monitorMode; // 'monitor' | 'lock'
  final bool enabled;
  final String cronExpr;
  final String createdAt;

  ArgoCDEnvironment({
    String? id,
    required this.name,
    required this.gitlabUrl,
    this.gitlabUsername,
    this.gitlabPassword,
    this.gitlabToken,
    required this.projectsPath,
    this.monitorMode = 'monitor',
    this.enabled = false,
    this.cronExpr = '300',
    String? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'gitlab_url': gitlabUrl,
        'gitlab_username': gitlabUsername,
        'gitlab_password': gitlabPassword,
        'gitlab_token': gitlabToken,
        'projects_path': projectsPath,
        'monitor_mode': monitorMode,
        'enabled': enabled ? 1 : 0,
        'cron_expr': cronExpr,
        'created_at': createdAt,
      };

  factory ArgoCDEnvironment.fromMap(Map<String, dynamic> map) => ArgoCDEnvironment(
        id: map['id'] as String,
        name: map['name'] as String,
        gitlabUrl: map['gitlab_url'] as String,
        gitlabUsername: map['gitlab_username'] as String?,
        gitlabPassword: map['gitlab_password'] as String?,
        gitlabToken: map['gitlab_token'] as String?,
        projectsPath: map['projects_path'] as String,
        monitorMode: map['monitor_mode'] as String? ?? 'monitor',
        enabled: (map['enabled'] as int? ?? 0) == 1,
        cronExpr: map['cron_expr'] as String? ?? '300',
        createdAt: map['created_at'] as String?,
      );

  ArgoCDEnvironment copyWith({
    String? id,
    String? name,
    String? gitlabUrl,
    String? gitlabUsername,
    String? gitlabPassword,
    String? gitlabToken,
    String? projectsPath,
    String? monitorMode,
    bool? enabled,
    String? cronExpr,
    String? createdAt,
  }) {
    return ArgoCDEnvironment(
      id: id ?? this.id,
      name: name ?? this.name,
      gitlabUrl: gitlabUrl ?? this.gitlabUrl,
      gitlabUsername: gitlabUsername ?? this.gitlabUsername,
      gitlabPassword: gitlabPassword ?? this.gitlabPassword,
      gitlabToken: gitlabToken ?? this.gitlabToken,
      projectsPath: projectsPath ?? this.projectsPath,
      monitorMode: monitorMode ?? this.monitorMode,
      enabled: enabled ?? this.enabled,
      cronExpr: cronExpr ?? this.cronExpr,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ArgoCDTag {
  final String id;
  final String envId;
  final String projectName;
  final String? currentTag;
  final String? targetTag;
  final bool muted;
  final bool enabled;
  final String? lastChecked;

  ArgoCDTag({
    String? id,
    required this.envId,
    required this.projectName,
    this.currentTag,
    this.targetTag,
    this.muted = false,
    this.enabled = true,
    this.lastChecked,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'env_id': envId,
        'project_name': projectName,
        'current_tag': currentTag,
        'target_tag': targetTag,
        'muted': muted ? 1 : 0,
        'enabled': enabled ? 1 : 0,
        'last_checked': lastChecked,
      };

  factory ArgoCDTag.fromMap(Map<String, dynamic> map) => ArgoCDTag(
        id: map['id'] as String,
        envId: map['env_id'] as String,
        projectName: map['project_name'] as String,
        currentTag: map['current_tag'] as String?,
        targetTag: map['target_tag'] as String?,
        muted: (map['muted'] as int? ?? 0) == 1,
        enabled: (map['enabled'] as int? ?? 1) == 1,
        lastChecked: map['last_checked'] as String?,
      );
}

// ============================================================================
// Data Source & SQL Models
// ============================================================================

class DataSource {
  final String id;
  final String name;
  final String sourceType; // 'phpmyadmin' | 'grafana' | 'pingcode'
  final String config;
  final String createdAt;

  DataSource({
    String? id,
    required this.name,
    required this.sourceType,
    required this.config,
    String? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> getConfigMap() {
    try {
      return jsonDecode(config) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'source_type': sourceType,
        'config': config,
        'created_at': createdAt,
      };

  factory DataSource.fromMap(Map<String, dynamic> map) => DataSource(
        id: map['id'] as String,
        name: map['name'] as String,
        sourceType: map['source_type'] as String,
        config: map['config'] as String,
        createdAt: map['created_at'] as String?,
      );
}

class SqlQuery {
  final String id;
  final String dataSourceId;
  final String name;
  final String sqlText;
  final String? description;

  SqlQuery({
    String? id,
    required this.dataSourceId,
    required this.name,
    required this.sqlText,
    this.description,
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'data_source_id': dataSourceId,
        'name': name,
        'sql_text': sqlText,
        'description': description,
      };

  factory SqlQuery.fromMap(Map<String, dynamic> map) => SqlQuery(
        id: map['id'] as String,
        dataSourceId: map['data_source_id'] as String,
        name: map['name'] as String,
        sqlText: map['sql_text'] as String,
        description: map['description'] as String?,
      );
}

// ============================================================================
// Excel & Template Models
// ============================================================================

class SheetData {
  final String name;
  final List<String> headers;
  final List<List<String>> rows;

  const SheetData({
    required this.name,
    required this.headers,
    required this.rows,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'headers': headers,
        'rows': rows,
      };

  factory SheetData.fromJson(Map<String, dynamic> json) => SheetData(
        name: json['name'] as String? ?? '',
        headers: (json['headers'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
        rows: (json['rows'] as List<dynamic>? ?? [])
            .map((r) => (r as List<dynamic>).map((c) => c.toString()).toList())
            .toList(),
      );
}

class ExcelData {
  final List<SheetData> sheets;

  const ExcelData({required this.sheets});

  SheetData? getSheet(String name) {
    try {
      return sheets.firstWhere((s) => s.name == name);
    } catch (_) {
      try {
        return sheets.firstWhere((s) => s.name.contains(name) || name.contains(s.name));
      } catch (_) {
        return null;
      }
    }
  }
}

class ExtractionRule {
  final String placeholder;
  final String sourceType; // 'excel' | 'database' | 'grafana' | 'pingcode'
  final String? sheetName;
  final String? cellRef;
  final String? column;
  final String? aggregation; // 'sum' | 'count' | 'avg' | 'max' | 'min'
  final String? filterColumn;
  final String? filterValue;
  final String? format; // 'number' | 'percent' | 'currency' | 'raw'
  final String? dataSourceId;
  final String? queryId;
  final Map<String, String>? params;

  const ExtractionRule({
    required this.placeholder,
    this.sourceType = 'excel',
    this.sheetName,
    this.cellRef,
    this.column,
    this.aggregation,
    this.filterColumn,
    this.filterValue,
    this.format = 'raw',
    this.dataSourceId,
    this.queryId,
    this.params,
  });

  Map<String, dynamic> toJson() => {
        'placeholder': placeholder,
        'source_type': sourceType,
        'sheet_name': sheetName,
        'cell_ref': cellRef,
        'column': column,
        'aggregation': aggregation,
        'filter_column': filterColumn,
        'filter_value': filterValue,
        'format': format,
        'data_source_id': dataSourceId,
        'query_id': queryId,
        'params': params,
      };

  factory ExtractionRule.fromJson(Map<String, dynamic> json) => ExtractionRule(
        placeholder: json['placeholder'] as String? ?? '',
        sourceType: json['source_type'] as String? ?? 'excel',
        sheetName: json['sheet_name'] as String?,
        cellRef: json['cell_ref'] as String?,
        column: json['column'] as String?,
        aggregation: json['aggregation'] as String?,
        filterColumn: json['filter_column'] as String?,
        filterValue: json['filter_value'] as String?,
        format: json['format'] as String? ?? 'raw',
        dataSourceId: json['data_source_id'] as String?,
        queryId: json['query_id'] as String?,
        params: (json['params'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())),
      );
}

class ReportTemplate {
  final String id;
  final String name;
  final String content;
  final List<ExtractionRule> rules;
  final String createdAt;
  final String updatedAt;

  ReportTemplate({
    String? id,
    required this.name,
    required this.content,
    this.rules = const [],
    String? createdAt,
    String? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'content': content,
        'rules': jsonEncode(rules.map((r) => r.toJson()).toList()),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory ReportTemplate.fromMap(Map<String, dynamic> map) {
    List<ExtractionRule> parsedRules = [];
    try {
      final raw = map['rules'];
      if (raw is String && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        parsedRules = list.map((e) => ExtractionRule.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}

    return ReportTemplate(
      id: map['id'] as String,
      name: map['name'] as String,
      content: map['content'] as String,
      rules: parsedRules,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}

// ============================================================================
// Report Models
// ============================================================================

class ReportSection {
  final String sectionType; // 'sales_overview' | 'service_automation' | 'order_alerts' | 'inventory_flow' | 'zeebe_monitor' | 'custom'
  final String title;
  final String content;
  final int order;

  const ReportSection({
    required this.sectionType,
    required this.title,
    required this.content,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
        'section_type': sectionType,
        'title': title,
        'content': content,
        'order': order,
      };

  factory ReportSection.fromJson(Map<String, dynamic> json) => ReportSection(
        sectionType: json['section_type'] as String? ?? 'custom',
        title: json['title'] as String? ?? '',
        content: json['content'] as String? ?? '',
        order: json['order'] as int? ?? 1,
      );
}

class Report {
  final String id;
  final String title;
  final String date;
  final String htmlContent;
  final List<ReportSection> sections;
  final String createdAt;
  final String updatedAt;

  Report({
    String? id,
    required this.title,
    required this.date,
    this.htmlContent = '',
    this.sections = const [],
    String? createdAt,
    String? updatedAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String(),
        updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'date': date,
        'html_content': htmlContent,
        'sections_json': jsonEncode(sections.map((s) => s.toJson()).toList()),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  factory Report.fromMap(Map<String, dynamic> map) {
    List<ReportSection> sections = const [];
    final rawSections = map['sections_json'];
    if (rawSections is String && rawSections.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawSections);
        if (decoded is List) {
          sections = decoded
              .where((item) => item is Map)
              .map((item) => ReportSection.fromJson(Map<String, dynamic>.from(item as Map)))
              .toList();
        }
      } catch (_) {
        // Fallback gracefully on parsing error
      }
    }
    return Report(
      id: map['id'] as String,
      title: map['title'] as String,
      date: map['date'] as String,
      htmlContent: map['html_content'] as String? ?? '',
      sections: sections,
      createdAt: map['created_at'] as String?,
      updatedAt: map['updated_at'] as String?,
    );
  }
}

// ============================================================================
// Email Models
// ============================================================================

class EmailAccount {
  final String id;
  final String name;
  final String smtpHost;
  final int smtpPort;
  final String username;
  final String password;
  final bool useTls;
  final String createdAt;

  EmailAccount({
    String? id,
    required this.name,
    required this.smtpHost,
    required this.smtpPort,
    required this.username,
    required this.password,
    this.useTls = true,
    String? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'username': username,
        'password_encrypted': password,
        'use_tls': useTls ? 1 : 0,
        'created_at': createdAt,
      };

  factory EmailAccount.fromMap(Map<String, dynamic> map) => EmailAccount(
        id: map['id'] as String,
        name: map['name'] as String,
        smtpHost: map['smtp_host'] as String,
        smtpPort: map['smtp_port'] as int,
        username: map['username'] as String,
        password: map['password_encrypted'] as String? ?? '',
        useTls: (map['use_tls'] as int? ?? 1) == 1,
        createdAt: map['created_at'] as String?,
      );
}

class EmailRecipient {
  final String id;
  final String accountId;
  final String name;
  final String email;
  final String groupName;

  EmailRecipient({
    String? id,
    required this.accountId,
    required this.name,
    required this.email,
    this.groupName = 'default',
  }) : id = id ?? _uuid.v4();

  Map<String, dynamic> toMap() => {
        'id': id,
        'account_id': accountId,
        'name': name,
        'email': email,
        'group_name': groupName,
      };

  factory EmailRecipient.fromMap(Map<String, dynamic> map) => EmailRecipient(
        id: map['id'] as String,
        accountId: map['account_id'] as String,
        name: map['name'] as String,
        email: map['email'] as String,
        groupName: map['group_name'] as String? ?? 'default',
      );
}

// ============================================================================
// Scheduler & Task Log Models
// ============================================================================

class ScheduledTask {
  final String id;
  final String name;
  final String taskType; // 'scrape' | 'generate_report' | 'send_email'
  final String config;
  final String cronExpr;
  final bool enabled;
  final String? lastRun;
  final String? nextRun;
  final String createdAt;

  ScheduledTask({
    String? id,
    required this.name,
    required this.taskType,
    required this.config,
    required this.cronExpr,
    this.enabled = true,
    this.lastRun,
    this.nextRun,
    String? createdAt,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> getConfigMap() {
    try {
      return jsonDecode(config) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'task_type': taskType,
        'config': config,
        'cron_expr': cronExpr,
        'enabled': enabled ? 1 : 0,
        'last_run': lastRun,
        'next_run': nextRun,
        'created_at': createdAt,
      };

  factory ScheduledTask.fromMap(Map<String, dynamic> map) => ScheduledTask(
        id: map['id'] as String,
        name: map['name'] as String,
        taskType: map['task_type'] as String,
        config: map['config'] as String,
        cronExpr: map['cron_expr'] as String,
        enabled: (map['enabled'] as int? ?? 1) == 1,
        lastRun: map['last_run'] as String?,
        nextRun: map['next_run'] as String?,
        createdAt: map['created_at'] as String?,
      );
}

class TaskLog {
  final String id;
  final String taskType;
  final String status; // 'running' | 'success' | 'failed'
  final String? message;
  final String startedAt;
  final String? finishedAt;

  TaskLog({
    String? id,
    required this.taskType,
    required this.status,
    this.message,
    String? startedAt,
    this.finishedAt,
  })  : id = id ?? _uuid.v4(),
        startedAt = startedAt ?? DateTime.now().toIso8601String();

  Map<String, dynamic> toMap() => {
        'id': id,
        'task_type': taskType,
        'status': status,
        'message': message,
        'started_at': startedAt,
        'finished_at': finishedAt,
      };

  factory TaskLog.fromMap(Map<String, dynamic> map) => TaskLog(
        id: map['id'] as String,
        taskType: map['task_type'] as String,
        status: map['status'] as String,
        message: map['message'] as String?,
        startedAt: map['started_at'] as String? ?? '',
        finishedAt: map['finished_at'] as String?,
      );
}
