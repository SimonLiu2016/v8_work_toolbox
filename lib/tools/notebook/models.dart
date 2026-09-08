import 'dart:convert';

/// 笔记本数据模型（纯 Dart，不依赖 drift 生成代码）
/// 用于 UI 层和导入/导出层的数据传递

class NotebookModel {
  final String id;
  final String name;
  final String icon;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NotebookModel({
    required this.id,
    required this.name,
    this.icon = '📓',
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });
}

class NoteModel {
  final String id;
  final String title;
  final String deltaJson; // Quill Delta JSON
  final String? notebookId;
  final bool isPinned;
  final bool isDeleted;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tagIds;
  final List<String> tags; // tag names for display

  const NoteModel({
    required this.id,
    required this.title,
    required this.deltaJson,
    this.notebookId,
    this.isPinned = false,
    this.isDeleted = false,
    required this.createdAt,
    required this.updatedAt,
    this.tagIds = const [],
    this.tags = const [],
  });

  /// 从 Delta JSON 提取纯文本摘要（前 120 字符）
  String get summary {
    try {
      final ops = jsonDecode(deltaJson) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in ops) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
        if (buffer.length >= 120) break;
      }
      final text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      return text.length > 120 ? '${text.substring(0, 120)}...' : text;
    } catch (_) {
      return '';
    }
  }

  /// 从 Delta JSON 提取纯文本（用于搜索索引）
  String get plainText {
    try {
      final ops = jsonDecode(deltaJson) as List<dynamic>;
      final buffer = StringBuffer();
      for (final op in ops) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            buffer.write(insert);
          }
        }
      }
      return buffer.toString();
    } catch (_) {
      return '';
    }
  }
}

class TagModel {
  final String id;
  final String name;
  final String? color;

  const TagModel({
    required this.id,
    required this.name,
    this.color,
  });
}

class AttachmentModel {
  final String id;
  final String noteId;
  final String? filename;
  final String? mime;
  final String localPath;
  final DateTime createdAt;

  const AttachmentModel({
    required this.id,
    required this.noteId,
    this.filename,
    this.mime,
    required this.localPath,
    required this.createdAt,
  });
}
