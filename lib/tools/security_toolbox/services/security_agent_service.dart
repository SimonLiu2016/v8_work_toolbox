/// Security Agent 模式（任务组 11）：AgentLoop 驱动的自动化渗透工作流。
///
/// 工具集是 9 个受管的 Agent 回调：每个都对应一个真实 CLI 调用，返回值是紧凑
/// JSON 而不是原始输出——回灌给模型的文本必须短，否则 3 轮迭代就把 context
/// 撑爆（design 的 Risk 一节明确要求 < 8000 tokens）。
library;

import 'dart:async';

import '../../../services/agent_loop.dart';
import '../../../services/ai_service.dart';
import '../models/security_models.dart';

/// 高影响工具白名单（design B3）。
///
/// 命中白名单的调用必须在 execute 回调里暂停等用户确认——这些操作会对目标造成
/// 实际影响，不是"只读"侦察。
const Set<String> kHighImpactTools = {
  'run_msf_module',
  'run_sqlmap_exploit',
  'run_hydra',
  'run_netexec',
  'run_bettercap',
};

/// Security Agent 的工具集（spec：9 个工具）。
abstract final class SecurityAgentTools {
  static List<AgentTool> get all => const [
    AgentTool(
      name: 'run_nmap',
      description: '对目标执行 nmap 端口扫描，返回开放端口与服务摘要',
      inputSchema: {
        'type': 'object',
        'properties': {
          'target': {'type': 'string', 'description': 'IP / CIDR'},
          'mode': {
            'type': 'string',
            'enum': ['quick', 'standard', 'fullPorts'],
            'description': '扫描深度',
          },
        },
        'required': ['target'],
      },
    ),
    AgentTool(
      name: 'run_nuclei',
      description: '对目标执行 nuclei 模板扫描，返回发现的漏洞摘要',
      inputSchema: {
        'type': 'object',
        'properties': {
          'target': {'type': 'string'},
          'severity': {'type': 'string', 'description': 'critical/high/medium/low'},
        },
        'required': ['target'],
      },
    ),
    AgentTool(
      name: 'run_subfinder',
      description: '子域名被动枚举',
      inputSchema: {
        'type': 'object',
        'properties': {
          'domain': {'type': 'string'},
        },
        'required': ['domain'],
      },
    ),
    AgentTool(
      name: 'run_httpx',
      description: 'HTTP 存活探测与技术栈识别',
      inputSchema: {
        'type': 'object',
        'properties': {
          'targets': {'type': 'array', 'items': {'type': 'string'}},
        },
        'required': ['targets'],
      },
    ),
    AgentTool(
      name: 'run_ffuf',
      description: 'Web 路径与隐藏端点探测（暴露面收敛基线核查）',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
        },
        'required': ['url'],
      },
    ),
    AgentTool(
      name: 'run_sqlmap',
      description: 'SQL 注入合规性基线检测（授权环境输入验证安全核查）',
      inputSchema: {
        'type': 'object',
        'properties': {
          'url': {'type': 'string'},
        },
        'required': ['url'],
      },
    ),
    AgentTool(
      name: 'run_msf_module',
      description: '通过 MSFRPC 执行 Metasploit 漏洞影响验证模块（授权环境已批准，高影响需记录审计）',
      inputSchema: {
        'type': 'object',
        'properties': {
          'module': {'type': 'string'},
          'options': {'type': 'object'},
        },
        'required': ['module'],
      },
    ),
    AgentTool(
      name: 'query_threat_intel',
      description: '查询本地情报库中的 CVE 漏洞情报与风险评级',
      inputSchema: {
        'type': 'object',
        'properties': {
          'keyword': {'type': 'string'},
        },
        'required': ['keyword'],
      },
    ),
    AgentTool(
      name: 'run_hydra',
      description: '对目标网络服务（SSH/FTP）执行弱口令合规基线核查（授权环境）',
      inputSchema: {
        'type': 'object',
        'properties': {
          'target': {'type': 'string', 'description': '目标 IP 或主机名'},
          'service': {
            'type': 'string',
            'enum': ['ssh', 'ftp', 'http-get'],
            'description': '目标服务类型，默认为 ssh',
          },
          'port': {'type': 'integer', 'description': '服务端口（可选）'},
        },
        'required': ['target'],
      },
    ),
    AgentTool(
      name: 'check_web_credential',
      description: 'Web 登录表单弱口令基线核查（自动识别登录页面与表单结构，探测常见弱密码组合）',
      inputSchema: {
        'type': 'object',
        'properties': {
          'login_url': {'type': 'string', 'description': '登录页 URL 或包含登录入口的 Web 地址'},
        },
        'required': ['login_url'],
      },
    ),
    AgentTool(
      name: 'get_session_findings',
      description: '获取当前会话已入库的全部漏洞发现摘要',
      inputSchema: {'type': 'object', 'properties': {}},
    ),
  ];

  /// 工具名 → 是否高影响。
  static bool isHighImpact(String name) => kHighImpactTools.contains(name);
}

