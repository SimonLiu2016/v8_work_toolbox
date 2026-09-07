import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// 无人值守状态模型
class UnattendedState {
  final bool enabled;
  final DateTime? since;
  final DateTime? expiresAt;
  final int ttlMinutes;
  final List<String> denylist;
  final bool keepSystemAwake;
  final bool keepDisplayAwake;

  const UnattendedState({
    required this.enabled,
    this.since,
    this.expiresAt,
    this.ttlMinutes = 120,
    this.denylist = defaultDenylist,
    this.keepSystemAwake = true,
    this.keepDisplayAwake = true,
  });

  /// 默认不可逾越的机械安全硬地板 (rm 命令由独立作用域解析器精确保护)
  static const List<String> defaultDenylist = [
    r'git\s+push\s+.*(--force|-f\b)',             // 破坏性 Git 远端分支强制覆盖
    r'git\s+reset\s+--hard',                      // 破坏性本地 Git 历史硬重置
    r'git\s+clean\s+-[a-zA-Z]*f',                 // 强制清除未跟踪文件与目录
    r'>\s*(\.env|.*\.pem|.*\.key|.*id_rsa)',      // 覆写或重定向到敏感凭证文件
    r'(curl|wget)\s+.*\|\s*(bash|sh|zsh)',        // 管道下载并执行远程不受信脚本
    r':\(\)\s*\{\s*:\s*\|\s*:\s*&\s*\}\s*;\s*:', // 经典 Bash Fork 炸弹
    r'(\bmkfs\b|\bdd\s+if=)',                     // 格式化与块设备抹除
    r'\b(shutdown|reboot|halt)\b',                // 系统关机与重启
  ];

  /// 是否在有效期内真正处于活跃状态
  bool get isEffectivelyActive {
    if (!enabled || expiresAt == null) return false;
    return DateTime.now().isBefore(expiresAt!);
  }

  /// 距离过期的剩余时长
  Duration get remainingTime {
    if (!isEffectivelyActive) return Duration.zero;
    final diff = expiresAt!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'since': since?.toIso8601String(),
    'expiresAt': expiresAt?.toIso8601String(),
    'ttlMinutes': ttlMinutes,
    'denylist': denylist,
    'keepSystemAwake': keepSystemAwake,
    'keepDisplayAwake': keepDisplayAwake,
  };

  factory UnattendedState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic val) {
      if (val is String && val.isNotEmpty) {
        try { return DateTime.parse(val); } catch (_) {}
      }
      return null;
    }

    final rawDenylist = json['denylist'];
    final list = rawDenylist is List
        ? rawDenylist.map((e) => e.toString()).toList()
        : defaultDenylist;

    return UnattendedState(
      enabled: json['enabled'] == true,
      since: parseDate(json['since']),
      expiresAt: parseDate(json['expiresAt']),
      ttlMinutes: json['ttlMinutes'] is int ? json['ttlMinutes'] as int : 120,
      denylist: list,
      keepSystemAwake: json['keepSystemAwake'] != false,
      keepDisplayAwake: json['keepDisplayAwake'] != false,
    );
  }

  UnattendedState copyWith({
    bool? enabled,
    DateTime? since,
    DateTime? expiresAt,
    int? ttlMinutes,
    List<String>? denylist,
    bool? keepSystemAwake,
    bool? keepDisplayAwake,
  }) {
    return UnattendedState(
      enabled: enabled ?? this.enabled,
      since: since ?? this.since,
      expiresAt: expiresAt ?? this.expiresAt,
      ttlMinutes: ttlMinutes ?? this.ttlMinutes,
      denylist: denylist ?? this.denylist,
      keepSystemAwake: keepSystemAwake ?? this.keepSystemAwake,
      keepDisplayAwake: keepDisplayAwake ?? this.keepDisplayAwake,
    );
  }
}

/// 审计流水条目
class AuditRecord {
  final DateTime timestamp;
  final String client;
  final String toolName;
  final String command;
  final String decision; // 'allow' or 'deny'
  final String reason;

  const AuditRecord({
    required this.timestamp,
    required this.client,
    required this.toolName,
    required this.command,
    required this.decision,
    required this.reason,
  });

  bool get isAllowed => decision == 'allow';
  bool get isDenied => decision == 'deny';

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'client': client,
    'toolName': toolName,
    'command': command,
    'decision': decision,
    'reason': reason,
  };

  factory AuditRecord.fromJson(Map<String, dynamic> json) {
    DateTime ts = DateTime.now();
    if (json['timestamp'] is String) {
      try { ts = DateTime.parse(json['timestamp'] as String); } catch (_) {}
    }
    return AuditRecord(
      timestamp: ts,
      client: (json['client'] as String?) ?? 'unknown',
      toolName: (json['toolName'] as String?) ?? 'Bash',
      command: (json['command'] as String?) ?? '',
      decision: (json['decision'] as String?) ?? 'allow',
      reason: (json['reason'] as String?) ?? '',
    );
  }
}

/// 客户端 Hook 安装状态
class ClientHookStatus {
  final bool claudeInstalled;
  final bool agyInstalled;
  final bool geminiInstalled;
  final String claudeSettingsPath;
  final String agyHooksPath;
  final String geminiSettingsPath;

  const ClientHookStatus({
    required this.claudeInstalled,
    required this.agyInstalled,
    this.geminiInstalled = false,
    required this.claudeSettingsPath,
    required this.agyHooksPath,
    this.geminiSettingsPath = '',
  });

  bool get isAllInstalled => claudeInstalled && agyInstalled && (geminiSettingsPath.isEmpty || geminiInstalled);
}

/// 路径安全性评估
class TargetSafety {
  final bool isSafe;
  final String? reason;
  const TargetSafety(this.isSafe, [this.reason]);
}

