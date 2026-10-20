import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/novel_models.dart';
import '../services/site_scraper_rule_service.dart';
import '../services/novel_scraper_coordinator.dart';
import 'site_catalog_discovery_dialog.dart';

/// 站点源管理（列表、新增、编辑、删除与测试连接）
class SiteRuleManagerDialog extends StatefulWidget {
  final String? targetNovelId;
  final String? targetNovelTitle;

  const SiteRuleManagerDialog({
    super.key,
    this.targetNovelId,
    this.targetNovelTitle,
  });

  @override
  State<SiteRuleManagerDialog> createState() => _SiteRuleManagerDialogState();
}

class _SiteRuleManagerDialogState extends State<SiteRuleManagerDialog> {
  final SiteScraperRuleService _ruleService = SiteScraperRuleService.instance;
  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;

  List<SiteScraperRule> _rules = [];
  bool _isLoading = true;
  SiteScraperRule? _selectedRule;

  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    setState(() => _isLoading = true);
    final rules = await _ruleService.getRules();
    if (mounted) {
      setState(() {
        _rules = rules;
        _isLoading = false;
        if (rules.isNotEmpty && _selectedRule == null) {
          _selectedRule = rules.first;
        }
      });
    }
  }

  Future<void> _openRuleEditDialog([SiteScraperRule? existingRule]) async {
    final isNew = existingRule == null;
    final nameCtrl = TextEditingController(text: existingRule?.name ?? '');
    final baseCtrl = TextEditingController(text: existingRule?.baseUrl ?? '');
    final tocCtrl = TextEditingController(text: existingRule?.tocSelector ?? '#list dl dd a, a');
    final contentCtrl = TextEditingController(text: existingRule?.contentSelector ?? '#content');
    final titleCtrl = TextEditingController(text: existingRule?.titleSelector ?? 'h1');
    final catalogUrlCtrl = TextEditingController(text: existingRule?.catalogUrl ?? '');
    final catalogSelectorCtrl = TextEditingController(text: existingRule?.catalogSelector ?? '#newscontent .l ul li');
    final cronCtrl = TextEditingController(text: existingRule?.cronExpression ?? '0 */6 * * *');
    bool bypass = existingRule?.enableBypass ?? false;
    bool cronEnabled = existingRule?.isCronEnabled ?? false;
    int delayMs = existingRule?.requestDelayMs ?? 500;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(isNew ? '新建书源规则' : '编辑书源规则: ${existingRule.name}'),
          content: SizedBox(
            width: 540,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: '书源站点名称 *', hintText: '如: 神州中文网', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: baseCtrl,
                    decoration: const InputDecoration(labelText: '站点根网址 (Base URL) *', hintText: '如: https://www.szlajc.com', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: tocCtrl,
                          decoration: const InputDecoration(labelText: '目录章节 CSS 选择器', hintText: '#list a', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: contentCtrl,
                          decoration: const InputDecoration(labelText: '正文容器 CSS 选择器', hintText: '#content', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: '章节标题 CSS 选择器', hintText: 'h1', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: catalogUrlCtrl,
                          decoration: const InputDecoration(
                            labelText: '站点小说库/书库网址',
                            hintText: '如: http://www.szlajc.com/class/1_1/',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: catalogSelectorCtrl,
                          decoration: const InputDecoration(
                            labelText: '书库书籍条目选择器',
                            hintText: '#newscontent ul li',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('启用反爬穿透 (Firecrawl / CF盾绕过)'),
                    subtitle: const Text('针对 Cloudflare Turnstile、类似 szlajc.com 等强防护站点开启'),
                    value: bypass,
                    onChanged: (v) => setDlgState(() => bypass = v),
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('开启定时巡检更新'),
                    subtitle: const Text('后台定时器周期性检查连载小说是否有新章节'),
                    value: cronEnabled,
                    onChanged: (v) => setDlgState(() => cronEnabled = v),
                  ),
                  if (cronEnabled) ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: cronCtrl,
                      decoration: const InputDecoration(labelText: 'Cron 调度表达式', hintText: '0 */6 * * * (每6小时一次)', border: OutlineInputBorder()),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final baseUrl = baseCtrl.text.trim();
                if (name.isEmpty || baseUrl.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请填写完整的书源名称与根网址')));
                  return;
                }

                final rule = SiteScraperRule(
                  id: existingRule?.id ?? const Uuid().v4(),
                  name: name,
                  baseUrl: baseUrl,
                  enableBypass: bypass,
                  tocSelector: tocCtrl.text.trim(),
                  contentSelector: contentCtrl.text.trim(),
                  titleSelector: titleCtrl.text.trim(),
                  catalogUrl: catalogUrlCtrl.text.trim(),
                  catalogSelector: catalogSelectorCtrl.text.trim(),
                  isCronEnabled: cronEnabled,
                  cronExpression: cronCtrl.text.trim(),
                  requestDelayMs: delayMs,
                );

                await _ruleService.saveRule(rule);
                Navigator.pop(ctx, true);
              },
              child: const Text('保存书源'),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      await _loadRules();
    }
  }

  Future<void> _startScrape() async {
    final novelId = widget.targetNovelId;
    final rule = _selectedRule;
    final url = _urlController.text.trim();

    if (novelId == null || rule == null || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写完整的采集目标小说目录页网址')),
      );
      return;
    }

    Navigator.pop(context);
    await _coordinator.startScrape(
      novelId: novelId,
      tocUrl: url,
      ruleId: rule.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 780,
        height: 580,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.settings_suggest, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  widget.targetNovelTitle != null
                      ? '为《${widget.targetNovelTitle}》配置网络采集'
                      : '书源站点与定制采集器管理',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.icon(
                  icon: const Icon(Icons.auto_stories, size: 16),
                  label: const Text('探索书库'),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (_) => SiteCatalogDiscoveryDialog(initialRule: _selectedRule),
                    );
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加新书源'),
                  onPressed: () => _openRuleEditDialog(),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            if (widget.targetNovelId != null) ...[
              const Text('目标小说目录页网址 (TOC URL):', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  hintText: '如: https://www.szlajc.com/book/12345/ 或普通小说目录地址',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 14),
            ],

            const Text('已配置的书源规则列表：', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _rules.length,
                      itemBuilder: (ctx, i) {
                        final r = _rules[i];
                        final isSelected = r.id == _selectedRule?.id;
                        return Card(
                          elevation: isSelected ? 2 : 0,
                          color: isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: ListTile(
                            title: Row(
                              children: [
                                Text(r.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                if (r.enableBypass)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('反爬穿透/CF盾', style: TextStyle(color: Colors.deepOrange, fontSize: 11)),
                                  ),
                                if (r.isCronEnabled) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text('定时巡检', style: TextStyle(color: Colors.green, fontSize: 11)),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text('根域名: ${r.baseUrl} | 目录选择器: ${r.tocSelector} | 正文: ${r.contentSelector}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.auto_stories, size: 18, color: Colors.indigoAccent),
                                  tooltip: '探索此源站书库',
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => SiteCatalogDiscoveryDialog(initialRule: r),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  tooltip: '编辑此书源规则',
                                  onPressed: () => _openRuleEditDialog(r),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                                  tooltip: '删除此书源',
                                  onPressed: () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (c) => AlertDialog(
                                        title: Text('确认删除书源《${r.name}》？'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                                          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                                        ],
                                      ),
                                    );
                                    if (ok == true) {
                                      await _ruleService.deleteRule(r.id);
                                      _loadRules();
                                    }
                                  },
                                ),
                              ],
                            ),
                            onTap: () => setState(() => _selectedRule = r),
                          ),
                        );
                      },
                    ),
            ),

            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
                if (widget.targetNovelId != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始幂等增量采集'),
                    onPressed: _startScrape,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