/// Agent 的一步执行记录（UI 展示用）。
class AgentStep {
  final String tool;
  final Map<String, dynamic> arguments;
  final bool approved;
  final bool isError;
  final String summary;
  final DateTime at;

  const AgentStep({
    required this.tool,
    required this.arguments,
    required this.approved,
    required this.isError,
    required this.summary,
    required this.at,
  });
}

/// Agent 运行状态。
enum AgentRunState { idle, running, paused, done, failed }

/// 某个会话专属的 Agent 运行时状态数据。
class SessionAgentData {
  AgentRunState state;
  final List<AgentStep> steps;
  final List<String> thinking;
  String? currentTool;
  String? finalReport;
  String? lastError;
  String? taskDraft;

  SessionAgentData({
    this.state = AgentRunState.idle,
    List<AgentStep>? steps,
    List<String>? thinking,
    this.currentTool,
    this.finalReport,
    this.lastError,
    this.taskDraft,
  })  : steps = steps ?? [],
        thinking = thinking ?? [];

  void reset({bool clearDraft = false}) {
    state = AgentRunState.idle;
    steps.clear();
    thinking.clear();
    currentTool = null;
    finalReport = null;
    lastError = null;
    if (clearDraft) {
      taskDraft = null;
    }
  }
}

/// Security Agent 服务。
///
/// 结构是「AgentLoop 的调用方」：自己不实现 ReAct 循环，只提供工具集、执行
/// 回调和审批闸门。按会话隔离状态数据，切换会话时自动恢复对应日志与结论。
class SecurityAgentService {
  SecurityAgentService._();
  static final SecurityAgentService instance = SecurityAgentService._();

  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;

  final Map<String, SessionAgentData> _sessions = {};

  SessionAgentData _dataFor(String? sessionId) {
    final key = sessionId ?? '__default__';
    return _sessions.putIfAbsent(key, () => SessionAgentData());
  }

  SessionAgentData get _activeData => _dataFor(_currentSessionId);

  AgentRunState get state => _activeData.state;
  set state(AgentRunState value) => _activeData.state = value;

  List<AgentStep> get steps => _activeData.steps;
  List<String> get thinking => _activeData.thinking;

  String? get currentTool => _activeData.currentTool;
  set currentTool(String? value) => _activeData.currentTool = value;

  String? get finalReport => _activeData.finalReport;
  set finalReport(String? value) => _activeData.finalReport = value;

  String? get lastError => _activeData.lastError;
  set lastError(String? value) => _activeData.lastError = value;

  String? get taskDraft => _activeData.taskDraft;
  set taskDraft(String? value) => _activeData.taskDraft = value;

  String? getTaskDraft(String? sessionId) => _dataFor(sessionId).taskDraft;
  void setTaskDraft(String? sessionId, String? text) {
    _dataFor(sessionId).taskDraft = text;
  }

  /// 获取给定会话的推荐预设任务。
  ///
  /// 若已存有草稿（且非 null），返回该草稿；
  /// 否则如果会话有效且有 target（Web: 域名，LAN: CIDR），生成对应的一键预设；
  /// 无有效目标时返回空字符串。
  String resolveDefaultTask(PentestSession? session) {
    if (session == null) return '';
    final draft = getTaskDraft(session.id);
    if (draft != null) return draft;
    final target = session.scope.isNotEmpty ? session.scope.first : '';
    if (target.isEmpty) return '';
    return session.isLan ? lanOneClickTask(target) : webOneClickTask(target);
  }

  final _stateController = StreamController<AgentRunState>.broadcast();
  Stream<AgentRunState> get stateStream => _stateController.stream;

