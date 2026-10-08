/// 渗透报告：数据聚合、AI 叙述生成、Markdown/PDF 导出、版本管理。
library;

import 'dart:convert';

import '../models/security_enums.dart';
import '../models/security_models.dart';

/// 一次报告所需的全部素材。
class ReportBundle {
  final PentestSession session;
  final List<PentestAsset> assets;
  final List<PentestFinding> findings;
  final List<TimelineEvent> timeline;
  final Map<String, dynamic> aiAnalysis;
  final DateTime generatedAt;

  const ReportBundle({
    required this.session,
    required this.assets,
    required this.findings,
    required this.timeline,
    this.aiAnalysis = const {},
    required this.generatedAt,
  });

  Map<Severity, int> get severityCounts {
    final counts = <Severity, int>{for (final s in Severity.values) s: 0};
    for (final f in findings) {
      counts[f.severityLevel] = (counts[f.severityLevel] ?? 0) + 1;
    }
    return counts;
  }

  int get findingCount => findings.length;
  int get assetCount => assets.length;
}

/// 报告聚合器：把会话数据打包成 [ReportBundle]。
class ReportDataAggregator {
  const ReportDataAggregator();

  ReportBundle aggregate({
    required PentestSession session,
    required List<PentestAsset> assets,
    required List<PentestFinding> findings,
    required List<TimelineEvent> timeline,
    Map<String, dynamic> aiAnalysis = const {},
  }) {
    return ReportBundle(
      session: session,
      assets: assets,
      findings: findings,
      timeline: timeline,
      aiAnalysis: aiAnalysis,
      generatedAt: DateTime.now(),
    );
  }
}

/// 喂给 AI 的报告 prompt（分段的其中一段）。
String buildReportSectionPrompt({
  required ReportBundle bundle,
  required String section,
}) {
  final sections = {
    'executive': '执行摘要（200 字内，面向管理层，突出风险评级与立即行动建议）',
    'narrative': '技术叙述（每个 Finding 的技术原理、业务影响、修复优先级，每个不少于 3 句）',
    'attack_path': '攻击路径描述（如存在成功利用，说明从信息收集到 getshell 的完整链条）',
    'remediation': '修复建议（按 Finding 逐条给出可执行的修复措施与优先级）',
  };
  final instruction = sections[section] ?? sections['executive']!;

  final buf = StringBuffer()
    ..writeln('你是一名资深渗透测试报告撰写人。请基于下列会话数据生成：$instruction')
    ..writeln()
    ..writeln('【会话】${bundle.session.name}（${SessionType.labelOf(bundle.session.type)}）')
    ..writeln('【目标范围】${bundle.session.scope.join(', ')}')
    ..writeln('【资产 ${bundle.assetCount} 项】');
  for (final a in bundle.assets.take(50)) {
    buf.writeln('- ${a.address} [${a.severity.label}]');
  }
  buf.writeln();
  buf.writeln('【发现物 ${bundle.findingCount} 项】');
  for (final f in bundle.findings.take(50)) {
    buf.writeln(
      '- [${f.severityLevel.label}${f.cvssScore != null ? ' CVSS ${f.cvssScore!.toStringAsFixed(1)}' : ''}] '
      '${f.title}${f.cveId != null ? ' (${f.cveId})' : ''}'
      ' 状态: ${FindingStatus.labelOf(f.status)}',
    );
  }
  return buf.toString();
}

