/// 安全工具箱的共享状态。
///
/// 一个 `ChangeNotifier` 承载「当前会话 + 工具状态板 + 资产/发现物列表」，
/// 各 Tab 视图都从它读、往里写。没有它的话每个 Tab 都要自己开数据库连接，
/// 面板间的联动（扫描完成 → 资产列表刷新 → AI 面板推送）也无从谈起。
library;

import 'package:drift/drift.dart' hide OrderingTerm;
import 'package:drift/drift.dart' as drift show OrderingTerm;
import 'package:flutter/foundation.dart';

import '../../../services/ai_service.dart';
import '../database/security_database.dart' as db;
import '../database/security_database.dart' show SecurityDatabase;
import '../services/brew_install_service.dart';
import '../models/security_models.dart';
import '../services/report_services.dart';
import '../services/intel_store.dart';
import '../services/security_agent_service.dart';
import '../services/security_repositories.dart';
import '../services/tool_status_checker.dart';

/// AI 面板里的一条消息。
class AiPanelMessage {
  final String role;
  final String text;
  final DateTime at;

  const AiPanelMessage({
    required this.role,
    required this.text,
    required this.at,
  });

  bool get isUser => role == 'user';
}

class SecuritySessionController extends ChangeNotifier {
  /// 默认构造：自己开生产连接。
  SecuritySessionController() : this._(SecurityDatabase());

  /// 仅供测试：注入已打开的数据库（内存库等）。
  ///
  /// 与默认构造的分工：默认构造自己开生产连接，测试可注入内存库而完全不碰
  /// 平台通道（macOS 上 sqflite 的平台实现在单测里不存在）。
  SecuritySessionController.withDatabase(SecurityDatabase db) : this._(db);

  SecuritySessionController._(this._db) {
    sessions = SessionRepository(_db);
    assets = AssetRepository(_db);
    findings = FindingRepository(_db);
    timeline = TimelineRepository(_db);
  }

  late final SecurityDatabase _db;

  /// 把内部数据库句柄交出去（情报仓储要复用同一连接）。
  ///
  /// 不让外部 `import` 数据库文件再 `SecurityDatabase()`——那会开出**第二个**
  /// SQLite 连接，两个连接的写入会互相覆盖未提交的缓存。暴露 `_db` 引用是
  /// 这里唯一的正解。
  SecurityDatabase dbForRepos() => _db;

  /// 情报仓储（Agent 的 query_threat_intel 与情报面板共用同一个仓储实例）。
  late final ThreatIntelRepository intelRepo = ThreatIntelRepository(_db);

  late final SessionRepository sessions;
  late final AssetRepository assets;
  late final FindingRepository findings;
  late final TimelineRepository timeline;

  bool initializing = true;

  List<PentestSession> sessionList = const [];
  PentestSession? current;

  List<PentestAsset> assetList = const [];
  List<PentestFinding> findingList = const [];
  List<TimelineEvent> timelineList = const [];

  ToolStatusBoard board = ToolStatusBoard.empty;
  bool probingTools = false;

  NucleiTemplateState templates = NucleiTemplateState.empty;

  /// 当前激活的 Tab 标识（'session', 'recon', 'agent', 'vuln', 'exploit', 'intel', 'script', 'report', 'tools'）。
  String activeTab = 'recon';

  /// 暂存的跨模块导航意图。
  NavigationIntent? pendingIntent;

  /// 切换激活的 Tab，并可选携带导航意图与上下文数据。
  void navigateToTab(String tab, {NavigationIntent? intent}) {
    activeTab = tab;
    if (intent != null) {
      pendingIntent = intent;
    }
    notifyListeners();
  }

  /// 设置当前 Tab。
  void setActiveTab(String tab) {
    if (activeTab != tab) {
      activeTab = tab;
      notifyListeners();
    }
  }

  /// 消费并清除当前暂存的导航意图（由目标视图在读取后调用）。
  NavigationIntent? consumeIntent() {
    final intent = pendingIntent;
    pendingIntent = null;
    return intent;
  }

  /// AI 面板消息（右侧常驻面板）。
  final List<AiPanelMessage> aiMessages = [];
  bool aiBusy = false;

  /// 扫描/安装日志（各 Tab 共用同一个日志缓冲区）。
  final List<String> logs = [];

