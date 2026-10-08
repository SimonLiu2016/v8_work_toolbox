/// 渗透会话相关枚举与取值校验。
///
/// 这些字符串会原样落库（drift 表里全是 TEXT 列），散落的字面量一旦漂移，
/// 读取端的过滤条件就会静默失配——不报错，只是查不到东西。所有写入与查询统一
/// 走这里的常量。
library;

/// 会话类型。
abstract final class SessionType {
  static const String lan = 'lan';
  static const String web = 'web';

  static const List<String> values = [lan, web];

  static String labelOf(String type) => switch (type) {
    lan => '局域网',
    web => 'Web 资产',
    _ => type,
  };
}

/// 会话状态。
abstract final class SessionStatus {
  static const String active = 'active';
  static const String paused = 'paused';
  static const String complete = 'complete';

  static const List<String> values = [active, paused, complete];

  static String labelOf(String status) => switch (status) {
    active => '进行中',
    paused => '已暂停',
    complete => '已完成',
    _ => status,
  };
}

/// 风险/严重等级。由高到低排列，UI 排序与筛选都依赖这个顺序。
enum Severity {
  critical('critical', '严重'),
  high('high', '高危'),
  medium('medium', '中危'),
  low('low', '低危'),
  info('info', '信息');

  final String key;
  final String label;

  const Severity(this.key, this.label);

  static Severity fromKey(String? key) {
    for (final s in Severity.values) {
      if (s.key == key) return s;
    }
    return Severity.info;
  }

  static Severity fromCvss(double? score) {
    if (score == null) return Severity.info;
    if (score >= 9.0) return Severity.critical;
    if (score >= 7.0) return Severity.high;
    if (score >= 4.0) return Severity.medium;
    return Severity.low;
  }

  static const List<Severity> ordered = [
    Severity.critical,
    Severity.high,
    Severity.medium,
    Severity.low,
    Severity.info,
  ];

  int get sortIndex => Severity.ordered.indexOf(this);
}

/// Finding 状态。
abstract final class FindingStatus {
  static const String open = 'open';
  static const String verified = 'verified';
  static const String exploited = 'exploited';
  static const String falsePositive = 'false_positive';

  static String labelOf(String status) => switch (status) {
    open => '待验证',
    verified => '已确认',
    exploited => '已利用',
    falsePositive => '误报',
    _ => status,
  };
}

/// Finding 来源。
abstract final class FindingSource {
  static const String nuclei = 'nuclei';
  static const String manual = 'manual';
  static const String intelMatch = 'intel_match';
  static const String msf = 'msf';
  static const String sqlmap = 'sqlmap';
  static const String nmap = 'nmap';

  static String labelOf(String source) => switch (source) {
    nuclei => 'nuclei',
    manual => '手动录入',
    intelMatch => '情报匹配',
    msf => 'Metasploit',
    sqlmap => 'sqlmap',
    nmap => 'nmap',
    _ => source,
  };
}

/// 资产类型。
abstract final class AssetType {
  static const String host = 'host';
  static const String url = 'url';

  static String labelOf(String type) =>
      type == host ? '主机' : type == url ? 'URL' : type;
}

/// 时间线事件类型。
abstract final class TimelineEventType {
  static const String toolRun = 'tool_run';
  static const String aiAnalysis = 'ai_analysis';
  static const String statusChange = 'status_change';
  static const String findingUpdate = 'finding_update';

  static const List<String> values = [
    toolRun,
    aiAnalysis,
    statusChange,
    findingUpdate,
  ];

  static String labelOf(String type) => switch (type) {
    toolRun => '工具执行',
    aiAnalysis => 'AI 分析',
    statusChange => '状态变更',
    findingUpdate => '发现物更新',
    _ => type,
  };
}

/// 工具用途分类（对应 spec 的 `lan_recon / web_recon / vuln_scan /
/// exploit / intel / script`）。
enum ToolPurpose {
  lanRecon('lan_recon', '局域网侦察'),
  webRecon('web_recon', 'Web 侦察'),
  vulnScan('vuln_scan', '漏洞扫描'),
  exploit('exploit', '漏洞利用'),
  intel('intel', '威胁情报'),
  script('script', '脚本辅助');

  final String key;
  final String label;

  const ToolPurpose(this.key, this.label);
}
