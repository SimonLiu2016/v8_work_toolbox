/// Security Agent 九个工具的真实执行层。
///
/// `SecurityAgentService` 只做编排（审批、步骤流、上下文拼装），不认识数据库；
/// 这里把它的 `executeTool` 回调落到具体服务上。分开的原因是测试可以直接构造
/// executor 喂内存库，不需要起 Widget。
///
/// 返回文本一律截断到 500 字符以内——回灌给模型的文本越长，3 轮迭代就越容易把
/// context 撑爆（design 的 Risk 一节要求 < 8000 tokens）。
library;

import 'dart:convert';

import '../../../services/agent_loop.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import 'exploit_services.dart';
import 'hydra_service.dart';
import 'lan_recon_services.dart';
import 'security_session_controller.dart';
import 'vuln_scan_services.dart';
import 'web_credential_service.dart';
import 'web_recon_services.dart';

/// Agent 工具的真实执行器。
class SecurityAgentExecutor {
  final SecuritySessionController controller;

  const SecurityAgentExecutor(this.controller);

  /// 按工具名分发执行。未知工具名返回 failure——不是 success：
  /// 模型需要知道自己调错了，否则会反复重试同一个名字。
  Future<AgentToolOutcome> call(
    String name,
    Map<String, dynamic> args,
  ) async {
    final session = controller.current;
    if (session == null) {
      return AgentToolOutcome.success(
        '当前没有会话。请先让用户在安全工具箱中创建一个 LAN 或 Web 会话，'
        '再执行扫描类工具。',
      );
    }

    switch (name) {
      case 'run_nmap':
        return _runNmap(args);
      case 'run_nuclei':
        return _runNuclei(args);
      case 'run_subfinder':
        return _runSubfinder(args);
      case 'run_httpx':
        return _runHttpx(args);
      case 'run_ffuf':
        return _runFfuf(args);
      case 'run_sqlmap':
        return _runSqlmap(args);
      case 'run_msf_module':
        return _runMsfModule(args);
      case 'run_hydra':
        return _runHydra(args);
      case 'check_web_credential':
        return _checkWebCredential(args);
      case 'query_threat_intel':
        return _queryIntel(args);
      case 'get_session_findings':
        return _getFindings();
      default:
        return AgentToolOutcome.failure(
          '未知工具: $name。可用工具见系统提示中的工具清单。',
        );
    }
  }

  // ---------------------------------------------------------------------------
  // 侦察类
  // ---------------------------------------------------------------------------