/// 生成 Markdown 报告正文（结构：封面信息 / 执行摘要 / 资产清单 / Finding / 修复建议）。
String buildMarkdownReport({
  required ReportBundle bundle,
  required String executiveSummary,
  required String narrative,
  required String remediation,
  String? attackPath,
}) {
  final buf = StringBuffer()
    ..writeln('# ${bundle.session.name} 渗透测试报告')
    ..writeln()
    ..writeln('| 项目 | 值 |')
    ..writeln('| --- | --- |')
    ..writeln('| 会话类型 | ${SessionType.labelOf(bundle.session.type)} |')
    ..writeln('| 目标范围 | ${bundle.session.scope.join('、')} |')
    ..writeln('| 资产数量 | ${bundle.assetCount} |')
    ..writeln('| 发现物数量 | ${bundle.findingCount} |')
    ..writeln('| 生成时间 | ${bundle.generatedAt.toIso8601String()} |')
    ..writeln()
    ..writeln('## 一、执行摘要')
    ..writeln()
    ..writeln(executiveSummary)
    ..writeln();

  final counts = bundle.severityCounts;
  buf
    ..writeln('### 风险概览')
    ..writeln()
    ..writeln('| 严重等级 | 数量 |')
    ..writeln('| --- | --- |');
  for (final s in Severity.ordered) {
    final n = counts[s] ?? 0;
    if (n > 0) buf.writeln('| ${s.label} | $n |');
  }
  buf.writeln();

  buf.writeln('## 二、资产清单');
  buf.writeln();
  if (bundle.assets.isEmpty) {
    buf.writeln('（本次会话未记录资产）');
    buf.writeln();
  } else {
    buf
      ..writeln('| 地址 | 类型 | 风险 | 备注 |')
      ..writeln('| --- | --- | --- | --- |');
    for (final a in bundle.assets) {
      final meta = a.metadata;
      final note = a.userNote ?? meta['os'] ?? meta['title'] ?? '';
      buf.writeln(
        '| ${a.address} | ${AssetType.labelOf(a.type)} | ${a.severity.label} | $note |',
      );
    }
    buf.writeln();
  }

  buf.writeln('## 三、漏洞发现');
  buf.writeln();
  if (bundle.findings.isEmpty) {
    buf.writeln('（未发现漏洞）');
    buf.writeln();
  } else {
    buf
      ..writeln('| 等级 | CVSS | 名称 | CVE | 状态 |')
      ..writeln('| --- | --- | --- | --- | --- |');
    for (final f in bundle.findings) {
      buf.writeln(
        '| ${f.severityLevel.label} | ${f.cvssScore?.toStringAsFixed(1) ?? '-'} | '
        '${f.title.replaceAll('|', r'\|')} | ${f.cveId ?? '-'} | ${FindingStatus.labelOf(f.status)} |',
      );
    }
    buf.writeln();
    // 每个 Finding 的技术叙述
    for (final f in bundle.findings) {
      buf
        ..writeln('### ${f.title}')
        ..writeln()
        ..writeln('- 等级：${f.severityLevel.label}'
            '${f.cvssScore != null ? '（CVSS ${f.cvssScore!.toStringAsFixed(1)}）' : ''}')
        ..writeln('- 来源：${FindingSource.labelOf(f.source)}')
        ..writeln('- 状态：${FindingStatus.labelOf(f.status)}');
      if (f.cveId != null) buf.writeln('- CVE：${f.cveId}');
      if (f.evidence != null && f.evidence!.trim().isNotEmpty) {
        buf
          ..writeln()
          ..writeln('**证据：**')
          ..writeln()
          ..writeln('```')
          ..writeln(f.evidence!.trim())
          ..writeln('```');
      }
      buf.writeln();
    }
  }

  if (narrative.trim().isNotEmpty) {
    buf.writeln('## 四、技术叙述');
    buf.writeln();
    buf.writeln(narrative);
    buf.writeln();
  }

  if (attackPath != null && attackPath.trim().isNotEmpty) {
    buf.writeln('## 五、攻击路径');
    buf.writeln();
    buf.writeln(attackPath);
    buf.writeln();
  }

  buf.writeln('## 六、修复建议');
  buf.writeln();
  buf.writeln(remediation);
  buf.writeln();

  if (bundle.timeline.isNotEmpty) {
    buf.writeln('## 附：操作时间线');
    for (final e in bundle.timeline.reversed) {
      buf.writeln('- ${e.timeLabel} **${TimelineEventType.labelOf(e.eventType)}** ${e.title}');
    }
    buf.writeln();
  }

  return buf.toString();
}

