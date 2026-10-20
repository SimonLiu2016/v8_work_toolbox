import 'package:flutter/material.dart';
import '../services/novel_repository.dart';
import '../services/novel_ai_editor_service.dart';

/// 章节阅读与编辑视图（支持在线修改、字数统计、AI 单章改写 Diff 对比与新章续写）
class ChapterEditorView extends StatefulWidget {
  final String novelId;
  final int chapterIndex;
  final VoidCallback? onChapterSaved;

  const ChapterEditorView({
    super.key,
    required this.novelId,
    required this.chapterIndex,
    this.onChapterSaved,
  });

  @override
  State<ChapterEditorView> createState() => _ChapterEditorViewState();
}

class _ChapterEditorViewState extends State<ChapterEditorView> {
  final NovelRepository _repo = NovelRepository.instance;
  final NovelAiEditorService _aiEditor = NovelAiEditorService.instance;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isAiBusy = false;
  String? _aiRewrittenPreview;

  @override
  void initState() {
    super.initState();
    _loadChapter();
  }

  @override
  void didUpdateWidget(covariant ChapterEditorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapterIndex != widget.chapterIndex || oldWidget.novelId != widget.novelId) {
      _loadChapter();
    }
  }

  Future<void> _loadChapter() async {
    setState(() {
      _isLoading = true;
      _aiRewrittenPreview = null;
    });

    final chapter = await _repo.getChapter(widget.novelId, widget.chapterIndex);
    if (chapter != null) {
      _titleController.text = chapter.title;
      _contentController.text = chapter.content;
    } else {
      _titleController.text = '第 ${widget.chapterIndex} 章';
      _contentController.text = '';
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCurrentChapter() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);

    try {
      await _repo.saveChapter(
        novelId: widget.novelId,
        chapterIndex: widget.chapterIndex,
        title: _titleController.text.trim(),
        content: _contentController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('章节保存成功')),
        );
      }
      widget.onChapterSaved?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showAiRewriteDialog() async {
    RewriteStyle selectedStyle = RewriteStyle.polish;
    final customPromptController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.amber),
              SizedBox(width: 8),
              Text('AI 章节改写与润色'),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('选择改写风格：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButton<RewriteStyle>(
                  value: selectedStyle,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: RewriteStyle.polish, child: Text('文笔润色 (提升修辞/语感)')),
                    DropdownMenuItem(value: RewriteStyle.expand, child: Text('细节扩写 (丰富感官与环境描写)')),
                    DropdownMenuItem(value: RewriteStyle.condense, child: Text('精简提炼 (节奏紧凑/去废话)')),
                    DropdownMenuItem(value: RewriteStyle.firstPerson, child: Text('第一人称视角 (深入主观心理)')),
                    DropdownMenuItem(value: RewriteStyle.thirdPerson, child: Text('第三人称视角 (上帝视角叙事)')),
                    DropdownMenuItem(value: RewriteStyle.dramatic, child: Text('增强戏剧冲突与悬念 (抓人爆点)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDlgState(() => selectedStyle = val);
                  },
                ),
                const SizedBox(height: 16),
                const Text('补充自定义指令（可选）：', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                TextField(
                  controller: customPromptController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '如：增加主角在危急时刻的心理独白，语言更具压迫感...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton.icon(
              icon: const Icon(Icons.bolt),
              label: const Text('开始改写'),
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _isAiBusy = true);
      try {
        final result = await _aiEditor.rewriteChapter(
          originalContent: _contentController.text,
          style: selectedStyle,
          customInstructions: customPromptController.text,
        );
        setState(() {
          _aiRewrittenPreview = result;
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('AI 改写失败: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _isAiBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final wordCount = _contentController.text.length;

    return Column(
      children: [
        // 顶部工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
            color: theme.colorScheme.surface,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _titleController,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                    hintText: '章节标题',
                    border: InputBorder.none,
                  ),
                ),
              ),
              Text(
                '字数: $wordCount',
                style: TextStyle(color: theme.textTheme.bodySmall?.color, fontSize: 13),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                icon: _isAiBusy
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome, size: 16, color: Colors.amber),
                label: const Text('AI 改写'),
                onPressed: _isAiBusy ? null : _showAiRewriteDialog,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: _isSaving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 16),
                label: const Text('保存'),
                onPressed: _isSaving ? null : _saveCurrentChapter,
              ),
            ],
          ),
        ),

        // 正文编辑区或 AI 改写对比区
        Expanded(
          child: _aiRewrittenPreview != null
              ? _buildDiffComparisonView(theme)
              : Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _contentController,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(fontSize: 15, height: 1.8),
                    decoration: const InputDecoration(
                      hintText: '请输入或编辑章节正文...',
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
        ),
      ],
    );
  }

  /// AI 改写效果对比确认面板
  Widget _buildDiffComparisonView(ThemeData theme) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.amber.withValues(alpha: 0.15),
          child: Row(
            children: [
              const Icon(Icons.compare_arrows, color: Colors.amber),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI 改写已生成！请对比右侧新文本，确认是否应用改写。', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              TextButton(
                onPressed: () => setState(() => _aiRewrittenPreview = null),
                child: const Text('放弃改写'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _contentController.text = _aiRewrittenPreview!;
                    _aiRewrittenPreview = null;
                  });
                  _saveCurrentChapter();
                },
                child: const Text('确认应用并保存'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              // 原文
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(border: Border(right: BorderSide(color: theme.dividerColor))),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('【改写前原文】', style: TextStyle(color: theme.colorScheme.secondary, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(_contentController.text, style: const TextStyle(fontSize: 14, height: 1.8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // AI 改写成果
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: theme.colorScheme.primary.withValues(alpha: 0.03),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('【AI 改写成果】', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: SelectableText(_aiRewrittenPreview!, style: const TextStyle(fontSize: 14, height: 1.8)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
