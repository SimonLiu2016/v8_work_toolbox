import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_repository.dart';

/// 编辑小说基本属性对话框
class NovelEditPropertiesDialog extends StatefulWidget {
  final NovelMetadata novel;

  const NovelEditPropertiesDialog({super.key, required this.novel});

  @override
  State<NovelEditPropertiesDialog> createState() => _NovelEditPropertiesDialogState();
}

class _NovelEditPropertiesDialogState extends State<NovelEditPropertiesDialog> {
  final NovelRepository _repo = NovelRepository.instance;

  late TextEditingController _titleCtrl;
  late TextEditingController _authorCtrl;
  late TextEditingController _genreCtrl;
  late TextEditingController _tagsCtrl;
  late TextEditingController _descCtrl;
  late double _heatScore;
  late double _recommendScore;
  late NovelStatus _status;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.novel.title);
    _authorCtrl = TextEditingController(text: widget.novel.author);
    _genreCtrl = TextEditingController(text: widget.novel.genre);
    _tagsCtrl = TextEditingController(text: widget.novel.tags.join(', '));
    _descCtrl = TextEditingController(text: widget.novel.description);
    _heatScore = widget.novel.heatScore;
    _recommendScore = widget.novel.recommendScore;
    _status = widget.novel.status;
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('书名不能为空')));
      return;
    }

    final tags = _tagsCtrl.text
        .split(RegExp(r'[,，\s]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    final updated = widget.novel.copyWith(
      title: title,
      author: _authorCtrl.text.trim().isNotEmpty ? _authorCtrl.text.trim() : '佚名',
      genre: _genreCtrl.text.trim(),
      tags: tags,
      description: _descCtrl.text.trim(),
      heatScore: _heatScore,
      recommendScore: _recommendScore,
      status: _status,
      updatedAt: DateTime.now(),
    );

    await _repo.saveNovel(updated);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        padding: const EdgeInsets.all(22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, color: Colors.blueAccent, size: 24),
                  const SizedBox(width: 8),
                  const Text('编辑小说属性与背景设定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: '书名 *', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _authorCtrl,
                      decoration: const InputDecoration(labelText: '作者', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _genreCtrl,
                      decoration: const InputDecoration(labelText: '主分类/题材 (如: 科幻、都市、玄幻)', border: OutlineInputBorder(), isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<NovelStatus>(
                      value: _status,
                      decoration: const InputDecoration(labelText: '连载状态', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: NovelStatus.ongoing, child: Text('连载中')),
                        DropdownMenuItem(value: NovelStatus.completed, child: Text('已完结')),
                        DropdownMenuItem(value: NovelStatus.draft, child: Text('本地草稿')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _status = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _tagsCtrl,
                decoration: const InputDecoration(
                  labelText: '类型标签 (多个标签用逗号或空格隔开)',
                  hintText: '如: 穿越, 系统, 热血, 爽文',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: _descCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '故事背景描述与剧情主线简介',
                  hintText: '用于向 AI 传递全剧设定、角色阵营与世界观背景...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('推荐指数: ${_recommendScore.toStringAsFixed(1)} / 100'),
                        Slider(
                          value: _recommendScore,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) => setState(() => _recommendScore = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('热度评分: ${_heatScore.toStringAsFixed(1)} / 100'),
                        Slider(
                          value: _heatScore,
                          min: 0,
                          max: 100,
                          divisions: 100,
                          onChanged: (v) => setState(() => _heatScore = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: _save, child: const Text('保存修改')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
