/// 原生安全工作流流水线服务：不依赖大模型，100% 本地确定性异步驱动。
library;

import 'dart:async';

import '../models/security_enums.dart';
import 'hydra_service.dart';
import 'lan_recon_services.dart';
import 'security_agent_executor.dart';
import 'security_agent_service.dart';
import 'security_session_controller.dart';
import 'vuln_scan_services.dart';
import 'web_credential_service.dart';
import 'web_recon_services.dart';

class SecurityPipelineService {
  SecurityPipelineService._();
  static final SecurityPipelineService instance = SecurityPipelineService._();

  bool _running = false;
  bool get isRunning => _running;

  bool _cancelled = false;

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    _running = false;
    SecurityAgentService.instance.updateCurrentTool(null);
    SecurityAgentService.instance.updateState(AgentRunState.idle);
    SecurityAgentService.instance.addThinking('用户手动中止了本地流水线执行');
  }

  /// 运行 Web 原生侦察与评估流水线：subfinder → httpx → katana → nuclei → AI 防御分析
  Future<void> runWebPipeline({
    required SecuritySessionController controller,
    required String domain,
  }) async {
    final session = controller.current;
    if (session == null) return;
    if (_running) return;

    _running = true;
    _cancelled = false;
    final agent = SecurityAgentService.instance;
    agent.reset(session.id);
    agent.updateState(AgentRunState.running);
    controller.log('═══ 启动 Web 原生确定性流水线: $domain ═══');

    try {
      // 阶段 1: subfinder 子域名枚举
      if (_cancelled) return;
      agent.updateCurrentTool('subfinder');
      agent.addThinking('阶段 1/6: subfinder 子域名被动枚举 ($domain)…');
      controller.log('[1/6] subfinder 枚举 $domain 子域名…');

      final subs = await SubfinderService.run([domain], onLog: controller.log);
      if (_cancelled) return;

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
        title: '原生流水线: subfinder 子域名枚举',
        detail: {'domain': domain, 'count': subs.length},
      );
      agent.addStep(AgentStep(
        tool: 'subfinder',
        arguments: {'domain': domain},
        approved: true,
        isError: false,
        summary: '发现 ${subs.length} 个子域名',
        at: DateTime.now(),
      ));

      // 阶段 2: httpx 存活探测与技术栈识别
      if (_cancelled) return;
      final targets = subs.map((s) => s.host).toList();
      final probeTargets = targets.isNotEmpty ? targets : [domain];
      agent.updateCurrentTool('httpx');
      agent.addThinking('阶段 2/6: httpx 存活探测与技术栈指纹识别 (${probeTargets.length} 个目标)…');
      controller.log('[2/6] httpx 存活探测 ${probeTargets.length} 个目标…');

      final httpResults = await HttpxService.run(probeTargets, onLog: controller.log);
      if (_cancelled) return;

      for (final r in httpResults) {
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
        title: '原生流水线: httpx 存活探测',
        detail: {'probed': probeTargets.length, 'alive': httpResults.length},
      );
      agent.addStep(AgentStep(
        tool: 'httpx',
        arguments: {'targets': probeTargets.length},
        approved: true,
        isError: false,
        summary: '存活 ${httpResults.length} 个 Web 资产',
        at: DateTime.now(),
      ));

      // 阶段 3: katana 爬虫采集端点
      if (_cancelled) return;
      agent.updateCurrentTool('katana');
      final crawlTargets = httpResults.isNotEmpty
          ? httpResults.take(10).map((r) => r.url).toList()
          : ['http://$domain'];
      agent.addThinking('阶段 3/6: katana 爬取 Web 端点与潜在输入口 (${crawlTargets.length} 个资产)…');
      controller.log('[3/6] katana 爬取 ${crawlTargets.length} 个存活端点…');

      var totalEndpoints = 0;
      for (final url in crawlTargets) {
        if (_cancelled) break;
        final endpoints = await KatanaService.run(url, onLog: controller.log);
        totalEndpoints += endpoints.length;
        if (endpoints.isNotEmpty) {
          final address = Uri.tryParse(url)?.host ?? domain;
          final existing = await controller.assets.byAddress(session.id, address);
          final merged = <String, dynamic>{
            ...?existing?.metadata,
            'crawled_urls': [
              ...((existing?.metadata['crawled_urls'] as List?) ?? const []),
              for (final e in endpoints) e.url,
            ].take(200).toList(),
          };
          await controller.assets.upsert(
            sessionId: session.id,
            type: AssetType.url,
            address: address,
            metadata: merged,
          );
        }
      }
      if (_cancelled) return;

      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '原生流水线: katana 爬虫',
        detail: {'crawled': crawlTargets.length, 'endpoints': totalEndpoints},
      );
      agent.addStep(AgentStep(
        tool: 'katana',
        arguments: {'targets': crawlTargets.length},
        approved: true,
        isError: false,
        summary: '爬取到 $totalEndpoints 个端点',
        at: DateTime.now(),
      ));

      // 阶段 4: Web 表单弱口令自动化探测
      if (_cancelled) return;
      agent.updateCurrentTool('web_credential');
      final allUrls = <String>{'http://$domain', 'https://$domain'};
      for (final r in httpResults) {
        allUrls.add(r.url);
      }
      for (final a in controller.assetList) {
        final urls = a.metadata['crawled_urls'];
        if (urls is List) {
          for (final u in urls) {
            if (u is String) allUrls.add(u);
          }
        }
      }
      agent.addThinking('阶段 4/6: Web 表单登录弱口令基线排查…');
      controller.log('[4/6] Web 表单弱口令排查…');

      final credFindings = await WebFormCredentialService.scan(
        candidateUrls: allUrls.toList(),
        baseUrl: httpResults.isNotEmpty ? httpResults.first.url : 'http://$domain',
        onLog: controller.log,
      );
      if (_cancelled) return;

      for (final f in credFindings) {
        await controller.findings.add(
          sessionId: session.id,
          title: 'Web 表单弱口令: ${f.loginUrl}',
          severity: f.confidence == 'confirmed' ? Severity.critical.key : Severity.medium.key,
          evidence: 'action=${f.actionUrl} username=${f.username} password=${f.password} confidence=${f.confidence}',
          source: FindingSource.manual,
        );
      }
      if (_cancelled) return;

      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '原生流水线: Web 弱口令排查',
        detail: {'hits': credFindings.length},
      );
      agent.addStep(AgentStep(
        tool: 'web_credential',
        arguments: {'candidates': allUrls.length},
        approved: true,
        isError: false,
        summary: credFindings.isNotEmpty
            ? '发现 ${credFindings.length} 处 Web 弱口令'
            : '未发现 Web 表单弱口令',
        at: DateTime.now(),
      ));

      // 阶段 5: sqlmap 自动注入探测（针对 Katana 爬取的含参数 URL）
      if (_cancelled) return;
      final allCrawledUrls = <String>{};
      for (final a in controller.assetList) {
        final urls = a.metadata['crawled_urls'];
        if (urls is List) {
          for (final u in urls) {
            if (u is String && hasQueryParameters(u)) {
              allCrawledUrls.add(u);
            }
          }
        }
      }
      final sqlmapTargets = allCrawledUrls.take(10).toList();
      if (sqlmapTargets.isNotEmpty) {
        agent.updateCurrentTool('sqlmap');
        agent.addThinking('阶段 5/6: sqlmap 自动检测 ${sqlmapTargets.length} 个含参数端点的 SQL 注入…');
        controller.log('[5/6] sqlmap 自动检测 ${sqlmapTargets.length} 个含参数端点…');

        final sqlmapFindings = await SqlmapService.scan(
          sqlmapTargets,
          onLog: controller.log,
        );
        if (_cancelled) return;

        for (final r in sqlmapFindings) {
          await controller.findings.add(
            sessionId: session.id,
            title: r.title ?? '${r.targetUrl} 疑似 SQL 注入',
            severity: Severity.high.key,
            evidence: 'parameter=${r.parameter} technique=${r.technique} dbms=${r.dbms}',
            source: FindingSource.sqlmap,
          );
        }
        await controller.reloadSessionData();
        await controller.recordEvent(
          eventType: TimelineEventType.toolRun,
          title: '原生流水线: sqlmap 注入检测',
          detail: {'targets': sqlmapTargets.length, 'findings': sqlmapFindings.length},
        );
        agent.addStep(AgentStep(
          tool: 'sqlmap',
          arguments: {'targets': sqlmapTargets.length},
          approved: true,
          isError: false,
          summary: '检测到 ${sqlmapFindings.length} 项 SQL 注入隐患',
          at: DateTime.now(),
        ));
      } else {
        controller.log('[5/6] 未发现含参数的 Web 端点，跳过 sqlmap 检测');
      }

      // 阶段 6: nuclei 脆弱性扫描（含 defaultLogins）
      if (_cancelled) return;
      agent.updateCurrentTool('nuclei');
      final nucleiTarget = httpResults.isNotEmpty ? httpResults.first.url : 'http://$domain';
      agent.addThinking('阶段 6/6: nuclei 核心安全基线核查与漏洞探测 ($nucleiTarget)…');
      controller.log('[6/6] nuclei 安全检测: $nucleiTarget…');

      var nucleiFindingCount = 0;
      await NucleiService.scan(
        targets: [nucleiTarget],
        categories: [
          NucleiCategory.cves,
          NucleiCategory.misconfiguration,
          NucleiCategory.exposures,
          NucleiCategory.defaultLogins, // 覆盖默认口令模板
        ],
        onLog: controller.log,
        onFinding: (finding) async {
          nucleiFindingCount++;
          final asset = await controller.assets.byAddress(session.id, Uri.tryParse(nucleiTarget)?.host ?? nucleiTarget);
          await controller.findings.add(
            sessionId: session.id,
            assetId: asset?.id,
            cveId: finding.cveId,
            title: finding.name,
            severity: finding.severity,
            evidence: finding.description ?? '',
            source: 'nuclei',
          );
        },
      );
      if (_cancelled) return;

      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '原生流水线: nuclei 脆弱性扫描',
        detail: {'target': nucleiTarget, 'findings': nucleiFindingCount},
      );
      agent.addStep(AgentStep(
        tool: 'nuclei',
        arguments: {'target': nucleiTarget},
        approved: true,
        isError: false,
        summary: '检测到 $nucleiFindingCount 项安全隐患',
        at: DateTime.now(),
      ));

      // 阶段 5: 防御型 AI 综合分析
      if (_cancelled) return;
      agent.updateCurrentTool(null);
      agent.addThinking('本地扫描流水线全部完成，正在由 AI 防御专家生成加固评估建议…');
      controller.log('正在生成防御加固评估报告…');

      final report = await agent.generateDefensiveReport(
        session: session,
        assets: controller.assetList,
        findings: controller.findingList,
      );
      agent.updateFinalReport(report);
      agent.updateState(AgentRunState.done);
      controller.log('═══ Web 原生流水线执行完毕 ═══');
    } catch (e) {
      controller.log('流水线执行异常: $e');
      agent.updateState(AgentRunState.failed);
    } finally {
      _running = false;
      agent.updateCurrentTool(null);
    }
  }

  /// 运行 LAN 原生侦察与评估流水线：ARP发现 → nmap深度扫描 → nuclei安全检测 → AI防御分析
  Future<void> runLanPipeline({
    required SecuritySessionController controller,
    required String targetCidr,
  }) async {
    final session = controller.current;
    if (session == null) return;
    if (_running) return;

    _running = true;
    _cancelled = false;
    final agent = SecurityAgentService.instance;
    agent.reset(session.id);
    agent.updateState(AgentRunState.running);
    controller.log('═══ 启动 LAN 原生确定性流水线: $targetCidr ═══');

    try {
      // 阶段 1: ARP 存活主机发现
      if (_cancelled) return;
      agent.updateCurrentTool('arp_scan');
      agent.addThinking('阶段 1/4: 局域网 ARP 主机探测 ($targetCidr)…');
      controller.log('[1/4] ARP 存活主机探测…');

      final arpHosts = await ArpScanService.scan(
        cidr: targetCidr,
        onLog: controller.log,
      );
      if (_cancelled) return;

      for (final h in arpHosts) {
        await controller.assets.upsert(
          sessionId: session.id,
          type: AssetType.host,
          address: h.ip,
          metadata: {
            if (h.mac != null) 'mac': h.mac,
            if (h.vendor != null) 'vendor': h.vendor,
            'source': 'arp',
          },
        );
      }
      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '流水线: ARP 设备探测',
        detail: {'count': arpHosts.length},
      );
      agent.addStep(AgentStep(
        tool: 'arp_scan',
        arguments: {'cidr': targetCidr},
        approved: true,
        isError: false,
        summary: '发现 ${arpHosts.length} 台活跃局域网设备',
        at: DateTime.now(),
      ));

      // 阶段 2: nmap 深度服务扫描
      if (_cancelled) return;
      agent.updateCurrentTool('nmap');
      agent.addThinking('阶段 2/4: nmap 服务枚举与端口扫描…');
      controller.log('[2/4] nmap 服务扫描 ($targetCidr)…');

      final nmapHosts = await NmapService.scan(
        target: targetCidr,
        mode: NmapScanMode.quick,
        onLog: controller.log,
      );
      if (_cancelled) return;

      for (final h in nmapHosts) {
        final existing = await controller.assets.byAddress(session.id, h.ip);
        final meta = h.toMetadata();
        final prevMeta = existing?.metadata ?? const {};
        if (meta['mac'] == null && prevMeta['mac'] != null) {
          meta['mac'] = prevMeta['mac'];
        }
        if (meta['vendor'] == null && prevMeta['vendor'] != null) {
          meta['vendor'] = prevMeta['vendor'];
        }
        await controller.assets.upsert(
          sessionId: session.id,
          type: AssetType.host,
          address: h.ip,
          metadata: meta,
          riskLevel: riskLevelForHost(h),
        );
      }
      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '流水线: nmap 深度扫描',
        detail: {'target': targetCidr, 'hosts': nmapHosts.length},
      );
      agent.addStep(AgentStep(
        tool: 'nmap',
        arguments: {'target': targetCidr},
        approved: true,
        isError: false,
        summary: '完成 ${nmapHosts.length} 台主机的端口与服务枚举',
        at: DateTime.now(),
      ));

      // 阶段 3: hydra 服务层弱口令核查（针对开放 SSH / FTP 端口的主机）
      if (_cancelled) return;
      final sshFtpTargets = <(String ip, String service, int port)>[];
      for (final h in nmapHosts) {
        for (final p in h.ports) {
          final isOpen = p.state == null || p.state == 'open';
          if (isOpen) {
            if (p.port == 22 || p.service.toLowerCase().contains('ssh')) {
              sshFtpTargets.add((h.ip, 'ssh', p.port));
            } else if (p.port == 21 || p.service.toLowerCase().contains('ftp')) {
              sshFtpTargets.add((h.ip, 'ftp', p.port));
            }
          }
        }
      }

      var hydraHits = 0;
      if (sshFtpTargets.isNotEmpty) {
        agent.updateCurrentTool('hydra');
        agent.addThinking('阶段 3/4: hydra 弱口令基线核查 (${sshFtpTargets.length} 个服务目标)…');
        controller.log('[3/4] hydra 弱口令核查 ${sshFtpTargets.length} 个服务…');

        for (final item in sshFtpTargets.take(5)) {
          if (_cancelled) break;
          final hits = await HydraService.scan(
            target: item.$1,
            service: item.$2,
            port: item.$3,
            onLog: controller.log,
          );
          for (final hit in hits) {
            hydraHits++;
            await controller.findings.add(
              sessionId: session.id,
              title: '弱口令核查命中: ${hit.service.toUpperCase()} (${hit.target}:${hit.port})',
              severity: Severity.critical.key,
              evidence: 'username=${hit.username} password=${hit.password}',
              source: FindingSource.manual,
            );
          }
        }

        if (_cancelled) return;
        await controller.reloadSessionData();
        await controller.recordEvent(
          eventType: TimelineEventType.toolRun,
          title: '流水线: hydra 弱口令核查',
          detail: {'targets': sshFtpTargets.length, 'hits': hydraHits},
        );
        agent.addStep(AgentStep(
          tool: 'hydra',
          arguments: {'targets': sshFtpTargets.length},
          approved: true,
          isError: false,
          summary: hydraHits > 0 ? '检出 $hydraHits 个弱口令服务账户' : '未检出弱口令服务',
          at: DateTime.now(),
        ));
      } else {
        controller.log('[3/4] 未发现开放 SSH/FTP 服务的主机，跳过弱口令核查');
      }

      // 阶段 4: nuclei 针对网络服务脆弱性排查
      if (_cancelled) return;
      agent.updateCurrentTool('nuclei');
      final firstIp = nmapHosts.isNotEmpty ? nmapHosts.first.ip : (arpHosts.isNotEmpty ? arpHosts.first.ip : '');
      var nucleiCount = 0;
      if (firstIp.isNotEmpty) {
        agent.addThinking('阶段 4/4: nuclei 网络服务安全检测 ($firstIp)…');
        controller.log('[4/4] nuclei 扫描: $firstIp…');

        await NucleiService.scan(
          targets: [firstIp],
          categories: [NucleiCategory.network, NucleiCategory.misconfiguration, NucleiCategory.defaultLogins],
          onLog: controller.log,
          onFinding: (finding) async {
            nucleiCount++;
            final asset = await controller.assets.byAddress(session.id, firstIp);
            await controller.findings.add(
              sessionId: session.id,
              assetId: asset?.id,
              cveId: finding.cveId,
              title: finding.name,
              severity: finding.severity,
              evidence: finding.description ?? '',
              source: 'nuclei',
            );
          },
        );
      }
      if (_cancelled) return;

      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.toolRun,
        title: '流水线: nuclei 弱点核查',
        detail: {'target': firstIp, 'findings': nucleiCount},
      );
      agent.addStep(AgentStep(
        tool: 'nuclei',
        arguments: {'target': firstIp},
        approved: true,
        isError: false,
        summary: '排查出 $nucleiCount 项安全缺陷',
        at: DateTime.now(),
      ));

      // 阶段 4: 防御型 AI 综合分析
      if (_cancelled) return;
      agent.updateCurrentTool(null);
      agent.addThinking('局域网扫描流水线全部完成，正在由 AI 防御专家生成加固评估建议…');
      controller.log('正在生成防御评估报告…');

      final report = await agent.generateDefensiveReport(
        session: session,
        assets: controller.assetList,
        findings: controller.findingList,
      );
      agent.updateFinalReport(report);
      agent.updateState(AgentRunState.done);
      controller.log('═══ LAN 原生流水线执行完毕 ═══');
    } catch (e) {
      controller.log('流水线执行异常: $e');
      agent.updateState(AgentRunState.failed);
    } finally {
      _running = false;
      agent.updateCurrentTool(null);
    }
  }
}

