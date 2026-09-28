import 'dart:async';
import 'package:flutter/foundation.dart';

import 'appflowy_codec.dart';
import 'note_database.dart';
import 'note_store.dart';
import 'notebook_kb_service.dart';

/// 批量整理的目标范围
enum BatchOrganizeScope {
  /// 全量有效笔记（排除回收站已删除的笔记）
  allNotes,

  /// 仅尚未建立任何星图关联的孤立笔记
  unlinkedOnly,
}

/// 批量整理运行时的进度快照
class BatchOrganizeProgress {
  final int current;
  final int total;
  final String currentNoteTitle;
  final int tagsAdded;
  final int linksCreated;
  final int skippedNotes;
  final int failedNotes;

  const BatchOrganizeProgress({
    required this.current,
    required this.total,
    required this.currentNoteTitle,
    this.tagsAdded = 0,
    this.linksCreated = 0,
    this.skippedNotes = 0,
    this.failedNotes = 0,
  });

  double get ratio => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
}

/// 批量整理结束后的统计汇总
class BatchOrganizeSummary {
  final int processedNotes;
  final int totalNotes;
  final int tagsAdded;
  final int linksCreated;
  final int skippedNotes;
  final int failedNotes;
  final bool wasCancelled;

  const BatchOrganizeSummary({
    required this.processedNotes,
    required this.totalNotes,
    required this.tagsAdded,
    required this.linksCreated,
    required this.skippedNotes,
    required this.failedNotes,
    required this.wasCancelled,
  });
}

/// 批量整理任务取消控制令牌
class BatchCancellationToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;

  void cancel() {
    _isCancelled = true;
  }
}

/// 知识星图“全量/批量 AI 整理建议”调度服务
class BatchOrganizerService {
  BatchOrganizerService({
    NoteStore? noteStore,
    NotebookKbService? kbService,
  })  : _noteStore = noteStore ?? NoteStore.instance,
        _kbService = kbService ?? NotebookKbService.instance;

  static final BatchOrganizerService instance = BatchOrganizerService();

  final NoteStore _noteStore;
  final NotebookKbService _kbService;

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 查询当前库中的有效笔记总数与未关联笔记数
  Future<({int totalNotes, int unlinkedNotes, List<Note> targetNotes})> getScopeMetrics({
    BatchOrganizeScope scope = BatchOrganizeScope.allNotes,
  }) async {
    final allNotes = await _noteStore.notesForNotebook(null);
    final allLinks = await _noteStore.allLinks();

    final linkedIds = <String>{};
    for (final l in allLinks) {
      linkedIds.add(l.sourceNoteId);
      linkedIds.add(l.targetNoteId);
    }

    final unlinkedList = allNotes.where((n) => !linkedIds.contains(n.id)).toList();
    final targetNotes = scope == BatchOrganizeScope.allNotes ? allNotes : unlinkedList;

    return (
      totalNotes: allNotes.length,
      unlinkedNotes: unlinkedList.length,
      targetNotes: targetNotes,
    );
  }

