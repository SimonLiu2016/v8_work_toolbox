/// 安全工具箱的领域模型。
///
/// 全部是可序列化的普通 Dart 对象——drift 生成的 DataClass 只在内层
/// （services/database）出现，UI 层拿到的是这些模型，避免把数据库类型泄露到
/// Widget 里（测试也就不需要真实数据库）。
library;

import 'dart:convert';

import 'security_enums.dart';

/// 一次渗透测试会话。
class PentestSession {
  final String id;
  final String name;

  /// [SessionType.lan] 或 [SessionType.web]。
  final String type;

  /// JSON 数组字符串：LAN 是 CIDR 列表，Web 是域名列表。
  final String scopeJson;

  /// [SessionStatus] 之一。
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PentestSession({
    required this.id,
    required this.name,
    required this.type,
    required this.scopeJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isLan => type == SessionType.lan;

  List<String> get scope {
    try {
      final decoded = jsonDecode(scopeJson);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {
      // 非法 JSON 时退化为空列表，别让整个会话列表渲染失败。
    }
    return const [];
  }

  PentestSession copyWith({
    String? name,
    String? type,
    String? scopeJson,
    String? status,
    DateTime? updatedAt,
  }) {
    return PentestSession(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      scopeJson: scopeJson ?? this.scopeJson,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'scope': scope,
    'status': status,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };
}

/// 会话内的一台主机或一个 URL 资产。
class PentestAsset {
  final String id;
  final String sessionId;

  /// [AssetType.host] 或 [AssetType.url]。
  final String type;
  final String address;

  /// JSON：os / mac / vendor / ports / techStack / statusCode / title 等。
  final String metadataJson;

  /// [Severity.key]，未知为 'unknown'。
  final String riskLevel;

  /// 用户手工备注。后续扫描不得覆盖（见 spec「资产手动标注」）。
  final String? userNote;
  final DateTime createdAt;
  final DateTime updatedAt;
  Map<String, dynamic>? _cachedMetadata;

  PentestAsset({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.address,
    required this.metadataJson,
    required this.riskLevel,
    this.userNote,
    required this.createdAt,
    required this.updatedAt,
    Map<String, dynamic>? cachedMetadata,
  }) : _cachedMetadata = cachedMetadata;

  Map<String, dynamic> get metadata {
    if (_cachedMetadata != null) return _cachedMetadata!;
    try {
      final decoded = jsonDecode(metadataJson);
      if (decoded is Map) {
        _cachedMetadata = Map<String, dynamic>.from(decoded);
        return _cachedMetadata!;
      }
    } catch (_) {
      // 同上：容错优先。
    }
    _cachedMetadata = <String, dynamic>{};
    return _cachedMetadata!;
  }

  Severity get severity => Severity.fromKey(riskLevel);

  /// 资产开放端口列表。
  List<Map<String, dynamic>> get openPorts {
    final raw = metadata['ports'];
    if (raw is List) {
      return raw
          .map((e) => e is Map ? Map<String, dynamic>.from(e) : null)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return const [];
  }

  PentestAsset copyWith({
    String? metadataJson,
    String? riskLevel,
    String? userNote,
    DateTime? updatedAt,
  }) {
    return PentestAsset(
      id: id,
      sessionId: sessionId,
      type: type,
      address: address,
      metadataJson: metadataJson ?? this.metadataJson,
      riskLevel: riskLevel ?? this.riskLevel,
      userNote: userNote ?? this.userNote,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      cachedMetadata: metadataJson == null ? _cachedMetadata : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'session_id': sessionId,
    'type': type,
    'address': address,
    'metadata': metadata,
    'risk_level': riskLevel,
    'user_note': userNote,
  };
}

/// 一条漏洞发现物。
class PentestFinding {
  final String id;
  final String sessionId;
  final String? assetId;
  final String? cveId;
  final String title;

  /// [Severity.key]。
  final String severity;

  final double? cvssScore;

  /// [FindingStatus] 之一。
  final String status;

  /// 工具原始输出片段。
  final String? evidence;

  /// [FindingSource] 之一。
  final String source;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PentestFinding({
    required this.id,
    required this.sessionId,
    this.assetId,
    this.cveId,
    required this.title,
    required this.severity,
    this.cvssScore,
    required this.status,
    this.evidence,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  Severity get severityLevel => Severity.fromKey(severity);

  PentestFinding copyWith({
    String? status,
    double? cvssScore,
    String? cveId,
    String? severity,
    DateTime? updatedAt,
  }) {
    return PentestFinding(
      id: id,
      sessionId: sessionId,
      assetId: assetId,
      cveId: cveId ?? this.cveId,
      title: title,
      severity: severity ?? this.severity,
      cvssScore: cvssScore ?? this.cvssScore,
      status: status ?? this.status,
      evidence: evidence,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'target': assetId,
    'cve': cveId,
    'title': title,
    'severity': severity,
    'cvss': cvssScore,
    'status': status,
    'source': source,
  };
}

/// 会话内的一条操作事件。
class TimelineEvent {
  final String id;
  final String sessionId;

  /// [TimelineEventType] 之一。
  final String eventType;
  final String title;

  /// JSON：command / args / durationMs / aiText 等。
  final String detailJson;
  final DateTime createdAt;

  const TimelineEvent({
    required this.id,
    required this.sessionId,
    required this.eventType,
    required this.title,
    required this.detailJson,
    required this.createdAt,
  });

  Map<String, dynamic> get detail {
    try {
      final decoded = jsonDecode(detailJson);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // 同上。
    }
    return <String, dynamic>{};
  }

  String get timeLabel {
    final t = createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}

/// 情报库里的一条 CVE。
class ThreatIntelEntry {
  final String cveId;
  final String title;
  final double? cvssScore;
  final String severity;
  final String description;
  final DateTime? published;
  final bool isKev;
  final String? pocUrl;
  final DateTime syncedAt;

  const ThreatIntelEntry({
    required this.cveId,
    required this.title,
    this.cvssScore,
    required this.severity,
    required this.description,
    this.published,
    required this.isKev,
    this.pocUrl,
    required this.syncedAt,
  });

  Severity get severityLevel => Severity.fromKey(severity);
}

/// 一次报告生成的历史版本。
class ReportVersionRecord {
  final String id;
  final String sessionId;
  final int version;

  /// 'executive' 或 'technical'。
  final String format;

  /// Markdown 正文。
  final String content;
  final DateTime createdAt;

  const ReportVersionRecord({
    required this.id,
    required this.sessionId,
    required this.version,
    required this.format,
    required this.content,
    required this.createdAt,
  });
}

/// 跨模块工作流导航意图与上下文载荷。
class NavigationIntent {
  /// 目标 Tab，如 'recon', 'vuln', 'exploit', 'script', 'agent', 'report'。
  final String targetTab;

  /// 关联的目标资产（可选）。
  final PentestAsset? targetAsset;

  /// 关联的漏洞发现项（可选）。
  final PentestFinding? targetFinding;

  /// 目标端口（可选）。
  final int? port;

  /// 端口对应的服务或协议名（可选，如 'http', 'smb', 'ssh'）。
  final String? service;

  /// 初始检索关键字（可选，如 CVE 编号或组件名称）。
  final String? initialQuery;

  /// 预设或推荐的任务提示词（可选，用于 Agent 或脚本生成）。
  final String? initialPrompt;

  /// 附加键值参数。
  final Map<String, dynamic> extra;

  const NavigationIntent({
    required this.targetTab,
    this.targetAsset,
    this.targetFinding,
    this.port,
    this.service,
    this.initialQuery,
    this.initialPrompt,
    this.extra = const {},
  });
}

/// Security Agent 推荐的下一步行动模型。
class AgentNextAction {
  final String title;
  final String description;
  final String actionLabel;
  final NavigationIntent intent;

  const AgentNextAction({
    required this.title,
    required this.description,
    required this.actionLabel,
    required this.intent,
  });
}
