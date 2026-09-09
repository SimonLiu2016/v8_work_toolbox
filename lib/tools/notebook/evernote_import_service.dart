import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'note_store.dart';

/// 导入进度回调
typedef ImportProgressCallback = void Function(int current, int total, String title);

/// 导入结果摘要
class ImportResult {
  final int total;
  final int imported;
  final int failed;
  final List<String> errors;

  const ImportResult({
    required this.total,
    required this.imported,
    required this.failed,
    this.errors = const [],
  });
}

/// 印象笔记导入服务
class EvernoteImportService {
  EvernoteImportService._();
  static final EvernoteImportService instance = EvernoteImportService._();

  /// 从印象笔记 API 导入全部笔记
  Future<ImportResult> importFromApi({
    ImportProgressCallback? onProgress,
  }) async {
    final store = NoteStore.instance;
    await store.init();

    // Find the Python script
    final scriptPath = p.join(p.current, 'scripts', 'evernote_import.py');
    final scriptFile = File(scriptPath);
    if (!await scriptFile.exists()) {
      // Try relative to the app bundle
      final altPath = p.join(p.current, '..', 'scripts', 'evernote_import.py');
      if (!await File(altPath).exists()) {
        return const ImportResult(
          total: 0, imported: 0, failed: 1,
          errors: ['evernote_import.py not found'],
        );
      }
    }

    // Step 1: List all notes
    debugPrint('[EvernoteImport] Listing notes...');
    final listResult = await Process.run('python3', [scriptPath, 'list']);
    if (listResult.exitCode != 0) {
      return ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['Failed to list notes: ${listResult.stderr}'],
      );
    }

    final listJson = jsonDecode(listResult.stdout as String) as Map<String, dynamic>;
    final notesMeta = listJson['notes'] as List<dynamic>;
    final total = notesMeta.length;
    debugPrint('[EvernoteImport] Found $total notes');

    // Step 2: Import each note
    int imported = 0;
    int failed = 0;
    final errors = <String>[];

    // Create notebooks
    final notebookNames = (listJson['notebooks'] as List<dynamic>?)?.cast<String>() ?? [];
    final notebookIds = <String, String>{};
    for (final name in notebookNames) {
      final existing = await store.allNotebooks();
      final match = existing.where((nb) => nb.name == name).toList();
      if (match.isNotEmpty) {
        notebookIds[name] = match.first.id;
      } else {
        final id = await store.createNotebook(name);
        notebookIds[name] = id;
      }
    }

