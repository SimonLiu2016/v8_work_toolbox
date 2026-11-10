import 'package:flutter/material.dart';
import '../../../services/privacy_security_service.dart';
import '../models/drama_models.dart';
import '../services/casual_short_drama_controller.dart';
import 'drama_episode_drawer.dart';
import 'drama_theater_surface.dart';
import 'widgets/drama_cover_widget.dart';

/// 隐私空间「随心短剧」主工作台页面
/// 采用两态桌面架构：
/// 1. 浏览态 (Browse Mode)：全宽网格片库探索，自适应海报流与分类
/// 2. 观影态 (Theater Mode)：大屏 16:9/自适应剧场 + 右侧常驻选集面板 + 一键返回片库
class CasualShortDramaPage extends StatefulWidget {
  const CasualShortDramaPage({super.key});

  @override
  State<CasualShortDramaPage> createState() => _CasualShortDramaPageState();
}

class _CasualShortDramaPageState extends State<CasualShortDramaPage> {
  late final CasualShortDramaController _controller;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();
  bool _showDrawer = true; // 观影态默认开启右侧选集面板
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    _controller = CasualShortDramaController.instance;
    _controller.addListener(_onControllerUpdated);
    _gridScrollController.addListener(_onGridScroll);
    _controller.init();
  }

  void _onGridScroll() {
    if (!_gridScrollController.hasClients) return;
    final maxScroll = _gridScrollController.position.maxScrollExtent;
    final currentScroll = _gridScrollController.position.pixels;
    if (maxScroll - currentScroll <= 350) {
      _controller.loadMoreCatalog();
    }
  }

  void _onControllerUpdated() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _gridScrollController.removeListener(_onGridScroll);
    _gridScrollController.dispose();
    _controller.removeListener(_onControllerUpdated);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPlayingDrama = _controller.currentDrama != null;

    final pageContent = Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: isPlayingDrama
            ? _buildTheaterView(theme)
            : _buildBrowseView(theme),
      ),
    );

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerHover: (_) => PrivacySecurityService.instance.recordActivity(),
      onPointerDown: (_) => PrivacySecurityService.instance.recordActivity(),
      onPointerSignal: (_) => PrivacySecurityService.instance.recordActivity(),
      onPointerMove: (_) => PrivacySecurityService.instance.recordActivity(),
      child: pageContent,
    );
  }

  // ==========================================
  // 1. 观影态 (Theater Mode)
  // ==========================================

  Widget _buildTheaterView(ThemeData theme) {
    return Row(
      key: const ValueKey('theater_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 主剧场视窗
        Expanded(
          child: DramaTheaterSurface(
            controller: _controller,
            onToggleDrawer: () {
              setState(() {
                _showDrawer = !_showDrawer;
              });
            },
            onBackToCatalog: () => _controller.exitTheater(),
            onFullscreenChanged: (isFull) {
              setState(() {
                _isFullscreen = isFull;
              });
            },
          ),
        ),

        // 右侧选集面板（真全屏时自动收起）
        if (_showDrawer && !_isFullscreen)
          Container(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: DramaEpisodeDrawer(
              controller: _controller,
              onClose: () {
                setState(() {
                  _showDrawer = false;
                });
              },
            ),
          ),
      ],
    );
  }

  // ==========================================
  // 2. 浏览态 (Browse Mode)
  // ==========================================

  Widget _buildBrowseView(ThemeData theme) {
    return Column(
      key: const ValueKey('browse_view'),
      children: [
        _buildBrowseHeader(theme),
        _buildCategoryTabBar(theme),
        _buildGenreAndSortFilterBar(theme),
        const Divider(height: 1, thickness: 0.5),
        Expanded(child: _buildDramaGridContent(theme)),
      ],
    );
  }

  Widget _buildBrowseHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.live_tv_rounded, color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 10),
          const Text(
            '随心短剧',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 0.3),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '纯净聚合',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Spacer(),

          // 搜索框
          SizedBox(
            width: 320,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索精彩短剧、主角名...',
                prefixIcon: const Icon(Icons.search_rounded, size: 18),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        onPressed: () {
                          _searchController.clear();
                          _controller.search('');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (query) => _controller.search(query),
            ),
          ),
          const SizedBox(width: 12),

          IconButton(
            icon: const Icon(Icons.alt_route_rounded, size: 20),
            tooltip: '线路设置与测速',
            onPressed: _showLineSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: '刷新片库',
            onPressed: () => _controller.refreshCatalog(),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabBar(ThemeData theme) {
    final tabs = [
      {'id': 'all', 'label': '全部 (3300+部)'},
      {'id': 'hot', 'label': '热榜'},
      {'id': 'recommend', 'label': '精选'},
      {'id': 'potential', 'label': '新剧'},
      {'id': 'favorites', 'label': '私密收藏'},
      {'id': 'history', 'label': '观看历史'},
    ];

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: Alignment.centerLeft,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final isSelected = _controller.currentTab == tab['id'] && _controller.currentSearchQuery.isEmpty;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Text(tab['label']!, style: const TextStyle(fontSize: 13)),
              selected: isSelected,
              showCheckmark: false,
              onSelected: (_) {
                _searchController.clear();
                _controller.switchTab(tab['id']!);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildGenreAndSortFilterBar(ThemeData theme) {
    // 仅在全部、推荐或搜索态显示题材过滤栏
    final showGenreFilter = _controller.currentTab == 'all' || _controller.currentTab == 'feed';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: Row(
        children: [
          // 题材标签选择栏
          if (showGenreFilter) ...[
            const Icon(Icons.label_outline_rounded, size: 16, color: Colors.grey),
            const SizedBox(width: 6),
            Expanded(
              child: SizedBox(
                height: 32,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // 全部题材
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: const Text('全部题材', style: TextStyle(fontSize: 12)),
                        selected: _controller.selectedTag.isEmpty,
                        showCheckmark: false,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          _controller.selectTag('');
                        },
                      ),
                    ),
                    // 热门题材标签
                    ...CasualShortDramaController.popularTags.map((tag) {
                      final isSelected = _controller.selectedTag == tag;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          showCheckmark: false,
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) {
                            _controller.selectTag(tag);
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
          ] else
            const Spacer(),

          // 排序选择控件
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sort_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                DropdownButton<DramaSortType>(
                  value: _controller.sortType,
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  borderRadius: BorderRadius.circular(8),
                  items: DramaSortType.values.map((sort) {
                    return DropdownMenuItem(
                      value: sort,
                      child: Text(
                        sort.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _controller.sortType == sort ? FontWeight.bold : FontWeight.normal,
                          color: _controller.sortType == sort ? theme.colorScheme.primary : null,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      _controller.setSortType(val);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDramaGridContent(ThemeData theme) {
    if (_controller.isLoadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.catalogError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(
                '加载失败: ${_controller.catalogError}',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: theme.colorScheme.error),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => _controller.refreshCatalog(),
                child: const Text('重试或切换数据线路'),
              ),
            ],
          ),
        ),
      );
    }

    // 私密收藏页展示
    if (_controller.currentTab == 'favorites' && _controller.currentSearchQuery.isEmpty) {
      if (_controller.favorites.isEmpty) {
        return const Center(
          child: Text('暂无私密收藏，在剧集中点击爱心即可收藏', style: TextStyle(color: Colors.grey, fontSize: 14)),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 300).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.8,
            ),
            itemCount: _controller.favorites.length,
            itemBuilder: (context, index) {
              final fav = _controller.favorites[index];
              return _buildFavoriteListItem(fav, theme);
            },
          );
        },
      );
    }

    // 观看历史页展示
    if (_controller.currentTab == 'history' && _controller.currentSearchQuery.isEmpty) {
      if (_controller.history.isEmpty) {
        return const Center(
          child: Text('暂无播放记录，点击短剧即刻起播', style: TextStyle(color: Colors.grey, fontSize: 14)),
        );
      }
      return LayoutBuilder(
        builder: (context, constraints) {
          final columns = (constraints.maxWidth / 300).floor().clamp(1, 4);
          return GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 2.8,
            ),
            itemCount: _controller.history.length,
            itemBuilder: (context, index) {
              final his = _controller.history[index];
              return _buildHistoryListItem(his, theme);
            },
          );
        },
      );
    }

    // 默认短剧卡片全宽大网格（支持无限滚动追加加载）
    final list = _controller.catalogItems;
    if (list.isEmpty) {
      return const Center(
        child: Text('未找到相关短剧', style: TextStyle(color: Colors.grey, fontSize: 14)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 自适应每列海报宽约 190px，列数在 2 到 8 列之间自动响应
        final columns = (constraints.maxWidth / 190).floor().clamp(2, 8);

        return CustomScrollView(
          controller: _gridScrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 18,
                  crossAxisSpacing: 16,
                  childAspectRatio: 0.65,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final card = list[index];
                    return _buildDramaCardItem(card, theme);
                  },
                  childCount: list.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32, top: 12),
                child: Center(
                  child: _buildLoadMoreFooter(theme, list.length),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadMoreFooter(ThemeData theme, int currentCount) {
    if (_controller.isLoadingMoreCatalog) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '正在加载更多精彩短剧...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      );
    }

    if (_controller.loadMoreError != null) {
      return TextButton.icon(
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: Text('加载失败，点击重试 (${_controller.loadMoreError})', style: const TextStyle(fontSize: 12)),
        onPressed: () => _controller.loadMoreCatalog(),
      );
    }

    if (!_controller.hasMoreCatalog && currentCount > 0) {
      return Text(
        '—— 已呈现全部短剧 (共 $currentCount 部) ——',
        style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildDramaCardItem(DramaCard card, ThemeData theme) {
    return InkWell(
      onTap: () {
        _controller.openDrama(card);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  DramaCoverWidget(
                    coverUrl: card.cover,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        card.totalEpisodes > 0 ? '${card.totalEpisodes}集全' : '更新中',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (card.score > 0) ...[
                        Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade700),
                        const SizedBox(width: 2),
                        Text(
                          card.score.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (card.tags.isNotEmpty)
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: card.tags.take(2).map((tag) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: InkWell(
                                    onTap: () => _controller.selectTag(tag),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteListItem(DramaFavoriteItem fav, ThemeData theme) {
    return InkWell(
      onTap: () => _controller.openDrama(fav.dramaId),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 55,
              height: 75,
              child: DramaCoverWidget(
                coverUrl: fav.cover,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    fav.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '共 ${fav.episodeCount} 集',
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.favorite_rounded, color: Colors.redAccent, size: 18),
              tooltip: '取消收藏',
              onPressed: () async {
                await _controller.removeFavorite(fav.dramaId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryListItem(DramaHistoryItem his, ThemeData theme) {
    return InkWell(
      onTap: () => _controller.openDrama(his.dramaId, startEp: his.lastWatchedEp),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 55,
              height: 75,
              child: DramaCoverWidget(
                coverUrl: his.cover,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    his.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '上次观看到第 ${his.lastWatchedEp} 集',
                    style: TextStyle(fontSize: 12, color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              tooltip: '删除此条记录',
              onPressed: () async {
                await _controller.removeHistory(his.dramaId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showLineSettingsDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final state = _controller.lineState;

            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.alt_route_rounded),
                  SizedBox(width: 8),
                  Text('数据线路与测速'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '当前使用线路: ${state.currentBase}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      const Text('官方固定线路：', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ...state.fixedLines.map((line) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(line.name, style: const TextStyle(fontSize: 13)),
                            subtitle: Text(line.url, style: const TextStyle(fontSize: 11)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (line.latencyMs != null)
                                  Text(
                                    '${line.latencyMs}ms',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: line.latencyMs! < 500 ? Colors.green : Colors.orange,
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                if (state.currentBase == line.url)
                                  const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18)
                                else
                                  TextButton(
                                    onPressed: () {
                                      _controller.switchBaseUrl(line.url);
                                      Navigator.pop(ctx);
                                    },
                                    child: const Text('切换'),
                                  ),
                              ],
                            ),
                          )),
                      const SizedBox(height: 8),
                      if (state.mirrorLines.isNotEmpty) ...[
                        const Text('发布页镜像线路：', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ...state.mirrorLines.take(6).map((line) => ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(line.name, style: const TextStyle(fontSize: 13)),
                              subtitle: Text(line.url, style: const TextStyle(fontSize: 11)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (line.latencyMs != null)
                                    Text(
                                      '${line.latencyMs}ms',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: line.latencyMs! < 500 ? Colors.green : Colors.orange,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  if (state.currentBase == line.url)
                                    const Icon(Icons.check_circle_rounded, color: Colors.green, size: 18)
                                  else
                                    TextButton(
                                      onPressed: () {
                                        _controller.switchBaseUrl(line.url);
                                        Navigator.pop(ctx);
                                      },
                                      child: const Text('切换'),
                                    ),
                                ],
                              ),
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton.icon(
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: const Text('拉取镜像并测速'),
                  onPressed: () async {
                    await _controller.refreshAndProbeLines();
                    setDialogState(() {});
                  },
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
