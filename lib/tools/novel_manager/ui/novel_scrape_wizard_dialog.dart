import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_repository.dart';
import '../services/site_scraper_rule_service.dart';
import '../services/novel_scraper_coordinator.dart';

/// 首页“网络采集”新建小说采集向导弹窗
class NovelScrapeWizardDialog extends StatefulWidget {
  const NovelScrapeWizardDialog({super.key});

  @override
  State<NovelScrapeWizardDialog> createState() => _NovelScrapeWizardDialogState();
}

class _NovelScrapeWizardDialogState extends State<NovelScrapeWizardDialog> {
  final SiteScraperRuleService _ruleService = SiteScraperRuleService.instance;
  final NovelRepository _repo = NovelRepository.instance;
  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;

  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _authorController = TextEditingController();

  List<SiteScraperRule> _rules = [];
  bool _isLoadingRules = true;
  SiteScraperRule? _selectedRule;

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoadingRules = true);
    final rules = await _ruleService.getRules();
    if (mounted) {
      setState(() {
        _rules = rules;
        _isLoadingRules = false;
        if (rules.isNotEmpty) _selectedRule = rules.first;
      });
    }
  }

  void _onUrlChanged(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;

    // 智能根据输入的 URL 自动匹配最佳书源规则
    for (final r in _rules) {
      if (r.baseUrl.isNotEmpty && trimmed.contains(Uri.tryParse(r.baseUrl)?.host ?? '')) {
        setState(() => _selectedRule = r);
        break;
      }
    }
  }

  Future<void> _startScrapeAndCreate() async {
    final url = _urlController.text.trim();
    final rule = _selectedRule;
    if (url.isEmpty || rule == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写小说目录页网址并选择书源规则')),
      );
      return;
    }

    String title = _titleController.text.trim();
    String author = _authorController.text.trim();

    if (title.isEmpty) {
      // 默认先以未命名小说占位，采集目录后或后续可自动更名
      title = '网络采集小说_${DateTime.now().month}月${DateTime.now().day}日';
    }
    if (author.isEmpty) author = '网络作者';

    Navigator.pop(context);

    // 1. 创建小说记录
    final novel = await _repo.createNovel(
      title: title,
      author: author,
      sourceUrl: url,
      sourceSiteId: rule.id,
      status: NovelStatus.ongoing,
    );

    // 2. 触发后台采集
    await _coordinator.startScrape(
      novelId: novel.id,
      tocUrl: url,
      ruleId: rule.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 640,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.travel_explore, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 8),
                const Text('新建网络小说采集任务', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),

            const Text('小说目录页网址 (TOC URL)：*', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: '如: https://www.szlajc.com/book/12345/ 或其他小说目录页',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: _onUrlChanged,
            ),
            const SizedBox(height: 14),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('小说书名 (选填，留空自动生成)：', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _titleController,
                        decoration: const InputDecoration(hintText: '如: 斗破苍穹', border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('小说作者 (选填)：', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _authorController,
                        decoration: const InputDecoration(hintText: '如: 天蚕土豆', border: OutlineInputBorder(), isDense: true),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            const Text('匹配书源规则：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _isLoadingRules
                ? const Center(child: CircularProgressIndicator())
                : DropdownButtonFormField<SiteScraperRule>(
                    value: _selectedRule,
                    isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: _rules.map((r) {
                      return DropdownMenuItem(
                        value: r,
                        child: Text('${r.name} (${r.baseUrl})${r.enableBypass ? ' [反爬穿透/CF]' : ''}'),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRule = val);
                    },
                  ),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                const SizedBox(width: 10),
                FilledButton.icon(
                  icon: const Icon(Icons.cloud_download),
                  label: const Text('立即建书并开始增量采集'),
                  onPressed: _startScrapeAndCreate,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