  Future<AgentToolOutcome> _runNmap(Map<String, dynamic> args) async {
    final session = controller.current!;
    final target = _stringArg(args, 'target');
    if (target == null) return _missingArg('target');
    final mode = _nmapMode(args['mode']);
    final hosts = await NmapService.scan(
      target: target,
      mode: mode,
      onLog: controller.log,
    );
    if (hosts.isEmpty) {
      return AgentToolOutcome.success('nmap 未发现主机（$target）。');
    }
    for (final host in hosts) {
      await controller.assets.upsert(
        sessionId: session.id,
        type: AssetType.host,
        address: host.ip,
        metadata: host.toMetadata(),
        riskLevel: riskLevelForHost(host),
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: nmap $target（${mode.label}）',
      detail: {'target': target, 'mode': mode.label, 'hosts': hosts.length},
    );
    return AgentToolOutcome.success(
      _json({
        'hosts': [
          for (final h in hosts)
            {
              'ip': h.ip,
              'os': h.osName,
              'open_ports': [
                for (final p in h.ports)
                  {'port': p.port, 'service': p.service, 'version': p.version},
              ],
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _runSubfinder(Map<String, dynamic> args) async {
    final session = controller.current!;
    final domain = _stringArg(args, 'domain');
    if (domain == null) return _missingArg('domain');
    final subs = await SubfinderService.run(
      [domain],
      onLog: controller.log,
    );
    for (final sub in subs) {
      await controller.assets.upsert(
        sessionId: session.id,
        type: AssetType.url,
        address: sub.host,
        metadata: {'source': sub.source ?? 'subfinder'},
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: subfinder $domain',
      detail: {'domain': domain, 'count': subs.length},
    );
    return AgentToolOutcome.success(
      _json({
        'count': subs.length,
        'sample': [for (final s in subs.take(20)) s.host],
      }),
    );
  }

  Future<AgentToolOutcome> _runHttpx(Map<String, dynamic> args) async {
    final session = controller.current!;
    final targets = _stringListArg(args, 'targets');
    if (targets == null || targets.isEmpty) return _missingArg('targets');
    final results = await HttpxService.run(
      targets,
      onLog: controller.log,
    );
    for (final r in results) {
      final address = r.host ?? Uri.tryParse(r.url)?.host ?? r.url;
      await controller.assets.upsert(
        sessionId: session.id,
        type: AssetType.url,
        address: address,
        metadata: r.toMetadata(),
        riskLevel: riskLevelForWeb(r),
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: httpx 探测 ${targets.length} 个目标',
      detail: {'probed': targets.length, 'alive': results.length},
    );
    return AgentToolOutcome.success(
      _json({
        'probed': targets.length,
        'alive': results.length,
        'sample': [
          for (final r in results.take(20))
            {
              'url': r.url,
              'status': r.statusCode,
              'title': r.title,
              'tech': r.tech,
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _runFfuf(Map<String, dynamic> args) async {
    final session = controller.current!;
    final url = _stringArg(args, 'url');
    if (url == null) return _missingArg('url');
    final findings = await FfufService.run(
      url,
      wordlist: _stringArg(args, 'wordlist') ?? '',
      onLog: controller.log,
    );
    if (findings.isEmpty) {
      return AgentToolOutcome.success(
        'ffuf 未发现有效路径（$url）。若日志提示未找到字典，请先安装 seclists。',
      );
    }
    final address = Uri.tryParse(url)?.host ?? url;
    final existing = await controller.assets.byAddress(session.id, address);
    final merged = <String, dynamic>{
      ...?existing?.metadata,
      'crawled_urls': [
        ...((existing?.metadata['crawled_urls'] as List?) ?? const []),
        for (final f in findings) f.url,
      ].take(200).toList(),
    };
    await controller.assets.upsert(
      sessionId: session.id,
      type: AssetType.url,
      address: address,
      metadata: merged,
    );
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: ffuf $url',
      detail: {'url': url, 'findings': findings.length},
    );
    return AgentToolOutcome.success(
      _json({
        'findings': findings.length,
        'sample': [
          for (final f in findings.take(20)) {'url': f.url, 'status': f.status},
        ],
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // 漏洞类
  // ---------------------------------------------------------------------------

  Future<AgentToolOutcome> _runNuclei(Map<String, dynamic> args) async {
    final session = controller.current!;
    final target = _stringArg(args, 'target');
    if (target == null) return _missingArg('target');
    final categories = _nucleiCategories(args);

    final added = <PentestFinding>[];
    await NucleiService.scan(
      targets: [target],
      categories: categories,
      onLog: controller.log,
      onFinding: (finding) async {
        var cvss = finding.cvssScore;
        var severity = finding.severityLevel;
        final cve = finding.cveId;
        // 模板没带 CVSS 时补查 NVD（spec 的 fallback）。
        if (cve != null && cvss == null) {
          final detail = await CveEnricher.instance.lookup(cve);
          if (detail != null) {
            cvss = detail.cvssScore;
            severity = Severity.fromKey(detail.severity);
          }
        }
        final asset = await controller.assets.byAddress(
          session.id,
          target,
        );
        added.add(
          await controller.findings.add(
            sessionId: session.id,
            assetId: asset?.id,
            cveId: cve,
            title: finding.name,
            severity: severity.key,
            cvssScore: cvss,
            evidence: finding.raw.toString(),
            source: FindingSource.nuclei,
          ),
        );
      },
    );
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: nuclei $target',
      detail: {'target': target, 'findings': added.length},
    );
    if (added.isEmpty) {
      return AgentToolOutcome.success('nuclei 未发现漏洞（$target）。');
    }
    return AgentToolOutcome.success(
      _json({
        'findings': [
          for (final f in added)
            {
              'title': f.title,
              'severity': f.severity,
              'cve': f.cveId,
              'cvss': f.cvssScore,
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _runSqlmap(Map<String, dynamic> args) async {
    final session = controller.current!;
    final url = _stringArg(args, 'url');
    if (url == null) return _missingArg('url');
    final results = await SqlmapService.scan([url], onLog: controller.log);
    for (final r in results) {
      await controller.findings.add(
        sessionId: session.id,
        title: r.title ?? '${r.targetUrl} 疑似注入点',
        severity: Severity.high.key,
        evidence:
            'parameter=${r.parameter} technique=${r.technique} dbms=${r.dbms}',
        source: FindingSource.sqlmap,
      );
    }
    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: sqlmap $url',
      detail: {'url': url, 'findings': results.length},
    );
    return AgentToolOutcome.success(
      _json({
        'findings': [
          for (final r in results)
            {'url': r.targetUrl, 'parameter': r.parameter, 'dbms': r.dbms},
        ],
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // 利用 / 情报 / 查询
  // ---------------------------------------------------------------------------

  Future<AgentToolOutcome> _runMsfModule(Map<String, dynamic> args) async {
    final module = _stringArg(args, 'module');
    if (module == null) return _missingArg('module');
    final service = MsfRpcService.instance;
    if (!await service.isDaemonRunning()) {
      return AgentToolOutcome.success(
        'msfrpcd 未运行。请用户在「漏洞利用」Tab 配置并点击连接，'
        '或确认已安装 metasploit。',
      );
    }
    final before = (await service.listSessions()).length;
    final options = <String, dynamic>{
      ..._mapArg(args, 'options'),
    };
    final jobId = await service.executeModule(
      moduleType: module.split('/').first,
      moduleName: module,
      options: options,
    );
    if (jobId == null) {
      return AgentToolOutcome.failure(
        'MSF 模块执行失败: ${service.lastError ?? '未知错误'}',
      );
    }
    // MSFRPC 的 execute 只回 job_id，会话建立是异步的——等一会儿再看。
    await Future.delayed(const Duration(seconds: 3));
    final sessions = await service.listSessions();
    if (sessions.length > before) {
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: 'Agent: MSF 建立会话',
        detail: {'module': module, 'sessions': sessions.length},
      );
    }
    return AgentToolOutcome.success(
      _json({
        'job_id': jobId,
        'sessions': [
          for (final s in sessions) {'id': s.id, 'type': s.type, 'via': s.viaExploit},
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _runHydra(Map<String, dynamic> args) async {
    final session = controller.current!;
    final target = _stringArg(args, 'target');
    if (target == null) return _missingArg('target');
    final service = _stringArg(args, 'service') ?? 'ssh';
    final portRaw = args['port'];
    final port = portRaw is int
        ? portRaw
        : (portRaw is String ? int.tryParse(portRaw) : null);

    final findings = await HydraService.scan(
      target: target,
      service: service,
      port: port,
      onLog: controller.log,
    );

    for (final f in findings) {
      await controller.findings.add(
        sessionId: session.id,
        title: '弱口令核查命中: ${f.service.toUpperCase()} ($target:${f.port})',
        severity: Severity.critical.key,
        evidence: 'username=${f.username} password=${f.password}',
        source: FindingSource.manual,
      );
    }

    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: hydra $service $target',
      detail: {'target': target, 'service': service, 'hits': findings.length},
    );

    if (findings.isEmpty) {
      return AgentToolOutcome.success('hydra 未发现 $target 的 $service 服务弱口令。');
    }

    return AgentToolOutcome.success(
      _json({
        'hits': [
          for (final f in findings)
            {
              'service': f.service,
              'port': f.port,
              'username': f.username,
              'password': f.password,
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _checkWebCredential(Map<String, dynamic> args) async {
    final session = controller.current!;
    final loginUrl = _stringArg(args, 'login_url');
    if (loginUrl == null) return _missingArg('login_url');

    final findings = await WebFormCredentialService.scan(
      candidateUrls: [loginUrl],
      baseUrl: loginUrl,
      onLog: controller.log,
    );

    for (final f in findings) {
      await controller.findings.add(
        sessionId: session.id,
        title: 'Web 表单弱口令: ${f.loginUrl}',
        severity: f.confidence == 'confirmed' ? Severity.critical.key : Severity.medium.key,
        evidence: 'action=${f.actionUrl} username=${f.username} password=${f.password} confidence=${f.confidence}',
        source: FindingSource.manual,
      );
    }

    await controller.reloadSessionData();
    await controller.recordEvent(
      eventType: TimelineEventType.toolRun,
      title: 'Agent: Web 弱口令核查 $loginUrl',
      detail: {'url': loginUrl, 'hits': findings.length},
    );

    if (findings.isEmpty) {
      return AgentToolOutcome.success('未发现 $loginUrl 表单的常见弱口令。');
    }

    return AgentToolOutcome.success(
      _json({
        'hits': [
          for (final f in findings)
            {
              'login_url': f.loginUrl,
              'action_url': f.actionUrl,
              'username': f.username,
              'password': f.password,
              'confidence': f.confidence,
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _queryIntel(Map<String, dynamic> args) async {
    final keyword = _stringArg(args, 'keyword');
    if (keyword == null) return _missingArg('keyword');
    final entries = await controller.intelRepo.all();
    final q = keyword.toLowerCase();
    final hits = entries
        .where(
          (e) =>
              e.cveId.toLowerCase().contains(q) ||
              e.title.toLowerCase().contains(q) ||
              e.description.toLowerCase().contains(q),
        )
        .toList()
      ..sort((a, b) {
        if (a.isKev != b.isKev) return a.isKev ? -1 : 1;
        return (b.cvssScore ?? -1).compareTo(a.cvssScore ?? -1);
      });
    if (hits.isEmpty) {
      return AgentToolOutcome.success(
        '情报库中没有匹配 "$keyword" 的条目。可先在威胁情报 Tab 执行同步。',
      );
    }
    return AgentToolOutcome.success(
      _json({
        'count': hits.length,
        'top': [
          for (final e in hits.take(10))
            {
              'cve': e.cveId,
              'cvss': e.cvssScore,
              'severity': e.severity,
              'is_kev': e.isKev,
              'title': e.title,
            },
        ],
      }),
    );
  }

  Future<AgentToolOutcome> _getFindings() async {
    final findings = controller.findingList;
    if (findings.isEmpty) {
      return AgentToolOutcome.success('当前会话没有漏洞发现。');
    }
    return AgentToolOutcome.success(
      _json({
        'count': findings.length,
        'findings': [for (final f in findings.take(30)) f.toJson()],
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // 参数与序列化辅助
  // ---------------------------------------------------------------------------

  /// 紧凑 JSON 序列化 + 500 字符硬截断。
  ///
  /// 截断是最后防线：即使某个工具回了异常长的输出，也不会把模型的下文挤掉。
  static String _json(Object? data, {int max = 500}) {
    final text = const JsonEncoder().convert(data);
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…（已截断）';
  }

  static String? _stringArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    if (v is num) return v.toString();
    return null;
  }

  static List<String>? _stringListArg(
    Map<String, dynamic> args,
    String key,
  ) {
    final v = args[key];
    if (v is List) return v.map((e) => e.toString()).toList();
    if (v is String) {
      return v
          .split(RegExp(r'[,\n]'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return null;
  }

  static Map<String, dynamic> _mapArg(Map<String, dynamic> args, String key) {
    final v = args[key];
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  static AgentToolOutcome _missingArg(String name) =>
      AgentToolOutcome.failure('缺少必填参数: $name');

  static NmapScanMode _nmapMode(dynamic raw) {
    switch (raw?.toString()) {
      case 'quick':
        return NmapScanMode.quick;
      case 'fullPorts':
        return NmapScanMode.fullPorts;
      default:
        return NmapScanMode.standard;
    }
  }

  /// 默认扫 CVE 与配置错误两类——全量模板一次跑几十分钟，
  /// Agent 场景下先拿高危结论比"全扫完再说话"有用。
  static List<NucleiCategory> _nucleiCategories(Map<String, dynamic> args) {
    final raw = _stringArg(args, 'categories');
    if (raw == null) {
      return const [NucleiCategory.cves, NucleiCategory.misconfiguration];
    }
    final keys = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final matched = NucleiCategory.values
        .where((c) => keys.contains(c.key))
        .toList();
    return matched.isEmpty
        ? const [NucleiCategory.cves, NucleiCategory.misconfiguration]
        : matched;
  }
}

/// 便捷入口：agent 视图只需要一行接线。
Future<AgentToolOutcome> runAgentTool(
  SecuritySessionController controller,
  String name,
  Map<String, dynamic> args,
) => SecurityAgentExecutor(controller).call(name, args);