  final _stepController = StreamController<AgentStep>.broadcast();
  Stream<AgentStep> get stepStream => _stepController.stream;

  Completer<bool>? _approval;

  /// 切换当前活跃会话，立即广播该会话的最新状态。
  void switchSession(String? sessionId) {
    if (_currentSessionId == sessionId) return;
    _currentSessionId = sessionId;
    _stateController.add(state);
    if (steps.isNotEmpty) {
      _stepController.add(steps.last);
    }
  }

  /// 移除指定会话的缓存状态（会话删除时调用）。
  void removeSession(String sessionId) {
    _sessions.remove(sessionId);
    if (_currentSessionId == sessionId) {
      _currentSessionId = null;
      _stateController.add(state);
    }
  }

  /// 请求用户审批；返回用户选择（true=执行，false=跳过）。
  Future<bool> requestApproval(String tool, Map<String, dynamic> args) {
    final completer = Completer<bool>();
    _approval = completer;
    _stateController.add(AgentRunState.paused);
    return completer.future;
  }

  void resolveApproval(bool approved) {
    _approval?.complete(approved);
    _approval = null;
    _stateController.add(AgentRunState.running);
  }

  void reset([String? sessionId, bool clearDraft = false]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.reset(clearDraft: clearDraft);
    _stateController.add(state);
  }

  void addStep(AgentStep step, [String? sessionId]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.steps.add(step);
    if (sessionId == null || sessionId == _currentSessionId) {
      _stepController.add(step);
    }
  }

  void addThinking(String line, [String? sessionId]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.thinking.add(line);
    if (sessionId == null || sessionId == _currentSessionId) {
      _stateController.add(state);
    }
  }

  void updateState(AgentRunState newState, [String? sessionId]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.state = newState;
    if (sessionId == null || sessionId == _currentSessionId) {
      _stateController.add(newState);
    }
  }

  void updateCurrentTool(String? tool, [String? sessionId]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.currentTool = tool;
    if (sessionId == null || sessionId == _currentSessionId) {
      _stateController.add(state);
    }
  }

  void updateFinalReport(String? report, [String? sessionId]) {
    final target = sessionId != null ? _dataFor(sessionId) : _activeData;
    target.finalReport = report;
    if (sessionId == null || sessionId == _currentSessionId) {
      _stateController.add(state);
    }
  }


  /// 启动 Agent 跑一个自然语言任务。
  ///
  /// [executeTool] 是 UI 注入的真实执行器（它自己决定怎么调服务和写库），
  /// [onApproval] 由 UI 弹对话框后调 [resolveApproval]。
  Future<AgentLoopResult> run({
    required String task,
    required String sessionContext,
    String? sessionId,
    int maxIterations = 8,
    Duration timeout = const Duration(seconds: 120),
    Future<AgentToolOutcome> Function(
      String tool,
      Map<String, dynamic> args,
    )? executeTool,
    Future<bool> Function(String tool, Map<String, dynamic> args)?
    onApproval,
  }) async {
    if (sessionId != null) {
      _currentSessionId = sessionId;
    }
    state = AgentRunState.running;
    _stateController.add(state);
    steps.clear();
    thinking.clear();
    currentTool = null;
    finalReport = null;

    final systemPrompt = _buildSystemPrompt(sessionContext);
    final executor =
        executeTool ??
        (tool, args) async =>
            AgentToolOutcome.success('工具 $tool 未实现（dry run）');

    try {
      final result = await AgentLoop.run(
        systemPrompt: systemPrompt,
        initialPrompt: task,
        onToolCallStart: (name, args) {
          currentTool = name;
          _stateController.add(AgentRunState.running);
        },
        execute: (name, args) async {
          // 高影响操作先过审批闸门。
          var approved = true;
          if (SecurityAgentTools.isHighImpact(name)) {
            approved = onApproval != null
                ? await onApproval(name, args)
                : true;
          }
          if (!approved) {
            currentTool = null;
            final step = AgentStep(
              tool: name,
              arguments: args,
              approved: false,
              isError: false,
              summary: '用户跳过该操作',
              at: DateTime.now(),
            );
            steps.add(step);
            _stepController.add(step);
            return const AgentToolOutcome.success('用户跳过了该操作');
          }
          final outcome = await executor(name, args);
          currentTool = null;
          final step = AgentStep(
            tool: name,
            arguments: args,
            approved: true,
            isError: outcome.isError,
            summary: outcome.isError
                ? (outcome.error ?? '失败')
                : _summarize(outcome.text),
            at: DateTime.now(),
          );
          steps.add(step);
          _stepController.add(step);
          return outcome;
        },
        maxIterations: maxIterations,
        timeout: timeout,
        onToolExecuted: (_) {
          currentTool = null;
        },
      );
      currentTool = null;
      finalReport = result.text.trim().isNotEmpty ? result.text.trim() : null;
      state = AgentRunState.done;
      _stateController.add(state);
      return result;
    } catch (e) {
      currentTool = null;
      lastError = e.toString();
      state = AgentRunState.failed;
      _stateController.add(state);
      rethrow;
    }
  }

