/// AI 威胁情报日报的本地存取。
///
/// 落成 `security/news_digests.json` 的列表而非覆盖单文件：日报的意义在于
/// 回看，覆盖式存储让"昨天那条说了什么"变成不可能。保留 7 天。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../services/app_paths.dart';

/// 一条日报记录。
class DigestRecord {
  final String id;
  final String text;
  final DateTime createdAt;

  const DigestRecord({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  static DigestRecord? fromJson(Map<String, dynamic> json) {
    final text = json['text'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    return DigestRecord(
      id: json['id'] as String? ??
          '${(json['created_at'] as num?)?.toInt() ?? 0}',
      text: text,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (json['created_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// 列表用的首行摘要。
  String get headline {
    final firstLine = text.split('\n').first.trim();
    if (firstLine.isEmpty) return '（空日报）';
    return firstLine.length > 60
        ? '${firstLine.substring(0, 60)}…'
        : firstLine;
  }
}

/// 日报列表存储。
class DigestStore {
  DigestStore._();
  static final DigestStore instance = DigestStore._();

  /// 仅供测试：覆盖存储目录。
  @visibleForTesting
  static Directory? debugOverrideDir;

  static File get _file {
    final override = debugOverrideDir;
    if (override != null) return File('${override.path}/news_digests.json');
    return File('${AppPaths.securityDir.path}/news_digests.json');
  }

  static const int retentionDays = 7;

  /// 读取最近 [retentionDays] 天的日报（新的在前）。
  Future<List<DigestRecord>> recent() async {
    final all = await _load();
    final cutoff = DateTime.now().subtract(
      const Duration(days: retentionDays),
    );
    final kept = all
        .where((d) => d.createdAt.isAfter(cutoff))
        .toList(growable: true);
    if (kept.length != all.length) {
      // 顺手裁剪落盘，避免文件无限增长。
      await _write(kept);
    }
    kept.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return kept;
  }

  Future<void> append(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    // _load 可能返回 const 列表（文件不存在时），必须先复制再 append。
    final all = List<DigestRecord>.of(await _load());
    all.add(
      DigestRecord(
        id: '${DateTime.now().millisecondsSinceEpoch}',
        text: trimmed,
        createdAt: DateTime.now(),
      ),
    );
    await _write(all);
  }

  Future<List<DigestRecord>> _load() async {
    try {
      if (!_file.existsSync()) return const [];
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => DigestRecord.fromJson(Map<String, dynamic>.from(e)))
          .whereType<DigestRecord>()
          .toList();
    } catch (_) {
      // 文件损坏时退化为空：日报是衍生数据，丢了不该让情报面板打不开。
      return const [];
    }
  }

  Future<void> _write(List<DigestRecord> records) async {
    try {
      final dir = _file.parent;
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _file.writeAsStringSync(
        jsonEncode([for (final r in records) r.toJson()]),
      );
    } catch (_) {
      // 磁盘不可写时静默失败：本次日报仍会显示在面板里，只是重启后不保留。
    }
  }
}