/// 生成执行摘要 Markdown 报告正文（面向管理层：封面信息 / 管理层摘要 / 风险概览 / 优先整改建议）。
String buildExecutiveMarkdownReport({
  required ReportBundle bundle,
  required String executiveSummary,
  String? remediation,
}) {
  final buf = StringBuffer()
    ..writeln('# ${bundle.session.name} 渗透测试报告（执行摘要）')
    ..writeln()
    ..writeln('| 项目 | 值 |')
    ..writeln('| --- | --- |')
    ..writeln('| 会话类型 | ${SessionType.labelOf(bundle.session.type)} |')
    ..writeln('| 目标范围 | ${bundle.session.scope.join('、')} |')
    ..writeln('| 资产数量 | ${bundle.assetCount} |')
    ..writeln('| 发现物数量 | ${bundle.findingCount} |')
    ..writeln('| 生成时间 | ${bundle.generatedAt.toIso8601String()} |')
    ..writeln()
    ..writeln('## 一、管理层摘要')
    ..writeln()
    ..writeln(executiveSummary)
    ..writeln();

  final counts = bundle.severityCounts;
  buf
    ..writeln('## 二、风险态势概览')
    ..writeln()
    ..writeln('| 严重等级 | 数量 |')
    ..writeln('| --- | --- |');
  for (final s in Severity.ordered) {
    final n = counts[s] ?? 0;
    if (n > 0) buf.writeln('| ${s.label} | $n |');
  }
  buf.writeln();

  if (remediation != null && remediation.trim().isNotEmpty) {
    buf.writeln('## 三、优先整改建议');
    buf.writeln();
    buf.writeln(remediation);
    buf.writeln();
  }

  return buf.toString();
}

/// PDF 封面/正文所需的纯数据（PDF 渲染在 UI 层，用 `pdf` 库）。
class PdfReportSpec {
  final String title;
  final String subtitle;
  final String sessionType;
  final List<String> scope;
  final String generatedAt;
  final String executiveSummary;
  final List<ReportFindingRow> findingRows;
  final String narrative;
  final String remediation;

  const PdfReportSpec({
    required this.title,
    required this.subtitle,
    required this.sessionType,
    required this.scope,
    required this.generatedAt,
    required this.executiveSummary,
    required this.findingRows,
    required this.narrative,
    required this.remediation,
  });
}

/// PDF 里 Finding 表格的一行。
class ReportFindingRow {
  final String severity;
  final String cvss;
  final String title;
  final String cve;
  final String status;

  const ReportFindingRow({
    required this.severity,
    required this.cvss,
    required this.title,
    required this.cve,
    required this.status,
  });
}

/// 从 [ReportBundle] 生成 PDF 规格。
PdfReportSpec toPdfSpec(ReportBundle bundle, String executiveSummary) {
  return PdfReportSpec(
    title: '${bundle.session.name} 渗透测试报告',
    subtitle: SessionType.labelOf(bundle.session.type),
    sessionType: bundle.session.type,
    scope: bundle.session.scope,
    generatedAt: bundle.generatedAt.toIso8601String().split('T').first,
    executiveSummary: executiveSummary,
    findingRows: [
      for (final f in bundle.findings)
        ReportFindingRow(
          severity: f.severityLevel.label,
          cvss: f.cvssScore?.toStringAsFixed(1) ?? '-',
          title: f.title,
          cve: f.cveId ?? '-',
          status: FindingStatus.labelOf(f.status),
        ),
    ],
    narrative: '',
    remediation: '',
  );
}

/// 报告版本号：同会话已有版本数 + 1。
int nextVersion(List<ReportVersionRecord> existing) {
  if (existing.isEmpty) return 1;
  final maxVersion = existing
      .map((r) => r.version)
      .reduce((a, b) => a > b ? a : b);
  return maxVersion + 1;
}

/// 版本上限（spec：最多保留 10 个版本）。
const int kMaxReportVersions = 10;

/// 超出上限时应删除的最旧版本 id 列表。
List<String> versionsToPrune(
  List<ReportVersionRecord> existing, {
  int limit = kMaxReportVersions,
}) {
  if (existing.length <= limit) return const [];
  final sorted = List<ReportVersionRecord>.of(existing)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return sorted.skip(limit).map((r) => r.id).toList().reversed.toList();
}

/// 报告内容 JSON 序列化（存入 report_versions 表的辅助）。
String encodeReportContent({
  required String executiveSummary,
  required String narrative,
  required String remediation,
  String? attackPath,
}) {
  return jsonEncode({
    'executive_summary': executiveSummary,
    'narrative': narrative,
    'remediation': remediation,
    'attack_path': attackPath,
  });
}

/// 解析 report_versions.content。
Map<String, dynamic> decodeReportContent(String content) {
  try {
    final decoded = jsonDecode(content);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : const {};
  } catch (_) {
    return const {};
  }
}
