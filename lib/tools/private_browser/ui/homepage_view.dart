import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../services/app_paths.dart';
import '../../../theme/app_theme.dart';
import '../services/private_browser_repository.dart';
import '../services/private_browser_service.dart';

/// 私密浏览器 N 宫格快捷方式首页视图
class HomepageView extends StatefulWidget {
  final ValueChanged<String> onOpenUrl;

  const HomepageView({
    super.key,
    required this.onOpenUrl,
  });

  @override
  State<HomepageView> createState() => _HomepageViewState();
}

class _HomepageViewState extends State<HomepageView> {
  final PrivateBrowserRepository _repo = PrivateBrowserService.instance.repository;
  final TextEditingController _searchController = TextEditingController();

  List<HomepageShortcutItem> _shortcuts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShortcuts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadShortcuts() async {
    final list = await _repo.getShortcuts();
    if (mounted) {
      setState(() {
        _shortcuts = list;
        _isLoading = false;
      });
    }
  }

  void _handleSearchOrNavigate(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      widget.onOpenUrl(trimmed);
    } else if (trimmed.contains('.') && !trimmed.contains(' ')) {
      widget.onOpenUrl('https://$trimmed');
    } else {
      // 默认走 Google 搜索
      widget.onOpenUrl('https://www.google.com/search?q=${Uri.encodeComponent(trimmed)}');
    }
  }

  Future<void> _showAddShortcutDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('添加快捷站点', style: TextStyle(color: context.textPrimary, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: '网站名称',
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: '如 YouTube',
                hintStyle: TextStyle(color: context.textTertiary),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: '网站网址',
                labelStyle: TextStyle(color: context.textSecondary),
                hintText: 'https://...',
                hintStyle: TextStyle(color: context.textTertiary),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: TextStyle(color: context.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.accentSolid,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('添加'),
          ),
        ],
      ),
    );

    if (confirmed == true && nameCtrl.text.trim().isNotEmpty && urlCtrl.text.trim().isNotEmpty) {
      var urlStr = urlCtrl.text.trim();
      if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
        urlStr = 'https://$urlStr';
      }

      // 异步抓取 favicon
      String? cachedFaviconPath;
      try {
        final uri = Uri.parse(urlStr);
        final faviconUrl = '${uri.scheme}://${uri.host}/favicon.ico';
        final resp = await http.get(Uri.parse(faviconUrl)).timeout(const Duration(seconds: 4));
        if (resp.statusCode == 200 && resp.bodyBytes.length > 50) {
          final fileName = 'fav_${uri.host.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.ico';
          final file = File(p.join(AppPaths.privateBrowserThumbnailsDir.path, fileName));
          await file.writeAsBytes(resp.bodyBytes);
          cachedFaviconPath = file.path;
        }
      } catch (_) {}

      final newItem = HomepageShortcutItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameCtrl.text.trim(),
        url: urlStr,
        faviconPath: cachedFaviconPath,
        orderIndex: _shortcuts.length,
      );

      await _repo.addShortcut(newItem);
      _loadShortcuts();
    }
  }

  Future<void> _deleteShortcut(HomepageShortcutItem item) async {
    await _repo.removeShortcut(item.id);
    _loadShortcuts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgWindow,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 顶部 Logo 与标语
                Icon(Icons.shield_moon_rounded, size: 56, color: context.accentSolid),
                const SizedBox(height: 12),
                Text(
                  '私密影音浏览器',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '无痕浏览 · 视频探测 · 一键解析下载 · 实时 AI 字幕',
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 28),

                // 居中大搜索框
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: context.borderSubtle),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, color: context.textSecondary, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: TextStyle(color: context.textPrimary, fontSize: 14),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '输入网址或搜索关键词 (回车直达)...',
                            hintStyle: TextStyle(color: context.textTertiary, fontSize: 13),
                          ),
                          onSubmitted: _handleSearchOrNavigate,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.arrow_forward_rounded, color: context.accentText, size: 18),
                        tooltip: '打开',
                        onPressed: () => _handleSearchOrNavigate(_searchController.text),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 36),

                // N 宫格网格列表
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final shortcut in _shortcuts)
                        _buildShortcutCard(shortcut),
                      _buildAddShortcutCard(),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShortcutCard(HomepageShortcutItem item) {
    final hasLocalFavicon = item.faviconPath != null && File(item.faviconPath!).existsSync();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => widget.onOpenUrl(item.url),
        child: Container(
          width: 120,
          height: 104,
          decoration: BoxDecoration(
            color: context.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderSubtle),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Stack(
            children: [
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: context.bgWindow,
                        shape: BoxShape.circle,
                        border: Border.all(color: context.borderSubtle),
                      ),
                      child: Center(
                        child: hasLocalFavicon
                            ? Image.file(
                                File(item.faviconPath!),
                                width: 22,
                                height: 22,
                                errorBuilder: (_, __, ___) =>
                                    Icon(Icons.public_rounded, size: 20, color: context.accentText),
                              )
                            : Icon(
                                _guessIconForDomain(item.url),
                                size: 22,
                                color: context.accentText,
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz_rounded, size: 14, color: context.textTertiary),
                  color: context.bgCard,
                  padding: EdgeInsets.zero,
                  onSelected: (val) {
                    if (val == 'delete') _deleteShortcut(item);
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('删除', style: TextStyle(color: Colors.redAccent.shade200, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddShortcutCard() {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: _showAddShortcutDialog,
        child: Container(
          width: 120,
          height: 104,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.borderSubtle, style: BorderStyle.solid),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 28, color: context.textSecondary),
              const SizedBox(height: 6),
              Text(
                '添加快捷',
                style: TextStyle(color: context.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _guessIconForDomain(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('youtube')) return Icons.smart_display_rounded;
    if (lower.contains('bilibili')) return Icons.live_tv_rounded;
    if (lower.contains('missav') || lower.contains('jav')) return Icons.movie_filter_rounded;
    if (lower.contains('porn')) return Icons.play_circle_filled_rounded;
    return Icons.public_rounded;
  }
}