/// 自适应 AI 驱动流水线：固定基础侦察阶段 + AI 研判循环（最多 3 轮深度探测）。
///
/// 与 [SecurityPipelineService]（确定性本地流水线）并存：基础阶段复用其逻辑，
/// AI 研判层调用 [SecurityAgentService.run] 进行 ReAct 循环，executeTool
/// 回调接入 [SecurityAgentExecutor] 真实执行工具并写库。
class AdaptiveAgentPipeline {
  AdaptiveAgentPipeline._();

  /// 启动自适应全量评估流水线。
  ///
  /// [isLan] 决定基础阶段走 Web 路径还是 LAN 路径。
  /// [onApprovalRequired] 为 null 时高影响工具自动批准（自动化流水线场景）。
  static Future<void> run({
    required SecuritySessionController controller,
    required String target,
    required bool isLan,
    Future<bool> Function(String tool, Map<String, dynamic> args)?
    onApprovalRequired,
  }) async {
    final pipeline = SecurityPipelineService.instance;
    final agent = SecurityAgentService.instance;
    final session = controller.current;
    if (session == null) return;
    if (pipeline.isRunning) return;

    controller.log('═══ 启动自适应 AI 全量评估流水线 ═══');
    agent.addThinking('▶ 阶段 1/2：确定性基础侦察扫描…');

    // ── 阶段 1：确定性基础侦察 ────────────────────────────────────────────
    try {
      if (isLan) {
        await pipeline.runLanPipeline(
          controller: controller,
          targetCidr: target,
        );
      } else {
        await pipeline.runWebPipeline(
          controller: controller,
          domain: target,
        );
      }
    } catch (e) {
      controller.log('基础侦察阶段异常: $e');
      // 即使基础阶段失败也继续进入 AI 研判，利用已有数据
    }

    // ── 阶段 2：AI 研判层（最多 3 轮） ──────────────────────────────────────
    agent.addThinking('▶ 阶段 2/2：AI 自适应研判与深度探测（最多 3 轮）…');
    controller.log('[AI] 开始自适应研判循环…');

    final executor = SecurityAgentExecutor(controller);

    for (var round = 1; round <= 3; round++) {
      // 构建当前状态摘要
      final assets = controller.assetList;
      final findings = controller.findingList;
      if (assets.isEmpty && findings.isEmpty && round == 1) {
        controller.log('[AI] 无资产数据，跳过研判循环');
        break;
      }

      final context = _buildRoundContext(session.name, target, assets, findings, round);
      agent.addThinking('第 $round 轮研判：${findings.length} 个发现物，${assets.length} 个资产');
      controller.log('[AI] 第 $round 轮研判开始…');

      try {
        final result = await agent.run(
          task: '基于当前巡检数据，识别高风险项并决定是否需要进一步深度核查。'
              '若发现明显配置缺陷或高危漏洞，调用相应工具深入验证；'
              '若已充分掌握风险全貌，请输出最终评估结论并停止工具调用。',
          sessionContext: context,
          sessionId: session.id,
          maxIterations: 5,
          timeout: const Duration(seconds: 180),
          executeTool: (name, args) => executor.call(name, args),
          // 自动化流水线中高影响工具自动批准
          onApproval: onApprovalRequired ??
              (tool, args) async {
                agent.addThinking('[自动批准] $tool（自动化流水线授权）');
                return true;
              },
        );

        // 若 AI 明确宣告"评估完成"或本轮无工具调用则提前退出
        final text = result.text.trim();
        final noMoreTools = result.executions.isEmpty;
        if (noMoreTools ||
            text.contains('评估完成') ||
            text.contains('已充分') ||
            text.contains('无需进一步')) {
          agent.addThinking('AI 宣告评估完成，结束研判循环（第 $round 轮）');
          controller.log('[AI] 评估完成，共 $round 轮');
          break;
        }
      } catch (e) {
        controller.log('[AI] 第 $round 轮研判异常: $e');
        break;
      }
    }

    // ── 最终报告 ──────────────────────────────────────────────────────────
    agent.addThinking('生成最终综合安全评估报告…');
    controller.log('正在生成最终报告…');
    try {
      final report = await agent.generateDefensiveReport(
        session: session,
        assets: controller.assetList,
        findings: controller.findingList,
      );
      agent.updateFinalReport(report);
      agent.updateState(AgentRunState.done);
      controller.log('═══ 自适应流水线全部完成 ═══');
    } catch (e) {
      controller.log('最终报告生成失败: $e');
      agent.updateState(AgentRunState.failed);
    }
  }

  /// 构建 AI 研判轮次的会话上下文摘要（控制在 800 字符内防止 context 膨胀）。
  static String _buildRoundContext(
    String sessionName,
    String target,
    List<dynamic> assets,
    List<dynamic> findings,
    int round,
  ) {
    final assetSummary = assets.isEmpty
        ? '暂无资产数据'
        : '共 ${assets.length} 个，示例: ${assets.take(5).map((a) => a.address).join(', ')}';

    final critHigh = findings
        .where((f) => f.severity == 'critical' || f.severity == 'high')
        .length;
    final findingSummary = findings.isEmpty
        ? '暂无发现物'
        : '共 ${findings.length} 项（高危/严重: $critHigh），'
            '示例: ${findings.take(5).map((f) => '[${f.severity.toUpperCase()}] ${f.title}').join('; ')}';

    return '巡检目标: $target（会话: $sessionName）\n'
        '当前资产: $assetSummary\n'
        '当前发现: $findingSummary\n'
        '研判轮次: 第 $round 轮（最多 3 轮）';
  }
}