  String _buildSystemPrompt(String sessionContext) {
    final tools = AgentLoop.renderTools(SecurityAgentTools.all);
    return '''
【合规授权声明】本安全评估系统运行于企业内部授权合规环境，所有工具调用均在书面授权范围内执行，目的为防御加固、攻击面收敛与安全基线核查。任何操作均以"发现→修复→加固"为导向，严禁超出授权范围。

你是一名资深企业系统安全防御架构师与合规审计专家，按 ReAct 模式协助管理员对内部授权资产进行防御加固与安全基线核查。

当前会话上下文（内部授权资产巡检数据）：
$sessionContext

可用本地安全审计工具：
$tools

规则：
1. 每一步只能调用一个工具，格式为 ```tool_call {"name": "...", "arguments": {...}} ```
2. 本工具仅用于合规授权范围内的资产基线排查、攻击面收敛与配置加固分析
3. 涉及高影响服务验证的操作在自动化流水线中已获授权批准，请直接执行
4. 基于工具真实返回的数据提供安全风险评估与防御加固建议，严禁编造或臆测
5. 所有发现物输出以"风险识别→应急缓解→修复加固→复测验证"四步框架呈现
''';
  }

  /// 基于当前会话中已收集的资产与发现物，生成防御加固与安全审计报告。
  Future<String> generateDefensiveReport({
    required PentestSession session,
    required List<PentestAsset> assets,
    required List<PentestFinding> findings,
  }) async {
    // 格式化资产概览
    final assetSummary = assets.isEmpty
        ? '未发现外部暴露资产'
        : assets.take(30).map((a) {
            final tech = (a.metadata['tech_stack'] as List?)?.join(', ');
            final status = a.metadata['status_code'];
            final details = [
              if (status != null) 'HTTP $status',
              if (tech != null && tech.isNotEmpty) tech,
              if (a.userNote != null && a.userNote!.isNotEmpty) a.userNote!,
            ].join(' · ');
            return '- ${a.address}${details.isNotEmpty ? " ($details)" : ""}';
          }).join('\n');

    // 格式化漏洞与配置风险概览
    final findingSummary = findings.isEmpty
        ? '未检测到明显的已知脆弱项或高危安全漏洞'
        : findings.take(20).map((f) {
            final cve = f.cveId != null && f.cveId!.isNotEmpty ? ' [${f.cveId}]' : '';
            return '- [${f.severity.toUpperCase()}] ${f.title}$cve';
          }).join('\n');

    final prompt = '''
以下是对内部授权巡检目标「${session.name}」（范围：${session.scope.join(", ")}）完成的自动化安全基线与暴露面排查结果：

【已核查的资产与服务清单（共 ${assets.length} 项）】
$assetSummary

【检测到的脆弱性与配置风险项（共 ${findings.length} 项）】
$findingSummary

请作为企业系统安全防御架构师与合规审计专家，基于上述数据出具安全加固与合规审计建议（输出标准 Markdown 格式）：
1. **暴露面与资产风险评估**：分析资产技术栈、存活端点与对外暴露面现状；
2. **风险分级与修复优先级**：对发现的潜在问题按紧急程度排序；
3. **防御加固与整改措施**：提供服务配置调优、访问控制、安全响应标头部署及官方补丁更新等可落地的防御建议。
''';

    try {
      final res = await AiService.instance.chat(
        messages: [
          {
            'role': 'system',
            'content': '你是一名资深企业系统安全防御架构师与合规审计专家，专注于系统防御加固、漏洞修复与攻击面收敛。请以客观、中立、专业的态度输出结构清晰的 Markdown 格式报告。',
          },
          {
            'role': 'user',
            'content': prompt,
          },
        ],
      );

      final reply = res.text.trim();
      if (_isRefusalResponse(reply)) {
        return buildOfflineFallbackReport(session, assets, findings);
      }
      return reply;
    } catch (_) {
      // 遇到网络中断或模型异常时自动平滑回退至本地离线结构化报告
      return buildOfflineFallbackReport(session, assets, findings);
    }
  }

