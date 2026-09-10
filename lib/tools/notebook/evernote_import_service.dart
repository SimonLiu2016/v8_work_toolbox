import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

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

/// 本机印象笔记探测结果
class LocalEvernoteInfo {
  final bool detected;
  final String? app;
  final String? account;
  final int notebookCount;
  final int noteCount;
  final int tagCount;

  const LocalEvernoteInfo({
    required this.detected,
    this.app,
    this.account,
    this.notebookCount = 0,
    this.noteCount = 0,
    this.tagCount = 0,
  });
}

/// 印象笔记导入服务
class EvernoteImportService {
  EvernoteImportService._();
  static final EvernoteImportService instance = EvernoteImportService._();

  Future<String?> _resolveScriptPath() async {
    final candidates = [
      p.join(p.dirname(Platform.resolvedExecutable), '..', 'Resources', 'scripts', 'evernote_import.py'),
      p.join(p.current, 'scripts', 'evernote_import.py'),
      p.join(p.current, '..', 'scripts', 'evernote_import.py'),
      '/Users/simon/ClaudeWorkspace/V8WorkToolbox/scripts/evernote_import.py',
    ];

    for (final path in candidates) {
      if (await File(path).exists()) {
        return p.normalize(path);
      }
    }
    return null;
  }

  /// 探测本机是否有安装并使用印象笔记/Evernote 客户端
  Future<LocalEvernoteInfo> detectLocalEvernote() async {
    final scriptPath = await _resolveScriptPath();
    if (scriptPath == null) {
      return const LocalEvernoteInfo(detected: false);
    }
    try {
      final result = await Process.run('python3', [scriptPath, 'detect_local']);
      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout as String) as Map<String, dynamic>;
        if (data['detected'] == true) {
          return LocalEvernoteInfo(
            detected: true,
            app: data['app'] as String?,
            account: data['account'] as String?,
            notebookCount: data['notebook_count'] as int? ?? 0,
            noteCount: data['note_count'] as int? ?? 0,
            tagCount: data['tag_count'] as int? ?? 0,
          );
        }
      }
    } catch (e) {
      debugPrint('[EvernoteImport] detectLocalEvernote error: $e');
    }
    return const LocalEvernoteInfo(detected: false);
  }

  /// 从本机印象笔记客户端一键全量免密迁移
  Future<ImportResult> importFromLocalClient({
    ImportProgressCallback? onProgress,
  }) async {
    final store = NoteStore.instance;
    await store.init();

    final scriptPath = await _resolveScriptPath();
    if (scriptPath == null) {
      return const ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['evernote_import.py 脚本未找到，请确认路径配置'],
      );
    }

    final tmpFile = p.join(Directory.systemTemp.path, 'evernote_local_import_${DateTime.now().millisecondsSinceEpoch}.json');
    try {
      final result = await Process.run(
        'python3', [scriptPath, 'import_local', '--output', tmpFile],
      );

      if (result.exitCode != 0 || !await File(tmpFile).exists()) {
        return ImportResult(
          total: 0, imported: 0, failed: 1,
          errors: ['本机印象笔记数据提取失败: ${result.stderr}'],
        );
      }

      final content = await File(tmpFile).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return await _batchImportJsonData(data, onProgress: onProgress);
    } catch (e) {
      return ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['导入异常: $e'],
      );
    } finally {
      final f = File(tmpFile);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// 从 .notes 或 .enex 文件导入元数据和附件（自动命名笔记本并关联本机明文）
  Future<ImportResult> importFromNotesFile({
    required String filePath,
    ImportProgressCallback? onProgress,
  }) async {
    final store = NoteStore.instance;
    await store.init();

    final scriptPath = await _resolveScriptPath();
    if (scriptPath == null) {
      return const ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['evernote_import.py 脚本未找到，请确认路径配置'],
      );
    }

    final tmpFile = p.join(Directory.systemTemp.path, 'evernote_notes_parse_${DateTime.now().millisecondsSinceEpoch}.json');
    try {
      final result = await Process.run(
        'python3', [scriptPath, 'parse_notes', '--file', filePath, '--output', tmpFile],
      );

      if (result.exitCode != 0 || !await File(tmpFile).exists()) {
        return ImportResult(
          total: 0, imported: 0, failed: 1,
          errors: ['解析文件失败: ${result.stderr}'],
        );
      }

      final content = await File(tmpFile).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      final fallbackNb = data['default_notebook'] as String? ?? p.basenameWithoutExtension(filePath);
      return await _batchImportJsonData(data, onProgress: onProgress, fallbackNotebook: fallbackNb);
    } catch (e) {
      return ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['导入失败: $e'],
      );
    } finally {
      final f = File(tmpFile);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// 从印象笔记官方 API 导入全部笔记
  Future<ImportResult> importFromApi({
    ImportProgressCallback? onProgress,
  }) async {
    final store = NoteStore.instance;
    await store.init();

    final scriptPath = await _resolveScriptPath();
    if (scriptPath == null) {
      return const ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['evernote_import.py 脚本未找到，请确认路径配置'],
      );
    }

    final tmpFile = p.join(Directory.systemTemp.path, 'evernote_api_export_${DateTime.now().millisecondsSinceEpoch}.json');
    try {
      final result = await Process.run(
        'python3', [scriptPath, 'export_all', '--output', tmpFile],
      );

      if (result.exitCode != 0 || !await File(tmpFile).exists()) {
        return ImportResult(
          total: 0, imported: 0, failed: 1,
          errors: ['API 批量导出失败: ${result.stderr}'],
        );
      }

      final content = await File(tmpFile).readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      return await _batchImportJsonData(data, onProgress: onProgress);
    } catch (e) {
      return ImportResult(
        total: 0, imported: 0, failed: 1,
        errors: ['API 导入失败: $e'],
      );
    } finally {
      final f = File(tmpFile);
      if (await f.exists()) {
        await f.delete();
      }
    }
  }

  /// 通用 JSON 批量入库逻辑
  Future<ImportResult> _batchImportJsonData(
    Map<String, dynamic> data, {
    ImportProgressCallback? onProgress,
    String? fallbackNotebook,
  }) async {
    final store = NoteStore.instance;
    final notes = data['notes'] as List<dynamic>? ?? [];
    final total = notes.length;

    int imported = 0;
    int failed = 0;
    final errors = <String>[];

    // 1. 预先解析并创建所有笔记本，缓存映射
    final notebookCache = <String, String>{};
    final rawNotebooks = (data['notebooks'] as List<dynamic>?) ?? [];
    for (final item in rawNotebooks) {
      String name;
      String? stack;
      if (item is Map) {
        name = (item['name'] as String? ?? '').trim();
        stack = item['stack'] as String?;
      } else {
        name = item.toString().trim();
      }
      if (name.isEmpty) continue;
      final existing = await store.allNotebooks();
      final match = existing.where((nb) => nb.name == name).firstOrNull;
      if (match != null) {
        notebookCache[name] = match.id;
        if (stack != null && (match.stack == null || match.stack != stack)) {
          await store.updateNotebook(match.id, stack: stack);
        }
      } else {
        notebookCache[name] = await store.createNotebook(name, stack: stack);
      }
    }

    // 2. 预先解析并创建所有标签，缓存映射
    final tagCache = <String, String>{};
    final rawTags = (data['tags'] as List<dynamic>?)?.cast<String>() ?? [];
    for (final name in rawTags) {
      if (name.trim().isEmpty) continue;
      final existing = await store.allTags();
      final match = existing.where((t) => t.name == name).firstOrNull;
      if (match != null) {
        tagCache[name] = match.id;
      } else {
        tagCache[name] = await store.createTag(name);
      }
    }

    // 3. 逐条创建笔记
    for (int i = 0; i < notes.length; i++) {
      final note = notes[i] as Map<String, dynamic>;
      final title = note['title'] as String? ?? '无标题笔记';
      final isEncrypted = note['is_encrypted'] as bool? ?? false;
      final rawNotebookName = note['notebook'] as String?;
      final notebookName = (rawNotebookName != null && rawNotebookName.isNotEmpty)
          ? rawNotebookName
          : fallbackNotebook;
      final noteStack = note['stack'] as String?;
      final tags = (note['tags'] as List<dynamic>?)?.cast<String>() ?? [];
      final markdown = note['markdown'] as String?;

      onProgress?.call(i + 1, total, title);

      try {
        String? nbId;
        if (notebookName != null && notebookName.isNotEmpty) {
          if (notebookCache.containsKey(notebookName)) {
            nbId = notebookCache[notebookName];
            if (noteStack != null) {
              final existing = await store.allNotebooks();
              final match = existing.where((nb) => nb.id == nbId).firstOrNull;
              if (match != null && (match.stack == null || match.stack != noteStack)) {
                await store.updateNotebook(match.id, stack: noteStack);
              }
            }
          } else {
            final existing = await store.allNotebooks();
            final match = existing.where((nb) => nb.name == notebookName).firstOrNull;
            if (match != null) {
              nbId = match.id;
              if (noteStack != null && (match.stack == null || match.stack != noteStack)) {
                await store.updateNotebook(match.id, stack: noteStack);
              }
            } else {
              nbId = await store.createNotebook(notebookName, stack: noteStack);
            }
            notebookCache[notebookName] = nbId;
          }
        }

        final noteId = const Uuid().v4();

        // 优先保存附件资源并建立哈希与文件名映射，供正文图片回填定位
        final attachmentMap = <String, String>{};
        final resources = (note['resources'] as List<dynamic>?) ?? [];
        for (final res in resources) {
          final resMap = res as Map<String, dynamic>;
          final base64Data = resMap['base64'] as String?;
          final mime = resMap['mime'] as String?;
          final filename = resMap['filename'] as String?;
          final hash = resMap['hash'] as String?;
          if (base64Data != null && base64Data.isNotEmpty) {
            try {
              final bytes = base64Decode(base64Data);
              final ext = _mimeToExtension(mime);
              final savedPath = await store.saveAttachmentFromBytes(
                noteId: noteId,
                bytes: bytes,
                filename: filename ?? 'attachment$ext',
                mime: mime,
              );
              if (hash != null && hash.isNotEmpty) {
                attachmentMap[hash.toLowerCase()] = savedPath;
              }
              if (filename != null && filename.isNotEmpty) {
                attachmentMap[filename] = savedPath;
              }
            } catch (e) {
              debugPrint('Save attachment error: $e');
            }
          }
        }

        String deltaJson;
        if (markdown != null && markdown.isNotEmpty) {
          deltaJson = _markdownToDelta(markdown, attachmentMap);
        } else if (isEncrypted) {
          deltaJson = '[{"insert":"[加密内容 - 官方专有格式，未能匹配到本机客户端明文]\\n"}]';
        } else {
          deltaJson = '[{"insert":"\\n"}]';
        }

        final createdStr = note['created'] as String?;
        final updatedStr = note['updated'] as String?;
        final createdAt = createdStr != null ? DateTime.tryParse(createdStr) : null;
        final updatedAt = updatedStr != null ? DateTime.tryParse(updatedStr) : null;

        await store.createNote(
          id: noteId,
          title: title,
          deltaJson: deltaJson,
          notebookId: nbId,
          createdAt: createdAt,
          updatedAt: updatedAt,
        );

        // 标签关联
        final noteTagIds = <String>[];
        for (final tagName in tags) {
          if (tagName.trim().isEmpty) continue;
          if (tagCache.containsKey(tagName)) {
            noteTagIds.add(tagCache[tagName]!);
          } else {
            final existing = await store.allTags();
            final match = existing.where((t) => t.name == tagName).firstOrNull;
            final tId = match != null ? match.id : await store.createTag(tagName);
            tagCache[tagName] = tId;
            noteTagIds.add(tId);
          }
        }
        if (noteTagIds.isNotEmpty) {
          await store.setNoteTags(noteId, noteTagIds);
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

  /// 供测试与外部调用的 Markdown → Quill Delta 转换入口
  @visibleForTesting
  String markdownToDelta(String markdown, [Map<String, String> attachmentMap = const {}]) =>
      _markdownToDelta(markdown, attachmentMap);

  /// 完整 Markdown → Quill Delta 转换器（支持代码块、待办、标题、行内格式与图片原位嵌入）
  String _markdownToDelta(String markdown, Map<String, String> attachmentMap) {
    final lines = markdown.split('\n');
    final ops = <Map<String, dynamic>>[];
    final usedImagePaths = <String>{};

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // 思维导图块判定 ```mindmap
      if (line.trimLeft().startsWith('```mindmap')) {
        final buffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          buffer.write(lines[i]);
          i++;
        }
        final rawData = buffer.toString();
        String finalData = rawData;
        try {
          final parsed = jsonDecode(rawData) as Map<String, dynamic>;
          final hash = parsed['hash'] as String?;
          if (hash != null && attachmentMap.containsKey(hash.toLowerCase())) {
            parsed['svg_path'] = attachmentMap[hash.toLowerCase()];
            finalData = jsonEncode(parsed);
          }
        } catch (_) {}
        ops.add({'insert': {'mindmap': finalData}});
        ops.add({'insert': '\n'});
        continue;
      }

      // 代码块围栏判定与嵌入式渲染
      if (line.trimLeft().startsWith('```')) {
        final lang = line.trimLeft().substring(3).trim();
        final codeBuffer = StringBuffer();
        i++;
        while (i < lines.length && !lines[i].trimLeft().startsWith('```')) {
          if (codeBuffer.isNotEmpty) codeBuffer.write('\n');
          codeBuffer.write(lines[i]);
          i++;
        }
        ops.add({
          'insert': {
            'code_block': jsonEncode({
              'code': codeBuffer.toString(),
              'language': lang.isEmpty ? 'plaintext' : lang,
            }),
          },
        });
        ops.add({'insert': '\n'});
        continue;
      }

      if (line.isEmpty) {
        ops.add({'insert': '\n'});
        continue;
      }

      // 1. 标题 (# ~ ######)
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        ops.addAll(_parseInline(headingMatch.group(2)!));
        ops.add({
          'insert': '\n',
          'attributes': {'header': level},
        });
        continue;
      }

      // 2. 待办勾选框 (- [ ] 或 - [x])
      final todoMatch = RegExp(r'^[-*+]\s+\[([ xX])\]\s*(.*)$').firstMatch(line);
      if (todoMatch != null) {
        final isChecked = todoMatch.group(1)!.toLowerCase() == 'x';
        ops.addAll(_parseInline(todoMatch.group(2)!));
        ops.add({
          'insert': '\n',
          'attributes': {'list': isChecked ? 'checked' : 'unchecked'},
        });
        continue;
      }

      // 3. 无序列表 (- 或 * 或 +)
      final bulletMatch = RegExp(r'^[-*+]\s+(.+)$').firstMatch(line);
      if (bulletMatch != null) {
        ops.addAll(_parseInline(bulletMatch.group(1)!));
        ops.add({
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        });
        continue;
      }

      // 4. 有序列表 (1. 2.)
      final numMatch = RegExp(r'^\d+\.\s+(.+)$').firstMatch(line);
      if (numMatch != null) {
        ops.addAll(_parseInline(numMatch.group(1)!));
        ops.add({
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        });
        continue;
      }

      // 5. 引用块 (> quote)
      final quoteMatch = RegExp(r'^>\s*(.+)$').firstMatch(line);
      if (quoteMatch != null) {
        ops.addAll(_parseInline(quoteMatch.group(1)!));
        ops.add({
          'insert': '\n',
          'attributes': {'blockquote': true},
        });
        continue;
      }

      // 6. 包含图片标记 ![image](url)
      final imgRegex = RegExp(r'!\[(.*?)\]\((.*?)\)');
      final imgMatches = imgRegex.allMatches(line).toList();
      if (imgMatches.isNotEmpty) {
        int lastIndex = 0;
        for (final m in imgMatches) {
          if (m.start > lastIndex) {
            ops.addAll(_parseInline(line.substring(lastIndex, m.start)));
          }
          final url = m.group(2)!.trim();
          String? resolvedPath;
          if (url.startsWith('en-media://')) {
            final h = url.substring('en-media://'.length).toLowerCase();
            resolvedPath = attachmentMap[h];
          } else if (attachmentMap.containsKey(url.toLowerCase())) {
            resolvedPath = attachmentMap[url.toLowerCase()];
          } else if (attachmentMap.containsKey(m.group(1)?.toLowerCase())) {
            resolvedPath = attachmentMap[m.group(1)!.toLowerCase()];
          } else if (File(url).existsSync()) {
            resolvedPath = url;
          }

          if (resolvedPath != null && _isImageFilePath(resolvedPath)) {
            if (ops.isNotEmpty && ops.last['insert'] != '\n') {
              ops.add({'insert': '\n'});
            }
            ops.add({'insert': {'image': resolvedPath}});
            ops.add({'insert': '\n'});
            usedImagePaths.add(resolvedPath);
          } else {
            ops.add({'insert': m.group(0)!});
          }
          lastIndex = m.end;
        }
        if (lastIndex < line.length) {
          ops.addAll(_parseInline(line.substring(lastIndex)));
          ops.add({'insert': '\n'});
        }
        continue;
      }

      // 7. 普通正文行
      ops.addAll(_parseInline(line));
      ops.add({'insert': '\n'});
    }

    // 补齐正文中未显式出现的图片资源至文档末尾（仅限图片格式）
    for (final entry in attachmentMap.entries) {
      final path = entry.value;
      if (_isImageFilePath(path) && !usedImagePaths.contains(path)) {
        usedImagePaths.add(path);
        if (ops.isNotEmpty && ops.last['insert'] != '\n') {
          ops.add({'insert': '\n'});
        }
        ops.add({'insert': {'image': path}});
        ops.add({'insert': '\n'});
      }
    }

    if (ops.isEmpty) {
      ops.add({'insert': '\n'});
    }

    return jsonEncode(ops);
  }

  /// 行内加粗、斜体、行内代码与链接解析
  List<Map<String, dynamic>> _parseInline(String text) {
    if (text.isEmpty) return [];
    final result = <Map<String, dynamic>>[];
    final inlineRegex = RegExp(
      r'(\*\*([^*]+)\*\*)|(\*([^*]+)\*)|(`([^`]+)`)|(\[([^\]]+)\]\(([^)]+)\))',
    );

    int lastIndex = 0;
    for (final match in inlineRegex.allMatches(text)) {
      if (match.start > lastIndex) {
        result.add({'insert': text.substring(lastIndex, match.start)});
      }

      if (match.group(1) != null) {
        // 加粗: **text**
        result.add({
          'insert': match.group(2)!,
          'attributes': {'bold': true},
        });
      } else if (match.group(3) != null) {
        // 斜体: *text*
        result.add({
          'insert': match.group(4)!,
          'attributes': {'italic': true},
        });
      } else if (match.group(5) != null) {
        // 行内代码: `code`
        result.add({
          'insert': match.group(6)!,
          'attributes': {'code': true},
        });
      } else if (match.group(7) != null) {
        // 超链接: [text](url)
        result.add({
          'insert': match.group(8)!,
          'attributes': {'link': match.group(9)!},
        });
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      result.add({'insert': text.substring(lastIndex)});
    }

    if (result.isEmpty) {
      result.add({'insert': text});
    }

    return result;
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

  static bool _isImageFilePath(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    return const {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp', '.svg'}.contains(ext);
  }
}