/// rm 作用域检测结果
class ScopeCheckResult {
  final bool isDestructiveRm;
  final bool isSafe;
  final String? blockedTarget;
  final String? reason;

  const ScopeCheckResult({
    required this.isDestructiveRm,
    required this.isSafe,
    this.blockedTarget,
    this.reason,
  });
}

/// 授权判定结果
class ApprovalEvaluationResult {
  final bool isAllowed;
  final String reason;
  final String? matchedPattern;

  const ApprovalEvaluationResult({
    required this.isAllowed,
    required this.reason,
    this.matchedPattern,
  });
}

/// 无人值守核心服务 (单例)
class UnattendedService extends ChangeNotifier {
  UnattendedService._();
  static final UnattendedService instance = UnattendedService._();

  UnattendedState _state = const UnattendedState(enabled: false);
  UnattendedState get state => _state;

  Timer? _countdownTimer;
  bool _initialized = false;

  /// 自定义或系统默认目录
  String get _home => Platform.environment['HOME'] ?? '';
  String get v8RootPath => '$_home/.v8worktoolbox';
  String get unattendedDirPath => '$v8RootPath/unattended';
  String get stateFilePath => customStateFilePath ?? '$unattendedDirPath/state.json';
  String get auditFilePath => customAuditFilePath ?? '$unattendedDirPath/audit.jsonl';
  String get binDirPath => customBinDirPath ?? '$v8RootPath/bin';
  String get proxyScriptPath => '$binDirPath/v8-approval-proxy';
  String get proxyJsPath => '$binDirPath/v8-approval-proxy.js';

  String? customClaudeSettingsPath;
  String? customAgyHooksPath;
  String? customGeminiSettingsPath;
  String? customAgySettingsPath;
  String? customAgyProjectPath;
  String? customStateFilePath;
  String? customAuditFilePath;
  String? customBinDirPath;

  String get claudeSettingsPath => customClaudeSettingsPath ?? '$_home/.claude/settings.json';
  String get agyHooksPath => customAgyHooksPath ?? '$_home/.gemini/config/hooks.json';
  String get geminiSettingsPath => customGeminiSettingsPath ?? '$_home/.gemini/settings.json';
  String get agySettingsPath => customAgySettingsPath ?? '$_home/.gemini/antigravity-cli/settings.json';
  String get agyProjectPath => customAgyProjectPath ?? '$_home/.gemini/config/projects/default-cli-project.json';

