import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../password/vault_store.dart';
import '../models/registered_account.dart';
import '../services/registered_account_store.dart';

class AccountHubView extends StatefulWidget {
  final VaultStore vaultStore;

  const AccountHubView({super.key, required this.vaultStore});

  @override
  State<AccountHubView> createState() => _AccountHubViewState();
}

class _AccountHubViewState extends State<AccountHubView> {
  final _store = RegisteredAccountStore.instance;
  final _searchController = TextEditingController();
  final Set<String> _selectedIds = {};
  final Set<String> _revealedPasswordIds = {};

  String _searchQuery = '';
  String _filterPlatform = 'all'; // 'all' | 'outlook' | 'hotmail'
  String _filterStatus = 'all'; // 'all' | 'SUCCESS' | 'FAILED'

  @override
  void initState() {
    super.initState();
    _store.load();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  List<RegisteredAccount> get _filteredAccounts {
    return _store.accounts.where((acc) {
      if (_filterPlatform != 'all' && acc.platform.toLowerCase() != _filterPlatform) {
        return false;
      }
      if (_filterStatus != 'all' && acc.status.toUpperCase() != _filterStatus) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchEmail = acc.email.toLowerCase().contains(q);
        final matchName = '${acc.firstName} ${acc.lastName}'.toLowerCase().contains(q);
        final matchRecovery = (acc.recoveryEmail ?? '').toLowerCase().contains(q);
        if (!matchEmail && !matchName && !matchRecovery) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _handleImportExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      dialogTitle: '选择已注册账号 Excel / CSV 文件',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      try {
        final count = await _store.importFromExcel(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功导入 $count 个账号！')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _handleExport(String format) async {
    final targets = _selectedIds.isEmpty
        ? _filteredAccounts
        : _store.accounts.where((a) => _selectedIds.contains(a.id)).toList();

    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前没有可导出的账号')),
      );
      return;
    }

    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '保存导出文件',
      fileName: '邮箱导出_${DateTime.now().millisecondsSinceEpoch}.$format',
    );

    if (savePath != null) {
      try {
        await _store.exportAccounts(
          targets: targets,
          format: format,
          outputPath: savePath,
          maskPassword: false,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('成功导出 ${targets.length} 条账号至: $savePath')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _handleSyncToVault() async {
    final targetIds = _selectedIds.isEmpty
        ? _filteredAccounts.map((a) => a.id).toList()
        : _selectedIds.toList();

    if (targetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择要同步的账号')),
      );
      return;
    }

    try {
      final synced = await _store.syncToPasswordVault(
        accountIds: targetIds,
        vaultStore: widget.vaultStore,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功将 $synced 个账号同步保存至系统【密码保险箱】！'),
            backgroundColor: Colors.green[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _handleDeleteSelected() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除账号'),
        content: Text('确定要永久删除选中的 ${_selectedIds.length} 个账号记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _store.deleteAccounts(_selectedIds);
      setState(() {
        _selectedIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = _filteredAccounts;

    return Column(
      children: [
        // 顶部操作栏与统计
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: Row(
            children: [
              // 搜索框
              SizedBox(
                width: 240,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: '搜索账号/姓名/恢复邮箱...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim()),
                ),
              ),
              const SizedBox(width: 12),
              // 筛选下拉
              DropdownButton<String>(
                value: _filterPlatform,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部平台')),
                  DropdownMenuItem(value: 'outlook', child: Text('Outlook')),
                  DropdownMenuItem(value: 'hotmail', child: Text('Hotmail')),
                ],
                onChanged: (v) => setState(() => _filterPlatform = v ?? 'all'),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _filterStatus,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部状态')),
                  DropdownMenuItem(value: 'SUCCESS', child: Text('成功')),
                  DropdownMenuItem(value: 'FAILED', child: Text('失败')),
                ],
                onChanged: (v) => setState(() => _filterStatus = v ?? 'all'),
              ),
              const Spacer(),
              // 操作按钮组
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('导入 Excel'),
                onPressed: _handleImportExcel,
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '导出为...',
                onSelected: _handleExport,
                itemBuilder: (ctx) => [
                  const PopupMenuItem(value: 'xlsx', child: Text('导出为 Excel (.xlsx)')),
                  const PopupMenuItem(value: 'csv', child: Text('导出为 CSV (.csv)')),
                  const PopupMenuItem(value: 'txt', child: Text('导出为 账号----密码 (.txt)')),
                  const PopupMenuItem(value: 'json', child: Text('导出为 JSON (.json)')),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.dividerColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download, size: 16),
                      SizedBox(width: 6),
                      Text('导出数据'),
                      Icon(Icons.arrow_drop_down, size: 16),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                icon: const Icon(Icons.lock_reset, size: 16),
                label: Text(_selectedIds.isEmpty ? '全部同步至保险箱' : '同步选中至保险箱 (${_selectedIds.length})'),
                onPressed: _handleSyncToVault,
              ),
              if (_selectedIds.isNotEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: '批量删除选中',
                  onPressed: _handleDeleteSelected,
                ),
              ],
            ],
          ),
        ),
        // 账号表格
        Expanded(
          child: accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_open, size: 48, color: theme.disabledColor),
                      const SizedBox(height: 12),
                      Text(
                        _store.accounts.isEmpty ? '暂无已注册账号，可启动任务注册或从 Excel 导入历史数据' : '没有匹配筛选条件的账号',
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final acc = accounts[index];
                    final isSelected = _selectedIds.contains(acc.id);
                    final isRevealed = _revealedPasswordIds.contains(acc.id);

                    return Container(
                      decoration: BoxDecoration(
                        color: isSelected ? theme.colorScheme.primaryContainer.withAlpha(50) : null,
                        border: Border(bottom: BorderSide(color: theme.dividerColor.withAlpha(80))),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Checkbox(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              if (v == true) {
                                _selectedIds.add(acc.id);
                              } else {
                                _selectedIds.remove(acc.id);
                              }
                            });
                          },
                        ),
                        title: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: acc.platform == 'outlook' ? Colors.blue.withAlpha(40) : Colors.amber.withAlpha(40),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                acc.platform.toUpperCase(),
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 8),
                            SelectableText(
                              acc.email,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 14),
                              tooltip: '复制邮箱',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: acc.email));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('邮箱已复制到剪贴板')),
                                );
                              },
                            ),
                            const Spacer(),
                            // 密码部分
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isRevealed ? acc.password : '••••••••••••',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                IconButton(
                                  icon: Icon(isRevealed ? Icons.visibility_off : Icons.visibility, size: 16),
                                  onPressed: () {
                                    setState(() {
                                      if (isRevealed) {
                                        _revealedPasswordIds.remove(acc.id);
                                      } else {
                                        _revealedPasswordIds.add(acc.id);
                                      }
                                    });
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 14),
                                  tooltip: '复制密码',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: acc.password));
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('密码已复制到剪贴板')),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Text(
                              '姓名: ${acc.firstName} ${acc.lastName}  |  生日: ${acc.birthDate}  |  注册于: ${acc.createdAt.toString().split('.')[0]}',
                              style: TextStyle(fontSize: 11, color: theme.hintColor),
                            ),
                            if (acc.recoveryEmail != null && acc.recoveryEmail!.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              Text(
                                '辅助邮箱: ${acc.recoveryEmail}',
                                style: TextStyle(fontSize: 11, color: Colors.teal[600]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
