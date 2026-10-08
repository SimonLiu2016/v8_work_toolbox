import 'dart:io';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../services/ai_library_assistant_service.dart';
import '../services/private_browser_repository.dart';
import '../services/private_browser_service.dart';

/// 隐私空间私密视频收藏库页面
class VideoLibraryView extends StatefulWidget {
  final void Function(String urlOrPath, {String? title, String? thumbnail})? onPlayMedia;

  const VideoLibraryView({
    super.key,
    this.onPlayMedia,
  });

  @override
  State<VideoLibraryView> createState() => _VideoLibraryViewState();
}

class _VideoLibraryViewState extends State<VideoLibraryView> {
  final PrivateBrowserRepository _repo = PrivateBrowserService.instance.repository;
  final AILibraryAssistantService _aiAssistant = AILibraryAssistantService.instance;

  final TextEditingController _searchController = TextEditingController();

  List<VideoCategoryItem> _categories = [];
  List<VideoTagItem> _tags = [];
  List<VideoBookmarkItem> _bookmarks = [];
  bool _isLoading = true;

  // 筛选状态
  String? _selectedCategoryId;
  String? _selectedTagId;
  String? _selectedPlatform;
  String _sortOrder = 'added_at_desc';
  bool _isSemanticSearch = false;
  bool _isAiSearching = false;

  // AI 咨询侧边抽屉
  bool _showAiChatDrawer = false;
  final List<Map<String, String>> _chatMessages = [];
  final TextEditingController _chatInputController = TextEditingController();
  bool _isChatReplying = false;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatInputController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    final cats = await _repo.getCategories();
    final tags = await _repo.getTags();
    final bms = await _repo.getBookmarksFiltered(
      categoryId: _selectedCategoryId,
      tagId: _selectedTagId,
      platform: _selectedPlatform,
      sortOrder: _sortOrder,
    );

