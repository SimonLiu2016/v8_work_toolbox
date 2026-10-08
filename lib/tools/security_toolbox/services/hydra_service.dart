/// 服务弱口令检测：Hydra CLI 调用封装与输出解析。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'security_process_runner.dart';

/// Hydra 命中一条弱口令凭据。
class HydraFinding {
  final String target;
  final int port;
  final String service;
  final String username;
  final String password;

  const HydraFinding({
    required this.target,
    required this.port,
    required this.service,
    required this.username,
    required this.password,
  });

  @override
  String toString() =>
      '[$port][$service] $target -> $username / $password';
}

/// Hydra 服务层弱口令扫描服务。
abstract final class HydraService {
  /// 内置常见弱口令基线用户名（20 条）。
  static const List<String> defaultUsers = [
    'root',
    'admin',
    'administrator',
    'user',
    'ubuntu',
    'test',
    'guest',
    'oracle',
    'postgres',
    'ftp',
    'deploy',
    'manager',
    'service',
    'webmaster',
    'operator',
    'support',
    'app',
    'default',
    'demo',
    'backup',
  ];

  /// 内置常见弱口令基线密码（50 条）。
  static const List<String> defaultPasswords = [
    '123456',
    'password',
    'admin',
    'root',
    '12345678',
    '1234',
    '111111',
    '123456789',
    'qwerty',
    'abc123',
    'admin123',
    'root123',
    '12345',
    'pass123',
    '123123',
    'welcome',
    'default',
    'P@ssw0rd',
    'guest',
    'test',
    'password123',
    '1234567',
    '000000',
    '666666',
    '888888',
    '5201314',
    'admin888',
    'rootroot',
    'pass@123',
    'test123',
    'admin@123',
    'changeme',
    'login',
    'iloveyou',
    'master',
    'service',
    'support',
    'server',
    'database',
    'oracle',
    'postgres',
    'mysql',
    'redis',
    'manager',
    'qwertyuiop',
    '1q2w3e4r',
    'asdfghjk',
    'zxcvbnm',
    '112233',
    '123321',
  ];

  /// 解析 Hydra 单行输出。若命中凭据则返回 [HydraFinding]，否则返回 null。
  ///
  /// 标准输出示例:
  /// `[22][ssh] host: 192.168.1.100   login: root   password: 123456`
  /// 宽松匹配示例:
  /// `host: 192.168.1.100   login: admin   password: password`
  static HydraFinding? parseOutputLine(
    String line, {
    String? fallbackTarget,
    String? fallbackService,
    int? fallbackPort,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return null;

    // 格式 1: 带中括号端口与服务名 [22][ssh] host: ... login: ... password: ...
    final fullRegex = RegExp(
      r'\[(\d+)\]\[([a-zA-Z0-9_-]+)\]\s+host:\s+(\S+)\s+login:\s+(\S+)\s+password:\s*(\S*)',
      caseSensitive: false,
    );
    final fullMatch = fullRegex.firstMatch(trimmed);
    if (fullMatch != null) {
      final port = int.tryParse(fullMatch.group(1)!) ?? (fallbackPort ?? 22);
      final service = fullMatch.group(2)!;
      final host = fullMatch.group(3)!;
      final user = fullMatch.group(4)!;
      final pass = fullMatch.group(5) ?? '';
      return HydraFinding(
        target: host,
        port: port,
        service: service,
        username: user,
        password: pass,
      );
    }

    // 格式 2: host: ... login: ... password: ...
    final simpleRegex = RegExp(
      r'host:\s+(\S+)\s+login:\s+(\S+)\s+password:\s*(\S*)',
      caseSensitive: false,
    );
    final simpleMatch = simpleRegex.firstMatch(trimmed);
    if (simpleMatch != null) {
      final host = simpleMatch.group(1)!;
      final user = simpleMatch.group(2)!;
      final pass = simpleMatch.group(3) ?? '';
      return HydraFinding(
        target: fallbackTarget ?? host,
        port: fallbackPort ?? 22,
        service: fallbackService ?? 'ssh',
        username: user,
        password: pass,
      );
    }

    return null;
  }

  /// 构建 hydra 命令行参数。
  static List<String> buildArgs({
    required String userFilePath,
    required String passFilePath,
    required String target,
    required String service,
    int? port,
    int threads = 4,
  }) {
    return [
      '-L',
      userFilePath,
      '-P',
      passFilePath,
      '-t',
      '$threads',
      '-f', // 找到第一个凭据即停止单主机爆破，降低压力
      '-vV',
      if (port != null) ...['-s', '$port'],
      target,
      service.toLowerCase(),
    ];
  }

  /// 对指定目标服务的弱口令核查。
  static Future<List<HydraFinding>> scan({
    required String target,
    String service = 'ssh',
    int? port,
    List<String>? userList,
    List<String>? passList,
    Duration timeout = const Duration(seconds: 90),
    void Function(HydraFinding finding)? onFinding,
    void Function(String line)? onLog,
  }) async {
    final resolved = resolveExecutable('hydra');
    if (resolved == null) {
      onLog?.call('未检测到 hydra，请先在工具状态面板安装');
      return [];
    }

    final tempDir = await Directory.systemTemp.createTemp('v8_hydra_');
    final userFile = File('${tempDir.path}/users.txt');
    final passFile = File('${tempDir.path}/pass.txt');

    try {
      final users = (userList != null && userList.isNotEmpty) ? userList : defaultUsers;
      final passwords = (passList != null && passList.isNotEmpty) ? passList : defaultPasswords;

      await userFile.writeAsString(users.join('\n'));
      await passFile.writeAsString(passwords.join('\n'));

      final args = buildArgs(
        userFilePath: userFile.path,
        passFilePath: passFile.path,
        target: target,
        service: service,
        port: port,
      );

      onLog?.call('启动 hydra $service 口令核查: $target${port != null ? ":$port" : ""}');

      final process = await Process.start(
        resolved,
        args,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );

      final findings = <HydraFinding>[];
      final done = <Future>[];

      done.add(
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final trimmed = line.trim();
              if (trimmed.isEmpty) return;
              onLog?.call('[hydra] $trimmed');
              final f = parseOutputLine(
                trimmed,
                fallbackTarget: target,
                fallbackService: service,
                fallbackPort: port,
              );
              if (f != null) {
                findings.add(f);
                onFinding?.call(f);
              }
            })
            .asFuture(),
      );

      done.add(
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
              final trimmed = line.trim();
              if (trimmed.isNotEmpty) {
                onLog?.call('[hydra err] $trimmed');
              }
            })
            .asFuture(),
      );

      final exitCodeFuture = process.exitCode;
      await Future.any([
        Future.wait([exitCodeFuture, ...done]),
        Future.delayed(timeout).then((_) {
          process.kill(ProcessSignal.sigkill);
          onLog?.call('hydra 扫描超时（已强制终止）');
        }),
      ]);

      return findings;
    } catch (e) {
      onLog?.call('hydra 执行异常: $e');
      return [];
    } finally {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }
}