  /// 执行批量 AI 整理调度循环
  Future<BatchOrganizeSummary> runBatch({
    BatchOrganizeScope scope = BatchOrganizeScope.allNotes,
    bool organizeTags = true,
    bool organizeLinks = true,
    BatchCancellationToken? cancellationToken,
    void Function(BatchOrganizeProgress progress)? onProgress,
  }) async {
    if (_isRunning) {
      throw StateError('Batch organizer is already running');
    }

    _isRunning = true;
    final token = cancellationToken ?? BatchCancellationToken();

    int tagsAdded = 0;
    int linksCreated = 0;
    int skippedNotes = 0;
    int failedNotes = 0;
    int processedCount = 0;

    try {
      final metrics = await getScopeMetrics(scope: scope);
      final queue = metrics.targetNotes;
      final total = queue.length;

      // 预缓存全局标签库，避免每次重复全量查表
      final existingAllTags = await _noteStore.allTags();
      final tagCacheByName = <String, String>{
        for (final t in existingAllTags) t.name: t.id,
      };

      for (var i = 0; i < queue.length; i++) {
        if (token.isCancelled) {
          return BatchOrganizeSummary(
            processedNotes: processedCount,
            totalNotes: total,
            tagsAdded: tagsAdded,
            linksCreated: linksCreated,
            skippedNotes: skippedNotes,
            failedNotes: failedNotes,
            wasCancelled: true,
          );
        }

        final note = queue[i];
        final plainText = AppFlowyCodec.jsonToPlainText(note.deltaJson).trim();

        // 通知进度：开始处理当前笔记
        onProgress?.call(BatchOrganizeProgress(
          current: i + 1,
          total: total,
          currentNoteTitle: note.title.isNotEmpty ? note.title : '无标题笔记',
          tagsAdded: tagsAdded,
          linksCreated: linksCreated,
          skippedNotes: skippedNotes,
          failedNotes: failedNotes,
        ));

        // 空白或过短笔记跳过（小于 5 个有效字符且标题为空）
        if (note.title.trim().isEmpty && plainText.length < 5) {
          skippedNotes++;
          processedCount++;
          continue;
        }

        try {
          // 单篇内并行请求标签与关联建议
          Future<List<String>> tagsTask = Future.value(const <String>[]);
          Future<List<LinkSuggestion>> linksTask = Future.value(const <LinkSuggestion>[]);

          if (organizeTags) {
            tagsTask = _kbService.suggestTags(note.id).catchError((e) {
              debugPrint('suggestTags failed for ${note.id}: $e');
              return const <String>[];
            });
          }

          if (organizeLinks) {
            linksTask = _kbService.suggestLinks(note.id).catchError((e) {
              debugPrint('suggestLinks failed for ${note.id}: $e');
              return const <LinkSuggestion>[];
            });
          }

          final results = await Future.wait([tagsTask, linksTask]);
          final suggestedTags = results[0] as List<String>;
          final suggestedLinks = results[1] as List<LinkSuggestion>;

          // 1. 自动安全落库标签
          if (suggestedTags.isNotEmpty) {
            final ownTags = await _noteStore.db.tagsForNote(note.id);
            final currentTagIds = ownTags.map((t) => t.id).toList();
            var addedThisNote = 0;

            for (final name in suggestedTags) {
              final trimmedName = name.trim();
              if (trimmedName.isEmpty) continue;

              var tagId = tagCacheByName[trimmedName];
              if (tagId == null) {
                tagId = await _noteStore.createTag(trimmedName);
                tagCacheByName[trimmedName] = tagId;
              }

              if (!currentTagIds.contains(tagId)) {
                currentTagIds.add(tagId);
                addedThisNote++;
              }
            }

            if (addedThisNote > 0) {
              await _noteStore.setNoteTags(note.id, currentTagIds);
              tagsAdded += addedThisNote;
            }
          }

          // 2. 自动安全落库关联关系
          if (suggestedLinks.isNotEmpty) {
            var createdThisNote = 0;
            for (final link in suggestedLinks) {
              if (link.noteId == note.id) continue; // 防自环
              try {
                await _noteStore.createLink(
                  note.id,
                  link.noteId,
                  reason: link.reason,
                );
                createdThisNote++;
              } catch (e) {
                debugPrint('createLink failed: $e');
              }
            }
            linksCreated += createdThisNote;
          }

          processedCount++;
        } catch (noteErr) {
          debugPrint('Error processing note ${note.id}: $noteErr');
          failedNotes++;
          processedCount++;
        }

        // 短暂休眠 30ms 释放调度时间片并平抑 API 峰值
        await Future.delayed(const Duration(milliseconds: 30));
      }

      return BatchOrganizeSummary(
        processedNotes: processedCount,
        totalNotes: total,
        tagsAdded: tagsAdded,
        linksCreated: linksCreated,
        skippedNotes: skippedNotes,
        failedNotes: failedNotes,
        wasCancelled: false,
      );
    } finally {
      _isRunning = false;
    }
  }
}