    if (mounted) {
      setState(() {
        _categories = cats;
        _tags = tags;
        _bookmarks = bms;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _loadAllData();
      return;
    }

    if (_isSemanticSearch) {
      // 触发 AI 语义智能检索
      setState(() => _isAiSearching = true);
      final all = await _repo.getBookmarksFiltered();
      final ranked = await _aiAssistant.semanticSearch(query: trimmed, allBookmarks: all);
      if (mounted) {
        setState(() {
          _bookmarks = ranked;
          _isAiSearching = false;
        });
      }
    } else {
      // 普通 FTS5 全文搜索
      final bms = await _repo.getBookmarksFiltered(
        categoryId: _selectedCategoryId,
        tagId: _selectedTagId,
        platform: _selectedPlatform,
        searchQuery: trimmed,
        sortOrder: _sortOrder,
      );
      if (mounted) {
        setState(() => _bookmarks = bms);
      }
    }
  }

  Future<void> _showCreateCategoryDialog() async {
    final nameCtrl = TextEditingController();
    String? parentId;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Text('新建视频分类', style: TextStyle(color: context.textPrimary, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: context.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: '分类名称',
                  labelStyle: TextStyle(color: context.textSecondary),
                  hintText: '如 日本AV / 剧情片 / 音乐',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: parentId,
                dropdownColor: context.bgCard,
                decoration: InputDecoration(
                  labelText: '父级分类 (可选)',
                  labelStyle: TextStyle(color: context.textSecondary),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('无 (根分类)')),
                  for (final c in _categories.where((c) => c.parentId == null))
                    DropdownMenuItem(value: c.id, child: Text(c.name)),
                ],
                onChanged: (val) => setDlgState(() => parentId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('取消', style: TextStyle(color: context.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final newCat = VideoCategoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        name: nameCtrl.text.trim(),
        parentId: parentId,
        displayOrder: _categories.length,
      );
      await _repo.addCategory(newCat);
      _loadAllData();
    }
  }

  Future<void> _sendChatMessage() async {
    final text = _chatInputController.text.trim();
    if (text.isEmpty || _isChatReplying) return;

    _chatInputController.clear();
    setState(() {
      _chatMessages.add({'role': 'user', 'content': text});
      _isChatReplying = true;
    });

    try {
      final activeTab = PrivateBrowserService.instance.activeTab;
      final reply = await _aiAssistant.chatWithAssistant(
        conversationHistory: _chatMessages,
        recentBookmarks: _bookmarks,
        categories: _categories,
        currentWebUrl: activeTab?.url,
        currentWebTitle: activeTab?.title,
      );

      if (mounted) {
        setState(() {
          _chatMessages.add({'role': 'assistant', 'content': reply});
          _isChatReplying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _chatMessages.add({'role': 'assistant', 'content': '抱歉，服务暂时不可用: $e'});
          _isChatReplying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgWindow,
      body: Row(
        children: [
          // 1. 左侧分类与标签筛选树
          Container(
            width: 240,
            decoration: BoxDecoration(
              color: context.bgSidebar,
              border: Border(right: BorderSide(color: context.borderSubtle)),
            ),
            child: _buildSidebar(),
          ),

          // 2. 右侧主工作区 (顶部搜索与过滤栏 + 视频网格/列表)
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    _buildHeaderBar(),
                    Expanded(child: _buildVideoGridOrList()),
                  ],
                ),

                // AI 咨询侧边抽屉
                if (_showAiChatDrawer)
                  Positioned(
                    top: 0,
                    right: 0,
                    bottom: 0,
                    width: 360,
                    child: _buildAiChatDrawer(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 分类标题栏
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.folder_copy_rounded, size: 16, color: context.accentText),
              const SizedBox(width: 8),
              Text(
                '视频分类',
                style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add_rounded, size: 16),
                tooltip: '新建分类',
                onPressed: _showCreateCategoryDialog,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 分类树列表
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              _buildCategoryTile(id: null, name: '全部视频', icon: Icons.all_inbox_rounded),
              for (final cat in _categories.where((c) => c.parentId == null)) ...[
                _buildCategoryTile(id: cat.id, name: cat.name, icon: Icons.folder_rounded),
                // 子分类
                for (final sub in _categories.where((c) => c.parentId == cat.id))
                  _buildCategoryTile(id: sub.id, name: '  └ ${sub.name}', icon: Icons.folder_open_rounded),
              ],
            ],
          ),
        ),

        const Divider(height: 1),

        // 标签云标题
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Icon(Icons.local_offer_rounded, size: 14, color: context.textSecondary),
              const SizedBox(width: 8),
              Text(
                '标签云',
                style: TextStyle(color: context.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),

        // 标签云区域
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in _tags)
                  FilterChip(
                    selected: _selectedTagId == tag.id,
                    label: Text('${tag.name} (${tag.usageCount})', style: const TextStyle(fontSize: 11)),
                    backgroundColor: context.bgCard,
                    selectedColor: context.accentSolid.withOpacity(0.2),
                    checkmarkColor: context.accentText,
                    onSelected: (val) {
                      setState(() {
                        _selectedTagId = val ? tag.id : null;
                      });
                      _loadAllData();
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryTile({required String? id, required String name, required IconData icon}) {
    final isSelected = _selectedCategoryId == id;
    return InkWell(
      onTap: () {
        setState(() => _selectedCategoryId = id);
        _loadAllData();
      },
      child: Container(
        height: 34,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isSelected ? context.accentSolid.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: isSelected ? context.accentText : context.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  color: isSelected ? context.accentText : context.textPrimary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.bgWindow,
        border: Border(bottom: BorderSide(color: context.borderSubtle)),
      ),
      child: Row(
        children: [
          // 搜索框
          Container(
            width: 320,
            height: 32,
            decoration: BoxDecoration(
              color: context.bgCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.borderSubtle),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 16, color: context.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: context.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      hintText: _isSemanticSearch ? 'AI 语义检索 (如: 找有中文字幕的高清片)...' : '搜索视频标题与备注...',
                      hintStyle: TextStyle(color: context.textTertiary, fontSize: 12),
                    ),
                    onSubmitted: _handleSearch,
                  ),
                ),
                if (_isAiSearching)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // 语义检索开关 Chip
          FilterChip(
            selected: _isSemanticSearch,
            avatar: Icon(Icons.auto_awesome_rounded, size: 12, color: _isSemanticSearch ? Colors.white : context.accentText),
            label: const Text('AI 语义检索', style: TextStyle(fontSize: 11)),
            selectedColor: context.accentSolid,
            labelStyle: TextStyle(color: _isSemanticSearch ? Colors.white : context.textPrimary),
            onSelected: (val) {
              setState(() => _isSemanticSearch = val);
              if (_searchController.text.trim().isNotEmpty) {
                _handleSearch(_searchController.text);
              }
            },
          ),
          const Spacer(),

          // 排序下拉
          DropdownButton<String>(
            value: _sortOrder,
            dropdownColor: context.bgCard,
            underline: const SizedBox(),
            style: TextStyle(color: context.textSecondary, fontSize: 12),
            items: const [
              DropdownMenuItem(value: 'added_at_desc', child: Text('最新收藏优先')),
              DropdownMenuItem(value: 'rating_desc', child: Text('最高评分优先')),
              DropdownMenuItem(value: 'title_asc', child: Text('标题字母排序')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _sortOrder = val);
                _loadAllData();
              }
            },
          ),
          const SizedBox(width: 12),

          // AI 咨询侧边栏唤起按钮
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.bgCard,
              foregroundColor: context.accentText,
              side: BorderSide(color: context.borderSubtle),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            ),
            icon: const Icon(Icons.smart_toy_rounded, size: 14),
            label: const Text('AI 咨询助理', style: TextStyle(fontSize: 12)),
            onPressed: () {
              setState(() => _showAiChatDrawer = !_showAiChatDrawer);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVideoGridOrList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bookmarks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: 48, color: context.textTertiary),
            const SizedBox(height: 12),
            Text('未找到任何视频收藏记录', style: TextStyle(color: context.textSecondary, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _bookmarks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, idx) {
        final b = _bookmarks[idx];
        return _buildBookmarkRow(b);
      },
    );
  }

  Widget _buildBookmarkRow(VideoBookmarkItem item) {
    final hasThumbnail = item.thumbnailPath != null && File(item.thumbnailPath!).existsSync();

    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderSubtle),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面缩略图 (64x44)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 72,
              height: 48,
              color: context.bgWindow,
              child: hasThumbnail
                  ? Image.file(File(item.thumbnailPath!), fit: BoxFit.cover)
                  : Center(
                      child: Icon(Icons.movie_rounded, size: 24, color: context.textTertiary),
                    ),
            ),
          ),
          const SizedBox(width: 14),

          // 中间标题与标签
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 平台徽章
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.accentSolid.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.platform,
                        style: TextStyle(color: context.accentText, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 星级展示
                    Row(
                      children: List.generate(5, (starIdx) {
                        return Icon(
                          starIdx < item.rating ? Icons.star_rounded : Icons.star_border_rounded,
                          size: 14,
                          color: Colors.amber,
                        );
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 6),

                // AI 标签与摘要展示
                Wrap(
                  spacing: 6,
                  children: [
                    for (final tag in item.aiTags)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: context.bgWindow,
                          borderRadius: BorderRadius.circular(3),
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(color: context.textSecondary, fontSize: 10),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 右侧快捷播放与操作
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                tooltip: '在私密浏览器中打开',
                onPressed: () {
                  PrivateBrowserService.instance.openNativeBrowser(url: item.url);
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                tooltip: '删除收藏',
                onPressed: () async {
                  await _repo.deleteVideoBookmark(item.id);
                  _loadAllData();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAiChatDrawer() {
    return Container(
      decoration: BoxDecoration(
        color: context.bgCard,
        border: Border(left: BorderSide(color: context.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 16,
            offset: const Offset(-4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: context.bgSidebar,
            child: Row(
              children: [
                Icon(Icons.smart_toy_rounded, size: 18, color: context.accentText),
                const SizedBox(width: 8),
                Text(
                  '私密视频助理',
                  style: TextStyle(color: context.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () => setState(() => _showAiChatDrawer = false),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _chatMessages.length,
              itemBuilder: (ctx, idx) {
                final msg = _chatMessages[idx];
                final isUser = msg['role'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isUser ? context.accentSolid : context.bgWindow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.borderSubtle),
                    ),
                    constraints: const BoxConstraints(maxWidth: 280),
                    child: Text(
                      msg['content'] ?? '',
                      style: TextStyle(color: isUser ? Colors.white : context.textPrimary, fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),
          if (_isChatReplying)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: context.accentText)),
                  const SizedBox(width: 8),
                  Text('助理正在组织回复...', style: TextStyle(color: context.textTertiary, fontSize: 11)),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.all(8),
            color: context.bgSidebar,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatInputController,
                    style: TextStyle(color: context.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: '问问助理，如: 帮我整理分类...',
                      hintStyle: TextStyle(color: context.textTertiary, fontSize: 11),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendChatMessage(),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send_rounded, size: 16, color: context.accentText),
                  onPressed: _sendChatMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