  /// 初始化服务：创建目录、读取持久化状态并开启倒计时心跳
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final uDir = Directory(unattendedDirPath);
      if (!uDir.existsSync()) {
        uDir.createSync(recursive: true);
      }
      final bDir = Directory(binDirPath);
      if (!bDir.existsSync()) {
        bDir.createSync(recursive: true);
      }
    } catch (_) {}

    await _loadState();
    await ensureProxyScriptInstalled();

    // 启动秒级心跳 Timer，驱动 UI 倒计时渲染与惰性超时检测
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_state.enabled) {
        if (!_state.isEffectivelyActive) {
          // 惰性超时自动关闭
          disable(silentReason: 'ttl_expired');
        } else {
          notifyListeners();
        }
      }
    });
  }

  /// 从磁盘读取状态
  Future<void> _loadState() async {
    final file = File(stateFilePath);
    if (file.existsSync()) {
      try {
        final content = file.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        _state = UnattendedState.fromJson(json);

        // 启动时检查是否已经过期
        if (_state.enabled && !_state.isEffectivelyActive) {
          _state = _state.copyWith(enabled: false);
          _saveState();
          await uninstallClientHooks();
        } else if (_state.isEffectivelyActive) {
          _startKeepAwakeIfActive();
        }
      } catch (_) {
        _state = const UnattendedState(enabled: false);
      }
    } else {
      _state = const UnattendedState(enabled: false);
      _saveState();
    }
    notifyListeners();
  }

  /// 写入状态到磁盘
  void _saveState() {
    try {
      final file = File(stateFilePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_state.toJson()));
    } catch (_) {}
  }

  Process? _caffeinateProcess;
  bool get isCaffeinateActive => _caffeinateProcess != null;

  /// 开启无人值守模式 (原子注入各客户端 Hook)
  Future<void> enable({
    required int ttlMinutes,
    bool? keepSystemAwake,
    bool? keepDisplayAwake,
  }) async {
    final now = DateTime.now();
    final expires = now.add(Duration(minutes: ttlMinutes));

    _state = _state.copyWith(
      enabled: true,
      since: now,
      expiresAt: expires,
      ttlMinutes: ttlMinutes,
      keepSystemAwake: keepSystemAwake ?? _state.keepSystemAwake,
      keepDisplayAwake: keepDisplayAwake ?? _state.keepDisplayAwake,
    );
    _saveState();
    await ensureProxyScriptInstalled();
    await installClientHooks();
    await _startKeepAwakeIfActive();
    notifyListeners();
  }

  /// 关闭无人值守模式 (完全移除各客户端 Hook 恢复零干预环境)
  Future<void> disable({String? silentReason}) async {
    _state = _state.copyWith(enabled: false);
    _saveState();
    _stopKeepAwake();
    await uninstallClientHooks();
    notifyListeners();
  }

  /// 切换“保持屏幕常亮”设置
  Future<void> setKeepDisplayAwake(bool value) async {
    if (_state.keepDisplayAwake == value) return;
    _state = _state.copyWith(keepDisplayAwake: value);
    _saveState();
    if (_state.isEffectivelyActive) {
      await _startKeepAwakeIfActive();
    }
    notifyListeners();
  }

  /// 切换“防止系统休眠”设置
  Future<void> setKeepSystemAwake(bool value) async {
    if (_state.keepSystemAwake == value) return;
    _state = _state.copyWith(keepSystemAwake: value);
    _saveState();
    if (_state.isEffectivelyActive) {
      await _startKeepAwakeIfActive();
    }
    notifyListeners();
  }

  /// 启动 macOS 随行 caffeinate 进程以防止休眠/息屏
  Future<void> _startKeepAwakeIfActive() async {
    _stopKeepAwake();

    if (!Platform.isMacOS) return;
    if (!_state.isEffectivelyActive) return;
    if (!_state.keepSystemAwake && !_state.keepDisplayAwake) return;

    final secondsRemaining = _state.remainingTime.inSeconds;
    if (secondsRemaining <= 0) return;

    final args = <String>[];
    if (_state.keepSystemAwake) {
      args.add('-i'); // 阻止系统空闲休眠
    }
    if (_state.keepDisplayAwake) {
      args.add('-d'); // 阻止显示器休眠
    }

    // 绑定当前应用 PID：若应用关闭或崩溃，macOS 自动终结 caffeinate
    final currentPid = pid;
    args.addAll(['-w', currentPid.toString()]);

    // 设置超时秒数双保险
    args.addAll(['-t', secondsRemaining.toString()]);

    try {
      final proc = await Process.start('/usr/bin/caffeinate', args);
      _caffeinateProcess = proc;
      proc.exitCode.then((_) {
        if (_caffeinateProcess == proc) {
          _caffeinateProcess = null;
        }
      });
    } catch (_) {
      _caffeinateProcess = null;
    }
  }

  /// 停止 caffeinate 进程
  void _stopKeepAwake() {
    try {
      _caffeinateProcess?.kill();
    } catch (_) {}
    _caffeinateProcess = null;
  }



  /// 更新安全硬地板黑名单规则
  Future<void> updateDenylist(List<String> newDenylist) async {
    _state = _state.copyWith(denylist: List.from(newDenylist));
    _saveState();
    notifyListeners();
  }

  /// 重置安全硬地板为系统预设
  Future<void> resetDenylistToDefaults() async {
    _state = _state.copyWith(denylist: UnattendedState.defaultDenylist);
    _saveState();
    notifyListeners();
  }

  /// 参数拆分器（尊重单双引号）
  static List<String> tokenizeArgs(String str) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    bool inSingle = false;
    bool inDouble = false;

    for (int i = 0; i < str.length; i++) {
      final c = str[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (c == ' ' && !inSingle && !inDouble) {
        if (buffer.isNotEmpty) {
          tokens.add(buffer.toString());
          buffer.clear();
        }
      } else {
        buffer.write(c);
      }
    }
    if (buffer.isNotEmpty) {
      tokens.add(buffer.toString());
    }
    return tokens;
  }

  /// 目标路径安全性检验
  static TargetSafety isTargetSafe(String rawTarget, String cwd, String home) {
    var target = rawTarget.trim();
    if (target.startsWith("'") && target.endsWith("'") && target.length >= 2) {
      target = target.substring(1, target.length - 1);
    } else if (target.startsWith('"') && target.endsWith('"') && target.length >= 2) {
      target = target.substring(1, target.length - 1);
    }
    target = target.trim();
    if (target.isEmpty) return const TargetSafety(true);

    if (target.startsWith('~')) {
      target = target.replaceFirst('~', home);
    } else if (target.startsWith(r'$HOME')) {
      target = target.replaceFirst(r'$HOME', home);
    }

    final resolved = p.isAbsolute(target)
        ? p.normalize(target)
        : p.normalize(p.join(cwd, target));
    final normCwd = p.normalize(cwd);
    final normHome = p.normalize(home);

    // 1. 绝对禁区：系统根、家目录根、系统核心目录、敏感凭证
    final forbiddenRoots = [
      '/',
      normHome,
      '/Users',
      '/System',
      '/Library',
      '/usr',
      '/bin',
      '/sbin',
      '/etc',
      '/opt',
      '/var',
      p.normalize('$normHome/.ssh'),
      p.normalize('$normHome/.gnupg'),
      p.normalize('$normHome/.aws'),
    ];

    for (final fb in forbiddenRoots) {
      if (fb.isNotEmpty && resolved == fb) {
        return TargetSafety(false, 'Target is forbidden root or sensitive directory: $target ($resolved)');
      }
    }

    // 禁止直接删除整个工作区根目录 (如 rm -rf .)
    if (resolved == normCwd) {
      return TargetSafety(false, 'Target is workspace root itself: $target ($resolved)');
    }

    // 2. 放行安全区域：
    // (a) 工作区内部子目录/文件
    if (p.isWithin(normCwd, resolved)) {
      return const TargetSafety(true);
    }

    // (b) 系统临时目录 (/tmp, /var/tmp, /var/folders, TMPDIR)
    final tmpDir = Platform.environment['TMPDIR'];
    if (p.isWithin('/tmp', resolved) ||
        p.isWithin('/var/tmp', resolved) ||
        p.isWithin('/var/folders', resolved) ||
        (tmpDir != null && tmpDir.isNotEmpty && p.isWithin(p.normalize(tmpDir), resolved))) {
      return const TargetSafety(true);
    }

    // (c) V8 自身沙箱目录 ~/.v8worktoolbox/
    final v8Dir = p.normalize('$normHome/.v8worktoolbox');
    if (p.isWithin(v8Dir, resolved)) {
      return const TargetSafety(true);
    }

    // 其它超出工作区且非临时目录的目标坚决拦截
    return TargetSafety(false, 'Target is outside workspace and not in temp directory: $target ($resolved)');
  }

  /// rm 作用域评估
  static ScopeCheckResult evaluateRmScope(String command, String cwd, String home) {
    final subcommands = command.split(RegExp(r'(&&|\|\||;|\|)'));
    for (final sub in subcommands) {
      final trimmed = sub.trim();
      final rmMatch = RegExp(r'\brm\s+([^;]+)').firstMatch(trimmed);
      if (rmMatch == null) continue;

      final argsStr = rmMatch.group(1) ?? '';
      final tokens = tokenizeArgs(argsStr);
      bool isRecursive = false;
      bool isForce = false;
      final targets = <String>[];

      for (final token in tokens) {
        if (token.startsWith('-')) {
          if (token == '-r' || token == '-R' || token == '--recursive') {
            isRecursive = true;
          } else if (token == '-f' || token == '--force') {
            isForce = true;
          } else if (RegExp(r'^-[a-zA-Z]+$').hasMatch(token)) {
            if (token.contains('r') || token.contains('R')) isRecursive = true;
            if (token.contains('f')) isForce = true;
          }
        } else {
          targets.add(token);
        }
      }

      if (isRecursive || isForce) {
        if (targets.isEmpty) continue;
        for (final target in targets) {
          final res = isTargetSafe(target, cwd, home);
          if (!res.isSafe) {
            return ScopeCheckResult(
              isDestructiveRm: true,
              isSafe: false,
              blockedTarget: target,
              reason: res.reason,
            );
          }
        }
      }
    }

    return const ScopeCheckResult(isDestructiveRm: false, isSafe: true);
  }

  /// 命令授权安全评估引擎 (Dart 实现，与 Proxy 脚本同源)
  ApprovalEvaluationResult evaluateCommand(
    String command, {
    String? cwd,
    String client = 'claude',
    String tool = 'Bash',
  }) {
    if (!_state.isEffectivelyActive) {
      return const ApprovalEvaluationResult(isAllowed: false, reason: 'unattended_inactive_or_expired');
    }

    final effectiveCwd = cwd ?? Directory.current.path;
    final home = _home;

    // 1. 作用域感知检测：针对 rm 破坏性删除命令精细判定
    final rmCheck = evaluateRmScope(command, effectiveCwd, home);
    if (rmCheck.isDestructiveRm && !rmCheck.isSafe) {
      return ApprovalEvaluationResult(
        isAllowed: false,
        reason: 'rm_target_out_of_bounds',
        matchedPattern: rmCheck.reason,
      );
    }

    // 2. 机械安全硬地板黑名单正则扫描
    final trimmed = command.trim();
    for (final pattern in _state.denylist) {
      try {
        final reg = RegExp(pattern, multiLine: true, caseSensitive: false);
        if (reg.hasMatch(trimmed)) {
          return ApprovalEvaluationResult(
            isAllowed: false,
            reason: 'matched_danger_floor',
            matchedPattern: pattern,
          );
        }
      } catch (_) {}
    }

    return const ApprovalEvaluationResult(isAllowed: true, reason: 'unattended_active_and_safe');
  }

  /// 记录审计流水
  Future<void> recordAudit(AuditRecord record) async {
    try {
      final file = File(auditFilePath);
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }
      final line = '${jsonEncode(record.toJson())}\n';
      file.writeAsStringSync(line, mode: FileMode.append, flush: true);
      notifyListeners();
    } catch (_) {}
  }

  /// 加载最新审计日志
  Future<List<AuditRecord>> loadAuditLogs({int limit = 200}) async {
    final file = File(auditFilePath);
    if (!file.existsSync()) return [];

    try {
      final lines = file.readAsLinesSync();
      final records = <AuditRecord>[];
      for (int i = lines.length - 1; i >= 0 && records.length < limit; i--) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;
        try {
          final json = jsonDecode(line) as Map<String, dynamic>;
          records.add(AuditRecord.fromJson(json));
        } catch (_) {}
      }
      return records;
    } catch (_) {
      return [];
    }
  }

  /// 清空审计日志
  Future<void> clearAuditLogs() async {
    try {
      final file = File(auditFilePath);
      if (file.existsSync()) {
        file.writeAsStringSync('');
      }
      notifyListeners();
    } catch (_) {}
  }

  /// 导出审计日志到指定文件路径
  Future<bool> exportAuditLogs(String targetPath) async {
    try {
      final src = File(auditFilePath);
      if (!src.existsSync()) return false;
      src.copySync(targetPath);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 部署并确保可执行代理脚本 (~/.v8worktoolbox/bin/v8-approval-proxy)
  Future<void> ensureProxyScriptInstalled() async {
    try {
      final bDir = Directory(binDirPath);
      if (!bDir.existsSync()) {
        bDir.createSync(recursive: true);
      }

      final proxyJs = File(proxyJsPath);
      proxyJs.writeAsStringSync(_buildProxyJsContent());

      final proxyShell = File(proxyScriptPath);
      proxyShell.writeAsStringSync(_buildProxyShellContent());

      if (Platform.isMacOS || Platform.isLinux) {
        Process.runSync('chmod', ['+x', proxyScriptPath]);
      }
    } catch (_) {}
  }

  /// 检查各客户端 Hook 安装状态
  Future<ClientHookStatus> checkHookInstallation() async {
    bool claudeOk = false;
    bool agyOk = false;
    bool geminiOk = false;

    try {
      final cFile = File(claudeSettingsPath);
      if (cFile.existsSync()) {
        final content = cFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final hooks = json['hooks'];
        if (hooks is Map && hooks['PreToolUse'] is List) {
          final list = hooks['PreToolUse'] as List;
          claudeOk = list.any((item) {
            final subHooks = item['hooks'];
            if (subHooks is List) {
              return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
            }
            return false;
          });
        }
      }
    } catch (_) {}

    try {
      final aFile = File(agyHooksPath);
      if (aFile.existsSync()) {
        final content = aFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final v8Hook = json['v8-unattended'];
        if (v8Hook is Map && v8Hook['enabled'] == true) {
          final preTool = v8Hook['PreToolUse'];
          if (preTool is List) {
            agyOk = preTool.any((item) {
              final subHooks = item['hooks'];
              if (subHooks is List) {
                return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
              }
              return false;
            });
          }
        }
      }
    } catch (_) {}

    final gFile = File(geminiSettingsPath);
    if (gFile.existsSync()) {
      try {
        final content = gFile.readAsStringSync();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final hooks = json['hooks'];
        if (hooks is Map && hooks['BeforeTool'] is List) {
          final list = hooks['BeforeTool'] as List;
          geminiOk = list.any((item) {
            final subHooks = item['hooks'];
            if (subHooks is List) {
              return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
            }
            return false;
          });
        }
      } catch (_) {}
    } else {
      // 若该目标路径不存在（如特定测试目录），默认对齐 agyOk
      geminiOk = agyOk;
    }

    return ClientHookStatus(
      claudeInstalled: claudeOk,
      agyInstalled: agyOk,
      geminiInstalled: geminiOk,
      claudeSettingsPath: claudeSettingsPath,
      agyHooksPath: agyHooksPath,
      geminiSettingsPath: geminiSettingsPath,
    );
  }

  /// 一键向 Claude Code、Antigravity CLI 与 Gemini CLI 幂等安装全局 Hook
  Future<bool> installClientHooks() async {
    await ensureProxyScriptInstalled();

    bool claudeSuccess = false;
    bool agySuccess = false;
    bool geminiSuccess = true;

    // 1. 安装 Claude Code Hook (~/.claude/settings.json)
    try {
      final file = File(claudeSettingsPath);
      Map<String, dynamic> json = {};
      if (file.existsSync()) {
        _backupFile(file);
        try {
          json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          json = {};
        }
      } else {
        file.parent.createSync(recursive: true);
      }

      var hooks = json['hooks'];
      if (hooks is! Map<String, dynamic>) {
        hooks = <String, dynamic>{};
        json['hooks'] = hooks;
      }

      var preToolUse = hooks['PreToolUse'];
      if (preToolUse is! List) {
        preToolUse = [];
        hooks['PreToolUse'] = preToolUse;
      }

      final alreadyInstalled = preToolUse.any((item) {
        final subHooks = item['hooks'];
        if (subHooks is List) {
          return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
        }
        return false;
      });

      if (!alreadyInstalled) {
        preToolUse.add({
          'matcher': 'Bash',
          'hooks': [
            {
              'type': 'command',
              'command': '$proxyScriptPath claude',
            }
          ]
        });
      }

      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      claudeSuccess = true;
    } catch (_) {}

    // 2. 安装 Antigravity CLI Hook (~/.gemini/config/hooks.json)
    try {
      final file = File(agyHooksPath);
      Map<String, dynamic> json = {};
      if (file.existsSync()) {
        _backupFile(file);
        try {
          json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          json = {};
        }
      } else {
        file.parent.createSync(recursive: true);
      }

      json['v8-unattended'] = {
        'enabled': true,
        'PreToolUse': [
          {
            'matcher': 'run_command|run_shell_command',
            'hooks': [
              {
                'type': 'command',
                'command': '$proxyScriptPath agy',
              }
            ]
          }
        ]
      };

      file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
      agySuccess = true;
    } catch (_) {}

    // 2b. 配置 Antigravity CLI 授权策略 (~/.gemini/antigravity-cli/settings.json)
    try {
      final sFile = File(agySettingsPath);
      if (sFile.existsSync()) {
        _backupFile(sFile);
        final sJson = jsonDecode(sFile.readAsStringSync()) as Map<String, dynamic>;
        if (sJson.containsKey('toolPermission') && !sJson.containsKey('toolPermission_v8bak')) {
          sJson['toolPermission_v8bak'] = sJson['toolPermission'];
        }
        sJson['toolPermission'] = 'always-proceed';

        var perms = sJson['permissions'];
        if (perms is! Map<String, dynamic>) {
          perms = <String, dynamic>{};
          sJson['permissions'] = perms;
        }
        var allow = perms['allow'];
        if (allow is! List) {
          allow = [];
          perms['allow'] = allow;
        }
        if (!allow.contains('command(*)')) {
          allow.insert(0, 'command(*)');
        }
        sFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sJson));
      }
    } catch (_) {}

    // 2c. 配置 Antigravity CLI 默认工程授权 (~/.gemini/config/projects/default-cli-project.json)
    try {
      final pFile = File(agyProjectPath);
      if (pFile.existsSync()) {
        _backupFile(pFile);
        final pJson = jsonDecode(pFile.readAsStringSync()) as Map<String, dynamic>;
        var settings = pJson['settings'];
        if (settings is! Map<String, dynamic>) {
          settings = <String, dynamic>{};
          pJson['settings'] = settings;
        }
        settings['autoExecutionPolicy'] = 'CASCADE_COMMANDS_AUTO_EXECUTION_AUTO';

        var permGrants = pJson['permissionGrants'];
        if (permGrants is! Map<String, dynamic>) {
          permGrants = <String, dynamic>{};
          pJson['permissionGrants'] = permGrants;
        }
        var innerPerms = permGrants['permissionGrants'];
        if (innerPerms is! Map<String, dynamic>) {
          innerPerms = <String, dynamic>{};
          permGrants['permissionGrants'] = innerPerms;
        }
        var allowList = innerPerms['allow'];
        if (allowList is! List) {
          allowList = [];
          innerPerms['allow'] = allowList;
        }
        if (!allowList.contains('command(*)')) {
          allowList.insert(0, 'command(*)');
        }
        pFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(pJson));
      }
    } catch (_) {}

    // 3. 安装 / 桥接 Gemini CLI Hook (~/.gemini/settings.json)
    try {
      final file = File(geminiSettingsPath);
      if (file.existsSync() || customGeminiSettingsPath != null) {
        _backupFile(file);
        Map<String, dynamic> json = {};
        try {
          json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {
          json = {};
        }

        var hooks = json['hooks'];
        if (hooks is! Map<String, dynamic>) {
          hooks = <String, dynamic>{};
          json['hooks'] = hooks;
        }

        var beforeTool = hooks['BeforeTool'];
        if (beforeTool is! List) {
          beforeTool = [];
          hooks['BeforeTool'] = beforeTool;
        }

        bool foundV8 = false;
        for (final item in beforeTool) {
          if (item is Map) {
            final subHooks = item['hooks'];
            if (subHooks is List) {
              for (final h in subHooks) {
                if (h is Map) {
                  final cmd = h['command']?.toString() ?? '';
                  if (cmd.contains('v8-approval-proxy')) {
                    foundV8 = true;
                  } else if (cmd.contains('rtk-hook-gemini.sh')) {
                    h['v8_original_command'] = cmd;
                    h['command'] = '$proxyScriptPath agy';
                    foundV8 = true;
                  }
                }
              }
            }
          }
        }

        if (!foundV8) {
          beforeTool.add({
            'matcher': 'run_shell_command',
            'hooks': [
              {
                'type': 'command',
                'command': '$proxyScriptPath agy',
              }
            ]
          });
          beforeTool.add({
            'matcher': 'run_command',
            'hooks': [
              {
                'type': 'command',
                'command': '$proxyScriptPath agy',
              }
            ]
          });
        }

        file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
        geminiSuccess = true;
      }
    } catch (_) {}

    notifyListeners();
    return claudeSuccess && agySuccess && geminiSuccess;
  }

  /// 卸载全局 Hook（保留用户的其他 Hook，完美对称还原）
  Future<bool> uninstallClientHooks() async {
    // 1. 卸载 Claude Code Hook
    try {
      final cFile = File(claudeSettingsPath);
      if (cFile.existsSync()) {
        final json = jsonDecode(cFile.readAsStringSync()) as Map<String, dynamic>;
        final hooks = json['hooks'];
        if (hooks is Map && hooks['PreToolUse'] is List) {
          (hooks['PreToolUse'] as List).removeWhere((item) {
            final subHooks = item['hooks'];
            if (subHooks is List) {
              return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
            }
            return false;
          });
          cFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
        }
      }
    } catch (_) {}

    // 2. 卸载 Antigravity CLI Hook
    try {
      final aFile = File(agyHooksPath);
      if (aFile.existsSync()) {
        final json = jsonDecode(aFile.readAsStringSync()) as Map<String, dynamic>;
        if (json.containsKey('v8-unattended')) {
          json.remove('v8-unattended');
          aFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
        }
      }
    } catch (_) {}

    // 2b. 还原 Antigravity CLI 授权策略 (~/.gemini/antigravity-cli/settings.json)
    try {
      final sFile = File(agySettingsPath);
      if (sFile.existsSync()) {
        final sJson = jsonDecode(sFile.readAsStringSync()) as Map<String, dynamic>;
        if (sJson.containsKey('toolPermission_v8bak')) {
          sJson['toolPermission'] = sJson['toolPermission_v8bak'];
          sJson.remove('toolPermission_v8bak');
        } else if (sJson['toolPermission'] == 'always-proceed') {
          sJson['toolPermission'] = 'proceed-in-sandbox';
        }
        final perms = sJson['permissions'];
        if (perms is Map && perms['allow'] is List) {
          (perms['allow'] as List).removeWhere((e) => e == 'command(*)');
        }
        sFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(sJson));
      }
    } catch (_) {}

    // 2c. 还原 Antigravity CLI 默认工程授权 (~/.gemini/config/projects/default-cli-project.json)
    try {
      final pFile = File(agyProjectPath);
      if (pFile.existsSync()) {
        final pJson = jsonDecode(pFile.readAsStringSync()) as Map<String, dynamic>;
        final settings = pJson['settings'];
        if (settings is Map) {
          settings.remove('autoExecutionPolicy');
        }
        final permGrants = pJson['permissionGrants'];
        if (permGrants is Map && permGrants['permissionGrants'] is Map) {
          final inner = permGrants['permissionGrants'] as Map;
          if (inner['allow'] is List) {
            (inner['allow'] as List).removeWhere((e) => e == 'command(*)');
          }
        }
        pFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(pJson));
      }
    } catch (_) {}

    // 3. 卸载 / 还原 Gemini CLI Hook
    try {
      final gFile = File(geminiSettingsPath);
      if (gFile.existsSync()) {
        final json = jsonDecode(gFile.readAsStringSync()) as Map<String, dynamic>;
        final hooks = json['hooks'];
        if (hooks is Map && hooks['BeforeTool'] is List) {
          final beforeTool = hooks['BeforeTool'] as List;
          for (final item in beforeTool) {
            if (item is Map) {
              final subHooks = item['hooks'];
              if (subHooks is List) {
                for (final h in subHooks) {
                  if (h is Map && h.containsKey('v8_original_command')) {
                    h['command'] = h['v8_original_command'];
                    h.remove('v8_original_command');
                  }
                }
              }
            }
          }
          beforeTool.removeWhere((item) {
            final subHooks = item['hooks'];
            if (subHooks is List) {
              return subHooks.any((h) => h['command']?.toString().contains('v8-approval-proxy') == true);
            }
            return false;
          });
          gFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
        }
      }
    } catch (_) {}

    notifyListeners();
    return true;
  }

  void _backupFile(File file) {
    try {
      final bak = File('${file.path}.v8bak');
      if (!bak.existsSync()) {
        file.copySync(bak.path);
      }
    } catch (_) {}
  }

  /// 构建跨平台 Shell 启动包装器
  String _buildProxyShellContent() {
    return '''#!/usr/bin/env bash
DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

# 智能探测可用的 Node.js 解释器
NODE_BIN="node"
if ! command -v node >/dev/null 2>&1; then
  if [ -x "/opt/homebrew/bin/node" ]; then
    NODE_BIN="/opt/homebrew/bin/node"
  elif [ -x "/usr/local/bin/node" ]; then
    NODE_BIN="/usr/local/bin/node"
  elif [ -d "\$HOME/.nvm/versions/node" ]; then
    LATEST_NVM="\$(ls -d "\$HOME/.nvm/versions/node"/* 2>/dev/null | tail -n 1)"
    if [ -x "\$LATEST_NVM/bin/node" ]; then
      NODE_BIN="\$LATEST_NVM/bin/node"
    fi
  fi
fi

exec "\$NODE_BIN" "\$DIR/v8-approval-proxy.js" "\$@"
''';
  }

  /// 构建 Node.js 策略代理脚本
  String _buildProxyJsContent() {
    return '''/**
 * V8WorkToolbox - Unattended AI Approval Proxy Engine
 * Sub-5ms lightweight decision proxy reading ~/.v8worktoolbox/unattended/state.json
 */
const fs = require('fs');
const path = require('path');
const { exec, execSync } = require('child_process');

const client = (process.argv[2] || 'claude').toLowerCase();
const HOME = process.env.HOME || '';
const STATE_FILE = process.env.V8_STATE_FILE || path.join(HOME, '.v8worktoolbox', 'unattended', 'state.json');
const AUDIT_FILE = process.env.V8_AUDIT_FILE || path.join(HOME, '.v8worktoolbox', 'unattended', 'audit.jsonl');

function logAudit(entry) {
  try {
    const line = JSON.stringify({
      timestamp: new Date().toISOString(),
      client: entry.client || client,
      toolName: entry.toolName || 'Bash',
      command: entry.command || '',
      decision: entry.decision || 'allow',
      reason: entry.reason || ''
    }) + '\\n';
    fs.appendFileSync(AUDIT_FILE, line);
  } catch (_) {}
}

function notifyDesktop(msg) {
  if (process.env.V8_TEST_MODE === '1' || process.env.NODE_ENV === 'test') return;
  try {
    const safeMsg = msg.replace(/"/g, '\\\\"') ;
    exec(`osascript -e 'display notification "\${safeMsg}" with title "V8 无人值守安全拦截" sound name "Basso"'`);
  } catch (_) {}
}

function tokenizeArgs(str) {
  const tokens = [];
  let current = '';
  let inSingle = false;
  let inDouble = false;
  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    if (c === "'" && !inDouble) {
      inSingle = !inSingle;
    } else if (c === '"' && !inSingle) {
      inDouble = !inDouble;
    } else if (c === ' ' && !inSingle && !inDouble) {
      if (current.length > 0) {
        tokens.push(current);
        current = '';
      }
    } else {
      current += c;
    }
  }
  if (current.length > 0) tokens.push(current);
  return tokens;
}

function isPathWithin(parent, child) {
  const rel = path.relative(parent, child);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function isTargetSafe(rawTarget, cwd, home) {
  let target = (rawTarget || '').trim().replace(/^['"]|['"]\$/g, '');
  if (!target) return { safe: true };

  if (target.startsWith('~')) {
    target = path.join(home, target.slice(1));
  } else if (target.startsWith('\$HOME')) {
    target = path.join(home, target.slice(5));
  }

  const resolved = path.isAbsolute(target) ? path.normalize(target) : path.normalize(path.resolve(cwd, target));
  const normCwd = path.normalize(cwd);
  const normHome = path.normalize(home);

  const forbiddenRoots = [
    '/',
    normHome,
    '/Users',
    '/System',
    '/Library',
    '/usr',
    '/bin',
    '/sbin',
    '/etc',
    '/opt',
    '/var',
    path.join(normHome, '.ssh'),
    path.join(normHome, '.gnupg'),
    path.join(normHome, '.aws')
  ];

  for (const fb of forbiddenRoots) {
    if (fb && resolved === fb) {
      return { safe: false, reason: 'Target is forbidden root or sensitive directory: ' + target + ' (' + resolved + ')' };
    }
  }

  if (resolved === normCwd) {
    return { safe: false, reason: 'Target is workspace root itself: ' + target + ' (' + resolved + ')' };
  }

  // 工作区内部子目录
  if (isPathWithin(normCwd, resolved)) {
    return { safe: true };
  }

  // 临时目录
  const tmpDir = process.env.TMPDIR ? path.normalize(process.env.TMPDIR) : null;
  if (
    isPathWithin('/tmp', resolved) ||
    isPathWithin('/var/tmp', resolved) ||
    isPathWithin('/var/folders', resolved) ||
    (tmpDir && isPathWithin(tmpDir, resolved))
  ) {
    return { safe: true };
  }

  // V8 沙箱目录
  const v8Dir = path.join(normHome, '.v8worktoolbox');
  if (isPathWithin(v8Dir, resolved)) {
    return { safe: true };
  }

  return { safe: false, reason: 'Target is outside workspace and not in temp directory: ' + target + ' (' + resolved + ')' };
}

function evaluateSafety(command, cwd, denylist, home) {
  const normCwd = cwd || process.cwd();
  const normHome = home || process.env.HOME || '';

  // 1. rm 作用域评估
  const subcommands = command.split(/&&|\\|\\||;|\\|/);
  for (const sub of subcommands) {
    const trimmed = sub.trim();
    const rmMatch = trimmed.match(/\\brm\\s+([^;]+)/);
    if (rmMatch) {
      const argsStr = rmMatch[1];
      const tokens = tokenizeArgs(argsStr);
      let isRecursive = false;
      let isForce = false;
      const targets = [];

      for (const token of tokens) {
        if (token.startsWith('-')) {
          if (token === '-r' || token === '-R' || token === '--recursive') isRecursive = true;
          else if (token === '-f' || token === '--force') isForce = true;
          else if (/^-[a-zA-Z]+\$/.test(token)) {
            if (token.includes('r') || token.includes('R')) isRecursive = true;
            if (token.includes('f')) isForce = true;
          }
        } else {
          targets.push(token);
        }
      }

      if (isRecursive || isForce) {
        for (const target of targets) {
          const res = isTargetSafe(target, normCwd, normHome);
          if (!res.safe) {
            return { isAllowed: false, reason: res.reason };
          }
        }
      }
    }
  }

  // 2. 正则黑名单扫描
  for (const pattern of denylist) {
    try {
      const reg = new RegExp(pattern, 'im');
      if (reg.test(command)) {
        return { isAllowed: false, reason: 'matched_danger_floor: ' + pattern };
      }
    } catch (_) {}
  }

  return { isAllowed: true, reason: 'unattended_active_and_safe' };
}

// 读取全部标准输入
let rawInput = '';
process.stdin.setEncoding('utf8');

process.stdin.on('data', chunk => {
  rawInput += chunk;
});

process.stdin.on('end', () => {
  try {
    let state = null;
    if (fs.existsSync(STATE_FILE)) {
      state = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
    }

    // 若是 agy 或 gemini 客户端，并且环境中存在 RTK，委托 RTK 执行改写
    let rtkResult = null;
    if (client === 'agy' || client === 'gemini') {
      try {
        const rtkScript = path.join(HOME, '.gemini', 'hooks', 'rtk-hook-gemini.sh');
        const targetCmd = fs.existsSync(rtkScript) ? rtkScript : 'rtk hook gemini';
        const rtkOut = execSync(targetCmd, {
          input: rawInput,
          encoding: 'utf8',
          timeout: 2500,
          stdio: ['pipe', 'pipe', 'ignore']
        });
        if (rtkOut && rtkOut.trim()) {
          rtkResult = JSON.parse(rtkOut.trim());
        }
      } catch (_) {}
    }

    const isStateActive = state && state.enabled;
    const now = Date.now();
    const expires = state && state.expiresAt ? new Date(state.expiresAt).getTime() : 0;
    const isExpired = expires > 0 && now >= expires;

    if (!isStateActive || isExpired) {
      if (isExpired && state) {
        state.enabled = false;
        try {
          fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
        } catch (_) {}
      }
      process.exit(0);
    }

    // 解析工具调用入参 (兼容 AGY 与 Claude Code)
    let data = {};
    try {
      data = JSON.parse(rawInput);
    } catch (_) {}

    let toolName = 'Bash';
    let command = '';
    let cwd = process.cwd();

    if (data.toolCall && typeof data.toolCall === 'object') {
      toolName = data.toolCall.name || 'run_command';
      const args = data.toolCall.args || {};
      command = args.CommandLine || args.command || '';
      if (args.Cwd) cwd = args.Cwd;
    } else if (data.tool_name || data.tool) {
      toolName = data.tool_name || data.tool || 'Bash';
      if (data.tool_input && typeof data.tool_input === 'object') {
        command = data.tool_input.CommandLine || data.tool_input.command || data.tool_input.path || '';
      }
      if (data.cwd) cwd = data.cwd;
    } else if (data.arguments && typeof data.arguments === 'object') {
      toolName = data.name || 'Bash';
      command = data.arguments.CommandLine || data.arguments.command || data.arguments.path || '';
      if (data.cwd) cwd = data.cwd;
    }

    const evalResult = evaluateSafety(command, cwd, state.denylist || [], HOME);

    if (!evalResult.isAllowed) {
      logAudit({ client, toolName, command, decision: 'deny', reason: evalResult.reason });
      notifyDesktop('已拦截高危操作: ' + command.slice(0, 80));

      if (client === 'claude') {
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'deny',
            permissionDecisionReason: 'Blocked by V8WorkToolbox Unattended Safety Floor: ' + evalResult.reason
          }
        }));
      } else {
        process.stdout.write(JSON.stringify({
          decision: 'deny',
          reason: 'Blocked by V8WorkToolbox Unattended Safety Floor: ' + evalResult.reason
        }));
      }
      process.exit(0);
    } else {
      // 安全命令：直接放行并审计
      logAudit({ client, toolName, command, decision: 'allow', reason: 'unattended_active_and_safe' });

      if (client === 'claude') {
        process.stdout.write(JSON.stringify({
          hookSpecificOutput: {
            hookEventName: 'PreToolUse',
            permissionDecision: 'allow',
            permissionDecisionReason: 'Allowed by V8WorkToolbox Unattended Mode'
          }
        }));
      } else {
        process.stdout.write(JSON.stringify({
          decision: 'allow',
          permissionOverrides: ['command(*)']
        }));
      }
      process.exit(0);
    }
  } catch (err) {
    // 发生任何不可预测异常，安全降级，不做任何放行
    process.exit(0);
  }
});
''';
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }
}
