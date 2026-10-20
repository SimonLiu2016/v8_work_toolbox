import 'package:flutter/material.dart';
import '../models/novel_models.dart';
import '../services/novel_repository.dart';
import '../services/site_scraper_rule_service.dart';
import '../services/novel_scraper_coordinator.dart';
import '../services/novel_deduplication_service.dart';

/// 站点源小说库按分类多页探索、AI智能去重与批量采集弹窗
class SiteCatalogDiscoveryDialog extends StatefulWidget {
  final SiteScraperRule? initialRule;

  const SiteCatalogDiscoveryDialog({
    super.key,
    this.initialRule,
  });

  @override
  State<SiteCatalogDiscoveryDialog> createState() => _SiteCatalogDiscoveryDialogState();
}

class _SiteCatalogDiscoveryDialogState extends State<SiteCatalogDiscoveryDialog> {
  final SiteScraperRuleService _ruleService = SiteScraperRuleService.instance;
  final NovelScraperCoordinator _coordinator = NovelScraperCoordinator.instance;
  final NovelRepository _repo = NovelRepository.instance;
  final NovelDeduplicationService _dedupService = NovelDeduplicationService.instance;

  List<SiteScraperRule> _rules = [];
  SiteScraperRule? _selectedRule;

  // 分类与分页设置
  String _selectedCategoryKey = '1';
  int _startPage = 1;
  int _endPage = 10;
  int _totalWorksCount = 0;
  int _totalPagesCount = 0;

  bool _isExploring = false;
  bool _isDeduplicating = false;
  String? _statusMessage;
  String? _exploreError;

  List<DiscoveredNovelItem> _rawNovels = [];
  List<DiscoveredNovelItem> _displayNovels = [];
  final Set<String> _selectedUrls = {};
  Set<String> _existingSourceUrls = {};

  // 默认分类表（若规则未自定义则以此为默认）
  static const Map<String, String> _defaultCategories = {
    '1': '玄幻奇幻',
    '2': '武侠仙侠',
    '3': '女频言情',
    '4': '现代都市',
    '5': '历史军事',
    '6': '游戏竞技',
    '7': '科幻灵异',
    '8': '美文同人',
    '9': '其他类型',
  };

  Map<String, String> get _currentCategoryMap {
    if (_selectedRule != null && _selectedRule!.categoryMap.isNotEmpty) {
      return _selectedRule!.categoryMap;
    }
    return _defaultCategories;
  }

  @override
  void initState() {
    super.initState();
    _loadRules();
  }

  Future<void> _loadRules() async {
    final rules = await _ruleService.getRules();
    final localNovels = await _repo.getNovels();
    _existingSourceUrls = localNovels
        .map((n) => n.sourceUrl.trim())
        .where((u) => u.isNotEmpty)
        .toSet();

    if (mounted) {
      setState(() {
        _rules = rules;
        if (rules.isNotEmpty) {
          _selectedRule = widget.initialRule ?? rules.first;
          if (!_currentCategoryMap.containsKey(_selectedCategoryKey)) {
            _selectedCategoryKey = _currentCategoryMap.keys.first;
          }
        }
      });
      if (_selectedRule != null) {
        _startExplore();
      }
    }
  }

  void _onRuleChanged(SiteScraperRule? rule) {
    if (rule == null) return;
    setState(() {
      _selectedRule = rule;
      if (!_currentCategoryMap.containsKey(_selectedCategoryKey)) {
        _selectedCategoryKey = _currentCategoryMap.keys.first;
      }
      _rawNovels = [];
      _displayNovels = [];
      _selectedUrls.clear();
      _exploreError = null;
      _totalWorksCount = 0;
      _totalPagesCount = 0;
    });
    _startExplore();
  }