  static const String kSystemPrompt = '''
你是一名资深企业系统安全防御架构师与合规审计专家，拥有 CISSP/CISA 级别的专业知识。
基于已授权巡检采集到的资产与漏洞数据，从蓝队防御和安全加固视角进行分析：
1. 评估资产攻击面与暴露风险，按照危害度与修补紧迫性排序优先级
2. 分析潜在的风险扩散链与薄弱节点
3. 给出切实可行的防御加固建议、安全配置调优方案与官方补丁修复指南
4. 技术描述精确，使用合规且规范的专业术语
''';

  void log(String line) {
    logs.add(line);
    if (logs.length > 500) logs.removeRange(0, logs.length - 500);
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  /// 获取最近追加的日志（滑动窗口，默认保留尾部 100 条）。
  List<String> recentLogs([int count = 100]) {
    if (logs.length <= count) return List.unmodifiable(logs);
    return List.unmodifiable(logs.sublist(logs.length - count));
  }

  /// 打开工具箱：载入会话列表 + 恢复上次进行中的会话 + 探测工具状态。
  Future<void> init() async {
    initializing = true;
    notifyListeners();
    await refreshSessions();
    final active = await sessions.lastActive();
    if (active != null) {
      await selectSession(active.id);
    }
    await refreshTools();
    BrewInstallService.instance.templates.listen((state) {
      templates = state;
      notifyListeners();
    });
    initializing = false;
    notifyListeners();
  }

  Future<void> refreshSessions() async {
    sessionList = await sessions.all();
    notifyListeners();
  }

  Future<void> selectSession(String id) async {
    final session = await sessions.byId(id);
    if (session == null) return;
    current = session;
    SecurityAgentService.instance.switchSession(session.id);
    await reloadSessionData();
    notifyListeners();
  }

  Future<void> reloadSessionData() async {
    final session = current;
    if (session == null) {
      assetList = const [];
      findingList = const [];
      timelineList = const [];
      return;
    }
    assetList = await assets.forSession(session.id);
    findingList = await findings.forSession(session.id);
    timelineList = await timeline.forSession(session.id);
    notifyListeners();
  }

  Future<PentestSession> createSession({
    required String name,
    required String type,
    required List<String> scope,
  }) async {
    final session = await sessions.create(
      name: name,
      type: type,
      scope: scope,
    );
    await refreshSessions();
    await selectSession(session.id);
    return session;
  }

  Future<void> deleteSession(String id) async {
    await sessions.delete(id);
    SecurityAgentService.instance.removeSession(id);
    await refreshSessions();
    if (current?.id == id) {
      if (sessionList.isNotEmpty) {
        await selectSession(sessionList.first.id);
      } else {
        current = null;
        await reloadSessionData();
      }
    } else {
      await reloadSessionData();
    }
  }

  Future<void> setSessionStatus(String status) async {
    final session = current;
    if (session == null) return;
    await sessions.setStatus(session.id, status);
    await refreshSessions();
    await selectSession(session.id);
  }

  /// 重新探测全部工具状态。
  Future<void> refreshTools() async {
    probingTools = true;
    notifyListeners();
    final probes = await ToolStatusChecker.probeAll();
    board = ToolStatusBoard(
      probes: probes,
      brewAvailable: await _brewAvailable(),
      checkedAt: DateTime.now(),
    );
    probingTools = false;
    notifyListeners();
    await BrewInstallService.instance.detectTemplates();
  }

  Future<bool> _brewAvailable() async {
    try {
      return await HomebrewDetector.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// 记录一条时间线事件并刷新列表。
  Future<void> recordEvent({
    required String eventType,
    required String title,
    Map<String, dynamic> detail = const {},
  }) async {
    final session = current;
    if (session == null) return;
    await timeline.append(
      sessionId: session.id,
      eventType: eventType,
      title: title,
      detail: detail,
    );
    timelineList = await timeline.forSession(session.id);
    await sessions.touch(session.id);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // AI 面板
  // ---------------------------------------------------------------------------

  void pushAiMessage(String role, String text) {
    aiMessages.add(
      AiPanelMessage(role: role, text: text, at: DateTime.now()),
    );
    notifyListeners();
  }

  void setAiBusy(bool value) {
    aiBusy = value;
    notifyListeners();
  }

  void clearAiMessages() {
    aiMessages.clear();
    notifyListeners();
  }

  /// 批量更新漏洞发现物的处置状态并刷新当前会话。
  Future<void> batchSetFindingStatus(List<String> ids, String status) async {
    if (ids.isEmpty) return;
    await findings.batchSetStatus(ids, status);
    await reloadSessionData();
  }

  /// 针对单个漏洞请求防御加固与应急缓解建议。
  ///
  /// - 严格使用防御合规提示词，严禁使用攻击/利用/Exploit/PoC 等易触发封禁词汇；
  /// - 精简请求上下文，移除全局 50 资产，截断 evidence <= 500 字符；
  /// - 支持 [ignoreCooldown] 绕过 60 秒熔断冷却限制；
  /// - 自定义单次请求超时（默认 45 秒）。
  Future<String> askFindingRemediation({
    required PentestFinding finding,
    required String targetHost,
    bool ignoreCooldown = false,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    setAiBusy(true);
    try {
      var rawEvidence = finding.evidence?.trim() ?? '';
      if (rawEvidence.length > 500) {
        rawEvidence = '${rawEvidence.substring(0, 500)}...[截断]';
      }

      final prompt = '''
请作为企业系统安全防护与加固专家，针对以下检测到的安全脆弱项提供专业的防御修复方案：
- 目标资产：$targetHost
- 风险项名称：${finding.title}
- CVE 编号：${finding.cveId ?? '无'}
- 严重级别：${finding.severityLevel.label} (CVSS: ${finding.cvssScore?.toStringAsFixed(1) ?? '未知'})
- 漏洞来源：${finding.source}
${rawEvidence.isNotEmpty ? '- 探测证据摘要：$rawEvidence' : ''}

请按以下结构提供清晰、可落地的防御处置指导：
1. 【漏洞成因与潜在危害】：分析该风险产生的技术原因以及对系统的潜在危害影响。
2. 【应急临时缓解措施】：若无法立即升级，可采取的网络 ACL、安全组、WAF 规则或临时配置变更。
3. 【官方补丁与修复方案】：推荐的官方修复版本升级路径或永久性配置加固步骤。
4. 【验证与复测要点】：如何以非破坏性的安全方式验证该漏洞已被成功修补。
''';

      final result = await AiService.instance.chat(
        timeout: timeout,
        ignoreCooldown: ignoreCooldown,
        messages: [
          {
            'role': 'system',
            'content':
                '你是一名资深企业系统安全防御与加固专家。你的职责是指导系统管理员与研发团队排查并修复系统安全漏洞，收敛资产暴露面，提供合规、严谨的系统防御与安全补丁加固建议。严禁提供任何黑客攻击入侵、利用脚本 (PoC/Exploit) 编写或攻击参数调试。',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
      );
      return result.text;
    } finally {
      setAiBusy(false);
    }
  }

  /// 针对当前会话中的发现物请求全量综合研判与整改处置方案。
  Future<String> askBatchRemediation({
    required List<PentestFinding> findings,
    bool ignoreCooldown = false,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final session = current;
    final sessionName = session?.name ?? '安全巡检会话';
    if (findings.isEmpty) {
      return '当前暂无漏洞发现项，无需生成加固处置方案。';
    }

    setAiBusy(true);
    try {
      // 聚合去重同类漏洞
      final grouped = <String, List<PentestFinding>>{};
      for (final f in findings) {
        grouped.putIfAbsent(f.title, () => []).add(f);
      }

      final itemsSummary = grouped.entries.take(15).map((e) {
        final f = e.value.first;
        return '- 【${f.severityLevel.label}】${e.key} (影响 ${e.value.length} 个目标, CVE: ${f.cveId ?? "无"})';
      }).join('\n');

      final prompt = '''
请针对以下系统安全巡检中发现的共性脆弱项，生成一份结构化的《系统漏洞排查与防御处置汇总报告》：
会话名称：$sessionName
发现物总数：${findings.length} 项（已聚合为 ${grouped.length} 类共性风险）

共性风险清单（前 15 项）：
$itemsSummary

请提供：
1. 【整体风险态势与处置优先级】：按严重等级（Critical/High/Medium）给出整改时间表建议。
2. 【关键共性脆弱点整改指引】：针对上述共性风险（如 SSH 管理端口暴露、Web 框架缺陷、SQL 注入等）分别给出标准配置加固方案。
3. 【系统安全基线长效建议】：从边界防护、访问鉴权、补丁生命周期等角度给出 3 点长效防御建议。
''';

      final result = await AiService.instance.chat(
        timeout: timeout,
        ignoreCooldown: ignoreCooldown,
        messages: [
          {
            'role': 'system',
            'content':
                '你是一名资深网络安全与合规审计顾问。请提供系统级防御加固指导与整改优先级规划，使用中立、建设性且专业的系统安全运维语言。',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
      );
      return result.text;
    } finally {
      setAiBusy(false);
    }
  }

  /// 向 AI 提一个问题，带当前会话上下文；返回回复文本。
  ///
  /// 失败抛给调用方（UI 决定怎么提示），但 `aiBusy` 一定复位——否则一次网络
  /// 失败会让面板永远停在"思考中"。
  Future<String> askAi(String prompt) async {
    setAiBusy(true);
    try {
      final result = await AiService.instance.chat(
        messages: [
          {'role': 'system', 'content': kSystemPrompt},
          {
            'role': 'user',
            'content': '当前会话状态：\n${sessionContextJson()}\n\n问题：$prompt',
          },
        ],
      );
      return result.text;
    } finally {
      setAiBusy(false);
    }
  }

  // ---------------------------------------------------------------------------
  // 报告版本
  // ---------------------------------------------------------------------------

  /// 保存一个报告版本，返回新版本号。超出上限时删掉最旧的。
  Future<int> saveReportVersion({
    required int version,
    required String content,
    String format = 'technical',
  }) async {
    final session = current;
    if (session == null) return 0;
    await _db.into(_db.reportVersionsTable).insert(
      db.ReportVersionsTableCompanion.insert(
        id: newId(),
        sessionId: session.id,
        version: Value(version),
        format: Value(format),
        content: content,
        createdAt: DateTime.now(),
      ),
    );
    final existing = await reportVersions();
    for (final id in versionsToPrune(existing)) {
      await (_db.delete(_db.reportVersionsTable)
            ..where((t) => t.id.equals(id)))
          .go();
    }
    return version;
  }

  Future<List<ReportVersionRecord>> reportVersions() async {
    final session = current;
    if (session == null) return const [];
    final rows =
        await (_db.select(_db.reportVersionsTable)
              ..where((t) => t.sessionId.equals(session.id))
              ..orderBy([(t) => drift.OrderingTerm.desc(t.createdAt)]))
            .get();
    return rows
        .map(
          (r) => ReportVersionRecord(
            id: r.id,
            sessionId: r.sessionId,
            version: r.version,
            format: r.format,
            content: r.content,
            createdAt: r.createdAt,
          ),
        )
        .toList();
  }

  /// 把当前会话的全部数据打包成报告素材；没有会话时返回 null。
  ///
  /// 报告视图要的是"快照"而不是流：AI 三段叙述之间若资产还在变，
  // 生成的报告会前后不一致，所以先固化一份再喂给模型。
  ReportBundle? buildReportBundle() {
    final session = current;
    if (session == null) return null;
    return const ReportDataAggregator().aggregate(
      session: session,
      assets: assetList,
      findings: findingList,
      timeline: timelineList,
    );
  }

  /// 当前会话的紧凑 JSON 摘要（AI 上下文，控制在 8000 tokens 内）。
  String sessionContextJson() {    final session = current;
    if (session == null) return '{}';
    return '''
{
  "session": {"name": "${session.name}", "type": "${session.type}", "scope": ${session.scope}},
  "assets": [
    ${assetList.take(50).map((a) => '{"address": "${a.address}", "risk": "${a.riskLevel}", "metadata": ${a.metadataJson}}').join(',\n    ')}
  ],
  "findings": [
    ${findingList.take(50).map((f) => '{"title": "${f.title.replaceAll('"', "'")}", "severity": "${f.severity}", "cve": "${f.cveId ?? ''}", "cvss": ${f.cvssScore ?? 'null'}}').join(',\n    ')}
  ]
}''';
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}
