import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_export_service.dart';

/// 小说统一格式导出弹窗
class NovelExportDialog extends StatefulWidget {
  final NovelMetadata novel;
  final List<NovelChapterIndex> chapters;

  const NovelExportDialog({
    super.key,
    required this.novel,
    required this.chapters,
  });

  @override
  State<NovelExportDialog> createState() => _NovelExportDialogState();
}

class _NovelExportDialogState extends State<NovelExportDialog> {
  final NovelExportService _exportService = NovelExportService.instance;

  NovelExportFormat _format = NovelExportFormat.txt;
  bool _exportAllChapters = true;
  final Set<int> _selectedIndices = {};
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _selectedIndices.addAll(widget.chapters.map((c) => c.chapterIndex));
  }

  Future<void> _doExport() async {
    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择导出保存目录',
    );

    if (selectedPath == null) return;
    final targetDir = Directory(selectedPath);

    setState(() => _isExporting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final indices = _exportAllChapters
          ? widget.chapters.map((c) => c.chapterIndex).toList()
          : _selectedIndices.toList();

      final exportedFile = await _exportService.exportNovel(
        novelId: widget.novel.id,
        chapterIndices: indices,
        format: _format,
        targetDir: targetDir,
      );

      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('导出成功！已保存至: ${exportedFile.path}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 480,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.download, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text('导出《${widget.novel.title}》', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            const Text('选择导出格式：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<NovelExportFormat>(
              segments: const [
                ButtonSegment(value: NovelExportFormat.txt, label: Text('TXT 纯文本')),
                ButtonSegment(value: NovelExportFormat.markdown, label: Text('Markdown')),
                ButtonSegment(value: NovelExportFormat.epub, label: Text('EPUB 电子书')),
                ButtonSegment(value: NovelExportFormat.json, label: Text('JSON 结构体')),
              ],
              selected: {_format},
              onSelectionChanged: (val) => setState(() => _format = val.first),
            ),

            const SizedBox(height: 20),
            const Text('选择章节范围：', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Radio<bool>(
                  value: true,
                  groupValue: _exportAllChapters,
                  onChanged: (v) => setState(() => _exportAllChapters = v ?? true),
                ),
                Text('全部章节 (共 ${widget.chapters.length} 章)'),
                const SizedBox(width: 16),
                Radio<bool>(
                  value: false,
                  groupValue: _exportAllChapters,
                  onChanged: (v) => setState(() => _exportAllChapters = v ?? false),
                ),
                const Text('自定义挑选章节'),
              ],
            ),

            if (!_exportAllChapters) ...[
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.builder(
                    itemCount: widget.chapters.length,
                    itemBuilder: (ctx, i) {
                      final ch = widget.chapters[i];
                      final isSelected = _selectedIndices.contains(ch.chapterIndex);
                      return CheckboxListTile(
                        dense: true,
                        title: Text(ch.title),
                        subtitle: Text('${ch.wordCount} 字'),
                        value: isSelected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selectedIndices.add(ch.chapterIndex);
                            } else {
                              _selectedIndices.remove(ch.chapterIndex);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
            ] else
              const Spacer(),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: _isExporting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_download),
                  label: const Text('选择文件夹并导出'),
                  onPressed: _isExporting ? null : _doExport,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