  Future<void> _startExplore() async {
    final rule = _selectedRule;
    if (rule == null) return;

    setState(() {
      _isExploring = true;
      _exploreError = null;
      _statusMessage = '正在连接源站扫描第 $_startPage ~ $_endPage 页分类列表...';
    });

    try {
      final pageResult = await _coordinator.exploreCategoryPages(
        rule: rule,
        categoryKey: _selectedCategoryKey,
        startPage: _startPage,
        endPage: _endPage,
        onProgress: (cur, total, count) {
          if (mounted) {
            setState(() {
              _statusMessage = '已抓取第 $cur/$total 页，累积发现原始条目 $count 条...';
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _isExploring = false;
        _totalWorksCount = pageResult.totalCount;
        _totalPagesCount = pageResult.totalPages;
        _rawNovels = pageResult.items;
      });

      // 抓取完毕后，全自动触发 AI 智能去重与书名净化
      await _runAiDeduplication();
    } catch (e) {
      if (mounted) {
        setState(() {
          _exploreError = e.toString();
          _isExploring = false;
          _statusMessage = null;
        });
      }
    }
  }

  /// 执行两阶段去重（本地预聚类 + AI 仲裁并自动净化书名）
  Future<void> _runAiDeduplication() async {
    if (_rawNovels.isEmpty) return;

    setState(() {
      _isDeduplicating = true;
      _statusMessage = '正在启动 AI 语义去重引擎（优选全集/无删减版本，清洗净化书名）...';
    });

    try {
      final deduped = await _dedupService.deduplicateWithAi(
        _rawNovels,
        onProgress: (status) {
          if (mounted) setState(() => _statusMessage = status);
        },
      );

      if (mounted) {
        setState(() {
          _isDeduplicating = false;
          _displayNovels = deduped;
          _statusMessage = '去重完成：原始 ${_rawNovels.length} 条变体 ➔ 保留 ${deduped.length} 部独立正版作品';
          // 默认勾选前 5 本未在本地书库的作品
          _selectedUrls.clear();
          for (final item in deduped) {
            if (!_isAlreadyCollected(item.detailUrl)) {
              _selectedUrls.add(item.detailUrl);
              if (_selectedUrls.length >= 5) break;
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDeduplicating = false;
          _displayNovels = _dedupService.deduplicateLocally(_rawNovels);
          _statusMessage = 'AI 处理异常，已自动切换为本地启发式规则去重完成';
        });
      }
    }
  }

  bool _isAlreadyCollected(String detailUrl) {
    final trimmed = detailUrl.trim();
    if (_existingSourceUrls.contains(trimmed)) return true;
    final noHttp = trimmed.replaceFirst('http://', '').replaceFirst('https://', '');
    return _existingSourceUrls.any((u) => u.contains(noHttp));
  }

  Future<void> _startBatchScrape() async {
    final rule = _selectedRule;
    if (rule == null || _selectedUrls.isEmpty) return;

    final itemsToScrape = _displayNovels.where((n) => _selectedUrls.contains(n.detailUrl)).toList();
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已成功将 ${itemsToScrape.length} 本小说加入后台并发增量采集队列！')),
    );

    // 逐个创建小说并启动后台增量采集
    for (final item in itemsToScrape) {
      final novel = await _repo.createNovel(
        title: item.title,
        author: item.author,
        sourceUrl: item.detailUrl,
        sourceSiteId: rule.id,
        genre: item.category ?? _currentCategoryMap[_selectedCategoryKey] ?? '',
        status: NovelStatus.ongoing,
      );

      // 后台触发章节与正文采集
      _coordinator.startScrape(
        novelId: novel.id,
        tocUrl: item.detailUrl,
        ruleId: rule.id,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 960,
        height: 680,
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部标题行
            Row(
              children: [
                const Icon(Icons.travel_explore, color: Colors.blueAccent, size: 28),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('分类书库多页探索与 AI 智能去重采集', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      _totalPagesCount > 0
                          ? '源站当前分类共 $_totalWorksCount 部作品 (共 $_totalPagesCount 页) • 支持批量多页拉取与 AI 仲裁优选'
                          : '自动计算全站总作品数与页数 • AI 语义识别并过滤同名变体 • 净化规范书名',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),

            // 操作控制面板：书源选择、分类下拉、页码范围、触发按钮
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 书源选择
                    SizedBox(
                      width: 200,
                      child: DropdownButtonFormField<SiteScraperRule>(
                        decoration: const InputDecoration(
                          labelText: '书源站点',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        initialValue: _selectedRule,
                        items: _rules.map((r) => DropdownMenuItem(value: r, child: Text(r.name, overflow: TextOverflow.ellipsis))).toList(),
                        onChanged: _isExploring ? null : _onRuleChanged,
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 分类下拉
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: '主菜单/类型',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        initialValue: _selectedCategoryKey,
                        items: _currentCategoryMap.entries.map((e) {
                          return DropdownMenuItem(value: e.key, child: Text('${e.key}.${e.value}'));
                        }).toList(),
                        onChanged: _isExploring ? null : (val) {
                          if (val != null) {
                            setState(() => _selectedCategoryKey = val);
                            _startExplore();
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 起止页码设置
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: _startPage.toString(),
                        decoration: const InputDecoration(
                          labelText: '起始页',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final p = int.tryParse(v);
                          if (p != null && p > 0) _startPage = p;
                        },
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Text('至'),
                    ),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        initialValue: _endPage.toString(),
                        decoration: const InputDecoration(
                          labelText: '结束页',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          final p = int.tryParse(v);
                          if (p != null && p > 0) _endPage = p;
                        },
                      ),
                    ),
                    const Spacer(),

                    // 开始检索按钮
                    FilledButton.icon(
                      icon: _isExploring
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.manage_search, size: 16),
                      label: const Text('多页检索'),
                      onPressed: (_isExploring || _isDeduplicating) ? null : _startExplore,
                    ),
                    const SizedBox(width: 8),

                    // 手动重新触发 AI 去重
                    OutlinedButton.icon(
                      icon: _isDeduplicating
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 16, color: Colors.purpleAccent),
                      label: const Text('AI 重新去重'),
                      onPressed: (_isExploring || _isDeduplicating || _rawNovels.isEmpty) ? null : _runAiDeduplication,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // 状态进度横条
            if (_statusMessage != null || _isExploring || _isDeduplicating)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    if (_isExploring || _isDeduplicating)
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    if (_isExploring || _isDeduplicating) const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _statusMessage ?? '',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),

            // 列表头部统计与勾选按钮
            if (_displayNovels.isNotEmpty)
              Row(
                children: [
                  Text(
                    '去重后共有 ${_displayNovels.length} 部作品，已勾选 ${_selectedUrls.length} 部',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 16),
                    label: const Text('勾选全部未采作品'),
                    onPressed: () {
                      setState(() {
                        final uncollected = _displayNovels
                            .where((n) => !_isAlreadyCollected(n.detailUrl))
                            .map((n) => n.detailUrl);
                        _selectedUrls.addAll(uncollected);
                      });
                    },
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedUrls.clear()),
                    child: const Text('清空选择'),
                  ),
                ],
              ),

            // 作品列表视图
            Expanded(
              child: _isExploring
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 14),
                          Text('正在抓取并加载源站多页分类列表，请稍候...'),
                        ],
                      ),
                    )
                  : _exploreError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                              const SizedBox(height: 12),
                              Text('抓取源站失败: $_exploreError', style: const TextStyle(color: Colors.redAccent)),
                              const SizedBox(height: 14),
                              ElevatedButton(onPressed: _startExplore, child: const Text('重试')),
                            ],
                          ),
                        )
                      : _displayNovels.isEmpty
                          ? const Center(child: Text('暂无小说，请点击上方“多页检索”开始扫描'))
                          : Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.dividerColor),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: ListView.separated(
                                itemCount: _displayNovels.length,
                                separatorBuilder: (_, __) => const Divider(height: 1),
                                itemBuilder: (ctx, i) {
                                  final novel = _displayNovels[i];
                                  final isCollected = _isAlreadyCollected(novel.detailUrl);
                                  final isSelected = _selectedUrls.contains(novel.detailUrl);

                                  return ListTile(
                                    leading: Checkbox(
                                      value: isSelected,
                                      onChanged: isCollected
                                          ? null // 严格幂等，已采集作品禁止重复勾选
                                          : (val) {
                                              setState(() {
                                                if (val == true) {
                                                  _selectedUrls.add(novel.detailUrl);
                                                } else {
                                                  _selectedUrls.remove(novel.detailUrl);
                                                }
                                              });
                                            },
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          novel.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.blueAccent.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            novel.category?.isNotEmpty == true
                                                ? novel.category!
                                                : _currentCategoryMap[_selectedCategoryKey] ?? '小说',
                                            style: const TextStyle(fontSize: 11, color: Colors.blueAccent),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        if (isCollected)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(Icons.check, size: 12, color: Colors.green),
                                                SizedBox(width: 2),
                                                Text('已在书库', style: TextStyle(fontSize: 11, color: Colors.green)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '作者: ${novel.author} | 最新章节: ${novel.latestChapter ?? "连载中"} | 更新时间: ${novel.lastUpdated ?? "近期"}',
                                          style: TextStyle(fontSize: 12, color: theme.textTheme.bodySmall?.color),
                                        ),
                                        if (novel.rawTitle != novel.title)
                                          Text(
                                            '源站原始标题: ${novel.rawTitle}',
                                            style: TextStyle(fontSize: 11, color: Colors.grey.withValues(alpha: 0.8)),
                                          ),
                                      ],
                                    ),
                                    trailing: isCollected
                                        ? const Text('无需重复采集', style: TextStyle(color: Colors.grey, fontSize: 12))
                                        : TextButton(
                                            onPressed: () {
                                              setState(() {
                                                if (isSelected) {
                                                  _selectedUrls.remove(novel.detailUrl);
                                                } else {
                                                  _selectedUrls.add(novel.detailUrl);
                                                }
                                              });
                                            },
                                            child: Text(isSelected ? '取消勾选' : '勾选采集'),
                                          ),
                                  );
                                },
                              ),
                            ),
            ),
            const SizedBox(height: 12),

            // 底部操作栏
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.download_for_offline),
                  label: Text('开始批量采集所选小说 (${_selectedUrls.length} 本)'),
                  onPressed: _selectedUrls.isEmpty ? null : _startBatchScrape,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
