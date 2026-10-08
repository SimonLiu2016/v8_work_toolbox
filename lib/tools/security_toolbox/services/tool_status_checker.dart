import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/security_enums.dart';

import 'security_process_runner.dart';
import 'security_tool_registry.dart';

/// 单个工具的探测结论。
enum ToolStatus {
  /// 已安装且满足最低版本。
  ready,

  /// 已安装但版本过旧。
  outdated,

  /// 未安装（which 未命中）。
  missing;

  String get label => switch (this) {
    ToolStatus.ready => '已就绪',
    ToolStatus.outdated => '需更新',
    ToolStatus.missing => '未安装',
  };
}

/// [ToolStatus] 加版本号。
@immutable
class ToolProbe {
  final String toolId;
  final ToolStatus status;

  /// 探测到的版本字符串，未安装为 null。
  final String? version;

  /// 可执行文件绝对路径，未安装为 null。
  final String? path;

  /// 探测失败原因（超时、命令异常）。
  final String? error;

  const ToolProbe({
    required this.toolId,
    required this.status,
    this.version,
    this.path,
    this.error,
  });

  /// 未安装的构造器。[ToolProbe.missing] 在调用点比 `ToolProbe(status: ToolStatus.missing)`
  /// 更短也更不容易写错。
  const ToolProbe.missing(this.toolId, {this.error})
    : status = ToolStatus.missing,
      version = null,
      path = null;

  bool get isReady => status == ToolStatus.ready;
}

/// 工具状态探测器。
///
/// 对每个工具并行跑 `which` + 版本命令，5 秒超时（spec 要求"在 5 秒内完成"）。
/// 全部走纯函数静态方法，UI 层可以直接 `await`，不需要持有实例。
abstract final class ToolStatusChecker {
  static const Duration probeTimeout = Duration(seconds: 5);

  /// 探测单个工具。
  ///
  /// [resolvePath] 可注入以在测试中替换 PATH 查找；传 null 走真实文件系统。
  static Future<ToolProbe> probe(
    SecurityTool tool, {
    String? Function(String executable)? resolvePath,
  }) async {
    final resolver = resolvePath ?? resolveExecutable;
    final path = resolver(tool.executable);
    if (path == null) {
      return ToolProbe.missing(tool.id);
    }
    final result = await runCaptured(
      path,
      [tool.versionArg],
      timeout: probeTimeout,
    );
    if (result.timedOut) {
      return ToolProbe(
        toolId: tool.id,
        // 超时不代表没装：版本命令可能只是挂着。按"已安装"报，版本未知。
        status: ToolStatus.ready,
        path: path,
        error: '版本探测超时（已安装）',
      );
    }
    final version = extractVersion('${result.stdout}\n${result.stderr}');
    final status = classify(tool, version);
    return ToolProbe(
      toolId: tool.id,
      status: status,
      version: version,
      path: path,
    );
  }

  /// 探测全部受管工具（并行）。
  static Future<Map<String, ToolProbe>> probeAll({
    List<SecurityTool>? tools,
    String? Function(String executable)? resolvePath,
  }) async {
    final list = tools ?? SecurityToolRegistry.tools;
    final entries = await Future.wait(
      list.map((t) => probe(t, resolvePath: resolvePath)),
    );
    return {for (final p in entries) p.toolId: p};
  }

  /// 按最低版本判定三态。
  ///
  /// 版本号解析失败（工具输出了大段 help 文本）时不升级为 outdated——用户机器上
  /// 能跑起来的工具不该被判成"需更新"。
  @visibleForTesting
  static ToolStatus classify(SecurityTool tool, String? version) {
    if (version == null) return ToolStatus.ready;
    final min = tool.minVersion;
    if (min == null) return ToolStatus.ready;
    final current = parseVersion(version);
    final required = parseVersion(min);
    if (current == null || required == null) return ToolStatus.ready;
    return compareVersions(version, min) >= 0
        ? ToolStatus.ready
        : ToolStatus.outdated;
  }

  /// 解析 `1.2.3` 为三元组；缺省段补 0。无法解析返回 null。
  static List<int>? parseVersion(String raw) {
    final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(raw);
    if (match == null) return null;
    final a = int.tryParse(match.group(1) ?? '');
    final b = int.tryParse(match.group(2) ?? '');
    final c = int.tryParse(match.group(3) ?? '0') ?? 0;
    if (a == null || b == null) return null;
    return [a, b, c];
  }