    // Create tags
    final tagNames = (listJson['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    final tagIds = <String, String>{};
    for (final name in tagNames) {
      final existing = await store.allTags();
      final match = existing.where((t) => t.name == name).toList();
      if (match.isNotEmpty) {
        tagIds[name] = match.first.id;
      } else {
        final id = await store.createTag(name);
        tagIds[name] = id;
      }
    }

    // Fetch and import each note
    for (int i = 0; i < notesMeta.length; i++) {
      final meta = notesMeta[i] as Map<String, dynamic>;
      final title = meta['title'] as String? ?? 'Untitled';
      final guid = meta['guid'] as String?;
      final notebookName = meta['notebook'] as String?;
      final tags = (meta['tags'] as List<dynamic>?)?.cast<String>() ?? [];

      onProgress?.call(i + 1, total, title);

      if (guid == null) {
        failed++;
        errors.add('$title: missing GUID');
        continue;
      }

      try {
        // Fetch note content via API
        final fetchResult = await Process.run(
          'python3', [scriptPath, 'fetch', '--guid', guid],
        );

        if (fetchResult.exitCode != 0) {
          failed++;
          errors.add('$title: fetch failed - ${fetchResult.stderr}');
          continue;
        }

        final fetchJson = jsonDecode(fetchResult.stdout as String) as Map<String, dynamic>;
        final markdown = fetchJson['markdown'] as String?;

        if (markdown == null || markdown.isEmpty) {
          failed++;
          errors.add('$title: empty content');
          continue;
        }

        // Convert Markdown to Delta
        final deltaJson = _markdownToDeltaSimple(markdown);

        // Create note
        final noteId = await store.createNote(
          title: title,
          deltaJson: deltaJson,
          notebookId: notebookName != null ? notebookIds[notebookName] : null,
        );

        // Set tags
        final noteTagIds = tags
            .where((t) => tagIds.containsKey(t))
            .map((t) => tagIds[t]!)
            .toList();
        if (noteTagIds.isNotEmpty) {
          await store.setNoteTags(noteId, noteTagIds);
        }

        // Import resources
        final resources = (fetchJson['resources'] as List<dynamic>?) ?? [];
        for (final res in resources) {
          final resMap = res as Map<String, dynamic>;
          final base64Data = resMap['base64'] as String?;
          final mime = resMap['mime'] as String?;
          if (base64Data != null) {
            final bytes = base64Decode(base64Data);
            final ext = _mimeToExtension(mime);
            await store.saveAttachmentFromBytes(
              noteId: noteId,
              bytes: bytes,
              filename: 'attachment$ext',
              mime: mime,
            );
          }
        }

        imported++;
        debugPrint('[EvernoteImport] [$imported/$total] $title');
      } catch (e) {
        failed++;
        errors.add('$title: $e');
        debugPrint('[EvernoteImport] FAILED: $title - $e');
      }
    }

    return ImportResult(
      total: total,
      imported: imported,
      failed: failed,
      errors: errors,
    );
  }

  /// 从 .notes 文件导入元数据和附件（正文通过 API 补充）
  Future<ImportResult> importFromNotesFile({
    required String filePath,
    ImportProgressCallback? onProgress,
  }) async {
    final store = NoteStore.instance;
    await store.init();

    // Parse .notes file with Python script
    final scriptPath = p.join(p.current, 'scripts', 'evernote_import.py');
    final result = await Process.run(
      'python3', [scriptPath, 'parse_notes', '--file', filePath],
    );

    if (result.exitCode != 0) {
      return ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['Failed to parse .notes file: ${result.stderr}'],
      );
    }

    final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
    final notes = data['notes'] as List<dynamic>;
    final total = notes.length;

    int imported = 0;
    int failed = 0;
    final errors = <String>[];

    for (int i = 0; i < notes.length; i++) {
      final note = notes[i] as Map<String, dynamic>;
      final title = note['title'] as String? ?? 'Untitled';
      final isEncrypted = note['is_encrypted'] as bool? ?? false;
      final notebookName = note['notebook'] as String?;
      final tags = (note['tags'] as List<dynamic>?)?.cast<String>() ?? [];

      onProgress?.call(i + 1, total, title);

      try {
        // Create notebook if needed
        String? notebookId;
        if (notebookName != null) {
          final existing = await store.allNotebooks();
          final match = existing.where((nb) => nb.name == notebookName).toList();
          if (match.isNotEmpty) {
            notebookId = match.first.id;
          } else {
            notebookId = await store.createNotebook(notebookName);
          }
        }

        // Content: use placeholder if encrypted
        final deltaJson = isEncrypted
            ? '[{"insert":"[加密内容 - 请使用印象笔记 API 导入获取正文]\\n"}]'
            : '[{"insert":"\\n"}]';

        final noteId = await store.createNote(
          title: title,
          deltaJson: deltaJson,
          notebookId: notebookId,
        );

        // Set tags
        for (final tagName in tags) {
          final existing = await store.allTags();
          final match = existing.where((t) => t.name == tagName).toList();
          String tagId;
          if (match.isNotEmpty) {
            tagId = match.first.id;
          } else {
            tagId = await store.createTag(tagName);
          }
          await store.setNoteTags(noteId, [tagId]);
        }

        // Import attachments
        final resources = (note['resources'] as List<dynamic>?) ?? [];
        for (final res in resources) {
          final resMap = res as Map<String, dynamic>;
          final base64Data = resMap['base64'] as String?;
          final mime = resMap['mime'] as String?;
          if (base64Data != null) {
            final bytes = base64Decode(base64Data);
            final ext = _mimeToExtension(mime);
            await store.saveAttachmentFromBytes(
              noteId: noteId,
              bytes: bytes,
              filename: 'attachment$ext',
              mime: mime,
            );
          }
        }

        imported++;
      } catch (e) {
        failed++;
        errors.add('$title: $e');
      }
    }

    return ImportResult(
      total: total,
      imported: imported,
      failed: failed,
      errors: errors,
    );
  }

  /// Simple Markdown → Delta conversion (for import)
  String _markdownToDeltaSimple(String markdown) {
    final lines = markdown.split('\n');
    final ops = <Map<String, dynamic>>[];

    for (final line in lines) {
      if (line.isEmpty) {
        ops.add({'insert': '\n'});
        continue;
      }

      // Heading
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        ops.add({
          'insert': headingMatch.group(2)!,
          'attributes': {'header': level},
        });
        ops.add({'insert': '\n'});
        continue;
      }

      // Code block
      if (line.trimLeft().startsWith('```')) {
        // Skip code block markers for simplicity
        continue;
      }

      // List item
      final listMatch = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line);
      if (listMatch != null) {
        ops.add({
          'insert': listMatch.group(1)!,
          'attributes': {'list': 'bullet'},
        });
        ops.add({'insert': '\n'});
        continue;
      }

      // Regular text
      ops.add({'insert': line});
      ops.add({'insert': '\n'});
    }

    if (ops.isEmpty) {
      ops.add({'insert': '\n'});
    }

    return jsonEncode(ops);
  }

  String _mimeToExtension(String? mime) {
    if (mime == null) return '.bin';
    if (mime.contains('png')) return '.png';
    if (mime.contains('jpeg') || mime.contains('jpg')) return '.jpg';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('pdf')) return '.pdf';
    if (mime.contains('svg')) return '.svg';
    return '.bin';
  }
}