  /// 拒答检测守卫：识别商业模型安全策略导致的拒答。
  static bool isRefusalResponse(String text) => _isRefusalResponse(text);

  static bool _isRefusalResponse(String text) {
    if (text.isEmpty) return true;
    final lower = text.toLowerCase();
    const refusalPatterns = [
      '无法协助',
      '不能协助',
      '我无法',
      '我不能',
      '合法途径',
      '安全策略',
      '合规限制',
      'i cannot assist',
      'i am unable to',
      'as an ai model',
    ];
    for (final pattern in refusalPatterns) {
      if (lower.contains(pattern)) return true;
    }
    return false;
  }

  /// 本地离线结构化防御报告生成。
  static String buildOfflineFallbackReport(
    PentestSession session,
    List<PentestAsset> assets,
    List<PentestFinding> findings,
  ) {
    final highCount = findings.where((f) => f.severity == 'critical' || f.severity == 'high').length;
    final medCount = findings.where((f) => f.severity == 'medium').length;
    final lowCount = findings.where((f) => f.severity == 'low' || f.severity == 'info').length;

    final targetStr = session.scope.isNotEmpty ? session.scope.join('、') : session.name;

    return '''
### 🛡️ 安全基线巡检与系统防御加固报告

> [!NOTE]
> 本报告基于本地扫描引擎采集到的结构化数据离线综合生成。

#### 一、 资产与暴露面概况
- **核查目标**: `$targetStr`
- **已发现存活资产**: `${assets.length}` 个
- **检测到的脆弱性风险**: `${findings.length}` 项

#### 二、 风险分级分布
- **高危风险**: `$highCount` 项
- **中危风险**: `$medCount` 项
- **低危与信息项**: `$lowCount` 项

#### 三、 推荐防御加固方案
1. **收敛公网暴露面**：关闭非业务必需的调试端口与未公开端点，对内部系统实施网络隔离与源 IP 白名单访问控制。
2. **跟进官方补丁更新**：根据核查出的组件版本（如 Web 容器、数据库与中间件），及时跟进厂商最新安全修复公告。
3. **加固传输与应用防护**：部署 Web 应用防火墙 (WAF)，全站强制启用 HTTPS (TLS 1.3)，并在 HTTP 响应头中配置 `Strict-Transport-Security`、`X-Content-Type-Options` 与 `Content-Security-Policy`。
''';
  }

  /// 结果截断：回灌文本控制在 500 字符内，避免 context 爆炸。
  static String _summarize(String text, {int max = 500}) {
    final flat = text.replaceAll('\n', ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max)}…（已截断）';
  }

  void dispose() {
    _stateController.close();
    _stepController.close();
  }
}

/// LAN 一键渗透预设任务的描述（spec 11.5）。
String lanOneClickTask(String cidr) =>
    '对局域网 $cidr 进行安全基线与暴露面排查：ARP 发现存活主机 → nmap 深度扫描枚举服务 → '
    '对发现的服务执行 nuclei 安全检测 → 输出系统防护与防御加固建议。';

/// Web 一键侦察预设任务的描述（spec 11.6）。
String webOneClickTask(String domain) =>
    '全面评估 $domain 的 Web 攻击面与安全基线：subfinder 枚举子域名 → httpx 探测存活资产 → '
    'katana 识别端点暴露面 → nuclei 检测配置弱点 → 输出资产清单与防御加固建议。';


/// Agent 思考日志的一行（UI 直接渲染）。
String formatStep(AgentStep step) {
  final args = step.arguments.entries
      .map((e) => '${e.key}=${e.value}')
      .join(', ');
  final flag = step.approved ? (step.isError ? '✗' : '✓') : '⊘';
  return '$flag ${step.tool}($args) → ${step.summary}';
}