  /// 从任意工具输出里抠出第一处 `x.y.z`。
  @visibleForTesting
  static String? extractVersion(String text) {
    final match = RegExp(r'(\d+\.\d+(?:\.\d+)?)').firstMatch(text);
    return match?.group(1);
  }

  /// 比较 `1.2.3` 与 `1.10.0`：按段数值比较，不是字符串比较
  /// （"1.10" < "1.9" 的字典序结论在这里是错的）。
  @visibleForTesting
  static int compareVersions(String a, String b) {
    final pa = parseVersion(a);
    final pb = parseVersion(b);
    if (pa == null || pb == null) return 0;
    for (var i = 0; i < 3; i++) {
      final c = pa[i].compareTo(pb[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}

/// Homebrew 可用性。
abstract final class HomebrewDetector {
  static Future<bool> isAvailable() async {
    final result = await runCaptured('which', ['brew'], timeout: const Duration(seconds: 3));
    return result.success && result.stdout.trim().isNotEmpty;
  }

  static String? brewPath() => resolveExecutable('brew');

  static const String installUrl = 'https://brew.sh';
}

/// 把探测结果映射回工具清单，供 UI 渲染。
class ToolStatusBoard {
  final Map<String, ToolProbe> probes;
  final bool brewAvailable;
  final DateTime checkedAt;

  const ToolStatusBoard({
    required this.probes,
    required this.brewAvailable,
    required this.checkedAt,
  });

  /// 首屏占位：没有任何探测结果。UI 拿到它时显示"检测中"。
  static final empty = ToolStatusBoard(
    probes: const {},
    brewAvailable: false,
    checkedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

  ToolProbe? probeOf(String toolId) => probes[toolId];

  int countOf(ToolStatus status) =>
      probes.values.where((p) => p.status == status).length;

  int get readyCount => countOf(ToolStatus.ready);
  int get outdatedCount => countOf(ToolStatus.outdated);
  int get missingCount => countOf(ToolStatus.missing);

  bool get allReady =>
      probes.isNotEmpty && probes.values.every((p) => p.isReady);

  ToolStatusBoard copyWith({
    Map<String, ToolProbe>? probes,
    bool? brewAvailable,
    DateTime? checkedAt,
  }) {
    return ToolStatusBoard(
      probes: probes ?? this.probes,
      brewAvailable: brewAvailable ?? this.brewAvailable,
      checkedAt: checkedAt ?? this.checkedAt,
    );
  }
}

/// 供 UI 分组：按用途列出该分类下的工具。
List<SecurityTool> toolsForPurpose(
  ToolPurpose purpose, {
  List<SecurityTool>? source,
}) {
  final list = source ?? SecurityToolRegistry.tools;
  return list.where((t) => t.purpose == purpose).toList();
}

/// 工具展示用的简短说明（面板里跟在名字后面那行小字）。
String toolHint(String id) => switch (id) {
  'nmap' => '端口扫描 · 服务与 OS 指纹',
  'arp-scan' => 'ARP 层主机发现',
  'masscan' => '超高速全网段端口扫描',
  'nuclei' => '模板化漏洞扫描',
  'subfinder' => '被动子域名枚举',
  'httpx' => 'HTTP 存活探测与技术栈识别',
  'katana' => 'JS 感知爬虫',
  'ffuf' => '目录与文件爆破',
  'sqlmap' => '自动化 SQL 注入检测',
  'gau' => '历史 URL 获取',
  'metasploit' => '漏洞利用框架',
  'bettercap' => '网络中间人与抓包',
  'netexec' => '网络服务口令喷洒与枚举',
  'searchsploit' => 'ExploitDB 本地检索',
  _ => '',
};

/// 把 json 编码工具清单（供 Agent 工具集描述复用）。
String toolCatalogJson({List<SecurityTool>? tools}) {
  final list = tools ?? SecurityToolRegistry.tools;
  return jsonEncode([
    for (final t in list)
      {'id': t.id, 'name': t.displayName, 'purpose': t.purpose.key},
  ]);
}
