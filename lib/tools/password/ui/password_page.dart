import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../migration/migration_service.dart';
import '../vault_models.dart';
import '../vault_store.dart';
import 'generator_panel.dart';
import 'health_report.dart';
import 'item_editor.dart';
import 'migration_wizard.dart';
import 'settings_panel.dart';

/// 密码工具主页面（三栏布局：标签侧栏 + 条目列表 + 详情面板）
class PasswordPage extends StatefulWidget {
  const PasswordPage({super.key, this.store});

  /// 测试注入；生产环境为 null 时使用默认 VaultStore
  final VaultStore? store;

  @override
  State<PasswordPage> createState() => _PasswordPageState();
}

class _PasswordPageState extends State<PasswordPage> {
  late final VaultStore _store;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String? _selectedTag;
  VaultItem? _selectedItem;
  bool _checkingMigration = true;
  bool _migrationNeeded = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? VaultStore();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final migration = MigrationService();
      final needed = await migration.needsMigration();
      await _store.load();
      if (mounted) {
        setState(() {
          _migrationNeeded = needed;
          _checkingMigration = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _checkingMigration = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VaultItem> get _visibleItems =>
      _store.search(_searchQuery, tag: _selectedTag);

  void _selectItem(VaultItem item) {
    setState(() => _selectedItem = item);
  }

  void _showEditor({VaultItem? existing}) {
    showDialog<void>(
      context: context,
      builder: (ctx) => ItemEditorDialog(
        store: _store,
        existing: existing,
        onSaved: (item) {
          setState(() => _selectedItem = item);
        },
      ),
    );
  }

  void _showGenerator() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      builder: (ctx) => const GeneratorPanel(),
    );
  }

  void _showHealthReport() {
    showDialog<void>(
      context: context,
      builder: (ctx) => HealthReportPanel(
        store: _store,
        onNavigateToItem: (item) {
          Navigator.of(ctx).pop();
          _selectItem(item);
        },
      ),
    );
  }

  void _showSettings() {
    showDialog<void>(
      context: context,
      builder: (ctx) => SettingsPanel(store: _store),
    );
  }

  Future<void> _deleteItem(VaultItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('删除条目', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '确定删除「${item.title}」？此操作不可撤销。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _store.delete(item.id);
      if (mounted) {
        setState(() {
          if (_selectedItem?.id == item.id) _selectedItem = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingMigration) {
      return const Scaffold(
        backgroundColor: AppTheme.bgContent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_migrationNeeded) {
      return Scaffold(
        backgroundColor: AppTheme.bgContent,
        body: MigrationWizard(
          onComplete: () {
            setState(() {
              _migrationNeeded = false;
            });
            _store.load();
          },
          onSkip: () {
            setState(() => _migrationNeeded = false);
          },
        ),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        backgroundColor: AppTheme.bgContent,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppTheme.error, size: 48),
                const SizedBox(height: 16),
                const Text(
                  '密码库加载失败',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  _loadError!,
                  style: const TextStyle(
                      color: AppTheme.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _loadError = null;
                      _checkingMigration = true;
                    });
                    _bootstrap();
                  },
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgContent,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Row(
              children: [
                _buildSidebar(),
                Container(width: 1, color: AppTheme.borderSubtle),
                _buildItemList(),
                Container(width: 1, color: AppTheme.borderSubtle),
                Expanded(child: _buildDetail()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppTheme.bgSidebar,
        border: Border(bottom: BorderSide(color: AppTheme.borderSubtle)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_rounded, color: AppTheme.accent, size: 22),
          const SizedBox(width: 8),
          const Text(
            '密码工具',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: '搜索标题、用户名或网址…',
                  hintStyle:
                      const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
                  prefixIcon: const Icon(Icons.search,
                      color: AppTheme.textTertiary, size: 18),
                  filled: true,
                  fillColor: AppTheme.bgInput,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _headerButton(
            icon: Icons.add,
            label: '新建',
            onPressed: () => _showEditor(),
            primary: true,
          ),
          const SizedBox(width: 8),
          _headerButton(
            icon: Icons.health_and_safety_outlined,
            label: '体检',
            onPressed: _showHealthReport,
          ),
          const SizedBox(width: 8),
          _headerButton(
            icon: Icons.password_rounded,
            label: '生成器',
            onPressed: _showGenerator,
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.lock_outline,
                color: AppTheme.textSecondary, size: 20),
            tooltip: '立即锁定',
            onPressed: () {
              _store.lock();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已锁定：内存中的密钥已清空')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined,
                color: AppTheme.textSecondary, size: 20),
            tooltip: '设置',
            onPressed: _showSettings,
          ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppTheme.accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: Size.zero,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 13)),
      );
    }
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.textSecondary,
        side: const BorderSide(color: AppTheme.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _buildSidebar() {
    final counts = _store.tagCounts();
    final total = _store.items.length;
    final tags = counts.keys.toList()..sort();

    return Container(
      width: 180,
      color: AppTheme.bgSidebar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _sidebarEntry(
            icon: Icons.apps_rounded,
            label: '全部',
            count: total,
            selected: _selectedTag == null,
            onTap: () => setState(() => _selectedTag = null),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              '标签',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
            ),
          ),
          for (final tag in tags)
            _sidebarEntry(
              icon: Icons.tag_rounded,
              label: tag,
              count: counts[tag]!,
              selected: _selectedTag == tag,
              onTap: () => setState(() => _selectedTag = tag),
            ),
        ],
      ),
    );
  }

  Widget _sidebarEntry({
    required IconData icon,
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: selected ? AppTheme.bgSelected : Colors.transparent,
        child: Row(
          children: [
            Icon(icon,
                size: 16,
                color: selected ? AppTheme.accent : AppTheme.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color:
                      selected ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$count',
              style:
                  const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList() {
    final items = _visibleItems;
    return Container(
      width: 280,
      color: AppTheme.bgContent,
      child: items.isEmpty
          ? Center(
              child: Text(
                _store.items.isEmpty ? '暂无条目，点击「新建」开始' : '无匹配条目',
                style: const TextStyle(
                    color: AppTheme.textTertiary, fontSize: 13),
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (ctx, i) => _buildItemTile(items[i]),
            ),
    );
  }

  Widget _buildItemTile(VaultItem item) {
    final selected = _selectedItem?.id == item.id;
    final icon = switch (item.type) {
      VaultEntryType.login => Icons.key_rounded,
      VaultEntryType.note => Icons.sticky_note_2_outlined,
      VaultEntryType.totp => Icons.timer_outlined,
    };
    return InkWell(
      onTap: () => _selectItem(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppTheme.bgSelected : Colors.transparent,
          border: const Border(
            bottom: BorderSide(color: AppTheme.borderSubtle, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: selected ? AppTheme.accent : AppTheme.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title.isEmpty ? '（无标题）' : item.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (item.username.isNotEmpty)
                    Text(
                      item.username,
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail() {
    final item = _selectedItem;
    if (item == null) {
      return const Center(
        child: Text(
          '选择左侧条目查看详情',
          style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
        ),
      );
    }
    return ItemDetailView(
      key: ValueKey(item.id),
      store: _store,
      item: item,
      onEdit: () => _showEditor(existing: item),
      onDelete: () => _deleteItem(item),
    );
  }
}
